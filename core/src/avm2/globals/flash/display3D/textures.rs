//! `flash.display3D.textures` namespace

#[cfg(feature = "jpegxr")]
mod atf_jpegxr;
#[cfg(not(feature = "jpegxr"))]
#[path = "textures/atf_jpegxr_stub.rs"]
mod atf_jpegxr;
// Timffle: ATF container upload (raw DXT/ETC/PVRTC payloads, GPU-native or
// CPU-decoded); the JPEG-XR based payloads come from `atf_jpegxr`.
mod atf_upload;

pub mod cube_texture;
pub mod rectangle_texture;
pub mod texture;
pub mod texture_base;
