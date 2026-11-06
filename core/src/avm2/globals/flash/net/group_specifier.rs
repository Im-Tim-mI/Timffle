//! Timffle: natives of `flash.net.GroupSpecifier` (and `NetGroup`'s group
//! addresses): UTF-8 hex, SHA-256 and strong random bytes.

use crate::avm2::function::FunctionArgs;
use crate::avm2::parameters::ParametersExt;
use crate::avm2::{Activation, Error, Value};
use crate::string::AvmString;
use rand::{TryRng, rngs::SysRng};
use sha2::{Digest, Sha256};

pub fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

pub fn sha256_hex_of(bytes: &[u8]) -> String {
    hex(&Sha256::digest(bytes))
}

pub fn utf8hex<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let text = args.get_string(activation, 0).to_string();
    Ok(AvmString::new_utf8(activation.gc(), hex(text.as_bytes())).into())
}

pub fn sha256hex<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let text = args.get_string(activation, 0).to_string();
    Ok(AvmString::new_utf8(activation.gc(), sha256_hex_of(text.as_bytes())).into())
}

pub fn random_hex<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let count = args.get_u32(0).min(1024) as usize;
    let mut bytes = vec![0u8; count];
    let mut rng = SysRng {};
    rng.try_fill_bytes(&mut bytes[..])
        .expect("system random source");
    Ok(AvmString::new_utf8(activation.gc(), hex(&bytes)).into())
}
