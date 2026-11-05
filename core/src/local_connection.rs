use crate::avm1::Object as Avm1Object;
use crate::avm1::globals::local_connection::LocalConnection as Avm1LocalConnectionObject;
use crate::avm2::Domain as Avm2Domain;
use crate::avm2::object::LocalConnectionObject;
use crate::context::UpdateContext;
use crate::string::AvmString;
use flash_lso::types::Value as AmfValue;
use fnv::FnvHashMap;
use gc_arena::Collect;
use gc_arena::collect::Trace;
use ruffle_macros::istr;
use ruffle_wstr::{WStr, WString};
use std::borrow::Cow;

#[derive(Clone, Collect)]
#[collect(no_drop)]
pub enum LocalConnectionKind<'gc> {
    Avm2(Avm2Domain<'gc>, LocalConnectionObject<'gc>),
    Avm1(Avm1Object<'gc>),
}

impl<'gc> From<(Avm2Domain<'gc>, LocalConnectionObject<'gc>)> for LocalConnectionKind<'gc> {
    fn from(obj: (Avm2Domain<'gc>, LocalConnectionObject<'gc>)) -> Self {
        Self::Avm2(obj.0, obj.1)
    }
}

impl<'gc> From<Avm1Object<'gc>> for LocalConnectionKind<'gc> {
    fn from(obj: Avm1Object<'gc>) -> Self {
        Self::Avm1(obj)
    }
}

impl<'gc> LocalConnectionKind<'gc> {
    pub fn send_status(&self, status: AvmString<'gc>, context: &mut UpdateContext<'gc>) {
        match self {
            LocalConnectionKind::Avm2(_domain, object) => {
                object.send_status(context, status);
            }
            LocalConnectionKind::Avm1(object) => {
                if let Err(e) = Avm1LocalConnectionObject::send_status(context, *object, status) {
                    tracing::error!("Unhandled AVM1 error during LocalConnection onStatus: {e}");
                }
            }
        }
    }

    pub fn run_method(
        &self,
        context: &mut UpdateContext<'gc>,
        method_name: AvmString<'gc>,
        arguments: Vec<AmfValue>,
    ) {
        match self {
            LocalConnectionKind::Avm2(domain, object) => {
                object.run_method(context, *domain, method_name, arguments);
            }
            LocalConnectionKind::Avm1(object) => {
                if let Err(e) =
                    Avm1LocalConnectionObject::run_method(context, *object, method_name, arguments)
                {
                    tracing::error!("Unhandled AVM1 error during LocalConnection onStatus: {e}");
                }
            }
        }
    }
}

#[derive(Collect)]
#[collect(no_drop)]
pub struct QueuedMessage<'gc> {
    source: LocalConnectionKind<'gc>,
    kind: QueuedMessageKind<'gc>,
}

#[derive(Collect)]
#[collect(no_drop)]
pub enum QueuedMessageKind<'gc> {
    Failure,
    Message {
        /// Timffle: false for a message sent between frames to a name nobody
        /// listened to yet (see `LocalConnections::send`); such a message waits
        /// for a receiver until the end of the second frame after it was sent.
        listened_at_send: bool,
        #[collect(require_static)]
        retries_left: u8,
        #[collect(require_static)]
        connection_name: WString,
        method_name: AvmString<'gc>,
        #[collect(require_static)]
        arguments: Vec<AmfValue>,
        /// Timffle: the URL of the SWF that sent the message, checked against
        /// the receiver's `allowDomain()` lists on delivery.
        #[collect(require_static)]
        sender_url: String,
    },
}

impl<'gc> QueuedMessageKind<'gc> {
    pub fn deliver(self, source: LocalConnectionKind<'gc>, context: &mut UpdateContext<'gc>) {
        match self {
            QueuedMessageKind::Failure => {
                source.send_status(istr!(context, "error"), context);
            }
            QueuedMessageKind::Message {
                listened_at_send,
                retries_left,
                connection_name,
                method_name,
                arguments,
                sender_url,
            } => {
                if let Some(receiver) = context.local_connections.find_listener(&connection_name) {
                    // Timffle: a receiver that did not allow the sender's domain
                    // refuses the call; the sender sees a `status` event with
                    // level `error`, like Flash (AVM1 receivers are not checked).
                    if let LocalConnectionKind::Avm2(_, receiver_object) = &receiver
                        && !receiver_object.accepts_sender(&sender_url)
                    {
                        source.send_status(istr!(context, "error"), context);
                        return;
                    }
                    let level = if listened_at_send {
                        istr!(context, "status")
                    } else {
                        istr!(context, "error")
                    };
                    source.send_status(level, context);
                    receiver.run_method(context, method_name, arguments);
                } else if retries_left > 0 {
                    context.local_connections.messages.push(QueuedMessage {
                        source,
                        kind: QueuedMessageKind::Message {
                            listened_at_send,
                            retries_left: retries_left - 1,
                            connection_name,
                            method_name,
                            arguments,
                            sender_url,
                        },
                    });
                } else {
                    source.send_status(istr!(context, "error"), context);
                }
            }
        }
    }
}

/// An opaque handle to an actively listening LocalConnection.
/// Owning this handle represents ownership of a LocalConnection;
/// However, a LocalConnection must be manually closed, you can't just Drop this handle.
#[derive(Debug)]
pub struct LocalConnectionHandle(WString);

