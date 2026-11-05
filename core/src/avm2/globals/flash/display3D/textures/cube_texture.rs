use ruffle_render::backend::Context3DTextureFormat;

use crate::avm2::Activation;
use crate::avm2::Error;
use crate::avm2::Value;
use crate::avm2::error::make_error_3669;
use crate::avm2::function::FunctionArgs;
use crate::avm2::globals::flash::display3D::textures::atf_jpegxr::do_compressed_upload;
use crate::avm2::parameters::ParametersExt;
use crate::avm2_stub_method;

use super::texture::do_copy;

pub fn upload_from_byte_array<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    // Timffle: same path as Texture.uploadFromByteArray (BGRA bytes of the
    // given side and mip level), no longer marked untested.
    let texture = this.as_texture().unwrap();
    texture.check_disposed(activation)?; // Timffle
    texture.context3d().check_disposed(activation)?;
    let data = args.get_object(activation, 0, "data")?;
    let byte_array_offset = args.get_u32(1);
    let side = args.get_u32(2);
    let mip_level = args.get_u32(3);

    do_copy(
        activation,
        data,
        texture,
        byte_array_offset,
        side,
        mip_level,
    )?;
    Ok(Value::Undefined)
}

pub fn upload_compressed_texture_from_byte_array_internal<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    // Timffle: same ATF path as Texture (cube map faces), no longer marked untested.
    let texture = this.as_texture().unwrap();
    texture.check_disposed(activation)?; // Timffle
    texture.context3d().check_disposed(activation)?;
    let data = args.get_object(activation, 0, "data")?;
    let byte_array_offset = args.get_u32(1) as usize;
    // Timffle: `async` is handled in CubeTexture.as (setTimeout + textureReady).

    if !matches!(texture.original_format(), Context3DTextureFormat::Bgra) {
        avm2_stub_method!(
            activation,
            "flash.display3D.textures.CubeTexture",
            "uploadCompressedTextureFromByteArray",
            "with unsupported format"
        );
        return Ok(Value::Undefined);
    }

    do_compressed_upload(activation, texture, data, byte_array_offset, true)?;
    Ok(Value::Undefined)
}

pub fn upload_from_bitmap_data<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(texture) = this.as_texture() {
        texture.check_disposed(activation)?; // Timffle
        texture.context3d().check_disposed(activation)?;
        let source_obj = args.get_object(activation, 0, "source")?;

        if let Some(source) = source_obj.as_bitmap_data() {
            let side = args.get_u32(1);
            let mip_level = args.get_u32(2);
            // Timffle: any mip level (see Texture.uploadFromBitmapData).
            if mip_level >= texture.handle().mip_level_count() {
                return Err(make_error_3669(activation));
            }
            texture.context3d().copy_bitmapdata_to_texture(
                &source.sync(activation.context.renderer).borrow(),
                texture.handle(),
                side,
                mip_level,
            );
        } else {
            unreachable!("Argument is BitmapData-typed");
        }
    }
    Ok(Value::Undefined)
}
