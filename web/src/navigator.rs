//! Navigator backend for web
use crate::SocketProxy;
use async_channel::{Receiver, Sender};
use futures::channel::oneshot;
use futures_util::future::Either;
use futures_util::{SinkExt, Stream, StreamExt, future};
use gloo_net::websocket::{Message, State, futures::WebSocket};
use js_sys::{Array, Promise, RegExp, Uint8Array};
use ruffle_core::Player;
use ruffle_core::backend::navigator::{
    ErrorResponse, NavigationMethod, NavigatorBackend, OwnedFuture, Request, SuccessResponse,
    async_return, create_fetch_error, create_specific_fetch_error, get_encoding,
};
use ruffle_core::config::NetworkingAccessMode;
use ruffle_core::indexmap::IndexMap;
use ruffle_core::loader::Error;
use ruffle_core::socket::{ConnectionState, SocketAction, SocketHandle};
use ruffle_core::swf::Encoding;
use std::borrow::Cow;
use std::cell::RefCell;
use std::rc::Rc;
use std::sync::{Arc, Mutex, Weak};
use std::task::Poll;
use std::time::Duration;
use tracing_subscriber::Registry;
use tracing_subscriber::layer::Layered;
use tracing_wasm::WASMLayer;
use url::{ParseError, Url};
use wasm_bindgen::closure::Closure;
use wasm_bindgen::{JsCast, JsValue};
use wasm_bindgen_futures::{JsFuture, spawn_local};
use wasm_streams::readable::ReadableStream;
use web_sys::{
    Blob, BlobPropertyBag, HtmlFormElement, HtmlInputElement, Request as WebRequest,
    RequestCredentials, RequestInit, Response as WebResponse, window,
};

/// The handling mode of links opening a new website.
#[derive(Clone, Copy, Debug, PartialEq, serde::Serialize, serde::Deserialize)]
pub enum OpenUrlMode {
    /// Allow all links to open a new website.
    #[serde(rename = "allow")]
    Allow,

    /// A confirmation dialog opens with every link trying to open a new website.
    #[serde(rename = "confirm")]
    Confirm,

    /// Deny all links to open a new website.
    #[serde(rename = "deny")]
    Deny,
}

pub struct WebNavigatorBackend {
    log_subscriber: Arc<Layered<WASMLayer, Registry>>,
    allow_script_access: bool,
    allow_networking: NetworkingAccessMode,
    upgrade_to_https: bool,
    url_rewrite_rules: Vec<(RegExp, String)>,
    base_url: Option<Url>,
    open_url_mode: OpenUrlMode,
    socket_proxies: Vec<SocketProxy>,
    credential_allow_list: Vec<String>,
    player: Weak<Mutex<Player>>,
}

/// Exact mappings keep their original priority, even if a wildcard appears first.
/// Among fallback mappings, configuration order breaks ties. An invalid selected
/// mapping fails closed instead of falling through to a different destination.
fn socket_proxy_url(proxies: &[SocketProxy], host: &str, port: u16) -> Option<Url> {
    let proxy = proxies
        .iter()
        .find(|proxy| proxy.host == host && proxy.port == port)
        .or_else(|| {
            proxies.iter().find(|proxy| {
                (proxy.host == host || proxy.host == "*") && (proxy.port == port || proxy.port == 0)
            })
        })?;

    if proxy.host == "*"
        && proxy.port == 0
        && (!proxy.proxy_url.contains("{host}") || !proxy.proxy_url.contains("{port}"))
    {
        return None;
    }

    // Use URL-component encoding, not a raw replacement or a URL authority.
    // In particular, IPv6 colons/brackets and query delimiters must remain data.
    // byte_serialize uses form encoding, so convert its space spelling to %20
    // to make this safe in both path components and query parameter values.
    let host = url::form_urlencoded::byte_serialize(host.as_bytes())
        .collect::<String>()
        .replace('+', "%20");
    let url = proxy
        .proxy_url
        .replace("{host}", &host)
        .replace("{port}", &port.to_string());
    let url = Url::parse(&url).ok()?;
    matches!(url.scheme(), "ws" | "wss").then_some(url)
}

