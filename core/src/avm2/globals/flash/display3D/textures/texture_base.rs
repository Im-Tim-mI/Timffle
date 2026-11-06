//! Timffle: `flash.display3D.textures.TextureBase` natives.

use crate::avm2::Activation;
use crate::avm2::Error;
use crate::avm2::Value;
use crate::avm2::function::FunctionArgs;

/// `TextureBase.dispose()`: releases the GPU texture (the renderer drops it as
/// soon as the context no longer samples from it) and subtracts it from
/// `Context3D.totalGPUMemory`. Every later upload or use of the texture throws
/// Error #3694 ("The object was disposed by an earlier call of dispose() on it").
/// A plain `new TextureBase()` has no GPU texture, so dispose() is a no-op there.
pub fn dispose<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    if let Some(texture) = this.as_object().and_then(|o| o.as_texture()) {
        texture.dispose();
    }
    Ok(Value::Undefined)
}