/// Manages the collection of local connections.
pub struct LocalConnections<'gc> {
    connections: FnvHashMap<WString, LocalConnectionKind<'gc>>,
    messages: Vec<QueuedMessage<'gc>>,
}

// TODO(moulins): use gc_arena::Static to avoid unsafe impl?
unsafe impl<'gc> Collect<'gc> for LocalConnections<'gc> {
    fn trace<C: Trace<'gc>>(&self, cc: &mut C) {
        for v in self.connections.values() {
            cc.trace(v);
        }
        cc.trace(&self.messages);
    }
}

impl<'gc> LocalConnections<'gc> {
    pub fn empty() -> Self {
        Self {
            connections: Default::default(),
            messages: Default::default(),
        }
    }

    pub fn connect<C: Into<LocalConnectionKind<'gc>>>(
        &mut self,
        domain: &str,
        connection: C,
        name: &WStr,
    ) -> Option<LocalConnectionHandle> {
        let key = if name.starts_with(b'_') {
            name.to_ascii_lowercase()
        } else {
            let mut key = WString::from_utf8(Self::get_superdomain(domain));
            key.push_char(':');
            key.push_str(name);
            key.make_ascii_lowercase();
            key
        };

        if self.connections.contains_key(&key) {
            None
        } else {
            self.connections.insert(key.to_owned(), connection.into());
            Some(LocalConnectionHandle(key))
        }
    }

    pub fn close(&mut self, handle: LocalConnectionHandle) {
        self.connections.remove(&handle.0);
    }

    /// Queue a `send()` from the SWF at `sender_url`, whose domain is `domain`.
    pub fn send<C: Into<LocalConnectionKind<'gc>>>(
        &mut self,
        domain: &str,
        sender_url: &str,
        source: C,
        connection_name: AvmString<'gc>,
        method_name: AvmString<'gc>,
        arguments: Vec<AmfValue>,
    ) {
        // There's two checks for "is connected":
        // 1 - At `send()` time, if there's no connections, just immediately queue up a failure
        // 2 - At `update_connections()` time, if the connection couldn't be found, queue up a failure
        // Even if one becomes available between send and update, it won't be used
        // Similarly, if one becomes unavailable between send and update, it'll error
        // If something *else* takes its place between send and update, it'll use that instead
        //
        // Timffle: except for a message sent between frames (from a download's
        // `complete`, a timer...) to a name nobody listens to yet: it waits for a
        // receiver until the end of the second frame (a frame script runs after the
        // delivery step of its frame) and is then delivered with the `error` status
        // of check 1. Flash Player 32 delivers it to AVM1 content that an AVM2
        // `Loader` added in `complete` and that connects in its first frame
        // (`mixed_avm/avm2_loads_avm1_v9`/`_v10`); a send and a `connect()` inside one
        // frame keep check 1 (`avm2/localconnection`, also Flash).

        let connection_name = Self::qualified_name(domain, &connection_name);

        let listening = self.find_listener(&connection_name).is_some();
        let kind = if listening || !crate::player::is_running_frame() {
            QueuedMessageKind::Message {
                listened_at_send: listening,
                retries_left: if listening { 0 } else { 1 },
                connection_name,
                method_name,
                arguments,
                sender_url: sender_url.to_string(),
            }
        } else {
            QueuedMessageKind::Failure
        };
        self.messages.push(QueuedMessage {
            source: source.into(),
            kind,
        });
    }

    /// The name a message to `connection_name` is actually addressed to:
    /// lowercased, and prefixed with the sender's superdomain unless it already
    /// has a prefix or starts with an underscore.
    pub fn qualified_name(domain: &str, connection_name: &WStr) -> WString {
        let mut connection_name = connection_name.to_ascii_lowercase();
        if !connection_name.contains(b':') && !connection_name.starts_with(b'_') {
            let mut result = WString::from_utf8(Self::get_superdomain(domain));
            result.push_char(':');
            result.push_str(&connection_name);
            connection_name = result;
        }
        connection_name
    }

    /// Whether something is listening on this (already qualified) name.
    pub fn has_listener(&self, qualified_name: &WStr) -> bool {
        self.find_listener(qualified_name).is_some()
    }

    fn find_listener(&self, name: &WStr) -> Option<LocalConnectionKind<'gc>> {
        self.connections.get(name).cloned()
    }

    pub fn update_connections(context: &mut UpdateContext<'gc>) {
        if context.local_connections.messages.is_empty() {
            return;
        }

        for message in std::mem::take(&mut context.local_connections.messages) {
            message.kind.deliver(message.source, context);
        }
    }

    pub fn get_domain(url: &str) -> Cow<'static, str> {
        if let Ok(url) = url::Url::parse(url) {
            if url.scheme() == "file" {
                Cow::Borrowed("localhost")
            } else if let Some(domain) = url.host_str() {
                Cow::Owned(domain.to_owned())
            } else {
                // no domain?
                Cow::Borrowed("localhost")
            }
        } else {
            tracing::error!("LocalConnection: Unable to parse movie URL: {url}");
            Cow::Borrowed("unknown") // this is surely an error but it'll hopefully highlight this case in issues for us
        }
    }

    pub fn get_superdomain(domain: &str) -> &str {
        if domain.parse::<std::net::IpAddr>().is_ok() {
            return domain;
        }
        domain.rsplit_once('.').map(|(_, b)| b).unwrap_or(domain)
    }
}
