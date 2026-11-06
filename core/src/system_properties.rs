use bitflags::bitflags;
use core::fmt;
use fluent_templates::{LanguageIdentifier, langid};
use percent_encoding::{AsciiSet, NON_ALPHANUMERIC};

// Timffle: Flash's serverString escapes like `escape()`: letters, digits, `-`, `_` and `.`
// stay ("AR=1.0", "ML=5.1", "L=zh-TW"), everything else is %XX ("OS=Windows%208").
const SERVER_STRING_ESCAPE: &AsciiSet = &NON_ALPHANUMERIC
    .remove(b'-')
    .remove(b'_')
    .remove(b'.');

/// Timffle: the values that differ between AVM1 and AVM2 (or depend on the player runtime)
/// and are needed to build `serverString`.
pub struct ServerStringHost<'a> {
    /// `Capabilities.version`, e.g. "WIN 32,0,0,0"
    pub version: &'a str,
    /// `Capabilities.manufacturer`, e.g. "Adobe Windows"
    pub manufacturer: &'a str,
    /// `Capabilities.os`
    pub os: &'a str,
    /// `Capabilities.language`
    pub language: &'a str,
    /// `Capabilities.playerType`
    pub player_type: &'a str,
    /// `Capabilities.screenResolutionX`
    pub width: u32,
    /// `Capabilities.screenResolutionY`
    pub height: u32,
}

/// Available cpu architectures
pub enum CpuArchitecture {
    PowerPc,
    X86,
    Sparc,
    Arm,
}

impl fmt::Display for CpuArchitecture {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            CpuArchitecture::PowerPc => "PowerPC",
            CpuArchitecture::X86 => "x86",
            CpuArchitecture::Sparc => "SPARC",
            CpuArchitecture::Arm => "ARM",
        })
    }
}

/// The available host operating systems
pub enum OperatingSystem {
    WindowsXp,
    Windows2k,
    WindowsNt,
    Windows98,
    Windows95,
    WindowsCe,
    WindowsUnknown,
    Linux,
    MacOs,
}

impl fmt::Display for OperatingSystem {
    fn fmt(&self, fmt: &mut fmt::Formatter<'_>) -> fmt::Result {
        fmt.write_str(match self {
            OperatingSystem::WindowsXp => "Windows XP",
            OperatingSystem::Windows2k => "Windows 2000",
            OperatingSystem::WindowsNt => "Windows NT",
            OperatingSystem::Windows98 => "Windows 98/ME",
            OperatingSystem::Windows95 => "Windows 95",
            OperatingSystem::WindowsCe => "Windows CE",
            OperatingSystem::WindowsUnknown => "Windows",
            OperatingSystem::Linux => "Linux",
            OperatingSystem::MacOs => "MacOS",
        })
    }
}

/// The available player manufacturers
pub enum Manufacturer {
    Windows,
    Macintosh,
    Linux,
    Other(String),
}

impl Manufacturer {
    pub fn get_manufacturer_string(&self, version: u8) -> String {
        let os_part = match self {
            Manufacturer::Windows => "Windows",
            Manufacturer::Macintosh => "Macintosh",
            Manufacturer::Linux => "Linux",
            Manufacturer::Other(name) => name.as_str(),
        };

        if version <= 8 {
            format!("Macromedia {os_part}")
        } else {
            format!("Adobe {os_part}")
        }
    }

    pub fn get_platform_name(&self) -> &str {
        match self {
            Manufacturer::Windows => "WIN",
            Manufacturer::Macintosh => "MAC",
            Manufacturer::Linux => "LNX",
            _ => "",
        }
    }
}

/// The language of the host os
pub enum Language {
    Czech,
    Danish,
    Dutch,
    English,
    Finnish,
    French,
    German,
    Hungarian,
    Italian,
    Japanese,
    Korean,
    Norwegian,
    Unknown,
    Polish,
    Portuguese,
    Russian,
    SimplifiedChinese,
    Spanish,
    Swedish,
    TraditionalChinese,
    Turkish,
}

