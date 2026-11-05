//! Timffle: a JPEG XR (ITU-T T.832 / ISO/IEC 29199-2) encoder for
//! `BitmapData.encode(rect, new JPEGXREncoderOptions(...))`.
//!
//! The Rust ecosystem only has JPEG XR decoders (Ruffle uses the `jpegxr` crate, the jxrlib
//! reference decoder, for DefineBitsJPEG4 and ATF), so this is a small encoder of its own. It
//! writes what Flash Player 32 writes (measured with timffle/difftest/src/D63JpegXr.hx,
//! D64JpegXrQp.hx and D65JpegXrMap.hx):
//!
//! - a TIFF-like container (`II`, 0xBC01, one IFD with PixelFormat, ImageWidth, ImageHeight,
//!   ImageOffset, ImageByteCount) holding one codestream at offset 90;
//! - 24bppBGR for opaque bitmaps, 32bppPBGRA (premultiplied, the bitmap's own pixel values) with
//!   an interleaved alpha plane for transparent ones;
//! - codestream version 1.9, one tile, spatial order, no index table, no overlap filter, no
//!   windowing, internal YUV 4:4:4 (Y_ONLY for the alpha plane), all subbands, frame-uniform
//!   quantisation (QP index 0 = lossless);
//! - `trimFlexBits` as the codestream's TRIM_FLEXBITS, for opaque bitmaps only (Flash ignores it
//!   when there is an alpha plane).
//!
//! The coding itself (colour conversion, the two-stage lapped transform without overlap,
//! quantisation, DC/LP/AC prediction, CBP prediction, adaptive scan orders, adaptive VLC tables
//! and the bit-plane (flexbit) refinement) follows the reference software semantics step by step,
//! so jxrlib decodes it bit-exactly: QP index 0 round-trips every pixel.

// The loops index several parallel tables the way the reference software does.
#![allow(clippy::needless_range_loop)]

// --------------------------------------------------------------------------------------------
// Constant tables (T.832 / jxrlib)
// --------------------------------------------------------------------------------------------

/// Position of pixel (row, column) of a 16x16 macroblock in the 256-entry working buffer.
const IDX_CC: [[u8; 16]; 16] = [
    [
        0x00, 0x01, 0x05, 0x04, 0x40, 0x41, 0x45, 0x44, 0x80, 0x81, 0x85, 0x84, 0xc0, 0xc1, 0xc5,
        0xc4,
    ],
    [
        0x02, 0x03, 0x07, 0x06, 0x42, 0x43, 0x47, 0x46, 0x82, 0x83, 0x87, 0x86, 0xc2, 0xc3, 0xc7,
        0xc6,
    ],
    [
        0x0a, 0x0b, 0x0f, 0x0e, 0x4a, 0x4b, 0x4f, 0x4e, 0x8a, 0x8b, 0x8f, 0x8e, 0xca, 0xcb, 0xcf,
        0xce,
    ],
    [
        0x08, 0x09, 0x0d, 0x0c, 0x48, 0x49, 0x4d, 0x4c, 0x88, 0x89, 0x8d, 0x8c, 0xc8, 0xc9, 0xcd,
        0xcc,
    ],
    [
        0x10, 0x11, 0x15, 0x14, 0x50, 0x51, 0x55, 0x54, 0x90, 0x91, 0x95, 0x94, 0xd0, 0xd1, 0xd5,
        0xd4,
    ],
    [
        0x12, 0x13, 0x17, 0x16, 0x52, 0x53, 0x57, 0x56, 0x92, 0x93, 0x97, 0x96, 0xd2, 0xd3, 0xd7,
        0xd6,
    ],
    [
        0x1a, 0x1b, 0x1f, 0x1e, 0x5a, 0x5b, 0x5f, 0x5e, 0x9a, 0x9b, 0x9f, 0x9e, 0xda, 0xdb, 0xdf,
        0xde,
    ],
    [
        0x18, 0x19, 0x1d, 0x1c, 0x58, 0x59, 0x5d, 0x5c, 0x98, 0x99, 0x9d, 0x9c, 0xd8, 0xd9, 0xdd,
        0xdc,
    ],
    [
        0x20, 0x21, 0x25, 0x24, 0x60, 0x61, 0x65, 0x64, 0xa0, 0xa1, 0xa5, 0xa4, 0xe0, 0xe1, 0xe5,
        0xe4,
    ],
    [
        0x22, 0x23, 0x27, 0x26, 0x62, 0x63, 0x67, 0x66, 0xa2, 0xa3, 0xa7, 0xa6, 0xe2, 0xe3, 0xe7,
        0xe6,
    ],
    [
        0x2a, 0x2b, 0x2f, 0x2e, 0x6a, 0x6b, 0x6f, 0x6e, 0xaa, 0xab, 0xaf, 0xae, 0xea, 0xeb, 0xef,
        0xee,
    ],
    [
        0x28, 0x29, 0x2d, 0x2c, 0x68, 0x69, 0x6d, 0x6c, 0xa8, 0xa9, 0xad, 0xac, 0xe8, 0xe9, 0xed,
        0xec,
    ],
    [
        0x30, 0x31, 0x35, 0x34, 0x70, 0x71, 0x75, 0x74, 0xb0, 0xb1, 0xb5, 0xb4, 0xf0, 0xf1, 0xf5,
        0xf4,
    ],
    [
        0x32, 0x33, 0x37, 0x36, 0x72, 0x73, 0x77, 0x76, 0xb2, 0xb3, 0xb7, 0xb6, 0xf2, 0xf3, 0xf7,
        0xf6,
    ],
    [
        0x3a, 0x3b, 0x3f, 0x3e, 0x7a, 0x7b, 0x7f, 0x7e, 0xba, 0xbb, 0xbf, 0xbe, 0xfa, 0xfb, 0xff,
        0xfe,
    ],
    [
        0x38, 0x39, 0x3d, 0x3c, 0x78, 0x79, 0x7d, 0x7c, 0xb8, 0xb9, 0xbd, 0xbc, 0xf8, 0xf9, 0xfd,
        0xfc,
    ],
];
const BLK_OFFSET: [usize; 16] = [
    0, 64, 16, 80, 128, 192, 144, 208, 32, 96, 48, 112, 160, 224, 176, 240,
];
const DCT_INDEX_AC: [usize; 16] = [0, 5, 1, 6, 10, 12, 8, 14, 2, 4, 3, 7, 9, 13, 11, 15];
const DCT_INDEX_DC: [usize; 16] = [
    0, 128, 64, 208, 32, 240, 48, 224, 16, 192, 80, 144, 112, 176, 96, 160,
];
const ZIGZAG_LOWPASS: [usize; 16] = [0, 1, 4, 5, 2, 8, 6, 9, 3, 12, 10, 7, 13, 11, 14, 15];
const ZIGZAG_H: [usize; 16] = [0, 1, 4, 5, 2, 8, 6, 9, 3, 12, 10, 7, 13, 11, 14, 15];
const ZIGZAG_V: [usize; 16] = [0, 4, 8, 5, 1, 12, 9, 6, 2, 13, 3, 15, 7, 10, 14, 11];
const SIGNIFICANT_RUN_BIN: [i32; 15] = [-1, -1, -1, -1, 2, 2, 2, 1, 1, 1, 1, 0, 0, 0, 0];
const SIGNIFICANT_RUN_FIXED_LENGTH: [u32; 15] = [0, 0, 1, 1, 3, 0, 0, 1, 1, 2, 0, 0, 0, 0, 1];

const MAXTOTAL: u32 = 32767;
const CTDC: usize = 5;
const CONTEXTX: usize = 8;
const NUMVLCTABLES: usize = 21;
const ALPHABET: [usize; NUMVLCTABLES] = [
    5, 4, 8, 7, 7, 12, 6, 6, 12, 6, 6, 7, 7, 12, 6, 6, 12, 6, 6, 7, 7,
];

