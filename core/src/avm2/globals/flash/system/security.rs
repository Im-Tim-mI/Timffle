//! `flash.system.Security` native methods

use crate::avm2::Error;
use crate::avm2::activation::Activation;
use crate::avm2::error::make_error_2052;
use crate::avm2::function::FunctionArgs;
use crate::avm2::value::Value;
use crate::avm2_stub_method;
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

pub fn load_policy_file<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    avm2_stub_method!(activation, "flash.system.Security", "loadPolicyFile");
    Ok(Value::Undefined)
}

pub fn show_settings<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    avm2_stub_method!(activation, "flash.system.Security", "showSettings");
    Ok(Value::Undefined)
}
