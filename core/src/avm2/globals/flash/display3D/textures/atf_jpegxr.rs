//! Timffle: the JPEG-XR based ATF payloads (formats 0/1 RGB(A) JPEG-XR,
//! 2 COMPRESSED and 4 COMPRESSED_ALPHA) decoded into RGBA8 pixels or DXT
//! blocks. The container itself and the raw payloads are handled in
//! `atf_upload`, which is compiled without the `jpegxr` feature too.

use super::atf_upload::LevelData;
use ruffle_render::atf::ATFTextureData;
use ruffle_render::compressed::CompressedFormat;
use std::io::Cursor;

use jpegxr::PixelFormat;
use std::io::Read;
use std::io::Seek;

/// One face/level of an ATF file as the bytes the GPU texture takes (RGBA8
/// for JPEG-XR levels, DXT1/DXT5 blocks for the compressed formats).
pub fn decode_jpegxr_level(
    data: &ATFTextureData,
    width: u32,
    height: u32,
) -> Result<LevelData, String> {
    let atf_texture_width = width;
    let atf_texture_height = height;
    // Timffle: the block-based formats store whole 4x4 blocks, so mip levels
    // smaller than a block (2x2, 1x1) still hold one block per dimension.
    let blocks_w = width.div_ceil(4);
    let blocks_h = height.div_ceil(4);
    match data {
        ATFTextureData::JpegXR(bytes) => {
            let image = jpegxr_to_tiff(
                atf_texture_width,
                atf_texture_height,
                &mut Cursor::new(bytes),
            )?
            .0;
            Ok(LevelData::Rgba(
                image.to_rgba8().pixels().flat_map(|p| p.0).collect(),
            ))
        }
        ATFTextureData::CompressedAlpha {
            dxt1_alpha_compressed,
            jpegxr_alpha: orig_jpegxr_alpha,
            dxt5_rgb_compressed,
            jpegxr_bgr: orig_jpegxr_bgr,
        } => {
            // See https://github.com/adobe/dds2atf/issues/5
            // The ATF format uses a weird version of LZMA that doesn't store the uncompressed length.
            // Compute it ourselves, and insert it where it should be
            let dxt1_alpha = atf_lzma_decompress(dxt1_alpha_compressed)?;
            let dxt5_rgb = atf_lzma_decompress(dxt5_rgb_compressed)?;

            // 'COMPRESSED_ALPHA' images are encoded in a very strange way. The LZMA-compressed DXT1/DXT5
            // sections just hold the DXT lookup table block. The associated values for each block
            // are stored in JPEG-XR images, which are optionally compressed
            let (jpegxr_alpha, pixel_format) =
                jpegxr_to_tiff(blocks_w, blocks_h * 2, &mut Cursor::new(orig_jpegxr_alpha))?;

            let jpegxr_alpha = jpegxr_alpha.to_rgba8();
            if pixel_format != PixelFormat::PixelFormat8bppGray {
                return Err("Unexpected JPEG-XR alpha format".into());
            }

            let jpegxr_bgr =
                jpegxr_to_raw_pixels(blocks_w, blocks_h * 2, &mut Cursor::new(orig_jpegxr_bgr))?;

            let mut reconstructed_dxt = vec![];

            if dxt1_alpha.len() / 6 != dxt5_rgb.len() / 4 {
                return Err("Bad DXT data".into());
            }
            if jpegxr_alpha.as_raw().len() / 8 != jpegxr_bgr.len() / 4 {
                return Err("Bad JPEG-XR data".into());
            }
            if dxt1_alpha.len() / 6 != jpegxr_alpha.as_raw().len() / 8 {
                return Err("Dxt data doesn't match jpegxr data".into());
            }

            let second_half = (blocks_w * blocks_h) as usize;

            // The two values for each pixels are split across the upper and lower halves of the image.
            // See https://github.com/adobe/dds2atf/blob/cbc479be2e77daa273306161af571f8255aec78d/pvr2atfcore.cpp#L884
            for i in 0..(dxt1_alpha.len() / 6) {
                let alpha_lookup_table = &dxt1_alpha[i * 6..(i + 1) * 6];
                let jpegxr_alpha_first = &jpegxr_alpha.as_raw()[i * 4..(i + 1) * 4];
                let jpegxr_alpha_second =
                    &jpegxr_alpha.as_raw()[(second_half + (i * 4))..(second_half + ((i + 1) * 4))];

                let rgb_lookup_table = &dxt5_rgb[i * 4..(i + 1) * 4];
                let jpegxr_bgr_first = &jpegxr_bgr[(i * 2)..((i + 1) * 2)];
                // Each pixel is 2 bytes, so multiply second_half by 2 to get the correct
                // start of the second half of the image
                let jpegxr_bgr_second =
                    &jpegxr_bgr[(second_half * 2 + (i * 2))..(second_half * 2 + ((i + 1) * 2))];

                // We decoded as grayscale, so just use the red values (all of the rgb values
                // should be the same)
                reconstructed_dxt.push(jpegxr_alpha_first[0]);
                reconstructed_dxt.push(jpegxr_alpha_second[0]);
                // Copy the corresponding lookup table
                reconstructed_dxt.extend(alpha_lookup_table);

                // Copy the two 16-bit values
                reconstructed_dxt.extend(jpegxr_bgr_first);
                reconstructed_dxt.extend(jpegxr_bgr_second);

                // Copy the lookup table
                reconstructed_dxt.extend(rgb_lookup_table);
            }

            Ok(LevelData::Blocks(CompressedFormat::Dxt5, reconstructed_dxt))
        }
        // Timffle: COMPRESSED (DXT1) is the RGB half of the layout above: an
        // LZMA stream of 4-byte lookup tables plus a JPEG-XR image whose upper
        // and lower halves hold the two 16-bit endpoint colours of each block.
        ATFTextureData::CompressedDxt1 {
            dxt1_lookup_compressed,
            jpegxr_rgb,
        } => {
            let lookup = atf_lzma_decompress(dxt1_lookup_compressed)?;
            let colors =
                jpegxr_to_raw_pixels(blocks_w, blocks_h * 2, &mut Cursor::new(jpegxr_rgb))?;
            let num_blocks = lookup.len() / 4;
            if colors.len() / 4 != num_blocks {
                return Err("DXT1 lookup data doesn't match jpegxr data".into());
            }
            let second_half = (blocks_w * blocks_h) as usize;
            let mut reconstructed = Vec::with_capacity(num_blocks * 8);
            for i in 0..num_blocks {
                reconstructed.extend(&colors[i * 2..(i + 1) * 2]);
                reconstructed
                    .extend(&colors[second_half * 2 + i * 2..second_half * 2 + (i + 1) * 2]);
                reconstructed.extend(&lookup[i * 4..(i + 1) * 4]);
            }
            Ok(LevelData::Blocks(CompressedFormat::Dxt1, reconstructed))
        }
        ATFTextureData::Raw { .. } | ATFTextureData::Unknown(_) => {
            Err("not a JPEG-XR payload".into())
        }
    }
}