// Adaptive VLC code tables: [n, (code, length) * n] per table variant.
static G4_CODES: [i32; 9] = [4, 1, 1, 1, 2, 0, 3, 1, 3];
static G5_CODES: [i32; 22] = [
    5, 1, 1, 1, 2, 1, 3, 0, 4, 1, 4, //
    5, 1, 1, 0, 3, 1, 3, 2, 3, 3, 3,
];
static G5_DELTA: [i32; 5] = [0, -1, 0, 1, 1];
static G6_CODES: [i32; 52] = [
    6, 1, 1, 0, 5, 1, 3, 1, 5, 1, 2, 1, 4, //
    6, 1, 2, 0, 4, 2, 2, 1, 4, 3, 2, 1, 3, //
    6, 0, 4, 1, 4, 1, 2, 2, 2, 3, 2, 1, 3, //
    6, 0, 5, 1, 5, 1, 2, 1, 1, 1, 4, 1, 3,
];
static G6_DELTA: [i32; 18] = [
    -1, 1, 1, 1, 0, 1, //
    -2, 0, 0, 2, 0, 0, //
    -1, -1, 0, 1, -2, 0,
];
static G7_CODES: [i32; 30] = [
    7, 1, 2, 2, 2, 3, 2, 1, 3, 1, 4, 0, 5, 1, 5, //
    7, 1, 1, 1, 2, 1, 3, 1, 4, 1, 5, 0, 6, 1, 6,
];
static G7_DELTA: [i32; 7] = [1, 0, -1, -1, -1, -1, -1];
static G8_CODES: [i32; 34] = [
    8, 2, 2, 1, 3, 1, 5, 1, 4, 3, 2, 2, 3, 0, 5, 3, 3, //
    8, 1, 3, 2, 3, 1, 4, 3, 3, 4, 3, 5, 3, 0, 4, 3, 2,
];
static G9_CODES: [i32; 38] = [
    9, 2, 3, 0, 5, 2, 4, 1, 5, 2, 5, 1, 1, 3, 3, 3, 5, 3, 4, //
    9, 1, 1, 1, 3, 2, 3, 1, 4, 1, 6, 3, 3, 1, 5, 0, 7, 1, 7,
];
static G9_DELTA: [i32; 9] = [2, 2, 1, 1, -1, -2, -2, -2, -3];
static G12_CODES: [i32; 125] = [
    12, 1, 5, 1, 6, 0, 7, 1, 7, 4, 5, 2, 3, 5, 5, 1, 1, 6, 5, 1, 4, 7, 5, 3, 3, //
    12, 2, 4, 2, 5, 0, 6, 1, 6, 3, 4, 2, 3, 3, 5, 3, 2, 3, 3, 4, 3, 1, 5, 5, 3, //
    12, 3, 2, 1, 3, 0, 7, 1, 7, 1, 5, 2, 3, 2, 7, 3, 3, 4, 3, 5, 3, 3, 7, 1, 4, //
    12, 1, 3, 3, 2, 0, 7, 1, 5, 2, 5, 2, 3, 1, 7, 3, 3, 3, 5, 4, 3, 1, 6, 5, 3, //
    12, 2, 3, 1, 1, 1, 7, 1, 4, 2, 7, 3, 3, 0, 8, 2, 4, 3, 7, 3, 4, 1, 8, 1, 5,
];
static G12_DELTA: [i32; 48] = [
    1, 1, 1, 1, 1, 0, 0, -1, 2, 1, 0, 0, //
    2, 2, -1, -1, -1, 0, -2, -1, 0, 0, -2, -1, //
    -1, 1, 0, 2, 0, 0, 0, 0, -2, 0, 1, 1, //
    0, 1, 0, 1, -2, 0, -1, -1, -2, -1, -2, -2,
];

/// Reciprocal (mantissa, exponent) of the quantiser mantissa.
const QP_RECIP: [(u32, i32); 32] = [
    (0x0, 0),
    (0x0, 0),
    (0x0, 1),
    (0xaaaaaaab, 1),
    (0x0, 2),
    (0xcccccccd, 2),
    (0xaaaaaaab, 2),
    (0x92492493, 2),
    (0x0, 3),
    (0xe38e38e4, 3),
    (0xcccccccd, 3),
    (0xba2e8ba3, 3),
    (0xaaaaaaab, 3),
    (0x9d89d89e, 3),
    (0x92492493, 3),
    (0x88888889, 3),
    (0x0, 4),
    (0xf0f0f0f1, 4),
    (0xe38e38e4, 4),
    (0xd79435e6, 4),
    (0xcccccccd, 4),
    (0xc30c30c4, 4),
    (0xba2e8ba3, 4),
    (0xb21642c9, 4),
    (0xaaaaaaab, 4),
    (0xa3d70a3e, 4),
    (0x9d89d89e, 4),
    (0x97b425ee, 4),
    (0x92492493, 4),
    (0x8d3dcb09, 4),
    (0x88888889, 4),
    (0x84210843, 4),
];

/// 24bppBGR and 32bppPBGRA pixel format GUIDs, in file byte order.
const GUID_24BPP_BGR: [u8; 16] = [
    0x24, 0xc3, 0xdd, 0x6f, 0x03, 0x4e, 0xfe, 0x4b, 0xb1, 0x85, 0x3d, 0x77, 0x76, 0x8d, 0xc9, 0x0c,
];
const GUID_32BPP_PBGRA: [u8; 16] = [
    0x24, 0xc3, 0xdd, 0x6f, 0x03, 0x4e, 0xfe, 0x4b, 0xb1, 0x85, 0x3d, 0x77, 0x76, 0x8d, 0xc9, 0x10,
];

// --------------------------------------------------------------------------------------------
// Public interface
// --------------------------------------------------------------------------------------------

/// The QP index Flash Player 32 uses for `JPEGXREncoderOptions.quantization` (0..=100):
/// 0 is lossless, 1..=15 map to 2q, 16..=48 to q + 18 and 49..=100 to q + 20 (D65JpegXrMap.hx).
pub fn quantization_to_qp_index(quantization: u32) -> u8 {
    match quantization {
        0 => 0,
        1..=15 => (quantization * 2) as u8,
        16..=48 => (quantization + 18) as u8,
        _ => (quantization.min(100) + 20) as u8,
    }
}

/// Encodes `width` x `height` pixels (row-major `[r, g, b, a]`, premultiplied when `alpha`) as a
/// JPEG XR file. With `alpha` false the alpha bytes are ignored.
pub fn encode(
    width: u32,
    height: u32,
    pixels: &[[u8; 4]],
    alpha: bool,
    qp_index: u8,
    trim_flex_bits: u8,
) -> Vec<u8> {
    assert!(width > 0 && height > 0 && pixels.len() == (width * height) as usize);
    let codestream = encode_codestream(width, height, pixels, alpha, qp_index, trim_flex_bits);

    // Container, laid out like Flash's: header, 5-entry IFD, pixel format GUID, codestream.
    const IFD_OFFSET: u32 = 8;
    const ENTRIES: u16 = 5;
    const GUID_OFFSET: u32 = IFD_OFFSET + 2 + 12 * ENTRIES as u32 + 4;
    const IMAGE_OFFSET: u32 = GUID_OFFSET + 16;
    let mut out = Vec::with_capacity(IMAGE_OFFSET as usize + codestream.len());
    out.extend_from_slice(b"II");
    out.extend_from_slice(&0x01bcu16.to_le_bytes());
    out.extend_from_slice(&IFD_OFFSET.to_le_bytes());
    out.extend_from_slice(&ENTRIES.to_le_bytes());
    let mut entry = |tag: u16, kind: u16, count: u32, value: u32| {
        out.extend_from_slice(&tag.to_le_bytes());
        out.extend_from_slice(&kind.to_le_bytes());
        out.extend_from_slice(&count.to_le_bytes());
        out.extend_from_slice(&value.to_le_bytes());
    };
    entry(0xbc01, 1, 16, GUID_OFFSET); // PixelFormat (BYTE[16])
    entry(0xbc80, 4, 1, width); // ImageWidth
    entry(0xbc81, 4, 1, height); // ImageHeight
    entry(0xbcc0, 4, 1, IMAGE_OFFSET); // ImageOffset
    entry(0xbcc1, 4, 1, codestream.len() as u32); // ImageByteCount
    out.extend_from_slice(&0u32.to_le_bytes()); // no next IFD
    out.extend_from_slice(if alpha {
        &GUID_32BPP_PBGRA
    } else {
        &GUID_24BPP_BGR
    });
    out.extend_from_slice(&codestream);
    out
}

// --------------------------------------------------------------------------------------------
// Bit writer
// --------------------------------------------------------------------------------------------

struct BitWriter {
    buf: Vec<u8>,
    acc: u64,
    bits: u32,
}

impl BitWriter {
    fn new() -> Self {
        Self {
            buf: Vec::new(),
            acc: 0,
            bits: 0,
        }
    }

    /// Writes the low `n` bits of `value`, most significant first.
    fn put(&mut self, value: u32, n: u32) {
        if n == 0 {
            return;
        }
        debug_assert!(n <= 32);
        let value = u64::from(value) & ((1u64 << n) - 1);
        self.acc = (self.acc << n) | value;
        self.bits += n;
        while self.bits >= 8 {
            self.bits -= 8;
            self.buf.push((self.acc >> self.bits) as u8);
        }
        self.acc &= (1u64 << self.bits) - 1;
    }

    fn align(&mut self) {
        if self.bits > 0 {
            self.put(0, 8 - self.bits);
        }
    }
}

// --------------------------------------------------------------------------------------------
// Adaptive VLC tables
// --------------------------------------------------------------------------------------------

#[derive(Clone)]
struct Huffman {
    symbols: usize,
    codes: &'static [i32],
    delta: Option<&'static [i32]>,
    delta1: Option<&'static [i32]>,
    table_index: i32,
    initialized: bool,
    discriminant: i32,
    discriminant1: i32,
    upper_bound: i32,
    lower_bound: i32,
}

impl Huffman {
    fn new(symbols: usize) -> Self {
        Self {
            symbols,
            codes: &G4_CODES,
            delta: None,
            delta1: None,
            table_index: 0,
            initialized: false,
            discriminant: 0,
            discriminant1: 0,
            upper_bound: 0,
            lower_bound: 0,
        }
    }

    fn put(&self, w: &mut BitWriter, index: usize) {
        w.put(
            self.codes[index * 2 + 1] as u32,
            self.codes[index * 2 + 2] as u32,
        );
    }

    fn add_delta(&mut self, index: usize) {
        self.discriminant += self.delta.expect("table without discriminant")[index];
    }

