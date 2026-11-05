use crate::avm2::Activation;
use crate::avm2::Error;
use crate::avm2::Value;
use crate::avm2::function::FunctionArgs;
use crate::avm2::globals::flash::display3D::textures::atf_upload::do_compressed_upload;
use crate::avm2::parameters::ParametersExt;

use super::texture::{do_copy, do_copy_bitmap_data};

pub fn upload_from_byte_array<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    // Timffle: same path as Texture.uploadFromByteArray (the format's own
    // pixel layout for the given side and mip level).
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

    // Timffle: same ATF path as Texture (cube map faces, every format).
    let texture = this.as_texture().unwrap();
    texture.check_disposed(activation)?; // Timffle
    texture.context3d().check_disposed(activation)?;
    let data = args.get_object(activation, 0, "data")?;
    let byte_array_offset = args.get_u32(1) as usize;
    // Timffle: `async` is handled in CubeTexture.as (setTimeout + textureReady).

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
            // Timffle: any mip level, every format (see Texture.uploadFromBitmapData).
            do_copy_bitmap_data(activation, source, texture, side, mip_level)?;
        } else {
            unreachable!("Argument is BitmapData-typed");
        }
    }
    Ok(Value::Undefined)
}
