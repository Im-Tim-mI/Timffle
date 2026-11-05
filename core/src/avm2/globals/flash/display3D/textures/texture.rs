use ruffle_render::backend::Context3DTextureFormat;
use ruffle_render::compressed::{self, CompressedFormat};

use super::atf_upload::do_compressed_upload;
use crate::avm2::Activation;
use crate::avm2::Value;
use crate::avm2::error::{make_error_3669_range, make_error_3674, make_error_3675};
use crate::avm2::function::FunctionArgs;
use crate::avm2::object::TextureObject;
use crate::avm2::parameters::ParametersExt;
use crate::avm2::{Error, Object};
use crate::bitmap::bitmap_data::BitmapData;

// Timffle: the whole upload path below is Timffle's. Flash (Adobe AS3
// Reference, Texture.uploadFromBitmapData / uploadFromByteArray):
// "Miplevel Too Large" (ArgumentError #3674) when the level does not exist,
// "Bad Input Size" (RangeError #3669) when the ByteArray has too few bytes
// from `byteArrayOffset`, "Texture Format Mismatch" (ArgumentError #3675) for a
// COMPRESSED / COMPRESSED_ALPHA texture "on a mobile platform where runtime
// texture compression is not supported" - on the desktop the pixels are
// DXT-compressed at upload time, which is what we do (the GPU texture stores
// DXT blocks) or emulate (RGBA8 storage, pixels pass through the DXT codec so
// they lose exactly the precision Flash's compression loses); a texture that
// the backend stores as ETC2 is the mobile case and throws #3675.

/// Bytes `uploadFromByteArray` reads for one pixel of a texture format.
fn bytes_per_pixel(format: Context3DTextureFormat) -> usize {
    match format {
        Context3DTextureFormat::Bgra
        | Context3DTextureFormat::Compressed
        | Context3DTextureFormat::CompressedAlpha => 4,
        Context3DTextureFormat::BgraPacked | Context3DTextureFormat::BgrPacked => 2,
        Context3DTextureFormat::RgbaHalfFloat => 8,
    }
}

/// Checks `mip_level` and returns the level's size (Flash: "Miplevel Too Large").
pub fn level_size<'gc>(
    activation: &mut Activation<'_, 'gc>,
    texture: TextureObject<'gc>,
    mip_level: u32,
) -> Result<(u32, u32), Error<'gc>> {
    if mip_level >= texture.handle().mip_level_count() {
        return Err(make_error_3674(activation));
    }
    Ok((
        (texture.handle().width() >> mip_level).max(1),
        (texture.handle().height() >> mip_level).max(1),
    ))
}

fn f32_to_f16_bits(value: f32) -> u16 {
    // Round-to-nearest-even conversion for normal values in [0, 1] (what an
    // 8-bit channel produces); zero and subnormals fall out naturally.
    let bits = value.to_bits();
    let sign = ((bits >> 16) & 0x8000) as u16;
    let exp = ((bits >> 23) & 0xff) as i32 - 127 + 15;
    let mant = bits & 0x7f_ffff;
    if exp <= 0 {
        if exp < -10 {
            return sign;
        }
        let m = (mant | 0x80_0000) >> (1 - exp + 13);
        return sign | m as u16;
    }
    if exp >= 31 {
        return sign | 0x7c00;
    }
    let mut half = sign | ((exp as u16) << 10) | (mant >> 13) as u16;
    let round = mant & 0x1fff;
    if round > 0x1000 || (round == 0x1000 && half & 1 == 1) {
        half += 1;
    }
    half
}

/// Uploads straight RGBA8 pixels (`width` x `height`, at most the level's
/// size) into `side`/`mip_level` of `texture`, converted to what the texture
/// stores.
pub fn upload_rgba<'gc>(
    activation: &mut Activation<'_, 'gc>,
    texture: TextureObject<'gc>,
    mut rgba: Vec<u8>,
    width: u32,
    height: u32,
    side: u32,
    mip_level: u32,
) -> Result<(), Error<'gc>> {
    let (level_w, level_h) = level_size(activation, texture, mip_level)?;
    if width > level_w || height > level_h || width == 0 || height == 0 {
        // Flash: "Invalid BitmapData Error" - the image does not fit the level.
        return Err(make_error_3675(activation));
    }
    let format = texture.original_format();
    let storage = texture.handle().compressed_format();
    let bytes: Vec<u8> = match format {
        Context3DTextureFormat::Bgra => rgba,
        Context3DTextureFormat::BgrPacked => {
            compressed::quantize_rgb565(&mut rgba);
            rgba
        }
        Context3DTextureFormat::BgraPacked => {
            compressed::quantize_rgba4444(&mut rgba);
            rgba
        }
        Context3DTextureFormat::Compressed | Context3DTextureFormat::CompressedAlpha => {
            let alpha = matches!(format, Context3DTextureFormat::CompressedAlpha);
            match storage {
                Some(CompressedFormat::Dxt1) => compressed::encode_dxt1(&rgba, width, height),
                Some(CompressedFormat::Dxt5) => compressed::encode_dxt5(&rgba, width, height),
                Some(CompressedFormat::Etc2Rgb) | Some(CompressedFormat::Etc2Rgba) => {
                    return Err(make_error_3675(activation));
                }
                None => {
                    // RGBA8 storage: round-trip through the DXT codec so the
                    // sampled result matches a runtime-compressed texture.
                    let decoded = if alpha {
                        compressed::decode_dxt5(
                            &compressed::encode_dxt5(&rgba, width, height),
                            width,
                            height,
                        )
                    } else {
                        compressed::decode_dxt1(
                            &compressed::encode_dxt1(&rgba, width, height),
                            width,
                            height,
                        )
                    };
                    decoded.unwrap_or(rgba)
                }
            }
        }
        Context3DTextureFormat::RgbaHalfFloat => rgba
            .iter()
            .flat_map(|&c| f32_to_f16_bits(c as f32 / 255.0).to_le_bytes())
            .collect(),
    };
    texture.context3d().copy_pixels_to_texture(
        &bytes,
        width,
        height,
        texture.handle(),
        side,
        mip_level,
    );
    Ok(())
}