impl Language {
    pub fn get_language_code(&self, player_version: u8) -> &str {
        match self {
            Language::Czech => "cs",
            Language::Danish => "da",
            Language::Dutch => "nl",
            Language::English => {
                if player_version < 7 {
                    "en-US"
                } else {
                    "en"
                }
            }
            Language::Finnish => "fi",
            Language::French => "fr",
            Language::German => "de",
            Language::Hungarian => "hu",
            Language::Italian => "it",
            Language::Japanese => "ja",
            Language::Korean => "ko",
            Language::Norwegian => "no",
            Language::Unknown => "xu",
            Language::Polish => "pl",
            Language::Portuguese => "pt",
            Language::Russian => "ru",
            Language::SimplifiedChinese => "zh-CN",
            Language::Spanish => "es",
            Language::Swedish => "sv",
            Language::TraditionalChinese => "zh-TW",
            Language::Turkish => "tr",
        }
    }
}

impl From<LanguageIdentifier> for Language {
    fn from(li: LanguageIdentifier) -> Self {
        match li.language.as_str() {
            "da" => Language::Danish,
            "nl" => Language::Dutch,
            "en" => Language::English,
            "fi" => Language::Finnish,
            "fr" => Language::French,
            "de" => Language::German,
            "hu" => Language::Hungarian,
            "it" => Language::Italian,
            "ja" => Language::Japanese,
            "ko" => Language::Korean,
            "no" => Language::Norwegian,
            "und" => Language::Unknown,
            "pl" => Language::Polish,
            "pt" => Language::Portuguese,
            "ru" => Language::Russian,
            "zh" => {
                if li == langid!("zh-TW") {
                    Language::TraditionalChinese
                } else {
                    Language::SimplifiedChinese
                }
            }
            "es" => Language::Spanish,
            "sv" => Language::Swedish,
            "tr" => Language::Turkish,
            // Fallback to English instead of Unknown for better compatibility.
            _ => Language::English,
        }
    }
}

/// Timffle: `Capabilities.touchscreenType`
pub enum TouchscreenType {
    None,
    Finger,
    Stylus,
}

impl fmt::Display for TouchscreenType {
    fn fmt(&self, fmt: &mut fmt::Formatter<'_>) -> fmt::Result {
        fmt.write_str(match self {
            TouchscreenType::None => "none",
            TouchscreenType::Finger => "finger",
            TouchscreenType::Stylus => "stylus",
        })
    }
}

/// The supported colors of the screen
pub enum ScreenColor {
    Color,
    Gray,
    BlackWhite,
}

impl fmt::Display for ScreenColor {
    fn fmt(&self, fmt: &mut fmt::Formatter<'_>) -> fmt::Result {
        fmt.write_str(match self {
            ScreenColor::Color => "color",
            ScreenColor::Gray => "gray",
            ScreenColor::BlackWhite => "bw",
        })
    }
}
/// The type of the player
pub enum PlayerType {
    StandAlone,
    External,
    PlugIn,
    ActiveX,
}

impl fmt::Display for PlayerType {
    fn fmt(&self, fmt: &mut fmt::Formatter<'_>) -> fmt::Result {
        fmt.write_str(match self {
            PlayerType::StandAlone => "StandAlone",
            PlayerType::External => "External",
            PlayerType::PlugIn => "PlugIn",
            PlayerType::ActiveX => "ActiveX",
        })
    }
}

bitflags! {
    pub struct SystemCapabilities: u32 {
        const AV_HARDWARE      = 1 << 0;
        const ACCESSIBILITY    = 1 << 1;
        const AUDIO            = 1 << 2;
        const AUDIO_ENCODER    = 1 << 3;
        const EMBEDDED_VIDEO   = 1 << 4;
        const IME              = 1 << 5;
        const MP3              = 1 << 6;
        const PRINTING         = 1 << 7;
        const SCREEN_BROADCAST = 1 << 8;
        const SCREEN_PLAYBACK  = 1 << 9;
        const STREAMING_AUDIO  = 1 << 10;
        const STREAMING_VIDEO  = 1 << 11;
        const VIDEO_ENCODER    = 1 << 12;
        const DEBUGGER         = 1 << 13;
        const LOCAL_FILE_READ  = 1 << 14;
        const PROCESS_64_BIT   = 1 << 15;
        const PROCESS_32_BIT   = 1 << 16;
        const ACROBAT_EMBEDDED = 1 << 17;
        const TLS              = 1 << 18;
        const WINDOW_LESS      = 1 << 19;
    }
}