/// Cancel the browser timer when a handshake finishes or its future is dropped.
struct SocketTimeout {
    window: web_sys::Window,
    handle: i32,
    // Keep the callback alive until after clearTimeout in Drop.
    _callback: Closure<dyn FnMut()>,
}

impl Drop for SocketTimeout {
    fn drop(&mut self) {
        self.window.clear_timeout_with_handle(self.handle);
    }
}

async fn socket_timeout(mut remaining: Duration) -> Result<(), ()> {
    let window = window().ok_or(())?;
    while !remaining.is_zero() {
        // setTimeout takes a signed 32-bit delay; larger Flash timeouts must
        // not overflow into an immediate timeout or be silently shortened.
        let chunk = remaining.min(Duration::from_millis(i32::MAX as u64));
        let (sender, receiver) = oneshot::channel();
        let callback = Closure::once_aborting(move || {
            let _ = sender.send(());
        });
        let handle = window
            .set_timeout_with_callback_and_timeout_and_arguments_0(
                callback.as_ref().unchecked_ref(),
                chunk.as_millis() as i32,
            )
            .map_err(|_| ())?;
        let _timer = SocketTimeout {
            window: window.clone(),
            handle,
            _callback: callback,
        };
        // A cancellable oneshot avoids retaining JsFuture callbacks for a
        // Promise that would never resolve after its timeout is cleared.
        receiver.await.map_err(|_| ())?;
        remaining -= chunk;
    }
    Ok(())
}

#[expect(clippy::too_many_arguments)]
impl WebNavigatorBackend {
    pub fn new(
        allow_script_access: bool,
        allow_networking: NetworkingAccessMode,
        upgrade_to_https: bool,
        url_rewrite_rules: Vec<(RegExp, String)>,
        base_url: Option<String>,
        log_subscriber: Arc<Layered<WASMLayer, Registry>>,
        open_url_mode: OpenUrlMode,
        socket_proxies: Vec<SocketProxy>,
        credential_allow_list: Vec<String>,
    ) -> Self {
        let window = web_sys::window().expect("window()");

        // Upgrade to HTTPS takes effect if the current page is hosted on HTTPS.
        let upgrade_to_https =
            upgrade_to_https && window.location().protocol().expect("protocol()") == "https:";

        // Retrieve and parse `document.baseURI`.
        let document_base_uri = || {
            let document = window.document().expect("document()");
            if let Ok(Some(base_uri)) = document.base_uri() {
                return Url::parse(&base_uri).ok();
            }

            None
        };

        let base_url = if let Some(mut base_url) = base_url {
            // Adding trailing slash so `Url::parse` will not drop the last part.
            if !base_url.ends_with('/') {
                base_url.push('/');
            }

            Url::parse(&base_url)
                .ok()
                .or_else(|| document_base_uri().and_then(|base_uri| base_uri.join(&base_url).ok()))
        } else {
            document_base_uri()
        };

        if base_url.is_none() {
            tracing::error!("Could not get base URL for base directory inference.");
        }

        Self {
            allow_script_access,
            allow_networking,
            upgrade_to_https,
            url_rewrite_rules,
            base_url,
            log_subscriber,
            open_url_mode,
            socket_proxies,
            credential_allow_list,
            player: Weak::new(),
        }
    }

    /// We need to set the player after construction because the player is created after the navigator.
    pub fn set_player(&mut self, player: Weak<Mutex<Player>>) {
        self.player = player;
    }

