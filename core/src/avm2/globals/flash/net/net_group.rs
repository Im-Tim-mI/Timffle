//! Timffle: natives of `flash.net.NetGroup`.

use crate::avm2::error::{Error2004Type, make_error_2004};
use crate::avm2::function::FunctionArgs;
use crate::avm2::globals::flash::net::group_specifier::sha256_hex_of;
use crate::avm2::parameters::ParametersExt;
use crate::avm2::{Activation, Error, Value};
use crate::string::AvmString;

/// `convertPeerIDToGroupAddress(peerID)`: a group address is the SHA-256 of
/// the peer ID's 32 bytes, as hex. A peer ID that is not 64 hex digits is
/// ArgumentError #2004.
pub fn convert_peer_id_to_group_address<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let peer_id = args.get_string_non_null(activation, 0, "peerID")?;
    let peer_id = peer_id.to_string();
    if peer_id.len() != 64 || !peer_id.bytes().all(|b| b.is_ascii_hexdigit()) {
        return Err(make_error_2004(activation, Error2004Type::ArgumentError));
    }
    let bytes: Vec<u8> = (0..32)
        .map(|i| u8::from_str_radix(&peer_id[i * 2..i * 2 + 2], 16).unwrap_or(0))
        .collect();
    Ok(AvmString::new_utf8(activation.gc(), sha256_hex_of(&bytes)).into())
}