    fn add_delta1(&mut self, index: usize) {
        self.discriminant1 += self.delta1.expect("table without discriminant")[index];
    }

    /// AdaptDiscriminant: switch between the table variants of this alphabet.
    fn adapt(&mut self) {
        const THRESHOLD: i32 = 8;
        const MEMORY: i32 = 8;
        const MAX_TABLES: [i32; 13] = [0, 0, 0, 0, 1, 2, 4, 2, 2, 2, 0, 0, 5];
        const SECOND_DISC: [bool; 13] = [
            false, false, false, false, false, false, true, false, false, false, false, false, true,
        ];
        let sym = self.symbols;
        if !self.initialized {
            self.initialized = true;
            self.discriminant = 0;
            self.discriminant1 = 0;
            self.table_index = SECOND_DISC[sym] as i32;
        }
        let dl = self.discriminant;
        let dh = if SECOND_DISC[sym] {
            self.discriminant1
        } else {
            self.discriminant
        };
        let mut change = false;
        if dl < self.lower_bound {
            self.table_index -= 1;
            change = true;
        } else if dh > self.upper_bound {
            self.table_index += 1;
            change = true;
        }
        if change {
            self.discriminant = 0;
            self.discriminant1 = 0;
        }
        let limit = THRESHOLD * MEMORY;
        self.discriminant = self.discriminant.clamp(-limit, limit);
        self.discriminant1 = self.discriminant1.clamp(-limit, limit);

        let t = self.table_index;
        let max = MAX_TABLES[sym];
        debug_assert!(t >= 0 && t < max);
        self.lower_bound = if t == 0 { i32::MIN } else { -THRESHOLD };
        self.upper_bound = if t == max - 1 { 1 << 30 } else { THRESHOLD };
        let tu = t as usize;
        let row = |n: usize, t: usize| (n * 2 + 1) * t;
        match sym {
            4 => {
                self.codes = &G4_CODES;
                self.delta = None;
            }
            5 => {
                self.codes = &G5_CODES[row(5, tu)..];
                self.delta = Some(&G5_DELTA);
            }
            6 => {
                self.codes = &G6_CODES[row(6, tu)..];
                self.delta1 = Some(&G6_DELTA[6 * (t - (t + 1 == max) as i32) as usize..]);
                self.delta = Some(&G6_DELTA[6 * (t - 1 + (t == 0) as i32) as usize..]);
            }
            7 => {
                self.codes = &G7_CODES[row(7, tu)..];
                self.delta = Some(&G7_DELTA);
            }
            8 => {
                self.codes = &G8_CODES;
                self.delta = None;
            }
            9 => {
                self.codes = &G9_CODES[row(9, tu)..];
                self.delta = Some(&G9_DELTA);
            }
            12 => {
                self.codes = &G12_CODES[row(12, tu)..];
                self.delta1 = Some(&G12_DELTA[12 * (t - (t + 1 == max) as i32) as usize..]);
                self.delta = Some(&G12_DELTA[12 * (t - 1 + (t == 0) as i32) as usize..]);
            }
            _ => unreachable!("no VLC table with {sym} symbols"),
        }
    }
}

// --------------------------------------------------------------------------------------------
// Coding context
// --------------------------------------------------------------------------------------------

#[derive(Clone, Copy, Default)]
struct Scan {
    total: u32,
    scan: usize,
}

#[derive(Clone, Copy, PartialEq, Eq, Default)]
enum Band {
    #[default]
    Dc,
    Lp,
    Ac,
}

#[derive(Clone, Copy, Default)]
struct Model {
    flc_state: [i32; 2],
    flc_bits: [i32; 2],
    band: Band,
}

impl Model {
    /// UpdateModelMB (4:4:4 and Y_ONLY).
    fn update(&mut self, y_only: bool, channels: usize, mut mean: [i32; 2]) {
        const MODELWEIGHT: i32 = 70;
        const WEIGHT0: [i32; 3] = [240, 12, 1];
        const WEIGHT1: [[i32; 16]; 3] = [
            [
                0, 240, 120, 80, 60, 48, 40, 34, 30, 27, 24, 22, 20, 18, 17, 16,
            ],
            [0, 12, 6, 4, 3, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1],
            [0, 16, 8, 5, 4, 3, 3, 2, 2, 2, 2, 1, 1, 1, 1, 1],
        ];
        let band = self.band as usize;
        mean[0] *= WEIGHT0[band];
        mean[1] *= WEIGHT1[band][channels - 1];
        if self.band == Band::Ac {
            mean[1] >>= 4;
        }
        for j in 0..2 {
            let mut ms = self.flc_state[j];
            let mut delta = (mean[j] - MODELWEIGHT) >> 2;
            if delta <= -8 {
                delta += 4;
                if delta < -16 {
                    delta = -16;
                }
                ms += delta;
                if ms < -8 {
                    if self.flc_bits[j] == 0 {
                        ms = -8;
                    } else {
                        ms = 0;
                        self.flc_bits[j] -= 1;
                    }
                }
            } else if delta >= 8 {
                delta -= 4;
                if delta > 15 {
                    delta = 15;
                }
                ms += delta;
                if ms > 8 {
                    if self.flc_bits[j] >= 15 {
                        self.flc_bits[j] = 15;
                        ms = 8;
                    } else {
                        ms = 0;
                        self.flc_bits[j] += 1;
                    }
                }
            }
            self.flc_state[j] = ms;
            if y_only {
                break;
            }
        }
    }
}

#[derive(Clone, Copy, Default)]
struct CbpModel {
    count0: [i32; 2],
    count1: [i32; 2],
    state: [i32; 2],
}

struct Context {
    cbpcy: Huffman,
    cbpcy1: Huffman,
    expt: Vec<Huffman>,
    scan_lowpass: [Scan; 16],
    scan_horiz: [Scan; 16],
    scan_vert: [Scan; 16],
    model_ac: Model,
    model_lp: Model,
    model_dc: Model,
    cbp_count_zero: i32,
    cbp_count_max: i32,
    cbp_model: CbpModel,
    trim_flex_bits: i32,
}

impl Context {
    fn new(y_only: bool, trim_flex_bits: i32) -> Self {
        let mut ctx = Self {
            cbpcy: Huffman::new(if y_only { 5 } else { 9 }),
            cbpcy1: Huffman::new(5),
            expt: ALPHABET.iter().map(|&n| Huffman::new(n)).collect(),
            scan_lowpass: [Scan::default(); 16],
            scan_horiz: [Scan::default(); 16],
            scan_vert: [Scan::default(); 16],
            model_ac: Model::default(),
            model_lp: Model::default(),
            model_dc: Model::default(),
            cbp_count_zero: 0,
            cbp_count_max: 0,
            cbp_model: CbpModel::default(),
            trim_flex_bits,
        };
        ctx.reset();
        ctx
    }

    /// ResetCodingContextEnc.
    fn reset(&mut self) {
        self.cbpcy.initialized = false;
        self.cbpcy1.initialized = false;
        for t in &mut self.expt {
            t.initialized = false;
        }
        self.adapt_lowpass();
        self.adapt_highpass();
        for i in 0..16 {
            self.scan_lowpass[i].scan = ZIGZAG_LOWPASS[i];
            self.scan_horiz[i].scan = DCT_INDEX_AC[ZIGZAG_H[i]];
            self.scan_vert[i].scan = DCT_INDEX_AC[ZIGZAG_V[i]];
        }
        self.model_ac = Model {
            band: Band::Ac,
            ..Model::default()
        };
        self.model_lp = Model {
            band: Band::Lp,
            flc_bits: [4, 4],
            ..Model::default()
        };
        self.model_dc = Model {
            band: Band::Dc,
            flc_bits: [8, 8],
            ..Model::default()
        };
        self.cbp_count_max = 1;
        self.cbp_count_zero = 1;
        self.cbp_model = CbpModel {
            count0: [-4, -4],
            count1: [4, 4],
            state: [0, 0],
        };
    }

    fn adapt_lowpass(&mut self) {
        for t in &mut self.expt[..CONTEXTX + CTDC] {
            t.adapt();
        }
    }

    fn adapt_highpass(&mut self) {
        self.cbpcy.adapt();
        self.cbpcy1.adapt();
        for t in &mut self.expt[CONTEXTX + CTDC..] {
            t.adapt();
        }
    }
}

fn reset_scan_totals(scan: &mut [Scan; 16]) {
    scan[0].total = MAXTOTAL;
    let mut weight = 32;
    for s in &mut scan[1..] {
        s.total = weight;
        weight -= 2;
    }
}

// --------------------------------------------------------------------------------------------
// Quantisation
// --------------------------------------------------------------------------------------------

#[derive(Clone, Copy)]
struct Quantizer {
    offset: i32,
    man: u32,
    exp: i32,
}

impl Quantizer {
    /// remapQP for frame-uniform quantisers (scaled arithmetic whenever the index is not 0).
    fn new(index: u8, shift: i32, dc: bool) -> Self {
        if index == 0 {
            return Self {
                offset: 0,
                man: 0,
                exp: 0,
            };
        }
        let index = i32::from(index);
        let (man, exp) = if index < 16 {
            (index, shift)
        } else {
            (16 + (index & 0xf), ((index >> 4) - 1) + shift)
        };
        let qp = man << exp;
        let (rman, rexp) = QP_RECIP[man as usize];
        Self {
            offset: if dc { qp >> 1 } else { (qp * 3 + 1) >> 3 },
            man: rman,
            exp: rexp + exp,
        }
    }