/// The properties modified by 'System'
pub struct SystemProperties {
    /// If true then settings should be saved and read from the exact same domain of the player
    /// If false then they should be saved to the super domain
    pub exact_settings: bool,
    /// If true, the system codepage should be used for text files
    /// If false, UTF-8 should be used for SWF version >= 6 and ISO Latin-1 for SWF version <= 5
    pub use_codepage: bool,
    /// The capabilities of the player
    pub capabilities: SystemCapabilities,
    /// The type of the player
    pub player_type: PlayerType,
    /// The type of screen available to the player
    pub screen_color: ScreenColor,
    /// The aspect ratio of the screens pixels
    pub pixel_aspect_ratio: f32,
    /// The dpi of the screen
    pub dpi: f32,
    /// The language of the host os
    pub language: Language,
    /// The manufacturer of the player
    pub manufacturer: Manufacturer,
    /// The os of the host
    pub os: OperatingSystem,
    /// The cpu architecture of the platform
    pub cpu_architecture: CpuArchitecture,
    /// Timffle: `Capabilities.cpuAddressSize`, the player's pointer width (32 or 64)
    pub cpu_address_size: u8,
    /// Timffle: `Capabilities.touchscreenType`
    pub touchscreen_type: TouchscreenType,
    /// The highest supported h264 decoder level
    pub idc_level: String,
}

impl SystemProperties {
    pub fn new(language: LanguageIdentifier) -> Self {
        SystemProperties {
            //TODO: default to true on fp>=7, false <= 6
            exact_settings: true,
            //TODO: default to false on fp>=7, true <= 6
            use_codepage: false,
            // Timffle: what this player really provides. Flash Player's constant capabilities
            // (audio, MP3, streaming and embedded video, the built-in Speex/H.264 encoders,
            // TLS, 32-bit processes) are set. AV_HARDWARE, LOCAL_FILE_READ and WINDOW_LESS
            // mean "not administratively disabled" (`avHardwareDisable` etc. are their
            // negation). PRINTING is set as on a desktop Flash Player 32 (true with or
            // without a printer, measured; PrintJob.start() answers as a cancelled print
            // dialog). Unset: ACCESSIBILITY (no accessibility bridge), IME (IME.isSupported
            // is false), SCREEN_BROADCAST/SCREEN_PLAYBACK (FMS
            // screen sharing; desktop Flash Player 32 reports both false), DEBUGGER (this is
            // a release player) and ACROBAT_EMBEDDED -- exactly what Flash Player reports on
            // a machine without those features.
            capabilities: SystemCapabilities::AUDIO
                | SystemCapabilities::STREAMING_AUDIO
                | SystemCapabilities::STREAMING_VIDEO
                | SystemCapabilities::EMBEDDED_VIDEO
                | SystemCapabilities::MP3
                | SystemCapabilities::AUDIO_ENCODER
                | SystemCapabilities::VIDEO_ENCODER
                | SystemCapabilities::TLS
                | SystemCapabilities::PROCESS_32_BIT
                | SystemCapabilities::AV_HARDWARE
                | SystemCapabilities::LOCAL_FILE_READ
                | SystemCapabilities::WINDOW_LESS
                | SystemCapabilities::PRINTING
                | if cfg!(any(target_pointer_width = "64", target_family = "wasm")) {
                    // A 64-bit player, or the browser plug-in: the OS runs 64-bit processes.
                    SystemCapabilities::PROCESS_64_BIT
                } else {
                    SystemCapabilities::empty()
                },
            player_type: PlayerType::StandAlone,
            screen_color: ScreenColor::Color,
            // TODO: note for fp <7 this should be the locale and the ui lang for >= 7, on windows
            language: language.into(),
            // source: https://web.archive.org/web/20230611050355/https://flylib.com/books/en/4.13.1.272/1/
            pixel_aspect_ratio: 1_f32,
            // source: https://tracker.adobe.com/#/view/FP-3949775
            dpi: 72_f32,
            manufacturer: Manufacturer::Linux,
            os: OperatingSystem::Linux,
            // Timffle: the real architecture of this build; wasm cannot see the host CPU and
            // reports x86 like the Windows host it pretends to be.
            cpu_architecture: if cfg!(any(target_arch = "arm", target_arch = "aarch64")) {
                CpuArchitecture::Arm
            } else if cfg!(any(target_arch = "powerpc", target_arch = "powerpc64")) {
                CpuArchitecture::PowerPc
            } else if cfg!(any(target_arch = "sparc", target_arch = "sparc64")) {
                CpuArchitecture::Sparc
            } else {
                CpuArchitecture::X86
            },
            cpu_address_size: if cfg!(target_pointer_width = "64") {
                64
            } else {
                32
            },
            // No touch input reaches the player as touch; see flash.ui.Multitouch.
            touchscreen_type: TouchscreenType::None,
            // Flash Player 32's software H.264 decoder level on desktop.
            idc_level: "5.1".into(),
        }
    }

