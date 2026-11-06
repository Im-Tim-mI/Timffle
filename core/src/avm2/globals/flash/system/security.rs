//! `flash.system.Security` native methods

use crate::avm2::Error;
use crate::avm2::activation::Activation;
use crate::avm2::error::{make_error_2052, make_error_2054};
use crate::avm2::function::FunctionArgs;
use crate::avm2::parameters::ParametersExt;
use crate::avm2::value::Value;
use crate::backend::navigator::Request;
use crate::string::AvmString;
use url::Url;

use ruffle_common::sandbox::SandboxType;

pub fn get_page_domain<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    if let Some(url) = activation
        .context
        .page_url
        .as_ref()
        .and_then(|page_url| Url::parse(page_url).ok())
    {
        if !url.origin().is_tuple() {
            tracing::warn!("flash.system.Security.pageDomain: Returning null for opaque origin");
            return Ok(Value::Null);
        }

        let mut domain = url.origin().ascii_serialization();
        domain.push('/'); // Add trailing slash that is used by Flash, but isn't part of a standard origin.
        Ok(AvmString::new_utf8(activation.gc(), domain).into())
    } else {
        tracing::warn!("flash.system.Security.pageDomain: No page-url available");
        Ok(Value::Null)
    }
}

pub fn get_sandbox_type<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let movie = activation
        .caller_movie()
        .expect("Caller movie expected for sandboxType");
    let sandbox_type = match movie.sandbox_type() {
        SandboxType::Remote => "remote",
        SandboxType::LocalWithFile => "localWithFile",
        SandboxType::LocalWithNetwork => "localWithNetwork",
        SandboxType::LocalTrusted => "localTrusted",
        SandboxType::Application => "application",
    };
    Ok(AvmString::new_utf8(activation.gc(), sandbox_type).into())
}

// Timffle: `Security.allowDomain()` / `allowInsecureDomain()` record the
// domains on the calling SWF (`SwfMovieData::allow_domains`). Ruffle does not
// enforce cross-scripting sandboxes, so the lists only feed what Flash
// exposes about them: `LoaderInfo.childAllowsParent`, `parentAllowsChild`
// and `isURLInaccessible`.
fn allow_domains_impl<'gc>(
    activation: &mut Activation<'_, 'gc>,
    args: FunctionArgs<'_, 'gc>,
    insecure: bool,
) -> Result<Value<'gc>, Error<'gc>> {
    let mut domains = Vec::with_capacity(args.len());
    for arg in args {
        // Flash tests the type: null, numbers and objects are ArgumentError #2052.
        match arg {
            Value::String(domain) => domains.push(domain.to_string()),
            _ => return Err(make_error_2052(activation)),
        }
    }
    activation
        .caller_movie_or_root()
        .allow_domains(domains.iter().map(String::as_str), insecure);
    Ok(Value::Undefined)
}

pub fn allow_domain<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    allow_domains_impl(activation, args, false)
}

pub fn allow_insecure_domain<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    allow_domains_impl(activation, args, true)
}

/// Timffle: `Security.exactSettings` (default true). With `false` the player
/// uses the Flash Player 6 "superdomain" rule when it chooses settings for a
/// domain — storage for persistent shared objects here (`SharedObject.getLocal`,
/// shared_object.rs), where www.example.com and store.example.com then share
/// example.com's. Once settings have been chosen with it the value is fixed:
/// changing it is `SecurityError #2054` (assigning the value it already has is
/// not a change).
pub fn get_exact_settings<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    Ok(activation.avm2().security_exact_settings.into())
}

pub fn set_exact_settings<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let value = args.get_bool(0);
    let current = activation.avm2().security_exact_settings;
    let used = activation.avm2().security_exact_settings_used;
    if value != current {
        if used {
            return Err(make_error_2054(activation));
        }
        activation.avm2().security_exact_settings = value;
    }
    Ok(Value::Undefined)
}

/// Timffle: `Security.disableAVM1Loading` (Flash Player 10.1, default false).
/// While true, a `Loader` refuses ActionScript 1.0/2.0 SWFs with
/// `securityError` #2111 (see `loader.rs`). Flash lets only an AS3 SWF that
/// can reach the stage set it (`SecurityError #2110`); every AVM2 caller here
/// is an AS3 SWF, and Ruffle does not model stage access denial, so the
/// assignment is accepted.
pub fn get_disable_avm1loading<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    Ok(activation.avm2().security_disable_avm1_loading.into())
}

pub fn set_disable_avm1loading<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let value = args.get_bool(0);
    activation.avm2().security_disable_avm1_loading = value;
    Ok(Value::Undefined)
}

/// Timffle: `Security.loadPolicyFile(url)`. This player does not enforce
/// cross-domain policy files (the browser's CORS rules apply instead), so the
/// call cannot grant or deny anything; it does what is observable from
/// outside: the URL is recorded (`url` null is `TypeError #2007`) and an
/// `http`/`https` policy file is requested once, the way Flash fetches a
/// policy file the first time it is needed, with the answer discarded. An
/// `xmlsocket://` URL names a socket policy server; without a socket policy
/// check there is nothing to ask it, so the URL is only recorded.
pub fn load_policy_file<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let url = args.get_string_non_null(activation, 0, "url")?;
    let url = url.to_string();
    if activation.avm2().policy_files_requested.contains(&url) {
        return Ok(Value::Undefined);
    }
    activation.avm2().policy_files_requested.push(url.clone());

    let Ok(resolved) = activation.context.navigator.resolve_url(&url) else {
        return Ok(Value::Undefined);
    };
    if matches!(resolved.scheme(), "http" | "https") {
        let request = Request::get(resolved.to_string());
        let fetch = activation.context.navigator.fetch(request);
        activation
            .context
            .navigator
            .spawn_future(Box::pin(async move {
                // The policy file is not enforced, so its contents are not kept.
                let _ = fetch.await;
                Ok(())
            }));
    }
    Ok(Value::Undefined)
}

/// Timffle: `Security.showSettings(panel)` opens the Flash Player Settings
/// panel (camera, microphone, storage, privacy) drawn by the player itself.
/// This player has no such panel — its settings live in the browser and the
/// extension's options page — so, as Flash does where the panel cannot be
/// shown (the Reference: in AIR "calling it has no effect"), the call does
/// nothing and throws nothing, whatever `panel` says.
pub fn show_settings<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    Ok(Value::Undefined)
}
