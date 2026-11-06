//! `flash.system.SecurityDomain` native methods

use crate::avm2::activation::Activation;
use crate::avm2::error::make_error_2012;
use crate::avm2::function::FunctionArgs;
use crate::avm2::object::SecurityDomainObject;
use crate::avm2::{ClassObject, Error, Object, Value};
use crate::string::AvmString;
use url::Url;

pub fn security_domain_allocator<'gc>(
    _class: ClassObject<'gc>,
    activation: &mut Activation<'_, 'gc>,
) -> Result<Object<'gc>, Error<'gc>> {
    Err(make_error_2012(activation, "SecurityDomain"))
}

pub fn instantiate_internal<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    Ok(SecurityDomainObject::new(activation).into())
}

/// Timffle: `SecurityDomain.domainID` (Flash Player 11.3): Flash Player 32
/// gives the SHA-256 of the calling SWF's host name as 64 upper-case hex digits
/// (measured: a SWF from `http://127.0.0.1:18865/` reads
/// `12CA17B4…`, the digest of "127.0.0.1"; the scheme and port are not part of it).
/// A local file has no host, so it is the digest of the empty string
/// (inferred, not measured).
pub fn get_domain_id<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    use sha2::{Digest, Sha256};
    use std::fmt::Write;

    let movie = activation.caller_movie_or_root();
    let host = Url::parse(movie.url())
        .ok()
        .and_then(|url| url.host_str().map(str::to_owned))
        .unwrap_or_default();
    let digest = Sha256::digest(host.as_bytes());
    let mut id = String::with_capacity(64);
    for byte in digest {
        let _ = write!(id, "{byte:02X}");
    }
    Ok(AvmString::new_utf8(activation.gc(), id).into())
}
