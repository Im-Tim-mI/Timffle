//! Timffle: `Texture.uploadCompressedTextureFromByteArray` and the CubeTexture
//! variant - decoding an ATF container into the texture.
//!
//! Flash's rules (Adobe AS3 Reference, `Texture.uploadCompressedTextureFromByteArray`):
//! "Texture Decoding Failed" (#3677) when the format cannot be derived from the
//! data or the ATF version is newer than the SWF allows ("ATF file version 2
//! requires SWF version 21 or newer and ATF file version 3 requires SWF version
//! 29 or newer"), "Texture Size Does Not Match" (#3679), "Texture Format
//! Mismatch" (#3675) when the decoded ATF holds no texture compatible with this
//! texture's format, RangeError "Bad Input Size" (#3669) when the ByteArray is
//! too short. A desktop Flash Player picks the DXT payload of the file; here
//! the payload matching the GPU texture's native block format is uploaded as-is
//! (DXT on adapters with BC support, ETC on adapters with ETC2 support) and a
//! texture stored as RGBA8 takes any payload, decoded on the CPU.

use super::atf_jpegxr;
use crate::avm2::activation::Activation;
use crate::avm2::bytearray::ByteArrayStorage;
use crate::avm2::error::{
    Error, make_error_3669_range, make_error_3675, make_error_3677, make_error_3679,
};
use crate::avm2::object::{Object, TextureObject};
use ruffle_render::atf::{ATFFormat, ATFTexture, ATFTextureData};
use ruffle_render::compressed::{self, CompressedFormat};

/// One decoded ATF level, as bytes in a known layout.
pub enum LevelData {
    /// Straight RGBA8 pixels.
    Rgba(Vec<u8>),
    /// Blocks of the given format.
    Blocks(CompressedFormat, Vec<u8>),
}

pub fn do_compressed_upload<'gc>(
    activation: &mut Activation<'_, 'gc>,
    texture: TextureObject<'gc>,
    data: Object<'gc>,
    byte_array_offset: usize,
    is_cube: bool,
) -> Result<(), Error<'gc>> {
    let bytes = data.as_bytearray().unwrap();
    let all = ByteArrayStorage::bytes(&bytes);
    // "byteArrayOffset + 6 exceeds the length of data" is a RangeError.
    if byte_array_offset.saturating_add(6) > all.len() {
        return Err(make_error_3669_range(activation));
    }
    let raw_atf = &all[byte_array_offset..];

    let atf_texture = match ATFTexture::from_bytes(raw_atf) {
        Ok(atf) => atf,
        Err(e) => {
            tracing::warn!("ATF decoding failed: {e}");
            return Err(make_error_3677(activation));
        }
    };

    let swf_version = activation.context.root_swf.version();
    if (atf_texture.version >= 3 && swf_version < 29)
        || (atf_texture.version == 2 && swf_version < 21)
    {
        return Err(make_error_3677(activation));
    }

    if atf_texture.width != texture.handle().width()
        || atf_texture.height != texture.handle().height()
    {
        return Err(make_error_3679(activation));
    }

    if is_cube != atf_texture.cubemap {
        return Err(make_error_3675(activation));
    }

    // Every face and every mip level the ATF file carries is uploaded (the
    // texture has a full mip chain).
    let storage = texture.handle().compressed_format();
    let num_faces = atf_texture.face_mip_data.len();
    let max_levels = texture.handle().mip_level_count() as usize;
    for face in 0..num_faces {
        for level in 0..atf_texture.face_mip_data[face].len().min(max_levels) {
            let level_w = (atf_texture.width >> level).max(1);
            let level_h = (atf_texture.height >> level).max(1);
            let data = &atf_texture.face_mip_data[face][level];
            let decoded = level_for_storage(data, &atf_texture.format, storage, level_w, level_h)
                .map_err(|e| match e {
                LevelError::Mismatch => {
                    tracing::warn!(
                        "ATF level {level} of face {face}: no payload for this texture format"
                    );
                    make_error_3675(activation)
                }
                LevelError::Decode(msg) => {
                    tracing::warn!("ATF level {level} of face {face}: {msg}");
                    make_error_3677(activation)
                }
            })?;
            let (bytes, w, h) = match decoded {
                LevelData::Rgba(bytes) => (bytes, level_w, level_h),
                LevelData::Blocks(_, bytes) => (bytes, level_w, level_h),
            };
            texture.context3d().copy_pixels_to_texture(
                &bytes,
                w,
                h,
                texture.handle(),
                face as u32,
                level as u32,
            );
        }
    }
    Ok(())
}

enum LevelError {
    /// The file has no payload the texture can take.
    Mismatch,
    Decode(String),
}

impl From<String> for LevelError {
    fn from(s: String) -> Self {
        LevelError::Decode(s)
    }
}