    /// Try to rewrite the URL using URL rewrite rules.
    fn rewrite_url(&self, url: &Url) -> Option<Url> {
        let url_string: js_sys::JsString = url.to_string().into();
        for (regexp, replacement) in &self.url_rewrite_rules {
            if !url_string.search(regexp) >= 0 {
                continue;
            }

            tracing::info!(
                "URL rewrite rule triggered ({:?} -> {}) for URL {}",
                regexp,
                replacement,
                url
            );

            let replaced = url_string.replace_by_pattern(regexp, replacement);
            let replaced = replaced.as_string()?;
            match Url::parse(&replaced) {
                Ok(new_url) => {
                    return Some(new_url);
                }
                // Handle relative rewrite URLs
                Err(ParseError::RelativeUrlWithoutBase) if self.base_url.is_some() => {
                    let base_url = self.base_url.as_ref().expect("condition");
                    match base_url.join(&replaced) {
                        Ok(new_url) => {
                            return Some(new_url);
                        }
                        Err(err) => {
                            tracing::error!(
                                "Rewritten URL (relative) is not valid: {}, {}",
                                replaced,
                                err
                            );
                        }
                    }
                }
                Err(err) => {
                    tracing::error!(
                        "Rewritten URL (absolute) is not valid: {}, {}",
                        replaced,
                        err
                    );
                }
            }
            break;
        }
        None
    }
}

impl NavigatorBackend for WebNavigatorBackend {
    fn navigate_to_url(
        &self,
        url: &str,
        target: &str,
        vars_method: Option<(NavigationMethod, IndexMap<String, String>)>,
    ) {
        // If the URL is empty, ignore the request.
        if url.is_empty() {
            return;
        }

        let url = match self.resolve_url(url) {
            Ok(url) => url,
            Err(e) => {
                tracing::error!(
                    "Could not parse URL because of {}, the corrupt URL was: {}",
                    e,
                    url
                );
                return;
            }
        };

        // If `allowNetworking` is set to `internal` or `none`, block all `navigate_to_url` calls.
        if self.allow_networking != NetworkingAccessMode::All {
            tracing::warn!("SWF tried to open a URL, but opening URLs is not allowed");
            return;
        }

        // If `allowScriptAccess` is disabled, reject the `javascript:` scheme.
        // Also reject any attempt to open a URL when `target` is a keyword that affects the current tab.
        if !self.allow_script_access {
            if url.scheme() == "javascript" {
                tracing::warn!("SWF tried to run a script, but script access is not allowed");
                return;
            } else {
                match target.to_lowercase().as_str() {
                    "_parent" | "_self" | "_top" | "" => {
                        tracing::warn!(
                            "SWF tried to open a URL, but opening URLs in the current tab is prevented by script access"
                        );
                        return;
                    }
                    _ => (),
                }
            }
        }

        let window = window().expect("window()");

        if url.scheme() != "javascript" {
            if self.open_url_mode == OpenUrlMode::Confirm {
                let message = format!("The SWF file wants to open the website {}", url);
                // TODO: Add a checkbox with a GUI toolkit
                let confirm = window
                    .confirm_with_message(&message)
                    .expect("confirm_with_message()");
                if !confirm {
                    tracing::info!(
                        "SWF tried to open a website, but the user declined the request"
                    );
                    return;
                }
            } else if self.open_url_mode == OpenUrlMode::Deny {
                tracing::warn!("SWF tried to open a website, but opening a website is not allowed");
                return;
            }
            // If the user confirmed or if in `Allow` mode, open the website.
        }

        // TODO: Should we return a result for failed opens? Does Flash care?
        match vars_method {
            Some((navmethod, formvars)) => {
                let document = window.document().expect("document()");
                let body = match document.body() {
                    Some(body) => body,
                    None => return,
                };

                let form: HtmlFormElement = document
                    .create_element("form")
                    .expect("create_element() must succeed")
                    .dyn_into()
                    .expect("create_element(\"form\") didn't give us a form");

                form.set_method(&navmethod.to_string());
                form.set_action(url.as_str());

                if !target.is_empty() {
                    form.set_target(target);
                }

                if navmethod == NavigationMethod::Get {
                    // Browsers will clobber any query string with "the whole form input", so we need to re-add them here
                    for (key, value) in url.query_pairs() {
                        let hidden: HtmlInputElement = document
                            .create_element("input")
                            .expect("create_element() must succeed")
                            .dyn_into()
                            .expect("create_element(\"input\") didn't give us an input");

                        hidden.set_type("hidden");
                        hidden.set_name(&key);
                        hidden.set_value(&value);

                        let _ = form.append_child(&hidden);
                    }
                }

                for (key, value) in formvars {
                    let hidden: HtmlInputElement = document
                        .create_element("input")
                        .expect("create_element() must succeed")
                        .dyn_into()
                        .expect("create_element(\"input\") didn't give us an input");

                    hidden.set_type("hidden");
                    hidden.set_name(&key);
                    hidden.set_value(&value);

                    let _ = form.append_child(&hidden);
                }

                let _ = body.append_child(&form);
                let _ = form.submit();
            }
            None => {
                if target.is_empty() {
                    let _ = window.location().assign(url.as_str());
                } else {
                    let _ = window.open_with_url_and_target(url.as_str(), target);
                }
            }
        };
    }