    fn quantize(&self, v: i32) -> i32 {
        let m = v >> 31;
        let a = (v ^ m).wrapping_sub(m).wrapping_add(self.offset);
        let q = if self.man == 0 {
            a >> self.exp
        } else {
            (((u64::from(a as u32) * u64::from(self.man)) >> 32) as u32 >> self.exp) as i32
        };
        (q ^ m).wrapping_sub(m)
    }
}

// --------------------------------------------------------------------------------------------
// Forward transform (no overlap filtering)
// --------------------------------------------------------------------------------------------

fn dct2x2dn(p: &mut [i32], ia: usize, ib: usize, ic: usize, id: usize) {
    let (mut a, mut b, cc, mut d) = (p[ia], p[ib], p[ic], p[id]);
    a += d;
    b -= cc;
    let t = (a - b) >> 1;
    let c = t - d;
    d = t - cc;
    a -= d;
    b += c;
    p[ia] = a;
    p[ib] = b;
    p[ic] = c;
    p[id] = d;
}

fn dct2x2up(p: &mut [i32], ia: usize, ib: usize, ic: usize, id: usize) {
    let (mut a, mut b, cc, mut d) = (p[ia], p[ib], p[ic], p[id]);
    a += d;
    b -= cc;
    let t = (a - b + 1) >> 1;
    let c = t - d;
    d = t - cc;
    a -= d;
    b += c;
    p[ia] = a;
    p[ib] = b;
    p[ic] = c;
    p[id] = d;
}

/// Kron(Rotate(pi/8), Rotate(pi/8)).
fn fwd_odd_odd(p: &mut [i32], ia: usize, ib: usize, ic: usize, id: usize) {
    let mut a = p[ia];
    let mut b = -p[ib];
    let mut c = -p[ic];
    let mut d = p[id];
    d += a;
    c -= b;
    let t1 = d >> 1;
    a -= t1;
    let t2 = c >> 1;
    b += t2;
    a += (b * 3 + 4) >> 3;
    b -= (a * 3 + 3) >> 2;
    a += (b * 3 + 3) >> 3;
    b -= t2;
    a += t1;
    c += b;
    d -= a;
    p[ia] = a;
    p[ib] = b;
    p[ic] = c;
    p[id] = d;
}

/// Kron(Rotate(pi/8), [1 1; 1 -1]/sqrt(2)).
fn fwd_odd(p: &mut [i32], ia: usize, ib: usize, ic: usize, id: usize) {
    let (mut a, mut b, mut c, mut d) = (p[ia], p[ib], p[ic], p[id]);
    b -= c;
    a += d;
    c += (b + 1) >> 1;
    d = ((a + 1) >> 1) - d;
    // ROTATE2(a, b), ROTATE2(c, d)
    b -= (a * 3 + 4) >> 3;
    a += (b * 3 + 4) >> 3;
    d -= (c * 3 + 4) >> 3;
    c += (d * 3 + 4) >> 3;
    d += b >> 1;
    c -= (a + 1) >> 1;
    b -= d;
    a += c;
    p[ia] = a;
    p[ib] = b;
    p[ic] = c;
    p[id] = d;
}

/// strDCT4x4Stage1 on the 16 values at `base`.
fn dct4x4_stage1(p: &mut [i32], base: usize) {
    let q = &mut p[base..base + 16];
    for i in 0..4 {
        dct2x2dn(q, i, i + 4, i + 8, i + 12);
    }
    dct2x2up(q, 0, 1, 2, 3);
    fwd_odd_odd(q, 15, 14, 13, 12);
    fwd_odd(q, 5, 4, 7, 6);
    fwd_odd(q, 10, 8, 11, 9);
}

/// strDCT4x4SecondStage on the 16 block DCs of a macroblock.
fn dct4x4_second_stage(p: &mut [i32]) {
    dct2x2dn(p, 0, 192, 48, 240);
    dct2x2dn(p, 64, 128, 112, 176);
    dct2x2dn(p, 16, 208, 32, 224);
    dct2x2dn(p, 80, 144, 96, 160);
    dct2x2up(p, 0, 64, 16, 80);
    fwd_odd_odd(p, 160, 224, 176, 240);
    fwd_odd(p, 128, 192, 144, 208);
    fwd_odd(p, 32, 48, 96, 112);
}

fn transform_macroblock(p: &mut [i32; 256], normalize_chroma: bool) {
    for block in 0..16 {
        dct4x4_stage1(p, block * 16);
    }
    if normalize_chroma {
        for i in (0..256).step_by(16) {
            p[i] >>= 1;
        }
    }
    dct4x4_second_stage(p);
}

// --------------------------------------------------------------------------------------------
// Entropy coding helpers
// --------------------------------------------------------------------------------------------

fn encode_significant_abs_level(level: u32, table: &mut Huffman, w: &mut BitWriter) {
    const INDEX: [usize; 16] = [0, 1, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5];
    const FIXED_LENGTH: [u32; 6] = [0, 0, 1, 2, 2, 2];
    debug_assert!(level > 0);
    let level = level - 1;
    if level >= 16 {
        let index = 6;
        let mut i = level >> 5;
        let mut fixed = 4u32;
        while i != 0 {
            fixed += 1;
            i >>= 1;
        }
        table.add_delta(index);
        table.put(w, index);
        if fixed > 18 {
            w.put(15, 4);
            if fixed > 21 {
                w.put(3, 2);
                w.put(fixed - 22, 3);
            } else {
                w.put(fixed - 19, 2);
            }
        } else {
            w.put(fixed - 4, 4);
        }
        w.put(level, fixed);
    } else {
        let index = INDEX[level as usize];
        table.add_delta(index);
        table.put(w, index);
        w.put(level, FIXED_LENGTH[index]);
    }
}

fn encode_significant_run(run: i32, max_run: i32, table: &Huffman, w: &mut BitWriter) {
    const INDEX: [usize; 34] = [
        0, 1, 2, 2, 3, 3, 4, 4, 4, 4, 4, 4, 4, 4, //
        0, 1, 2, 2, 3, 3, 4, 4, 4, 4, 0, 0, 0, 0, //
        0, 1, 2, 3, 4, 4,
    ];
    if max_run < 5 {
        const LEN: [u32; 4] = [3, 3, 2, 1];
        if max_run > 1 {
            w.put(
                (max_run != run) as u32,
                LEN[(max_run - run) as usize] - (4 - max_run) as u32,
            );
        }
        return;
    }
    let bin = SIGNIFICANT_RUN_BIN[max_run as usize];
    let index = INDEX[(run + bin * 14 - 1) as usize];
    let flc = SIGNIFICANT_RUN_FIXED_LENGTH[index + bin as usize * 5];
    table.put(w, index);
    w.put((run + 1) as u32, flc);
}

/// EncodeBlock: run/level coding of one block's significant coefficients; `offset` selects the
/// LP or HP group of VLC tables (runs always use table 0).
fn encode_block(
    chroma: bool,
    coefs: &[i32],
    count: usize,
    expt: &mut [Huffman],
    offset: usize,
    w: &mut BitWriter,
    mut location: i32,
) {
    // first symbol
    let lev = coefs[1];
    let sr = (coefs[0] == 0) as usize;
    let sl = ((lev + 1) as u32 > 2) as usize;
    let mut srn = if count == 1 {
        0
    } else if coefs[2] > 0 {
        2
    } else {
        1
    };
    let index = srn * 4 + sl * 2 + sr;
    {
        let t = &mut expt[offset + chroma as usize * 3];
        t.add_delta(index);
        t.add_delta1(index);
        w.put(
            t.codes[index * 2 + 1] as u32 * 2 + (lev < 0) as u32,
            t.codes[index * 2 + 2] as u32 + 1,
        );
    }
    // iCont = iSR & iSRn (bitwise, with iSRn in 0..=2)
    let mut cont = sr & srn;
    if sl != 0 {
        let t = &mut expt[6 + offset + cont];
        encode_significant_abs_level(lev.unsigned_abs() - 1, t, w);
    }
    if sr == 0 {
        encode_significant_run(coefs[0], 15 - location, &expt[0], w);
    }
    location += coefs[0] + 1;
    for k in 1..count {
        if srn == 2 {
            encode_significant_run(coefs[k * 2], 15 - location, &expt[0], w);
        }
        location += coefs[k * 2] + 1;
        srn = if k == count - 1 {
            0
        } else if coefs[k * 2 + 2] > 0 {
            2
        } else {
            1
        };
        let lev = coefs[k * 2 + 1];
        let sl = ((lev + 1) as u32 > 2) as usize;
        let index = srn * 2 + sl;
        let sign = (lev < 0) as u32;
        // EncodeIndex
        if location < 15 {
            let t = &mut expt[offset + cont + 1 + chroma as usize * 3];
            t.add_delta(index);
            t.add_delta1(index);
            w.put(
                t.codes[index * 2 + 1] as u32 * 2 + sign,
                t.codes[index * 2 + 2] as u32 + 1,
            );
        } else if location == 15 {
            const CODE: [u32; 4] = [0, 6, 2, 7];
            const LEN: [u32; 4] = [1, 3, 2, 3];
            w.put(CODE[index] * 2 + sign, LEN[index] + 1);
        } else {
            w.put(index as u32 * 2 + sign, 2);
        }
        cont &= srn;
        if sl != 0 {
            let t = &mut expt[6 + offset + cont];
            encode_significant_abs_level(lev.unsigned_abs() - 1, t, w);
        }
    }
}

