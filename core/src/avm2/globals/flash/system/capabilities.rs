//! `flash.display.Capabilities` native methods

use crate::avm2::function::FunctionArgs;
use crate::avm2::{Activation, AvmString, Error, Value};
use crate::player::PlayerRuntime;
use crate::system_properties::{ServerStringHost, SystemCapabilities};

// Timffle: the host Flash Player pretends to run on. Flash Player content mostly checks for
// Windows, so the Flash Player runtime always reports Windows; AIR reports the real OS.
// `os`, `version`, `manufacturer` and `serverString` all derive from this one description.
struct Host {
    /// `Capabilities.os`
    os: &'static str,
    /// The platform part of `Capabilities.version` ("WIN 32,0,0,0")
    platform: &'static str,
    /// `Capabilities.manufacturer`
    manufacturer: &'static str,
}

const WINDOWS_8: Host = Host {
    os: "Windows 8",
    platform: "WIN",
    manufacturer: "Adobe Windows",
};

fn host(runtime: PlayerRuntime) -> Host {
    match runtime {
        // For most normal Flash Player usage, the OS should not matter,
        // so let's pretend it's Windows for the broadest possible compatibility.
        PlayerRuntime::FlashPlayer => WINDOWS_8,
        PlayerRuntime::AIR => {
            if cfg!(windows) {
                Host {
                    os: "Windows 10",
                    platform: "WIN",
                    manufacturer: "Adobe Windows",
                }
            } else if cfg!(target_vendor = "apple") {
                Host {
                    os: "Mac OS 10.5.2",
                    platform: "MAC",
                    manufacturer: "Adobe Macintosh",
                }
            } else {
                Host {
                    os: "Linux 5.10.49",
                    platform: "LNX",
                    manufacturer: "Adobe Linux",
                }
            }
        }
    }
}

fn version_string(activation: &mut Activation<'_, '_>) -> String {
    let host = host(activation.avm2().player_runtime);
    format!(
        "{} {},0,0,0",
        host.platform,
        activation.avm2().player_version
    )
}

fn player_type(activation: &mut Activation<'_, '_>) -> &'static str {
    // TODO: When should "External" be returned?
    if cfg!(target_family = "wasm") {
        "PlugIn"
    } else {
        match activation.context.avm2.player_runtime {
            PlayerRuntime::FlashPlayer => "StandAlone",
            PlayerRuntime::AIR => "Desktop",
        }
    }
}

/// The screen size as Flash reports it: the viewport, adjusted for HiDPI.
/// Timffle: shared with `Stage.fullScreenWidth` / `fullScreenHeight`.
pub fn screen_resolution(activation: &mut Activation<'_, '_>) -> (f64, f64) {
    let viewport_dimensions = activation.context.renderer.viewport_dimensions();
    let width = f64::from(viewport_dimensions.width) / viewport_dimensions.scale_factor;
    let height = f64::from(viewport_dimensions.height) / viewport_dimensions.scale_factor;
    (width.round(), height.round())
}

fn language(activation: &mut Activation<'_, '_>) -> String {
    activation
        .context
        .system
        .language
        .get_language_code(activation.context.player_version)
        .to_string()
}

/// Implements `flash.system.Capabilities.os`
pub fn get_os<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let os = host(activation.avm2().player_runtime).os;
    Ok(AvmString::new_utf8(activation.gc(), os).into())
}

/// Implements `flash.system.Capabilities.manufacturer`
pub fn get_manufacturer<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let manufacturer = host(activation.avm2().player_runtime).manufacturer;
    Ok(AvmString::new_utf8(activation.gc(), manufacturer).into())
}

/// Implements `flash.system.Capabilities.version`
pub fn get_version<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let version = version_string(activation);
    Ok(AvmString::new_utf8(activation.gc(), version).into())
}

/// Implements `flash.system.Capabilities.playerType`
pub fn get_player_type<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let player_type = player_type(activation);
    Ok(AvmString::new_utf8(activation.gc(), player_type).into())
}

/// Implements `flash.system.Capabilities.screenResolutionX`
pub fn get_screen_resolution_x<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    Ok(screen_resolution(activation).0.into())
}

/// Implements `flash.system.Capabilities.screenResolutionY`
pub fn get_screen_resolution_y<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    Ok(screen_resolution(activation).1.into())
}

/// Implements `flash.system.Capabilities.pixelAspectRatio`
pub fn get_pixel_aspect_ratio<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    // source: https://web.archive.org/web/20230611050355/https://flylib.com/books/en/4.13.1.272/1/
    Ok(f64::from(activation.context.system.pixel_aspect_ratio).into())
}

/// Implements `flash.system.Capabilities.screenDPI`
pub fn get_screen_dpi<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    // source: https://tracker.adobe.com/#/view/FP-3949775
    Ok(f64::from(activation.context.system.dpi).into())
}

/// Implements `flash.system.Capabilities.language`
pub fn get_language<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let language = language(activation);
    Ok(AvmString::new_utf8(activation.gc(), language).into())
}