/// Produces the bytes the GPU texture takes for one level: the native block
/// payload when the texture stores blocks of that format, RGBA8 otherwise.
fn level_for_storage(
    data: &ATFTextureData,
    format: &ATFFormat,
    storage: Option<CompressedFormat>,
    width: u32,
    height: u32,
) -> Result<LevelData, LevelError> {
    match data {
        ATFTextureData::Raw {
            alpha,
            dxt,
            pvrtc,
            etc1,
            etc2,
        } => {
            let dxt_fmt = if *alpha {
                CompressedFormat::Dxt5
            } else {
                CompressedFormat::Dxt1
            };
            match storage {
                Some(CompressedFormat::Dxt1) | Some(CompressedFormat::Dxt5) => {
                    let want = storage.unwrap();
                    if want != dxt_fmt || dxt.is_empty() {
                        return Err(LevelError::Mismatch);
                    }
                    check_len(dxt, want, width, height)?;
                    Ok(LevelData::Blocks(want, dxt.clone()))
                }
                Some(CompressedFormat::Etc2Rgb) => {
                    if *alpha {
                        return Err(LevelError::Mismatch);
                    }
                    let blocks = if !etc2.is_empty() { etc2 } else { etc1 };
                    if blocks.is_empty() {
                        return Err(LevelError::Mismatch);
                    }
                    check_len(blocks, CompressedFormat::Etc2Rgb, width, height)?;
                    Ok(LevelData::Blocks(CompressedFormat::Etc2Rgb, blocks.clone()))
                }
                Some(CompressedFormat::Etc2Rgba) => {
                    if !*alpha {
                        return Err(LevelError::Mismatch);
                    }
                    if !etc2.is_empty() {
                        check_len(etc2, CompressedFormat::Etc2Rgba, width, height)?;
                        Ok(LevelData::Blocks(CompressedFormat::Etc2Rgba, etc2.clone()))
                    } else if !etc1.is_empty() {
                        // ETC1 has no alpha: wrap each block in an opaque EAC block.
                        check_len(etc1, CompressedFormat::Etc2Rgb, width, height)?;
                        Ok(LevelData::Blocks(
                            CompressedFormat::Etc2Rgba,
                            compressed::etc2_rgb_to_rgba_opaque(etc1),
                        ))
                    } else {
                        Err(LevelError::Mismatch)
                    }
                }
                None => {
                    // RGBA8 storage: decode whichever payload the file has.
                    let decoded = if !dxt.is_empty() {
                        if *alpha {
                            compressed::decode_dxt5(dxt, width, height)
                        } else {
                            compressed::decode_dxt1(dxt, width, height)
                        }
                    } else if !etc2.is_empty() {
                        if *alpha {
                            compressed::decode_etc2_rgba(etc2, width, height)
                        } else {
                            compressed::decode_etc2_rgb(etc2, width, height)
                        }
                    } else if !etc1.is_empty() {
                        compressed::decode_etc2_rgb(etc1, width, height)
                    } else if !pvrtc.is_empty() {
                        compressed::decode_pvrtc_4bpp(pvrtc, width, height)
                    } else {
                        return Err(LevelError::Mismatch);
                    };
                    decoded
                        .map(LevelData::Rgba)
                        .ok_or_else(|| LevelError::Decode("payload too short".into()))
                }
            }
        }
        ATFTextureData::JpegXR(_)
        | ATFTextureData::CompressedAlpha { .. }
        | ATFTextureData::CompressedDxt1 { .. } => {
            let decoded = atf_jpegxr::decode_jpegxr_level(data, width, height)?;
            match (&decoded, storage) {
                (LevelData::Rgba(_), None) => Ok(decoded),
                (LevelData::Rgba(_), Some(_)) => Err(LevelError::Mismatch),
                // The JPEG-XR formats only carry DXT; a texture stored as ETC2
                // cannot take them (Flash on such a device: format mismatch).
                (LevelData::Blocks(fmt, _), Some(want)) => {
                    if *fmt == want {
                        Ok(decoded)
                    } else {
                        Err(LevelError::Mismatch)
                    }
                }
                (LevelData::Blocks(fmt, bytes), None) => {
                    let rgba = match fmt {
                        CompressedFormat::Dxt1 => compressed::decode_dxt1(bytes, width, height),
                        CompressedFormat::Dxt5 => compressed::decode_dxt5(bytes, width, height),
                        CompressedFormat::Etc2Rgb => {
                            compressed::decode_etc2_rgb(bytes, width, height)
                        }
                        CompressedFormat::Etc2Rgba => {
                            compressed::decode_etc2_rgba(bytes, width, height)
                        }
                    };
                    rgba.map(LevelData::Rgba)
                        .ok_or_else(|| LevelError::Decode("payload too short".into()))
                }
            }
        }
        ATFTextureData::Unknown(_) => Err(LevelError::Decode(format!(
            "ATF format {format:?} (COMPRESSED_LOSSY) is not supported"
        ))),
    }
}

fn check_len(
    blocks: &[u8],
    format: CompressedFormat,
    width: u32,
    height: u32,
) -> Result<(), LevelError> {
    if blocks.len() < format.level_bytes(width, height) {
        Err(LevelError::Decode(format!(
            "{} bytes of {format:?} for {width}x{height}",
            blocks.len()
        )))
    } else {
        Ok(())
    }
}
