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

/// Timffle: `SecurityDomain.domainID` (Flash Player 11.3): a string naming
/// the security domain. Ruffle has one `SecurityDomain` object, standing for
/// the domain of the calling SWF, so the ID is that SWF's origin
/// (`scheme://host[:port]`, as `Security.pageDomain` spells it) — a local
/// file's origin is opaque, so a local SWF reads "file://". Adobe's reference
/// no longer documents this member and the exact text Flash gives was not
/// measured.
pub fn get_domain_id<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let movie = activation.caller_movie_or_root();
    let id = match Url::parse(movie.url()) {
        Ok(url) if url.origin().is_tuple() => url.origin().ascii_serialization(),
        Ok(url) => format!("{}://", url.scheme()),
        Err(_) => String::new(),
    };
    Ok(AvmString::new_utf8(activation.gc(), id).into())
}