/// AdaptiveScan: collects (run, level) pairs in adaptive scan order into `rl`, the flexbit
/// residuals by position into `residual`, and returns the number of significant coefficients.
fn adaptive_scan(
    coefs: &[i32],
    residual: &mut [i32; 16],
    scan: &mut [Scan; 16],
    model_bits: i32,
    trim_bits: i32,
    rl: &mut [i32; 32],
) -> usize {
    let mut count = 0usize;
    let bump = |scan: &mut [Scan; 16], k: usize| {
        scan[k].total += 1;
        if k > 1 && scan[k].total > scan[k - 1].total {
            scan.swap(k, k - 1);
        }
    };
    if model_bits == 0 {
        let mut run = 0;
        for k in 1..16 {
            let level = coefs[scan[k].scan];
            if level != 0 {
                bump(scan, k);
                rl[count * 2] = run;
                rl[count * 2 + 1] = level;
                count += 1;
                run = 0;
            } else {
                run += 1;
            }
        }
        return count;
    }
    let th_off = (1u32 << model_bits) - 1;
    let th = th_off * 2 + 1;
    if model_bits <= trim_bits {
        let mut run = 0;
        for k in 1..16 {
            let level = coefs[scan[k].scan];
            if (level as u32).wrapping_add(th_off) >= th {
                let t = (level.unsigned_abs() >> model_bits) as i32;
                bump(scan, k);
                rl[count * 2] = run;
                rl[count * 2 + 1] = if level < 0 { -t } else { t };
                count += 1;
                run = 0;
            } else {
                run += 1;
            }
        }
        return count;
    }
    let mut run = 0;
    for k in 1..16 {
        let pos = scan[k].scan;
        let level = coefs[pos];
        if (level as u32).wrapping_add(th_off) >= th {
            let a = level.unsigned_abs();
            let t = (a >> model_bits) as i32;
            residual[pos] = (((a & th_off) >> trim_bits) * 2) as i32;
            bump(scan, k);
            rl[count * 2] = run;
            rl[count * 2 + 1] = if level < 0 { -t } else { t };
            count += 1;
            run = 0;
        } else {
            run += 1;
            let s = -((level < 0) as i32);
            let l = ((level + s) >> trim_bits) - s; // round towards zero
            let s = -((l < 0) as i32);
            residual[pos] = (l ^ s) * 4 + (6 & s) + (l != 0) as i32;
        }
    }
    count
}

// --------------------------------------------------------------------------------------------
// Image plane (primary YUV 4:4:4 or the interleaved Y_ONLY alpha plane)
// --------------------------------------------------------------------------------------------

#[derive(Clone, Copy, Default)]
struct PredInfo {
    cbp: i32,
    dc: i32,
    ad: [i32; 6],
}

#[derive(Clone, Copy)]
struct Position {
    mbx: usize,
    ctx_left: bool,
    ctx_top: bool,
    reset_context: bool,
}

struct Plane {
    y_only: bool,
    channels: usize,
    scaled: bool,
    quant_dc: [Quantizer; 3],
    quant_lp: [Quantizer; 3],
    quant_hp: [Quantizer; 3],
    ctx: Context,
    pred: Vec<Vec<PredInfo>>,
    pred_prev: Vec<Vec<PredInfo>>,
    mb: Vec<[i32; 256]>,
    block_dc: [[i32; 16]; 3],
    cbp: [i32; 3],
    diff_cbp: [i32; 3],
    orientation: i32,
}

impl Plane {
    fn new(y_only: bool, mb_width: usize, qp_index: u8, trim_flex_bits: i32) -> Self {
        let channels = if y_only { 1 } else { 3 };
        // DC and LP chroma quantisers use one bit less of shift (formatQuantizer bShiftedUV).
        let q = |ch: usize, uv_shifted: bool, dc: bool| {
            let shift = if ch > 0 && uv_shifted { 0 } else { 1 };
            Quantizer::new(qp_index, shift, dc)
        };
        Self {
            y_only,
            channels,
            scaled: qp_index != 0,
            quant_dc: [q(0, true, true), q(1, true, true), q(2, true, true)],
            quant_lp: [q(0, true, false), q(1, true, false), q(2, true, false)],
            quant_hp: [q(0, false, false), q(1, false, false), q(2, false, false)],
            ctx: Context::new(y_only, trim_flex_bits),
            pred: vec![vec![PredInfo::default(); mb_width]; channels],
            pred_prev: vec![vec![PredInfo::default(); mb_width]; channels],
            mb: vec![[0; 256]; channels],
            block_dc: [[0; 16]; 3],
            cbp: [0; 3],
            diff_cbp: [0; 3],
            orientation: 0,
        }
    }

    fn write_header(&self, w: &mut BitWriter, qp_index: u8) {
        w.put(if self.y_only { 0 } else { 3 }, 3); // internal colour format
        w.put(self.scaled as u32, 1);
        w.put(0, 4); // all subbands
        if !self.y_only {
            w.put(0, 4); // chroma centering
            w.put(0, 4);
        }
        // Like Flash: lossless writes "mixed" channel mode, lossy one QP for all channels.
        let write_quantizer = |w: &mut BitWriter| {
            let mode = if qp_index == 0 { 1 } else { 0 };
            if self.channels > 1 {
                w.put(mode, 2);
            }
            w.put(u32::from(qp_index), 8);
            if self.channels > 1 && mode == 1 {
                w.put(u32::from(qp_index), 8);
            }
        };
        w.put(1, 1); // DC frame uniform
        write_quantizer(w);
        w.put(0, 1); // LP: not the DC quantiser
        w.put(1, 1); // LP frame uniform
        write_quantizer(w);
        w.put(0, 1); // HP: not the LP quantiser
        w.put(1, 1); // HP frame uniform
        write_quantizer(w);
        w.align();
    }

    fn next_row(&mut self) {
        std::mem::swap(&mut self.pred, &mut self.pred_prev);
    }

    fn encode_macroblock(&mut self, w: &mut BitWriter, pos: Position) {
        for ch in 0..self.channels {
            transform_macroblock(&mut self.mb[ch], self.scaled && ch > 0);
        }
        self.encode_dc(w, pos);
        self.encode_lowpass(w, pos);
        self.encode_highpass(w, pos);
    }

    fn quantize(&mut self) {
        for ch in 0..self.channels {
            let p = &mut self.mb[ch];
            for (j, &off) in BLK_OFFSET.iter().enumerate() {
                p[off] = if j == 0 {
                    self.quant_dc[ch].quantize(p[off])
                } else {
                    self.quant_lp[ch].quantize(p[off])
                };
                for i in 1..16 {
                    p[off + i] = self.quant_hp[ch].quantize(p[off + i]);
                }
            }
            for i in 0..16 {
                self.block_dc[ch][i] = p[DCT_INDEX_DC[i]];
            }
        }
    }

    fn dcac_pred_mode(&self, pos: Position) -> (i32, i32) {
        let mbx = pos.mbx;
        let dc_mode = if pos.ctx_left && pos.ctx_top {
            3
        } else if pos.ctx_left {
            1
        } else if pos.ctx_top {
            0
        } else {
            let l = self.pred[0][mbx - 1].dc;
            let t = self.pred_prev[0][mbx].dc;
            let tl = self.pred_prev[0][mbx - 1].dc;
            let (str_h, str_v) = if self.y_only {
                ((tl - l).abs(), (tl - t).abs())
            } else {
                let c = |ch: usize| {
                    let t = self.pred_prev[ch][mbx].dc;
                    let l = self.pred[ch][mbx - 1].dc;
                    let tl = self.pred_prev[ch][mbx - 1].dc;
                    ((tl - l).abs(), (tl - t).abs())
                };
                let (uh, uv) = c(1);
                let (vh, vv) = c(2);
                ((tl - l).abs() * 2 + uh + vh, (tl - t).abs() * 2 + uv + vv)
            };
            if str_h * 4 < str_v {
                1
            } else if str_v * 4 < str_h {
                0
            } else {
                2
            }
        };
        // The QP index never changes between macroblocks, so AD prediction follows DC.
        let ad_mode = match dc_mode {
            0 => 0,
            1 => 1,
            _ => 2,
        };
        (dc_mode, ad_mode)
    }

    fn ac_pred_mode(&self) -> i32 {
        let c = &self.block_dc[0];
        let mut str_h = c[1].abs() + c[2].abs() + c[3].abs();
        let mut str_v = c[4].abs() + c[8].abs() + c[12].abs();
        if !self.y_only {
            let u = &self.block_dc[1];
            let v = &self.block_dc[2];
            str_h += u[1].abs() + v[1].abs();
            str_v += u[4].abs() + v[4].abs();
        }
        if str_h * 4 < str_v {
            1
        } else if str_v * 4 < str_h {
            0
        } else {
            2
        }
    }

