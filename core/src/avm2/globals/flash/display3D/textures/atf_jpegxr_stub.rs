// Timffle: without the `jpegxr` feature the JPEG-XR based ATF payloads cannot
// be decoded (the raw DXT/ETC/PVRTC payloads still work, see `atf_upload`).
use super::atf_upload::LevelData;
use ruffle_render::atf::ATFTextureData;

pub fn decode_jpegxr_level(
    _data: &ATFTextureData,
    _width: u32,
    _height: u32,
) -> Result<LevelData, String> {
    Err("Support for JPEG-XR compressed textures not compiled in.".into())
}