/// `uploadFromByteArray` for every texture format: the ByteArray holds one
/// full level in the format's own pixel layout (BGRA bytes; little-endian
/// 4-4-4-4 / 5-6-5 u16 for the packed formats; 4 half floats for
/// RGBA_HALF_FLOAT; BGRA bytes that get compressed for the compressed formats).
pub fn do_copy<'gc>(
    activation: &mut Activation<'_, 'gc>,
    data: Object<'gc>,
    texture: TextureObject<'gc>,
    byte_array_offset: u32,
    side: u32,
    mip_level: u32,
) -> Result<(), Error<'gc>> {
    let (width, height) = level_size(activation, texture, mip_level)?;
    let format = texture.original_format();
    let len = (width * height) as usize * bytes_per_pixel(format);
    let bytearray = data.as_bytearray().unwrap();
    let Ok(bytes) = bytearray.read_at(len, byte_array_offset as usize) else {
        return Err(make_error_3669_range(activation));
    };

    let rgba = match format {
        Context3DTextureFormat::Bgra
        | Context3DTextureFormat::Compressed
        | Context3DTextureFormat::CompressedAlpha => bytes
            .as_chunks::<4>()
            .0
            .iter()
            // The ByteArray is in BGRA format (straight alpha).
            .flat_map(|chunk| [chunk[2], chunk[1], chunk[0], chunk[3]])
            .collect(),
        Context3DTextureFormat::BgrPacked => compressed::rgb565_le_to_rgba(bytes),
        Context3DTextureFormat::BgraPacked => compressed::argb4444_le_to_rgba(bytes),
        Context3DTextureFormat::RgbaHalfFloat => {
            // Already the texture's own layout.
            let raw = bytes.to_vec();
            drop(bytearray);
            texture.context3d().copy_pixels_to_texture(
                &raw,
                width,
                height,
                texture.handle(),
                side,
                mip_level,
            );
            return Ok(());
        }
    };
    drop(bytearray);
    upload_rgba(activation, texture, rgba, width, height, side, mip_level)
}

/// `uploadFromBitmapData` for Texture and CubeTexture.
pub fn do_copy_bitmap_data<'gc>(
    activation: &mut Activation<'_, 'gc>,
    source: BitmapData<'gc>,
    texture: TextureObject<'gc>,
    side: u32,
    mip_level: u32,
) -> Result<(), Error<'gc>> {
    let (rgba, width, height) = {
        let sync = source.sync(activation.context.renderer);
        let raw = sync.borrow();
        (raw.pixels_rgba().to_vec(), raw.width(), raw.height())
    };
    upload_rgba(activation, texture, rgba, width, height, side, mip_level)
}

pub fn upload_compressed_texture_from_byte_array_internal<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    let texture = this.as_texture().unwrap();
    texture.check_disposed(activation)?; // Timffle
    texture.context3d().check_disposed(activation)?;
    let data = args.get_object(activation, 0, "data")?;
    let byte_array_offset = args.get_u32(1) as usize;

    // Timffle: every texture format takes an ATF whose payload matches
    // (`atf_upload` throws #3675 otherwise).
    do_compressed_upload(activation, texture, data, byte_array_offset, false)?;

    Ok(Value::Undefined)
}

pub fn upload_from_byte_array<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    let texture = this.as_texture().unwrap();
    texture.check_disposed(activation)?; // Timffle
    texture.context3d().check_disposed(activation)?;
    let data = args.get_object(activation, 0, "data")?;
    let byte_array_offset = args.get_u32(1);
    let mip_level = args.get_u32(2);

    do_copy(activation, data, texture, byte_array_offset, 0, mip_level)?;
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
            let mip_level = args.get_u32(1);
            // Timffle: any level of the mip chain, every texture format.
            do_copy_bitmap_data(activation, source, texture, 0, mip_level)?;
        } else {
            unreachable!("Argument is BitmapData-typed");
        }
    }
    Ok(Value::Undefined)
}