    /// predMacroblockEnc (4:4:4 / Y_ONLY).
    fn predict(&mut self, pos: Position) {
        let mbx = pos.mbx;
        let (dc_mode, ad_mode) = self.dcac_pred_mode(pos);
        let ac_mode = self.ac_pred_mode();
        self.orientation = 2 - ac_mode;
        // updatePredInfo, before the prediction changes the values
        for ch in 0..self.channels {
            let p = &self.block_dc[ch];
            let info = &mut self.pred[ch][mbx];
            info.dc = p[0];
            info.ad = [p[1], p[2], p[3], p[4], p[8], p[12]];
        }
        for ch in 0..self.channels {
            let org = &mut self.block_dc[ch];
            match dc_mode {
                1 => org[0] -= self.pred_prev[ch][mbx].dc,
                0 => org[0] -= self.pred[ch][mbx - 1].dc,
                2 => org[0] -= (self.pred[ch][mbx - 1].dc + self.pred_prev[ch][mbx].dc) >> 1,
                _ => {}
            }
            if ad_mode == 1 {
                let r = self.pred_prev[ch][mbx].ad;
                org[4] -= r[3];
                org[8] -= r[4];
                org[12] -= r[5];
            } else if ad_mode == 0 {
                let r = self.pred[ch][mbx - 1].ad;
                org[1] -= r[0];
                org[2] -= r[1];
                org[3] -= r[2];
            }
            let p = &mut self.mb[ch];
            if ac_mode == 1 {
                for k in (0..=192).step_by(64) {
                    for j in [48, 32, 16] {
                        p[k + j + 10] -= p[k + j + 10 - 16];
                        p[k + j + 2] -= p[k + j + 2 - 16];
                        p[k + j + 9] -= p[k + j + 9 - 16];
                    }
                }
            } else if ac_mode == 0 {
                for k in (0..64).step_by(16) {
                    for j in [192, 128, 64] {
                        p[k + j + 5] -= p[k + j + 5 - 64];
                        p[k + j + 1] -= p[k + j + 1 - 64];
                        p[k + j + 6] -= p[k + j + 6 - 64];
                    }
                }
            }
        }
    }

    fn encode_dc(&mut self, w: &mut BitWriter, pos: Position) {
        let mut model_bits = self.ctx.model_dc.flc_bits[0];
        self.quantize();
        self.predict(pos);
        let mut mean = [0i32; 2];
        if self.y_only {
            let dc = self.block_dc[0][0];
            let a = dc.unsigned_abs();
            let qdc = a >> model_bits;
            if qdc != 0 {
                w.put(1, 1);
                encode_significant_abs_level(qdc, &mut self.ctx.expt[3], w);
                mean[0] += 1;
            } else {
                w.put(0, 1);
            }
            w.put(a, model_bits as u32);
            if dc != 0 {
                w.put((dc < 0) as u32, 1);
            }
        } else {
            let [y, u, v] = [
                self.block_dc[0][0],
                self.block_dc[1][0],
                self.block_dc[2][0],
            ];
            let qy = y.unsigned_abs() >> model_bits;
            let uv_bits = self.ctx.model_dc.flc_bits[1];
            let qu = u.unsigned_abs() >> uv_bits;
            let qv = v.unsigned_abs() >> uv_bits;
            let index = (qy != 0) as usize * 4 + (qu != 0) as usize * 2 + (qv != 0) as usize;
            self.ctx.expt[2].put(w, index);
            if qy != 0 {
                encode_significant_abs_level(qy, &mut self.ctx.expt[3], w);
                mean[0] += 1;
            }
            w.put(y.unsigned_abs(), model_bits as u32);
            if y != 0 {
                w.put((y < 0) as u32, 1);
            }
            model_bits = uv_bits;
            for (value, q) in [(u, qu), (v, qv)] {
                if q != 0 {
                    encode_significant_abs_level(q, &mut self.ctx.expt[4], w);
                    mean[1] += 1;
                }
                w.put(value.unsigned_abs(), model_bits as u32);
                if value != 0 {
                    w.put((value < 0) as u32, 1);
                }
            }
        }
        self.ctx.model_dc.update(self.y_only, self.channels, mean);
    }

    fn encode_lowpass(&mut self, w: &mut BitWriter, pos: Position) {
        let channels = self.channels;
        if pos.mbx & 0xf == 0 {
            reset_scan_totals(&mut self.ctx.scan_lowpass);
        }
        let mut rl = [[0i32; 32]; 3];
        let mut residual = [[0i32; 16]; 3];
        let mut counts = [0usize; 3];
        let mut model_bits = self.ctx.model_lp.flc_bits[0];
        for ch in 0..channels {
            counts[ch] = adaptive_scan(
                &self.block_dc[ch],
                &mut residual[ch],
                &mut self.ctx.scan_lowpass,
                model_bits,
                0,
                &mut rl[ch],
            );
            model_bits = self.ctx.model_lp.flc_bits[1];
        }
        if !self.y_only {
            let max = 7; // (1 << channels) - 1
            let mut count_max = self.ctx.cbp_count_max;
            let mut count_zero = self.ctx.cbp_count_zero;
            let cbp =
                (counts[0] > 0) as i32 + (counts[1] > 0) as i32 * 2 + (counts[2] > 0) as i32 * 4;
            if count_zero <= 0 || count_max < 0 {
                let mut val = cbp;
                if count_max < count_zero {
                    val = max - cbp;
                }
                if val == 0 {
                    w.put(0, 1);
                } else if val == 1 {
                    w.put(4, 3); // (iFullChannels + 1) & 6 in iFullChannels bits
                } else {
                    w.put((val + max + 1) as u32, 4);
                }
            } else {
                w.put(cbp as u32, 3);
            }
            count_max += 1 - 4 * (cbp == max) as i32;
            count_zero += 1 - 4 * (cbp == 0) as i32;
            self.ctx.cbp_count_max = count_max.clamp(-8, 7);
            self.ctx.cbp_count_zero = count_zero.clamp(-8, 7);
        } else {
            w.put((counts[0] > 0) as u32, 1);
        }
        let mut mean = [0i32; 2];
        let mut mean_index = 0;
        model_bits = self.ctx.model_lp.flc_bits[0];
        for ch in 0..channels {
            if counts[ch] != 0 {
                mean[mean_index] += counts[ch] as i32;
                encode_block(ch > 0, &rl[ch], counts[ch], &mut self.ctx.expt, CTDC, w, 1);
            }
            if model_bits != 0 {
                for k in 1..16 {
                    let r = residual[ch][k];
                    w.put((r >> 1) as u32, (model_bits + (r & 1)) as u32);
                }
            }
            mean_index = 1;
            model_bits = self.ctx.model_lp.flc_bits[1];
        }
        self.ctx.model_lp.update(self.y_only, channels, mean);
        if pos.reset_context {
            self.ctx.adapt_lowpass();
        }
    }

    fn predict_cbp(&mut self, pos: Position) {
        let mbx = pos.mbx;
        for ch in 0..self.channels {
            let bits = self.ctx.model_ac.flc_bits[(ch > 0) as usize];
            let threshold = (1i32 << bits) - 1;
            let threshold2 = (threshold * 2 + 1) as u32;
            let mut cbp = 0i32;
            let p = &self.mb[ch];
            for (j, &off) in BLK_OFFSET.iter().enumerate() {
                if (1..16).any(|i| (p[off + i].wrapping_add(threshold) as u32) >= threshold2) {
                    cbp |= 1 << j;
                }
            }
            self.cbp[ch] = cbp;
            self.pred[ch][mbx].cbp = cbp;

            // predCBPCEnc
            let n_orig = (cbp & 0xffff).count_ones() as i32;
            const N_DIFF: i32 = 3;
            let mut pred = if pos.ctx_left {
                if pos.ctx_top {
                    1
                } else {
                    (self.pred_prev[ch][mbx].cbp >> 10) & 1
                }
            } else {
                (self.pred[ch][mbx - 1].cbp >> 5) & 1
            };
            pred |= (cbp & 0x3300) << 2;
            pred |= (cbp & 0xcc) << 6;
            pred |= (cbp & 0x33) << 2;
            pred |= (cbp & 0x11) << 1;
            pred |= (cbp & 0x2) << 3;
            let c = (ch > 0) as usize;
            let m = &mut self.ctx.cbp_model;
            self.diff_cbp[ch] = match m.state[c] {
                0 => pred ^ cbp,
                1 => cbp,
                _ => cbp ^ 0xffff,
            };
            let saturate = |x: i32| {
                if (x + 16) as u32 >= 32 {
                    if x < 0 { -16 } else { 15 }
                } else {
                    x
                }
            };
            m.count0[c] = saturate(m.count0[c] + n_orig - N_DIFF);
            m.count1[c] = saturate(m.count1[c] + 16 - n_orig - N_DIFF);
            m.state[c] = if m.count0[c] < 0 {
                if m.count0[c] < m.count1[c] { 1 } else { 2 }
            } else if m.count1[c] < 0 {
                2
            } else {
                0
            };
        }
    }