    fn fetch(&self, request: Request) -> OwnedFuture<Box<dyn SuccessResponse>, ErrorResponse> {
        let url = match self.resolve_url(request.url()) {
            Ok(url) => url,
            Err(e) => {
                return async_return(Err(create_fetch_error(request.url(), e)));
            }
        };

        let credentials = if let Some(host) = url.host_str() {
            if self
                .credential_allow_list
                .iter()
                .any(|allowed| allowed == &format!("{}://{}", url.scheme(), host))
            {
                RequestCredentials::Include
            } else {
                RequestCredentials::SameOrigin
            }
        } else {
            RequestCredentials::SameOrigin
        };

        Box::pin(async move {
            let init = RequestInit::new();

            init.set_method(&request.method().to_string());
            init.set_credentials(credentials);

            if let Some((data, mime)) = request.body() {
                let options = BlobPropertyBag::new();
                options.set_type(mime);
                let blob = Blob::new_with_buffer_source_sequence_and_options(
                    &Array::from_iter([Uint8Array::from(data.as_slice()).buffer()]),
                    &options,
                )
                .map_err(|_| ErrorResponse {
                    url: url.to_string(),
                    error: Error::FetchError("Got JS error".to_string()),
                })?
                .dyn_into()
                .map_err(|_| ErrorResponse {
                    url: url.to_string(),
                    error: Error::FetchError("Got JS error".to_string()),
                })?;

                init.set_body(&blob);
            }

            let web_request = match WebRequest::new_with_str_and_init(url.as_str(), &init) {
                Ok(web_request) => web_request,
                Err(_) => {
                    return Err(create_specific_fetch_error(
                        "Unable to create request for",
                        url.as_str(),
                        "",
                    ));
                }
            };

            let headers = web_request.headers();

            for (header_name, header_val) in request.headers() {
                headers
                    .set(header_name, header_val)
                    .map_err(|_| ErrorResponse {
                        url: url.to_string(),
                        error: Error::FetchError("Got JS error".to_string()),
                    })?;
            }

            let window = web_sys::window().expect("window()");
            let fetchval = JsFuture::from(window.fetch_with_request(&web_request))
                .await
                .map_err(|_| {
                    if url.scheme() == "file" {
                        create_specific_fetch_error(
                            "WASM target can't fetch local URL",
                            url.as_str(),
                            "",
                        )
                    } else {
                        ErrorResponse {
                            url: url.to_string(),
                            error: Error::FetchError("Got JS error".to_string()),
                        }
                    }
                })?;

            let response: WebResponse = fetchval.dyn_into().map_err(|_| ErrorResponse {
                url: url.to_string(),
                error: Error::FetchError("Fetch result wasn't a WebResponse".to_string()),
            })?;
            let url = response.url();
            let status = response.status();
            let redirected = response.redirected();
            if !response.ok() && !request.preserve_error_body {
                let error = Error::HttpNotOk(
                    format!("Got {}", response.status_text()),
                    status,
                    redirected,
                    0,
                );
                return Err(ErrorResponse { url, error });
            }

            let wrapper: Box<dyn SuccessResponse> = Box::new(WebResponseWrapper {
                rewritten_url: None,
                response,
                body_stream: None,
            });

            Ok(wrapper)
        })
    }