// Timffle: the boolean capabilities come from the shared host description.
macro_rules! capability_getter {
    ($name:ident, $capability:expr) => {
        pub fn $name<'gc>(
            activation: &mut Activation<'_, 'gc>,
            _this: Value<'gc>,
            _args: FunctionArgs<'_, 'gc>,
        ) -> Result<Value<'gc>, Error<'gc>> {
            Ok(activation.context.system.has_capability($capability).into())
        }
    };
}

/// `avHardwareDisable` and `localFileReadDisable` are the negated capabilities.
macro_rules! inverse_capability_getter {
    ($name:ident, $capability:expr) => {
        pub fn $name<'gc>(
            activation: &mut Activation<'_, 'gc>,
            _this: Value<'gc>,
            _args: FunctionArgs<'_, 'gc>,
        ) -> Result<Value<'gc>, Error<'gc>> {
            Ok((!activation.context.system.has_capability($capability)).into())
        }
    };
}

capability_getter!(get_has_accessibility, SystemCapabilities::ACCESSIBILITY);
capability_getter!(get_has_audio, SystemCapabilities::AUDIO);
capability_getter!(get_has_audio_encoder, SystemCapabilities::AUDIO_ENCODER);
capability_getter!(get_has_embedded_video, SystemCapabilities::EMBEDDED_VIDEO);
capability_getter!(get_has_ime, SystemCapabilities::IME);
capability_getter!(get_has_mp3, SystemCapabilities::MP3);
capability_getter!(get_has_printing, SystemCapabilities::PRINTING);
capability_getter!(
    get_has_screen_broadcast,
    SystemCapabilities::SCREEN_BROADCAST
);
capability_getter!(get_has_screen_playback, SystemCapabilities::SCREEN_PLAYBACK);
capability_getter!(get_has_streaming_audio, SystemCapabilities::STREAMING_AUDIO);
capability_getter!(get_has_streaming_video, SystemCapabilities::STREAMING_VIDEO);
capability_getter!(get_has_tls, SystemCapabilities::TLS);
capability_getter!(get_has_video_encoder, SystemCapabilities::VIDEO_ENCODER);
capability_getter!(get_is_debugger, SystemCapabilities::DEBUGGER);
capability_getter!(
    get_is_embedded_in_acrobat,
    SystemCapabilities::ACROBAT_EMBEDDED
);
capability_getter!(
    get_supports32bit_processes,
    SystemCapabilities::PROCESS_32_BIT
);
capability_getter!(
    get_supports64bit_processes,
    SystemCapabilities::PROCESS_64_BIT
);
inverse_capability_getter!(get_av_hardware_disable, SystemCapabilities::AV_HARDWARE);
inverse_capability_getter!(
    get_local_file_read_disable,
    SystemCapabilities::LOCAL_FILE_READ
);

/// Implements `flash.system.Capabilities._internal`
#[allow(non_snake_case)]
pub fn get__internal<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    // Undocumented. Flash Player 32.0.0.465 (standalone, measured through
    // timffle/difftest d41capabilities) returns 37 regardless of the SWF.
    Ok(37u32.into())
}

/// Implements `flash.system.Capabilities.cpuAddressSize`
pub fn get_cpu_address_size<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    Ok(f64::from(activation.context.system.cpu_address_size).into())
}

/// Implements `flash.system.Capabilities.cpuArchitecture`
pub fn get_cpu_architecture<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let arch = activation.context.system.cpu_architecture.to_string();
    Ok(AvmString::new_utf8(activation.gc(), arch).into())
}

/// Implements `flash.system.Capabilities.maxLevelIDC`
pub fn get_max_level_idc<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let level = activation.context.system.idc_level.clone();
    Ok(AvmString::new_utf8(activation.gc(), level).into())
}

/// Implements `flash.system.Capabilities.screenColor`
pub fn get_screen_color<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let color = activation.context.system.screen_color.to_string();
    Ok(AvmString::new_utf8(activation.gc(), color).into())
}

/// Implements `flash.system.Capabilities.touchscreenType`
pub fn get_touchscreen_type<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let touchscreen = activation.context.system.touchscreen_type.to_string();
    Ok(AvmString::new_utf8(activation.gc(), touchscreen).into())
}

/// Implements `flash.system.Capabilities.hasMultiChannelAudio`
pub fn has_multi_channel_audio<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    // Multichannel (Dolby/DTS pass-through) output only exists on Flash Player for TVs.
    // Desktop Flash Player 32 answers false for every type, including "" and null.
    Ok(false.into())
}

/// Implements `flash.system.Capabilities.serverString`
pub fn get_server_string<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let host = host(activation.avm2().player_runtime);
    let version = version_string(activation);
    let (width, height) = screen_resolution(activation);
    let player_type = player_type(activation);
    let language = language(activation);
    let server_string = activation
        .context
        .system
        .get_server_string(&ServerStringHost {
            version: &version,
            manufacturer: host.manufacturer,
            os: host.os,
            language: &language,
            player_type,
            width: width as u32,
            height: height as u32,
        });
    Ok(AvmString::new_utf8(activation.gc(), server_string).into())
}