    fn code_cbp(&mut self, w: &mut BitWriter, pos: Position) {
        const NUM_ONES: [usize; 16] = [0, 1, 1, 2, 1, 2, 2, 3, 1, 2, 2, 3, 2, 3, 3, 4];
        const TAB_LEN: [u32; 16] = [0, 2, 2, 2, 2, 2, 3, 2, 2, 3, 3, 2, 3, 2, 2, 0];
        const TAB_CODE: [u32; 16] = [0, 0, 1, 0, 2, 1, 4, 3, 3, 5, 6, 2, 7, 1, 0, 0];
        const TAB0: [i32; 16] = [0, 1, 1, 2, 1, 3, 3, 4, 1, 3, 3, 4, 2, 4, 4, 5];
        const FL0: [u32; 16] = [0, 2, 2, 1, 2, 2, 2, 2, 2, 2, 2, 2, 1, 2, 2, 0];
        const CODE0: [u32; 16] = [0, 0, 1, 0, 2, 0, 1, 0, 3, 2, 3, 1, 1, 2, 3, 0];

        self.predict_cbp(pos);
        let mut dy = self.diff_cbp[0];
        let mut du = if self.y_only { 0 } else { self.diff_cbp[1] };
        let mut dv = if self.y_only { 0 } else { self.diff_cbp[2] };

        let mut pattern = 0usize;
        let mut d = dy | du | dv;
        for _ in 0..4 {
            pattern |= ((d & 0xf) != 0) as usize * 0x10;
            d >>= 4;
            pattern >>= 1;
        }
        let count = NUM_ONES[pattern];
        self.ctx.cbpcy1.put(w, count);
        self.ctx.cbpcy1.add_delta(count);
        if TAB_LEN[pattern] != 0 {
            w.put(TAB_CODE[pattern], TAB_LEN[pattern]);
        }
        for _ in 0..4 {
            let mut code = dy & 0xf;
            let code_u = (du & 0xf) as usize;
            let code_v = (dv & 0xf) as usize;
            code |= ((code_u != 0) as i32) << 4;
            code |= ((code_v != 0) as i32) << 5;
            dy >>= 4;
            du >>= 4;
            dv >>= 4;
            if code == 0 {
                continue;
            }
            let chroma = code >> 4;
            let code = (code & 0xf) as usize;
            let val = if chroma != 0 {
                if TAB0[code] > 2 { 8 } else { TAB0[code] + 5 }
            } else {
                TAB0[code] - 1
            } as usize;
            self.ctx.cbpcy.put(w, val);
            self.ctx.cbpcy.add_delta(val);
            if chroma != 0 {
                if chroma == 1 {
                    w.put(1, 1);
                } else {
                    w.put((3 - chroma) as u32, 2);
                }
            }
            if val == 8 {
                if TAB0[code] == 3 {
                    w.put(1, 1);
                } else {
                    w.put((5 - TAB0[code]) as u32, 2);
                }
            }
            if FL0[code] != 0 {
                w.put(CODE0[code], FL0[code]);
            }
            if !self.y_only {
                for p in [code_u, code_v] {
                    if p != 0 {
                        let c = NUM_ONES[p] - 1;
                        self.ctx.expt[1].put(w, c);
                        if TAB_LEN[p] != 0 {
                            w.put(TAB_CODE[p], TAB_LEN[p]);
                        }
                    }
                }
            }
        }
    }

    fn code_coefficients(&mut self, w: &mut BitWriter) {
        let mut model_bits = self.ctx.model_ac.flc_bits[0];
        let trim_setting = self.ctx.trim_flex_bits;
        let flex_for = |model_bits: i32| -> (i32, i32, i32) {
            if trim_setting <= model_bits {
                let flex = model_bits - trim_setting;
                (trim_setting, flex, (1 << flex) - 1)
            } else {
                (0, 0, 0)
            }
        };
        let (mut trim, mut flex, mut mask) = flex_for(model_bits);
        let mut mean = [0i32; 2];
        let mut mean_index = 0;
        let mut chroma = false;
        let vertical = self.orientation == 1;
        for plane in 0..self.channels {
            let mut pattern = self.cbp[plane];
            let mut index = 0;
            for block in 0..4 {
                for _ in 0..4 {
                    let off = BLK_OFFSET[index];
                    let coefs: [i32; 16] = self.mb[plane][off..off + 16].try_into().unwrap();
                    if pattern & 1 == 0 {
                        if flex != 0 {
                            for k in 1..16 {
                                let data = coefs[DCT_INDEX_AC[k]];
                                let at = data.unsigned_abs() >> trim;
                                let mut word = at & mask as u32;
                                let mut len = flex as u32;
                                if at != 0 {
                                    word = word * 2 + (data < 0) as u32;
                                    len += 1;
                                }
                                w.put(word, len);
                            }
                        }
                    } else {
                        let mut rl = [0i32; 32];
                        let mut residual = [0i32; 16];
                        let scan = if vertical {
                            &mut self.ctx.scan_vert
                        } else {
                            &mut self.ctx.scan_horiz
                        };
                        let count =
                            adaptive_scan(&coefs, &mut residual, scan, model_bits, trim, &mut rl);
                        mean[mean_index] += count as i32;
                        encode_block(
                            chroma,
                            &rl,
                            count,
                            &mut self.ctx.expt,
                            CTDC + CONTEXTX,
                            w,
                            1,
                        );
                        if flex != 0 {
                            for k in 1..16 {
                                let r = residual[DCT_INDEX_AC[k]];
                                w.put((r >> 1) as u32, (flex + (r & 1)) as u32);
                            }
                        }
                    }
                    pattern >>= 1;
                    index += 1;
                }
                if block == 3 {
                    model_bits = self.ctx.model_ac.flc_bits[1];
                    mean_index = 1;
                    chroma = true;
                    (trim, flex, mask) = flex_for(model_bits);
                }
            }
        }
        self.ctx.model_ac.update(self.y_only, self.channels, mean);
    }

    fn encode_highpass(&mut self, w: &mut BitWriter, pos: Position) {
        if pos.mbx & 0xf == 0 {
            reset_scan_totals(&mut self.ctx.scan_horiz);
            reset_scan_totals(&mut self.ctx.scan_vert);
        }
        self.code_cbp(w, pos);
        self.code_coefficients(w);
        if pos.reset_context {
            self.ctx.adapt_highpass();
        }
    }
}

// --------------------------------------------------------------------------------------------
// Codestream
// --------------------------------------------------------------------------------------------

fn encode_codestream(
    width: u32,
    height: u32,
    pixels: &[[u8; 4]],
    alpha: bool,
    qp_index: u8,
    trim_flex_bits: u8,
) -> Vec<u8> {
    let qp_index = if qp_index < 2 { 0 } else { qp_index };
    // With an alpha plane Flash writes no TRIM_FLEXBITS at all (bitmapdata_encode_jpegxr): the
    // tile header has one value, which decoders apply to the image plane only.
    let trim = if alpha {
        0
    } else {
        i32::from(trim_flex_bits.min(15))
    };
    let mb_width = width.div_ceil(16) as usize;
    let mb_height = height.div_ceil(16) as usize;
    let abbreviated = mb_width <= 255 && mb_height <= 255;

    let mut w = BitWriter::new();
    w.buf.extend_from_slice(b"WMPHOTO\0");
    w.put(1, 4); // version
    w.put(9, 4); // subversion: new scaling, hard tile boundaries (as Flash writes)
    w.put(0, 1); // no tiling
    w.put(0, 1); // spatial order
    w.put(0, 3); // no rotation / flip
    w.put(0, 1); // no index table
    w.put(0, 2); // no overlap filter
    w.put(abbreviated as u32, 1);
    w.put(1, 1); // long words
    w.put(0, 1); // no windowing
    w.put((trim > 0) as u32, 1);
    w.put(0, 1); // no tile stretching
    w.put(0, 2); // reserved
    w.put(alpha as u32, 1);
    w.put(7, 4); // source: RGB
    w.put(1, 4); // source: 8 bits per channel
    let size_bits = if abbreviated { 16 } else { 32 };
    w.put(width - 1, size_bits);
    w.put(height - 1, size_bits);
    w.align();

    let mut planes = vec![Plane::new(false, mb_width, qp_index, trim)];
    if alpha {
        planes.push(Plane::new(true, mb_width, qp_index, trim));
    }
    for plane in &planes {
        plane.write_header(&mut w, qp_index);
    }
    // Profile/level information (no index table)
    w.align();
    w.put(4, 16);
    w.put(111, 8);
    w.put(255, 8);
    w.put(1, 16);

    let shift = if qp_index != 0 { 3 } else { 0 };
    let offset = 128 << shift;
    for mby in 0..mb_height {
        for mbx in 0..mb_width {
            // Load the macroblock (edge pixels repeat beyond the image)
            for row in 0..16 {
                let y = (mby * 16 + row).min(height as usize - 1);
                for col in 0..16 {
                    let x = (mbx * 16 + col).min(width as usize - 1);
                    let [r, g, b, a] = pixels[y * width as usize + x];
                    let i = IDX_CC[row][col] as usize;
                    let mut r = i32::from(r) << shift;
                    let mut g = i32::from(g) << shift;
                    let mut b = i32::from(b) << shift;
                    b -= r;
                    r += ((b + 1) >> 1) - g;
                    g += r >> 1;
                    let p = &mut planes[0];
                    p.mb[0][i] = g - offset;
                    p.mb[1][i] = -r;
                    p.mb[2][i] = b;
                    if alpha {
                        planes[1].mb[0][i] = (i32::from(a) - 128) << shift;
                    }
                }
            }
            let pos = Position {
                mbx,
                ctx_left: mbx == 0,
                ctx_top: mby == 0,
                reset_context: mbx & 0xf == 0 || mbx + 1 == mb_width,
            };
            if mbx == 0 && mby == 0 {
                // Packet header of the (only) tile: 00 00 01, type 0 (spatial), tile 0
                w.put(0, 8);
                w.put(0, 8);
                w.put(1, 8);
                w.put(0, 8);
                if trim > 0 {
                    w.put(trim as u32, 4);
                }
            }
            for plane in &mut planes {
                plane.encode_macroblock(&mut w, pos);
            }
        }
        for plane in &mut planes {
            plane.next_row();
        }
    }
    w.align();
    w.buf
}