    fn resolve_url(&self, url: &str) -> Result<Url, ParseError> {
        if let Some(base_url) = &self.base_url {
            match base_url.join(url) {
                Ok(full_url) => Ok(self.pre_process_url(full_url)),
                Err(error) => Err(error),
            }
        } else {
            match Url::parse(url) {
                Ok(parsed_url) => Ok(self.pre_process_url(parsed_url)),
                Err(error) => Err(error),
            }
        }
    }

    fn spawn_future(&mut self, future: OwnedFuture<(), Error>) {
        let subscriber = self.log_subscriber.clone();
        let player = self.player.clone();

        spawn_local(async move {
            let _subscriber = tracing::subscriber::set_default(subscriber.clone());
            if player
                .upgrade()
                .expect("Called spawn_future after player was dropped")
                .try_lock()
                .is_err()
            {
                // The player is locked - this can occur due to 'wasm-bindgen-futures' using
                // 'queueMicroTask', which may result in one of our future's getting polled
                // while we're still inside of our 'requestAnimationFrame' callback (e.g.
                // when we call into javascript).
                //
                // When this happens, we 'reschedule' this future by waiting for a 'setTimeout'
                // callback to be resolved. This will cause our future to get woken up from
                // inside the 'setTimeout' JavaScript task (which is a new top-level call stack),
                // outside of the 'requestAnimationFrame' callback, which will allow us to lock
                // the Player.
                let promise = Promise::new(&mut |resolve, _reject| {
                    web_sys::window()
                        .expect("window")
                        .set_timeout_with_callback(&resolve)
                        .expect("Failed to call setTimeout with dummy promise");
                });
                let _ = JsFuture::from(promise).await;
            }
            if let Err(e) = future.await {
                tracing::error!("Asynchronous error occurred: {}", e);
            }
        })
    }

    fn pre_process_url(&self, mut url: Url) -> Url {
        if let Some(rewritten_url) = self.rewrite_url(&url) {
            url = rewritten_url;
        }

        if self.upgrade_to_https && url.scheme() == "http" && url.set_scheme("https").is_err() {
            tracing::error!("Url::set_scheme failed on: {}", url);
        }

        url
    }