// Timffle: ATF's LZMA streams omit the uncompressed length; insert "unknown".
fn atf_lzma_decompress(compressed: &[u8]) -> Result<Vec<u8>, String> {
    if compressed.len() < 5 {
        return Err("LZMA stream too short".into());
    }
    let mut with_len = compressed.to_vec();
    with_len.splice(5..5, u64::MAX.to_le_bytes());
    let mut out = Vec::with_capacity(compressed.len() * 4);
    lzma_rs::lzma_decompress(&mut with_len.as_slice(), &mut out)
        .map_err(|e| format!("LZMA decoding failed: {e:?}"))?;
    Ok(out)
}

fn jpegxr_to_raw_pixels<R: Read + Seek>(
    atf_width: u32,
    atf_height: u32,
    bytes: R,
) -> Result<Vec<u8>, String> {
    let mut decoder = jpegxr::ImageDecode::with_reader(bytes)
        .map_err(|e| format!("Failed to decode JPEG-XR image: {e:?}"))?;

    let pixel_format = decoder
        .get_pixel_format()
        .map_err(|e| format!("Failed to get pixel format: {e:?}"))?;
    let (jpeg_width, jpeg_height) = decoder
        .get_size()
        .map_err(|e| format!("Failed to get JPEG-XR size: {e:?}"))?;

    if jpeg_width as u32 != atf_width || jpeg_height as u32 != atf_height {
        return Err("Mismatched JPEG-XR size".into());
    }

    let info = jpegxr::PixelInfo::from_format(pixel_format);
    let stride = jpeg_width as usize * info.bits_per_pixel() / 8;

    let size = stride * jpeg_height as usize;

    let mut output = vec![0; size];

    decoder
        .copy_all(&mut output, stride)
        .map_err(|e| format!("Failed to decode: {e:?}"))?;
    Ok(output)
}

fn jpegxr_to_tiff<R: Read + Seek>(
    atf_width: u32,
    atf_height: u32,
    bytes: R,
) -> Result<(image::DynamicImage, jpegxr::PixelFormat), String> {
    let mut decoder = jpegxr::ImageDecode::with_reader(bytes)
        .map_err(|e| format!("Failed to decode JPEG-XR image: {e:?}"))?;

    let pixel_format = decoder
        .get_pixel_format()
        .map_err(|e| format!("Failed to get pixel format: {e:?}"))?;

    let (jpeg_width, jpeg_height) = decoder
        .get_size()
        .map_err(|e| format!("Failed to get JPEG-XR size: {e:?}"))?;
    let jpeg_width = jpeg_width as u32;
    let jpeg_height = jpeg_height as u32;

    if jpeg_width != atf_width || jpeg_height != atf_height {
        return Err("Mismatched JPEG-XR size".into());
    }

    let info = jpegxr::PixelInfo::from_format(pixel_format);
    let stride = jpeg_width as usize * info.bits_per_pixel() / 8;
    let size = stride * jpeg_height as usize;

    // We convert the result to a TIFF - this makes the jpegxr library handle
    // all of the weird JPEG-XR alpha formats for us. We can then use the normal
    // `image` crate to decode the TIFF to an rgba array.
    let mut bmp_buffer = vec![0; size];
    decoder
        .convert_to_tiff(&mut Cursor::new(&mut bmp_buffer))
        .map_err(|e| format!("Failed to convert to bitmap: {e:?}"))?;

    let image_reader =
        image::ImageReader::with_format(Cursor::new(bmp_buffer), image::ImageFormat::Tiff);
    Ok((
        image_reader
            .decode()
            .map_err(|e| format!("Failed to decode Bitmap: {e}"))?,
        pixel_format,
    ))
}