    pub fn get_version_string(&self, player_version: u8) -> String {
        format!(
            "{} {},0,0,0",
            self.manufacturer.get_platform_name(),
            player_version
        )
    }

    pub fn has_capability(&self, cap: SystemCapabilities) -> bool {
        self.capabilities.contains(cap)
    }

    fn encode_capability(&self, cap: SystemCapabilities) -> &str {
        if self.has_capability(cap) { "t" } else { "f" }
    }

    fn encode_not_capability(&self, cap: SystemCapabilities) -> &str {
        if self.has_capability(cap) { "f" } else { "t" }
    }

    fn encode_string(&self, s: &str) -> String {
        percent_encoding::utf8_percent_encode(s, SERVER_STRING_ESCAPE).to_string()
    }

    // Timffle: rewritten. The fields and their order are those of Flash Player 32
    // (32.0.0.465 standalone: A, SA, SV, EV, MP3, AE, VE, ACC, PR, SP, SB, DEB, V, M, R, COL,
    // AR, OS, ARCH, L, IME, PR32, PR64, CAS, PT, AVD, LFD, WD, TLS, ML, DP). Ruffle's version
    // lacked V/ARCH/PR32/PR64/CAS/WD/TLS/ML, inverted ACC, and percent-encoded M and OS twice.
    pub fn get_server_string(&self, host: &ServerStringHost<'_>) -> String {
        let flag = |cap| self.encode_capability(cap);
        let not_flag = |cap| self.encode_not_capability(cap);
        let pairs: [(&str, String); 31] = [
            ("A", flag(SystemCapabilities::AUDIO).into()),
            ("SA", flag(SystemCapabilities::STREAMING_AUDIO).into()),
            ("SV", flag(SystemCapabilities::STREAMING_VIDEO).into()),
            ("EV", flag(SystemCapabilities::EMBEDDED_VIDEO).into()),
            ("MP3", flag(SystemCapabilities::MP3).into()),
            ("AE", flag(SystemCapabilities::AUDIO_ENCODER).into()),
            ("VE", flag(SystemCapabilities::VIDEO_ENCODER).into()),
            ("ACC", flag(SystemCapabilities::ACCESSIBILITY).into()),
            ("PR", flag(SystemCapabilities::PRINTING).into()),
            ("SP", flag(SystemCapabilities::SCREEN_PLAYBACK).into()),
            ("SB", flag(SystemCapabilities::SCREEN_BROADCAST).into()),
            ("DEB", flag(SystemCapabilities::DEBUGGER).into()),
            ("V", self.encode_string(host.version)),
            ("M", self.encode_string(host.manufacturer)),
            ("R", format!("{}x{}", host.width, host.height)),
            ("COL", self.screen_color.to_string()),
            ("AR", format!("{:.1}", self.pixel_aspect_ratio)),
            ("OS", self.encode_string(host.os)),
            ("ARCH", self.cpu_architecture.to_string()),
            ("L", self.encode_string(host.language)),
            ("IME", flag(SystemCapabilities::IME).into()),
            ("PR32", flag(SystemCapabilities::PROCESS_32_BIT).into()),
            ("PR64", flag(SystemCapabilities::PROCESS_64_BIT).into()),
            ("CAS", self.cpu_address_size.to_string()),
            ("PT", self.encode_string(host.player_type)),
            ("AVD", not_flag(SystemCapabilities::AV_HARDWARE).into()),
            ("LFD", not_flag(SystemCapabilities::LOCAL_FILE_READ).into()),
            ("WD", not_flag(SystemCapabilities::WINDOW_LESS).into()),
            ("TLS", flag(SystemCapabilities::TLS).into()),
            ("ML", self.encode_string(&self.idc_level)),
            ("DP", format!("{}", self.dpi)),
        ];
        pairs
            .iter()
            .map(|(key, value)| format!("{key}={value}"))
            .collect::<Vec<_>>()
            .join("&")
    }
}