    fn connect_socket(
        &mut self,
        host: String,
        port: u16,
        timeout: Duration,
        handle: SocketHandle,
        receiver: Receiver<Vec<u8>>,
        sender: Sender<SocketAction>,
    ) {
        let Some(proxy_url) = socket_proxy_url(&self.socket_proxies, &host, port) else {
            tracing::warn!("Missing or invalid WebSocket proxy mapping");
            let _ = sender.try_send(SocketAction::Connect(handle, ConnectionState::Failed));
            return;
        };

        // Do not log proxy URLs or browser error details: they can contain tokens.
        let mut ws = match WebSocket::open(proxy_url.as_str()) {
            Ok(ws) => ws,
            Err(_) => {
                tracing::warn!("Failed to create WebSocket proxy connection");
                let _ = sender.try_send(SocketAction::Connect(handle, ConnectionState::Failed));
                return;
            }
        };

        self.spawn_future(Box::pin(async move {
            // Poll the outgoing channel too, so a local close/reconnect cancels a
            // pending handshake promptly. Preserve any writes queued before OPEN.
            let mut receiver = std::pin::pin!(receiver);
            let mut pending_writes = Vec::new();
            let mut pending_reads = Vec::new();
            let state = {
                let handshake = future::poll_fn(|cx| {
                    if receiver.is_closed() {
                        return Poll::Ready(ConnectionState::Failed);
                    }
                    while let Poll::Ready(message) = receiver.as_mut().poll_next(cx) {
                        match message {
                            Some(message) => pending_writes.push(message),
                            None => return Poll::Ready(ConnectionState::Failed),
                        }
                    }

                    // gloo's close callback wakes the stream, not the sink, and
                    // an early error may arrive while readyState is CONNECTING.
                    // Register both wakers and preserve any already queued data.
                    while let Poll::Ready(message) = ws.poll_next_unpin(cx) {
                        match message {
                            Some(Ok(message)) => pending_reads.push(message),
                            Some(Err(_)) | None => return Poll::Ready(ConnectionState::Failed),
                        }
                    }
                    if let Poll::Ready(Err(_)) = ws.poll_ready_unpin(cx) {
                        return Poll::Ready(ConnectionState::Failed);
                    }
                    // gloo's poll_ready is also Ok for CLOSING/CLOSED, so it
                    // cannot itself establish that the native handshake worked.
                    match ws.state() {
                        State::Open => Poll::Ready(ConnectionState::Connected),
                        State::Connecting => Poll::Pending,
                        State::Closing | State::Closed => Poll::Ready(ConnectionState::Failed),
                    }
                });
                match future::select(
                    std::pin::pin!(handshake),
                    std::pin::pin!(socket_timeout(timeout)),
                )
                .await
                {
                    Either::Left((state, _)) => state,
                    Either::Right((Ok(()), _)) => ConnectionState::TimedOut,
                    Either::Right((Err(()), _)) => ConnectionState::Failed,
                }
            };

            if state != ConnectionState::Connected {
                let _ = ws.close(None, None);
                let _ = sender.try_send(SocketAction::Connect(handle, state));
                return Ok(());
            }

            // OPEN proves target TCP readiness only for proxies that defer HTTP
            // 101 until their target connection succeeds (legacy proxies may not).
            if sender
                .try_send(SocketAction::Connect(handle, ConnectionState::Connected))
                .is_err()
            {
                let _ = ws.close(None, None);
                return Ok(());
            }

            let (mut ws_write, mut ws_read) = ws.split();
            let notify_close = 'connected: {
                for message in pending_reads {
                    match message {
                        Message::Bytes(buf) => {
                            if sender.try_send(SocketAction::Data(handle, buf)).is_err() {
                                break 'connected false;
                            }
                        }
                        Message::Text(_) => {
                            tracing::warn!("Server sent an unexpected text message");
                        }
                    }
                }
                for message in pending_writes {
                    if ws_write.send(Message::Bytes(message)).await.is_err() {
                        tracing::warn!("Failed to send message to WebSocket proxy");
                        break 'connected true;
                    }
                }

                loop {
                    match future::select(ws_read.next(), std::pin::pin!(receiver.recv())).await {
                        Either::Left((Some(Ok(Message::Bytes(buf))), _)) => {
                            if sender.try_send(SocketAction::Data(handle, buf)).is_err() {
                                break 'connected false;
                            }
                        }
                        Either::Left((Some(Ok(Message::Text(_))), _)) => {
                            tracing::warn!("Server sent an unexpected text message");
                        }
                        // EOF, an error, or a close event all produce exactly one
                        // remote Close action, including clean stream exhaustion.
                        Either::Left((Some(Err(_)) | None, _)) => break 'connected true,
                        Either::Right((Ok(message), _)) => {
                            if ws_write.send(Message::Bytes(message)).await.is_err() {
                                tracing::warn!("Failed to send message to WebSocket proxy");
                                break 'connected true;
                            }
                        }
                        // Local close is not a remote Close event.
                        Either::Right((Err(_), _)) => break 'connected false,
                    }
                }
            };

            let ws = ws_write
                .reunite(ws_read)
                .expect("both originate from the same websocket");
            let _ = ws.close(None, None);
            if notify_close {
                let _ = sender.try_send(SocketAction::Close(handle));
            }

            Ok(())
        }));
    }
}