#[cfg(all(test, feature = "jpegxr"))]
mod tests {
    use super::*;
    use std::io::Cursor;

    /// Decodes like Loader.loadBytes does (jxrlib via `ruffle_render`), returning
    /// (width, height, [r, g, b, a] pixels, whether the file has alpha).
    fn decode(data: &[u8]) -> (u32, u32, Vec<[u8; 4]>, bool) {
        let alpha = {
            let d = jpegxr::ImageDecode::with_reader(Cursor::new(data)).expect("decoder");
            jpegxr::PixelInfo::from_format(d.get_pixel_format().expect("format")).has_alpha()
        };
        let bitmap = ruffle_render::utils::decode_define_bits_jpeg(data, None).expect("decode");
        assert_eq!(bitmap.format().supports_transparency(), alpha);
        let px = bitmap
            .data()
            .chunks(if alpha { 4 } else { 3 })
            .map(|c| [c[0], c[1], c[2], if alpha { c[3] } else { 255 }])
            .collect();
        (bitmap.width(), bitmap.height(), px, alpha)
    }

    fn rng(seed: &mut u32) -> u32 {
        *seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
        *seed >> 8
    }

    fn premultiply(c: [u8; 4]) -> [u8; 4] {
        let a = u32::from(c[3]);
        let m = |v: u8| ((u32::from(v) * a + 127) / 255) as u8;
        [m(c[0]), m(c[1]), m(c[2]), c[3]]
    }

    fn random_image(w: u32, h: u32, seed: u32, alpha: bool) -> Vec<[u8; 4]> {
        let mut s = seed;
        (0..w * h)
            .map(|_| {
                let v = rng(&mut s);
                let c = [
                    v as u8,
                    (v >> 8) as u8,
                    (v >> 16) as u8,
                    if alpha { rng(&mut s) as u8 } else { 255 },
                ];
                if alpha { premultiply(c) } else { c }
            })
            .collect()
    }

    fn gradient_image(w: u32, h: u32, alpha: bool) -> Vec<[u8; 4]> {
        let mut v = Vec::new();
        for y in 0..h {
            for x in 0..w {
                let r = (x * 255 / (w - 1).max(1)) as u8;
                let g = (y * 255 / (h - 1).max(1)) as u8;
                let b = ((x * 3 + y * 5) & 255) as u8;
                let a = if alpha {
                    (((x + y) * 9) & 255) as u8 | 1
                } else {
                    255
                };
                v.push(if alpha {
                    premultiply([r, g, b, a])
                } else {
                    [r, g, b, a]
                });
            }
        }
        v
    }

    fn psnr(a: &[[u8; 4]], b: &[[u8; 4]], channels: usize) -> f64 {
        let mut se = 0f64;
        for (p, q) in a.iter().zip(b) {
            for c in 0..channels {
                let d = f64::from(p[c]) - f64::from(q[c]);
                se += d * d;
            }
        }
        let mse = se / (a.len() * channels) as f64;
        if mse == 0.0 {
            f64::INFINITY
        } else {
            10.0 * (255.0 * 255.0 / mse).log10()
        }
    }

    const SIZES: [(u32, u32); 9] = [
        (1, 1),
        (8, 8),
        (16, 16),
        (17, 3),
        (64, 48),
        (33, 70),
        (300, 20),
        (5, 260),
        (257, 33),
    ];

    #[test]
    fn lossless_round_trip() {
        for (i, &(w, h)) in SIZES.iter().enumerate() {
            for alpha in [false, true] {
                for img in [
                    random_image(w, h, i as u32 * 7 + 1, alpha),
                    gradient_image(w, h, alpha),
                ] {
                    {
                        let trim = 0;
                        let data = encode(w, h, &img, alpha, 0, trim);
                        let (dw, dh, px, dalpha) = decode(&data);
                        assert_eq!((dw, dh, dalpha), (w, h, alpha));
                        assert!(
                            px == img,
                            "lossless mismatch {w}x{h} alpha={alpha} trim={trim}"
                        );
                    }
                }
            }
        }
    }

    #[test]
    fn lossy_quality() {
        for &(w, h) in &SIZES[1..] {
            for alpha in [false, true] {
                let img = gradient_image(w, h, alpha);
                for (q, min_psnr) in [(1, 38.0), (20, 33.0), (50, 26.0), (100, 12.0)] {
                    for trim in [0, 4, 15] {
                        let data = encode(w, h, &img, alpha, quantization_to_qp_index(q), trim);
                        let (_, _, px, _) = decode(&data);
                        let p = psnr(&img, &px, if alpha { 4 } else { 3 });
                        assert!(
                            p >= min_psnr,
                            "{w}x{h} alpha={alpha} q={q} trim={trim}: PSNR {p:.1}"
                        );
                    }
                }
                let noise = random_image(w, h, w * 31 + h, alpha);
                let data = encode(w, h, &noise, alpha, quantization_to_qp_index(20), 0);
                let (_, _, px, _) = decode(&data);
                let p = psnr(&noise, &px, 3);
                assert!(p > 30.0, "noise {w}x{h} alpha={alpha}: PSNR {p:.1}");
            }
        }
    }

    #[test]
    fn qp_mapping() {
        assert_eq!(quantization_to_qp_index(0), 0);
        assert_eq!(quantization_to_qp_index(1), 2);
        assert_eq!(quantization_to_qp_index(15), 30);
        assert_eq!(quantization_to_qp_index(16), 34);
        assert_eq!(quantization_to_qp_index(20), 38);
        assert_eq!(quantization_to_qp_index(48), 66);
        assert_eq!(quantization_to_qp_index(49), 69);
        assert_eq!(quantization_to_qp_index(100), 120);
    }

    /// Flash Player 32 output (D63JpegXr.hx). Flash's encoder is jxrlib with the same settings,
    /// so with the exact source pixels (Flash's premultiplied values, read back from its lossless
    /// file) our files are byte-identical to Flash's, except that Flash appends one or two zero
    /// bytes after the codestream.
    #[test]
    fn flash_output() {
        let bytes = |hex: &str| -> Vec<u8> {
            (0..hex.len())
                .step_by(2)
                .map(|i| u8::from_str_radix(&hex[i..i + 2], 16).unwrap())
                .collect()
        };
        let samples = super::super::jpegxr_flash_samples::SAMPLES;
        for &(name, quantization, hex, argb) in samples {
            let data = bytes(hex);
            let (w, h, px, alpha) = decode(&data);
            assert_eq!(px.len(), argb.len(), "{name}");
            // The decoded lossless file is exactly the bitmap Flash encoded.
            let bitmap = name.split(' ').next().unwrap();
            let lossless = samples
                .iter()
                .find(|s| s.0.starts_with(bitmap) && s.1 == 0)
                .expect("lossless sample");
            let (_, _, source, _) = decode(&bytes(lossless.2));
            for (s, &c) in source.iter().zip(argb) {
                // getPixel32 of the source bitmap = the decoded pixel, un-premultiplied
                let a = c >> 24;
                assert_eq!(u32::from(s[3]), a, "{name}: alpha");
                if a == 255 {
                    assert_eq!(
                        [s[0], s[1], s[2]],
                        [(c >> 16) as u8, (c >> 8) as u8, c as u8],
                        "{name}"
                    );
                }
            }
            if quantization != 0 {
                assert!(psnr(&source, &px, 3) > 30.0, "{name}");
            }
            let ours = encode(
                w,
                h,
                &source,
                alpha,
                quantization_to_qp_index(quantization),
                0,
            );
            // Container: everything but ImageByteCount (bytes 66..70) is the same
            assert_eq!(ours[..66], data[..66], "{name}: container");
            assert_eq!(ours[70..90], data[70..90], "{name}: container");
            assert!(
                data.len() >= ours.len() && data.len() <= ours.len() + 2,
                "{name}: length"
            );
            assert!(
                data[70..ours.len()] == ours[70..],
                "{name}: codestream differs from Flash's"
            );
            // Flash's ImageByteCount counts none or some of its padding
            let count = u32::from_le_bytes(data[66..70].try_into().unwrap()) as usize;
            assert!(
                count >= ours.len() - 90 && count <= data.len() - 90,
                "{name}: count"
            );
            assert!(
                data[ours.len()..].iter().all(|&b| b == 0),
                "{name}: padding"
            );
        }
    }
}