struct WebResponseWrapper {
    rewritten_url: Option<String>,
    response: WebResponse,
    body_stream: Option<Rc<RefCell<ReadableStream>>>,
}

impl SuccessResponse for WebResponseWrapper {
    fn url(&self) -> Cow<'_, str> {
        self.rewritten_url
            .as_ref()
            .map(|url| Cow::<'_, str>::Borrowed(url))
            .unwrap_or_else(|| Cow::Owned(self.response.url()))
    }

    fn set_url(&mut self, url: String) {
        self.rewritten_url = Some(url);
    }

    fn body(self: Box<Self>) -> OwnedFuture<Vec<u8>, Error> {
        Box::pin(async move {
            let body = JsFuture::from(
                self.response
                    .array_buffer()
                    .map_err(|_| Error::FetchError("Got JS error".to_string()))?,
            )
            .await
            .map_err(|_| {
                Error::FetchError("Could not allocate array buffer for response".to_string())
            })?
            .dyn_into()
            .map_err(|_| {
                Error::FetchError("array_buffer result wasn't an ArrayBuffer".to_string())
            })?;
            let body = Uint8Array::new(&body).to_vec();

            Ok(body)
        })
    }

    fn text_encoding(&self) -> Option<&'static Encoding> {
        if let Ok(Some(content_type)) = self.response.headers().get("Content-Type") {
            get_encoding(&content_type)
        } else {
            None
        }
    }

    fn status(&self) -> u16 {
        self.response.status()
    }

    fn redirected(&self) -> bool {
        self.response.redirected()
    }

    #[expect(clippy::await_holding_refcell_ref)]
    fn next_chunk(&mut self) -> OwnedFuture<Option<Vec<u8>>, Error> {
        if self.body_stream.is_none() {
            let body = self.response.body();
            if body.is_none() {
                return Box::pin(async move { Ok(None) });
            }

            self.body_stream = Some(Rc::new(RefCell::new(ReadableStream::from_raw(
                body.expect("body").unchecked_into(),
            ))));
        }

        let body_stream = self.body_stream.clone().expect("web body stream");
        Box::pin(async move {
            let read_lock = body_stream.try_borrow_mut();
            if read_lock.is_err() {
                return Err(Error::FetchError(
                    "Concurrent read operations on the same stream are not supported.".to_string(),
                ));
            }

            let mut read_lock = read_lock.expect("web response reader");
            let mut body_reader = read_lock.get_reader();

            let chunk = body_reader.read();
            match chunk.await {
                Ok(Some(chunk)) => Ok(Some(Uint8Array::new(&chunk).to_vec())),
                Ok(None) => Ok(None),
                Err(_) => Err(Error::FetchError("Cannot read next chunk".to_string())), //TODO: JsValue to string?!
            }
        })
    }

    fn expected_length(&self) -> Result<Option<u64>, Error> {
        let length = self
            .response
            .headers()
            .get("Content-Length")
            .map_err(|js_err| {
                Error::FetchError(
                    (js_err + JsValue::from(""))
                        .as_string()
                        .expect("JavaScript String addition to yield String"),
                )
            })?;

        if let Some(length) = length {
            Ok(Some(length.parse::<u64>()?))
        } else {
            Ok(None)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::socket_proxy_url;
    use crate::SocketProxy;

    fn proxy(host: &str, port: u16, proxy_url: &str) -> SocketProxy {
        SocketProxy {
            host: host.to_string(),
            port,
            proxy_url: proxy_url.to_string(),
        }
    }

    #[test]
    fn socket_proxy_exact_mapping_precedes_wildcards_and_duplicates() {
        let proxies = [
            proxy(
                "*",
                0,
                "wss://relay.example/dynamic?host={host}&port={port}",
            ),
            proxy("game.example", 443, "ws://relay.example/first"),
            proxy("game.example", 443, "wss://relay.example/second"),
        ];
        assert_eq!(
            socket_proxy_url(&proxies, "game.example", 443)
                .unwrap()
                .as_str(),
            "ws://relay.example/first"
        );
        assert_eq!(
            socket_proxy_url(&proxies, "other.example", 8000)
                .unwrap()
                .as_str(),
            "wss://relay.example/dynamic?host=other.example&port=8000"
        );
    }

    #[test]
    fn socket_proxy_partial_wildcards_use_configuration_order() {
        let proxies = [
            proxy("game.example", 0, "wss://relay.example/by-host/{port}"),
            proxy("*", 443, "wss://relay.example/by-port/{host}"),
        ];
        assert_eq!(
            socket_proxy_url(&proxies, "game.example", 443)
                .unwrap()
                .as_str(),
            "wss://relay.example/by-host/443"
        );
        assert_eq!(
            socket_proxy_url(&proxies, "other.example", 443)
                .unwrap()
                .as_str(),
            "wss://relay.example/by-port/other.example"
        );
        assert!(socket_proxy_url(&proxies, "other.example", 8000).is_none());
        assert!(socket_proxy_url(&[], "game.example", 443).is_none());
    }

    #[test]
    fn socket_proxy_static_mapping_is_unchanged() {
        let proxies = [proxy("game.example", 443, "wss://relay.example/static")];
        assert_eq!(
            socket_proxy_url(&proxies, "game.example", 443)
                .unwrap()
                .as_str(),
            "wss://relay.example/static"
        );
        assert!(socket_proxy_url(&proxies, "GAME.example", 443).is_none());
        assert!(socket_proxy_url(&proxies, "game.example", 444).is_none());
    }

    #[test]
    fn socket_proxy_catch_all_requires_both_placeholders() {
        for template in [
            "wss://relay.example/static",
            "wss://relay.example/?host={host}",
            "wss://relay.example/?port={port}",
        ] {
            let proxies = [proxy("*", 0, template)];
            assert!(socket_proxy_url(&proxies, "game.example", 443).is_none());
        }
    }

    #[test]
    fn socket_proxy_substitution_encodes_ipv6_and_delimiters() {
        let proxies = [proxy(
            "*",
            0,
            "wss://relay.example/{host}/{port}?host={host}&port={port}",
        )];
        assert_eq!(
            socket_proxy_url(&proxies, "[2001:db8::1]", 65535)
                .unwrap()
                .as_str(),
            "wss://relay.example/%5B2001%3Adb8%3A%3A1%5D/65535?host=%5B2001%3Adb8%3A%3A1%5D&port=65535"
        );
        let host = "a b&port=1#/%+{port}例";
        let url = socket_proxy_url(&proxies, host, 8000).unwrap();
        assert_eq!(
            url.path(),
            "/a%20b%26port%3D1%23%2F%25%2B%7Bport%7D%E4%BE%8B/8000"
        );
        let pairs = url.query_pairs().collect::<Vec<_>>();
        assert_eq!(pairs.len(), 2);
        assert_eq!(pairs[0].0, "host");
        assert_eq!(pairs[0].1, host);
        assert_eq!(pairs[1].0, "port");
        assert_eq!(pairs[1].1, "8000");
    }

    #[test]
    fn socket_proxy_invalid_exact_mapping_does_not_fall_back() {
        for template in [
            "http://relay.example/tcp",
            "https://relay.example/tcp",
            "javascript:void(0)",
            "/relative-proxy",
            "ws://",
        ] {
            let proxies = [
                proxy("*", 0, "wss://relay.example/?host={host}&port={port}"),
                proxy("game.example", 443, template),
            ];
            assert!(socket_proxy_url(&proxies, "game.example", 443).is_none());
        }
    }
}
