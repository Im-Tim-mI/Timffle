//! Timffle: CPU codecs for the block-compressed and packed texture formats
//! Stage3D can take (`Context3DTextureFormat` BGR_PACKED / BGRA_PACKED /
//! COMPRESSED / COMPRESSED_ALPHA and the ATF container's DXT1, DXT5, ETC1,
//! ETC2 RGB/RGBA and PVRTC 4bpp payloads).
//!
//! Every decoder produces straight (non-premultiplied) RGBA8, row-major,
//! `width * height * 4` bytes. The decoders follow the format specifications:
//! DXT from the Direct3D BC1/BC3 definition, ETC1/ETC2/EAC from the Khronos
//! Data Format Specification (section "ETC2 compressed texture image formats",
//! including the T, H and planar modes), PVRTC 4bpp from Imagination's
//! reference decompressor (two bilinearly upscaled colour planes blended per
//! pixel by a 2-bit modulation value, blocks stored in Morton order).

/// Block formats a GPU texture of a compressed Stage3D format may store
/// natively (chosen by the render backend from the adapter's features).
#[derive(Debug, Copy, Clone, PartialEq, Eq)]
pub enum CompressedFormat {
    /// BC1 / DXT1, 8 bytes per 4x4 block.
    Dxt1,
    /// BC3 / DXT5, 16 bytes per 4x4 block.
    Dxt5,
    /// ETC2 RGB8, 8 bytes per 4x4 block (ETC1 blocks are valid ETC2 RGB blocks).
    Etc2Rgb,
    /// ETC2 RGBA8 (EAC alpha + ETC2 RGB), 16 bytes per 4x4 block.
    Etc2Rgba,
}

impl CompressedFormat {
    pub fn block_bytes(self) -> usize {
        match self {
            CompressedFormat::Dxt1 | CompressedFormat::Etc2Rgb => 8,
            CompressedFormat::Dxt5 | CompressedFormat::Etc2Rgba => 16,
        }
    }

    /// Bytes one mip level of `width` x `height` pixels takes in this format.
    pub fn level_bytes(self, width: u32, height: u32) -> usize {
        blocks(width) * blocks(height) * self.block_bytes()
    }
}

/// Number of 4-pixel blocks covering `pixels` pixels (at least one).
pub fn blocks(pixels: u32) -> usize {
    (pixels.max(1) as usize).div_ceil(4)
}

// ---------------------------------------------------------------------------
// Packed 16-bit formats
// ---------------------------------------------------------------------------

/// Quantises straight RGBA8 to 5-6-5 (alpha dropped, opaque) and expands it
/// back, so sampling gives exactly the precision of a BGR_PACKED texture.
pub fn quantize_rgb565(rgba: &mut [u8]) {
    for px in rgba.chunks_exact_mut(4) {
        let packed = pack_565(px[0], px[1], px[2]);
        let (r, g, b) = unpack_565(packed);
        px[0] = r;
        px[1] = g;
        px[2] = b;
        px[3] = 255;
    }
}

/// Quantises straight RGBA8 to 4-4-4-4 and expands it back (BGRA_PACKED).
pub fn quantize_rgba4444(rgba: &mut [u8]) {
    for px in rgba.chunks_exact_mut(4) {
        let packed = pack_4444(px[0], px[1], px[2], px[3]);
        let (r, g, b, a) = unpack_4444(packed);
        px[0] = r;
        px[1] = g;
        px[2] = b;
        px[3] = a;
    }
}

/// RGB565 pixels as Flash's `uploadFromByteArray` takes them for a
/// BGR_PACKED texture (one little-endian u16 per pixel, bits 15..11 red,
/// 10..5 green, 4..0 blue) to RGBA8.
pub fn rgb565_le_to_rgba(packed: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(packed.len() * 2);
    for px in packed.chunks_exact(2) {
        let (r, g, b) = unpack_565(u16::from_le_bytes([px[0], px[1]]));
        out.extend_from_slice(&[r, g, b, 255]);
    }
    out
}

/// ARGB4444 pixels (one little-endian u16 per pixel, bits 15..12 alpha,
/// 11..8 red, 7..4 green, 3..0 blue — the BGRA_PACKED layout) to RGBA8.
pub fn argb4444_le_to_rgba(packed: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(packed.len() * 2);
    for px in packed.chunks_exact(2) {
        let (r, g, b, a) = unpack_4444(u16::from_le_bytes([px[0], px[1]]));
        out.extend_from_slice(&[r, g, b, a]);
    }
    out
}

fn pack_565(r: u8, g: u8, b: u8) -> u16 {
    ((r as u16 >> 3) << 11) | ((g as u16 >> 2) << 5) | (b as u16 >> 3)
}

fn unpack_565(c: u16) -> (u8, u8, u8) {
    let r = ((c >> 11) & 0x1f) as u8;
    let g = ((c >> 5) & 0x3f) as u8;
    let b = (c & 0x1f) as u8;
    (
        (r << 3) | (r >> 2),
        (g << 2) | (g >> 4),
        (b << 3) | (b >> 2),
    )
}

fn pack_4444(r: u8, g: u8, b: u8, a: u8) -> u16 {
    ((a as u16 >> 4) << 12) | ((r as u16 >> 4) << 8) | ((g as u16 >> 4) << 4) | (b as u16 >> 4)
}

fn unpack_4444(c: u16) -> (u8, u8, u8, u8) {
    let x4 = |v: u16| -> u8 {
        let v = (v & 0xf) as u8;
        (v << 4) | v
    };
    (x4(c >> 8), x4(c >> 4), x4(c), x4(c >> 12))
}

// ---------------------------------------------------------------------------
// DXT1 / DXT5 (BC1 / BC3)
// ---------------------------------------------------------------------------

fn lerp3(a: u8, b: u8, wa: u32, wb: u32) -> u8 {
    ((a as u32 * wa + b as u32 * wb + 1) / 3) as u8
}

/// Decodes the 8-byte colour part of a BC1/BC3 block into 16 RGBA pixels.
/// `four_color` forces the 4-colour palette (BC3's colour block is always
/// decoded that way); otherwise `c0 <= c1` selects the 3-colour mode with a
/// transparent black fourth entry (DXT1's 1-bit alpha).
fn decode_dxt_color_block(block: &[u8], four_color: bool, out: &mut [[u8; 4]; 16]) {
    let c0 = u16::from_le_bytes([block[0], block[1]]);
    let c1 = u16::from_le_bytes([block[2], block[3]]);
    let (r0, g0, b0) = unpack_565(c0);
    let (r1, g1, b1) = unpack_565(c1);
    let mut palette = [[r0, g0, b0, 255], [r1, g1, b1, 255], [0; 4], [0; 4]];
    if four_color || c0 > c1 {
        palette[2] = [
            lerp3(r0, r1, 2, 1),
            lerp3(g0, g1, 2, 1),
            lerp3(b0, b1, 2, 1),
            255,
        ];
        palette[3] = [
            lerp3(r0, r1, 1, 2),
            lerp3(g0, g1, 1, 2),
            lerp3(b0, b1, 1, 2),
            255,
        ];
    } else {
        palette[2] = [
            ((r0 as u32 + r1 as u32) / 2) as u8,
            ((g0 as u32 + g1 as u32) / 2) as u8,
            ((b0 as u32 + b1 as u32) / 2) as u8,
            255,
        ];
        palette[3] = [0, 0, 0, 0];
    }
    let indices = u32::from_le_bytes([block[4], block[5], block[6], block[7]]);
    for (i, px) in out.iter_mut().enumerate() {
        *px = palette[((indices >> (i * 2)) & 3) as usize];
    }
}

/// Decodes the 8-byte alpha part of a BC3 block into 16 alpha values.
fn decode_dxt5_alpha_block(block: &[u8], out: &mut [u8; 16]) {
    let a0 = block[0];
    let a1 = block[1];
    let mut palette = [a0, a1, 0, 0, 0, 0, 0, 0];
    if a0 > a1 {
        for (i, p) in palette.iter_mut().enumerate().skip(2) {
            let w = (i - 1) as u32;
            *p = ((a0 as u32 * (7 - w) + a1 as u32 * w + 3) / 7) as u8;
        }
    } else {
        for (i, p) in palette.iter_mut().enumerate().take(6).skip(2) {
            let w = (i - 1) as u32;
            *p = ((a0 as u32 * (5 - w) + a1 as u32 * w + 2) / 5) as u8;
        }
        palette[6] = 0;
        palette[7] = 255;
    }
    let mut bits = 0u64;
    for (i, b) in block[2..8].iter().enumerate() {
        bits |= (*b as u64) << (i * 8);
    }
    for (i, a) in out.iter_mut().enumerate() {
        *a = palette[((bits >> (i * 3)) & 7) as usize];
    }
}

fn write_block(out: &mut [u8], width: u32, height: u32, bx: usize, by: usize, px: &[[u8; 4]; 16]) {
    for (i, p) in px.iter().enumerate() {
        let x = bx * 4 + (i % 4);
        let y = by * 4 + (i / 4);
        if x < width as usize && y < height as usize {
            let o = (y * width as usize + x) * 4;
            out[o..o + 4].copy_from_slice(p);
        }
    }
}

/// DXT1 blocks (8 bytes each, row-major over the block grid) to RGBA8.
pub fn decode_dxt1(data: &[u8], width: u32, height: u32) -> Option<Vec<u8>> {
    let (bw, bh) = (blocks(width), blocks(height));
    if data.len() < bw * bh * 8 {
        return None;
    }
    let mut out = vec![0; (width * height * 4) as usize];
    let mut px = [[0u8; 4]; 16];
    for by in 0..bh {
        for bx in 0..bw {
            let o = (by * bw + bx) * 8;
            decode_dxt_color_block(&data[o..o + 8], false, &mut px);
            write_block(&mut out, width, height, bx, by, &px);
        }
    }
    Some(out)
}

/// DXT5 blocks (16 bytes each) to RGBA8.
pub fn decode_dxt5(data: &[u8], width: u32, height: u32) -> Option<Vec<u8>> {
    let (bw, bh) = (blocks(width), blocks(height));
    if data.len() < bw * bh * 16 {
        return None;
    }
    let mut out = vec![0; (width * height * 4) as usize];
    let mut px = [[0u8; 4]; 16];
    let mut alpha = [0u8; 16];
    for by in 0..bh {
        for bx in 0..bw {
            let o = (by * bw + bx) * 16;
            decode_dxt5_alpha_block(&data[o..o + 8], &mut alpha);
            decode_dxt_color_block(&data[o + 8..o + 16], true, &mut px);
            for (p, a) in px.iter_mut().zip(alpha) {
                p[3] = a;
            }
            write_block(&mut out, width, height, bx, by, &px);
        }
    }
    Some(out)
}

fn read_block(rgba: &[u8], width: u32, height: u32, bx: usize, by: usize) -> [[u8; 4]; 16] {
    let mut px = [[0u8; 4]; 16];
    for (i, p) in px.iter_mut().enumerate() {
        let x = (bx * 4 + (i % 4)).min(width as usize - 1);
        let y = (by * 4 + (i / 4)).min(height as usize - 1);
        let o = (y * width as usize + x) * 4;
        p.copy_from_slice(&rgba[o..o + 4]);
    }
    px
}

fn color_dist(a: [u8; 4], b: [u8; 4]) -> u32 {
    (0..3)
        .map(|i| {
            let d = a[i] as i32 - b[i] as i32;
            (d * d) as u32
        })
        .sum()
}

/// Encodes 16 RGBA pixels as a BC1 colour block (4-colour mode; endpoints are
/// the brightest and darkest pixel, every pixel snaps to the nearest palette
/// entry). This is the "runtime texture compression" desktop Flash applies
/// when BitmapData is uploaded into a COMPRESSED texture: lossy by design.
fn encode_dxt_color_block(px: &[[u8; 4]; 16], out: &mut [u8]) {
    let lum = |p: &[u8; 4]| p[0] as u32 * 299 + p[1] as u32 * 587 + p[2] as u32 * 114;
    let hi = px
        .iter()
        .max_by_key(|p| lum(p))
        .expect("a block has 16 pixels");
    let lo = px
        .iter()
        .min_by_key(|p| lum(p))
        .expect("a block has 16 pixels");
    let mut c0 = pack_565(hi[0], hi[1], hi[2]);
    let mut c1 = pack_565(lo[0], lo[1], lo[2]);
    if c0 < c1 {
        std::mem::swap(&mut c0, &mut c1);
    }
    let mut indices = 0u32;
    if c0 != c1 {
        let block = [c0.to_le_bytes(), c1.to_le_bytes()].concat();
        let mut palette = [[0u8; 4]; 16];
        decode_dxt_color_block(&[block, vec![0b11100100; 4]].concat(), true, &mut palette);
        let palette = [palette[0], palette[1], palette[2], palette[3]];
        for (i, p) in px.iter().enumerate() {
            let best = (0..4)
                .min_by_key(|&k| color_dist(*p, palette[k]))
                .expect("the palette has 4 entries");
            indices |= (best as u32) << (i * 2);
        }
    }
    out[0..2].copy_from_slice(&c0.to_le_bytes());
    out[2..4].copy_from_slice(&c1.to_le_bytes());
    out[4..8].copy_from_slice(&indices.to_le_bytes());
}

fn encode_dxt5_alpha_block(px: &[[u8; 4]; 16], out: &mut [u8]) {
    let a0 = px
        .iter()
        .map(|p| p[3])
        .max()
        .expect("a block has 16 pixels");
    let a1 = px
        .iter()
        .map(|p| p[3])
        .min()
        .expect("a block has 16 pixels");
    out[0] = a0;
    out[1] = a1;
    let mut bits = 0u64;
    if a0 != a1 {
        let mut palette = [0u8; 16];
        decode_dxt5_alpha_block(&[a0, a1, 0, 0, 0, 0, 0, 0], &mut palette);
        for (i, p) in px.iter().enumerate() {
            let best = (0..8)
                .min_by_key(|&k| (p[3] as i32 - palette[k] as i32).abs())
                .expect("the palette has 8 entries");
            bits |= (best as u64) << (i * 3);
        }
    }
    for (i, b) in out[2..8].iter_mut().enumerate() {
        *b = (bits >> (i * 8)) as u8;
    }
}

/// RGBA8 to DXT1 blocks (alpha ignored: DXT1 textures are opaque in Flash).
pub fn encode_dxt1(rgba: &[u8], width: u32, height: u32) -> Vec<u8> {
    let (bw, bh) = (blocks(width), blocks(height));
    let mut out = vec![0; bw * bh * 8];
    for by in 0..bh {
        for bx in 0..bw {
            let px = read_block(rgba, width, height, bx, by);
            let o = (by * bw + bx) * 8;
            encode_dxt_color_block(&px, &mut out[o..o + 8]);
        }
    }
    out
}

/// RGBA8 to DXT5 blocks.
pub fn encode_dxt5(rgba: &[u8], width: u32, height: u32) -> Vec<u8> {
    let (bw, bh) = (blocks(width), blocks(height));
    let mut out = vec![0; bw * bh * 16];
    for by in 0..bh {
        for bx in 0..bw {
            let px = read_block(rgba, width, height, bx, by);
            let o = (by * bw + bx) * 16;
            encode_dxt5_alpha_block(&px, &mut out[o..o + 8]);
            encode_dxt_color_block(&px, &mut out[o + 8..o + 16]);
        }
    }
    out
}

// ---------------------------------------------------------------------------
// ETC1 / ETC2 / EAC
// ---------------------------------------------------------------------------

const ETC_MODIFIERS: [[i32; 2]; 8] = [
    [2, 8],
    [5, 17],
    [9, 29],
    [13, 42],
    [18, 60],
    [24, 80],
    [33, 106],
    [47, 183],
];

const ETC2_DISTANCES: [i32; 8] = [3, 6, 11, 16, 23, 32, 41, 64];

const EAC_MODIFIERS: [[i32; 8]; 16] = [
    [-3, -6, -9, -15, 2, 5, 8, 14],
    [-3, -7, -10, -13, 2, 6, 9, 12],
    [-2, -5, -8, -13, 1, 4, 7, 12],
    [-2, -4, -6, -13, 1, 3, 5, 12],
    [-3, -6, -8, -12, 2, 5, 7, 11],
    [-3, -7, -9, -11, 2, 6, 8, 10],
    [-4, -7, -8, -11, 3, 6, 7, 10],
    [-3, -5, -8, -11, 2, 4, 7, 10],
    [-2, -6, -8, -10, 1, 5, 7, 9],
    [-2, -5, -8, -10, 1, 4, 7, 9],
    [-2, -4, -8, -10, 1, 3, 7, 9],
    [-2, -5, -7, -10, 1, 4, 6, 9],
    [-3, -4, -7, -10, 2, 3, 6, 9],
    [-1, -2, -3, -10, 0, 1, 2, 9],
    [-4, -6, -8, -9, 3, 5, 7, 8],
    [-3, -5, -7, -9, 2, 4, 6, 8],
];

fn clamp8(v: i32) -> u8 {
    v.clamp(0, 255) as u8
}

fn x4(v: u8) -> i32 {
    ((v & 0xf) * 17) as i32
}

fn x5(v: u8) -> i32 {
    let v = v & 0x1f;
    ((v << 3) | (v >> 2)) as i32
}

/// Decodes one 8-byte ETC2 RGB block (which includes every ETC1 block) into
/// 16 pixels in row-major order; alpha is left at 255.
fn decode_etc2_rgb_block(b: &[u8], out: &mut [[u8; 4]; 16]) {
    let diff = b[3] & 2 != 0;
    // Pixel index bits: pixel i (column-major, i = x * 4 + y) has its lsb at
    // bit i and msb at bit 16 + i of the low 32-bit word.
    let low = u32::from_be_bytes([b[4], b[5], b[6], b[7]]);
    let idx = |i: usize| -> usize { (((low >> (16 + i)) & 1) << 1 | ((low >> i) & 1)) as usize };
    let set = |out: &mut [[u8; 4]; 16], i: usize, c: [i32; 3]| {
        let (x, y) = (i / 4, i % 4);
        out[y * 4 + x] = [clamp8(c[0]), clamp8(c[1]), clamp8(c[2]), 255];
    };

    let (base1, base2);
    if !diff {
        base1 = [x4(b[0] >> 4), x4(b[1] >> 4), x4(b[2] >> 4)];
        base2 = [x4(b[0]), x4(b[1]), x4(b[2])];
    } else {
        let r1 = (b[0] >> 3) as i32;
        let g1 = (b[1] >> 3) as i32;
        let b1 = (b[2] >> 3) as i32;
        let sign3 = |v: u8| -> i32 { ((v & 7) as i32) - if v & 4 != 0 { 8 } else { 0 } };
        let r2 = r1 + sign3(b[0]);
        let g2 = g1 + sign3(b[1]);
        let b2 = b1 + sign3(b[2]);
        if !(0..32).contains(&r2) {
            // T mode
            let r1 = ((b[0] >> 1) & 0xc) | (b[0] & 3);
            let c1 = [x4(r1), x4(b[1] >> 4), x4(b[1])];
            let c2 = [x4(b[2] >> 4), x4(b[2]), x4(b[3] >> 4)];
            let d = ETC2_DISTANCES[(((b[3] >> 2) & 3) << 1 | (b[3] & 1)) as usize];
            let paints = [
                c1,
                [c2[0] + d, c2[1] + d, c2[2] + d],
                c2,
                [c2[0] - d, c2[1] - d, c2[2] - d],
            ];
            for i in 0..16 {
                set(out, i, paints[idx(i)]);
            }
            return;
        }
        if !(0..32).contains(&g2) {
            // H mode
            let r1 = (b[0] >> 3) & 0xf;
            let g1 = ((b[0] & 7) << 1) | ((b[1] >> 4) & 1);
            let b1 = (b[1] & 8) | ((b[1] & 3) << 1) | ((b[2] >> 7) & 1);
            let r2 = (b[2] >> 3) & 0xf;
            let g2 = ((b[2] & 7) << 1) | ((b[3] >> 7) & 1);
            let b2 = (b[3] >> 3) & 0xf;
            let c1 = [x4(r1), x4(g1), x4(b1)];
            let c2 = [x4(r2), x4(g2), x4(b2)];
            let v1 = (c1[0] << 16) | (c1[1] << 8) | c1[2];
            let v2 = (c2[0] << 16) | (c2[1] << 8) | c2[2];
            let di = ((b[3] >> 2) & 1) << 2 | (b[3] & 1) << 1 | (v1 >= v2) as u8;
            let d = ETC2_DISTANCES[di as usize];
            let paints = [
                [c1[0] + d, c1[1] + d, c1[2] + d],
                [c1[0] - d, c1[1] - d, c1[2] - d],
                [c2[0] + d, c2[1] + d, c2[2] + d],
                [c2[0] - d, c2[1] - d, c2[2] - d],
            ];
            for i in 0..16 {
                set(out, i, paints[idx(i)]);
            }
            return;
        }
        if !(0..32).contains(&b2) {
            // Planar mode
            let x6 = |v: u8| -> i32 {
                let v = v & 0x3f;
                ((v << 2) | (v >> 4)) as i32
            };
            let x7 = |v: u8| -> i32 {
                let v = v & 0x7f;
                ((v << 1) | (v >> 6)) as i32
            };
            let ro = x6(b[0] >> 2);
            let go = x7(((b[0] & 1) << 6) | ((b[1] >> 1) & 0x3f));
            let bo = x6(((b[1] & 1) << 5) | (((b[2] >> 4) & 3) << 3) | (b[2] & 7));
            let rh = x6(((b[3] >> 3) << 1) | (b[3] & 1));
            let gh = x7(b[4] >> 1);
            let bh = x6(((b[4] & 1) << 5) | (b[5] >> 3));
            let rv = x6(((b[5] & 7) << 3) | (b[6] >> 5));
            let gv = x7(((b[6] & 0x1f) << 2) | (b[7] >> 6));
            let bv = x6(b[7]);
            for y in 0..4i32 {
                for x in 0..4i32 {
                    let c = [
                        (x * (rh - ro) + y * (rv - ro) + 4 * ro + 2) >> 2,
                        (x * (gh - go) + y * (gv - go) + 4 * go + 2) >> 2,
                        (x * (bh - bo) + y * (bv - bo) + 4 * bo + 2) >> 2,
                    ];
                    out[(y * 4 + x) as usize] = [clamp8(c[0]), clamp8(c[1]), clamp8(c[2]), 255];
                }
            }
            return;
        }
        base1 = [x5(r1 as u8), x5(g1 as u8), x5(b1 as u8)];
        base2 = [x5(r2 as u8), x5(g2 as u8), x5(b2 as u8)];
    }

    // Individual / differential mode: two sub-blocks with their own
    // modifier tables.
    let flip = b[3] & 1 != 0;
    let table1 = (b[3] >> 5) as usize;
    let table2 = ((b[3] >> 2) & 7) as usize;
    for i in 0..16 {
        let (x, y) = (i / 4, i % 4);
        let first = if flip { y < 2 } else { x < 2 };
        let (base, table) = if first {
            (base1, table1)
        } else {
            (base2, table2)
        };
        let k = idx(i);
        let m = ETC_MODIFIERS[table][k & 1];
        let m = if k & 2 != 0 { -m } else { m };
        set(out, i, [base[0] + m, base[1] + m, base[2] + m]);
    }
}

/// Decodes one 8-byte EAC alpha block into 16 alpha values (row-major).
fn decode_eac_alpha_block(b: &[u8], out: &mut [u8; 16]) {
    let base = b[0] as i32;
    let mult = (b[1] >> 4) as i32;
    let table = &EAC_MODIFIERS[(b[1] & 0xf) as usize];
    let mut bits = 0u64;
    for v in &b[2..8] {
        bits = (bits << 8) | *v as u64;
    }
    for i in 0..16 {
        // Pixel i (column-major) uses the i-th 3-bit group from the MSB.
        let k = ((bits >> (45 - i * 3)) & 7) as usize;
        let (x, y) = (i / 4, i % 4);
        out[y * 4 + x] = clamp8(base + mult * table[k]);
    }
}

/// ETC1 or ETC2 RGB blocks (8 bytes each) to RGBA8.
pub fn decode_etc2_rgb(data: &[u8], width: u32, height: u32) -> Option<Vec<u8>> {
    let (bw, bh) = (blocks(width), blocks(height));
    if data.len() < bw * bh * 8 {
        return None;
    }
    let mut out = vec![0; (width * height * 4) as usize];
    let mut px = [[0u8; 4]; 16];
    for by in 0..bh {
        for bx in 0..bw {
            let o = (by * bw + bx) * 8;
            decode_etc2_rgb_block(&data[o..o + 8], &mut px);
            write_block(&mut out, width, height, bx, by, &px);
        }
    }
    Some(out)
}

/// ETC2 RGBA blocks (EAC alpha + ETC2 RGB, 16 bytes each) to RGBA8.
pub fn decode_etc2_rgba(data: &[u8], width: u32, height: u32) -> Option<Vec<u8>> {
    let (bw, bh) = (blocks(width), blocks(height));
    if data.len() < bw * bh * 16 {
        return None;
    }
    let mut out = vec![0; (width * height * 4) as usize];
    let mut px = [[0u8; 4]; 16];
    let mut alpha = [0u8; 16];
    for by in 0..bh {
        for bx in 0..bw {
            let o = (by * bw + bx) * 16;
            decode_eac_alpha_block(&data[o..o + 8], &mut alpha);
            decode_etc2_rgb_block(&data[o + 8..o + 16], &mut px);
            for (p, a) in px.iter_mut().zip(alpha) {
                p[3] = a;
            }
            write_block(&mut out, width, height, bx, by, &px);
        }
    }
    Some(out)
}

/// Wraps ETC1/ETC2 RGB blocks into ETC2 RGBA blocks with a fully opaque EAC
/// alpha block (base 255, multiplier 0) in front of each, so an opaque ATF
/// payload can be uploaded to an ETC2 RGBA texture unchanged.
pub fn etc2_rgb_to_rgba_opaque(data: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(data.len() * 2);
    for block in data.chunks_exact(8) {
        out.extend_from_slice(&[255, 0, 0, 0, 0, 0, 0, 0]);
        out.extend_from_slice(block);
    }
    out
}

// ---------------------------------------------------------------------------
// PVRTC 4bpp
// ---------------------------------------------------------------------------

#[derive(Clone, Copy, Default)]
struct PvrBlock {
    /// Colour A and B as 5-bit RGB + 4-bit alpha.
    a: [i32; 4],
    b: [i32; 4],
    modulation: u32,
    punch_through: bool,
}

fn pvr_color_a(c: u32) -> [i32; 4] {
    if c & 0x8000 != 0 {
        // Opaque RGB 554
        let b4 = ((c & 0x1e) >> 1) as i32;
        [
            ((c & 0x7c00) >> 10) as i32,
            ((c & 0x3e0) >> 5) as i32,
            (b4 << 1) | (b4 >> 3),
            0xf,
        ]
    } else {
        // ARGB 3443
        let r4 = ((c & 0xf00) >> 8) as i32;
        let g4 = ((c & 0xf0) >> 4) as i32;
        let b3 = ((c & 0xe) >> 1) as i32;
        [
            (r4 << 1) | (r4 >> 3),
            (g4 << 1) | (g4 >> 3),
            (b3 << 2) | (b3 >> 1),
            (((c & 0x7000) >> 12) << 1) as i32,
        ]
    }
}

fn pvr_color_b(c: u32) -> [i32; 4] {
    if c & 0x8000_0000 != 0 {
        // Opaque RGB 555
        [
            ((c & 0x7c00_0000) >> 26) as i32,
            ((c & 0x3e0_0000) >> 21) as i32,
            ((c & 0x1f_0000) >> 16) as i32,
            0xf,
        ]
    } else {
        // ARGB 3444
        let r4 = ((c & 0xf00_0000) >> 24) as i32;
        let g4 = ((c & 0xf0_0000) >> 20) as i32;
        let b4 = ((c & 0xf_0000) >> 16) as i32;
        [
            (r4 << 1) | (r4 >> 3),
            (g4 << 1) | (g4 >> 3),
            (b4 << 1) | (b4 >> 3),
            (((c & 0x7000_0000) >> 28) << 1) as i32,
        ]
    }
}

/// Morton (Z-order) index of block (x, y) in a `bw` x `bh` block grid, as
/// Imagination's `TwiddleUV`: the smaller dimension's bits interleave (y in
/// the even positions), the larger dimension's remaining bits go on top.
fn pvr_twiddle(bw: usize, bh: usize, x: usize, y: usize) -> usize {
    let min_dim = bw.min(bh);
    let mut max_value = if bw > bh { x } else { y };
    let mut twiddled = 0;
    let mut src_bit = 1;
    let mut dst_bit = 1;
    let mut shift = 0;
    while src_bit < min_dim {
        if y & src_bit != 0 {
            twiddled |= dst_bit;
        }
        if x & src_bit != 0 {
            twiddled |= dst_bit << 1;
        }
        src_bit <<= 1;
        dst_bit <<= 2;
        shift += 1;
    }
    max_value >>= shift;
    twiddled | (max_value << (2 * shift))
}

/// PVRTC 4bpp blocks (8 bytes each, Morton order) to RGBA8. `width` and
/// `height` must be powers of two of at least 4 (ATF guarantees this).
pub fn decode_pvrtc_4bpp(data: &[u8], width: u32, height: u32) -> Option<Vec<u8>> {
    let (bw, bh) = (blocks(width), blocks(height));
    if data.len() < bw * bh * 8 || !width.is_power_of_two() || !height.is_power_of_two() {
        return None;
    }
    let mut grid = vec![PvrBlock::default(); bw * bh];
    for (by, row) in grid.chunks_exact_mut(bw).enumerate() {
        for (bx, blk) in row.iter_mut().enumerate() {
            let o = pvr_twiddle(bw, bh, bx, by) * 8;
            let modulation = u32::from_le_bytes([data[o], data[o + 1], data[o + 2], data[o + 3]]);
            let colors = u32::from_le_bytes([data[o + 4], data[o + 5], data[o + 6], data[o + 7]]);
            *blk = PvrBlock {
                a: pvr_color_a(colors),
                b: pvr_color_b(colors),
                modulation,
                punch_through: colors & 1 != 0,
            };
        }
    }

    let (w, h) = (width as usize, height as usize);
    let mut out = vec![0; w * h * 4];
    for y in 0..h {
        for x in 0..w {
            // The block whose centre is at or left/above the pixel, and its
            // three neighbours (wrapping around the texture).
            let px = (x + w - 2) / 4 % bw;
            let py = (y + h - 2) / 4 % bh;
            let qx = (px + 1) % bw;
            let ry = (py + 1) % bh;
            let (i, j) = (((x + 2) % 4) as i32, ((y + 2) % 4) as i32);
            let wp = (4 - i) * (4 - j);
            let wq = i * (4 - j);
            let wr = (4 - i) * j;
            let ws = i * j;
            let p = grid[py * bw + px];
            let q = grid[py * bw + qx];
            let r = grid[ry * bw + px];
            let s = grid[ry * bw + qx];
            let mut ca = [0i32; 4];
            let mut cb = [0i32; 4];
            for k in 0..4 {
                // 16 x the 5-bit (4-bit alpha) value, expanded to 8 bits
                // the way the reference decoder does.
                let va = wp * p.a[k] + wq * q.a[k] + wr * r.a[k] + ws * s.a[k];
                let vb = wp * p.b[k] + wq * q.b[k] + wr * r.b[k] + ws * s.b[k];
                if k < 3 {
                    ca[k] = (va >> 6) + (va >> 1);
                    cb[k] = (vb >> 6) + (vb >> 1);
                } else {
                    ca[k] = (va >> 4) + va;
                    cb[k] = (vb >> 4) + vb;
                }
            }
            let blk = grid[(y / 4) * bw + (x / 4)];
            let bits = (blk.modulation >> (((y % 4) * 4 + (x % 4)) * 2)) & 3;
            let (m, zero_alpha) = if blk.punch_through {
                match bits {
                    0 => (0, false),
                    1 => (4, false),
                    2 => (4, true),
                    _ => (8, false),
                }
            } else {
                ([0, 3, 5, 8][bits as usize], false)
            };
            let o = (y * w + x) * 4;
            for k in 0..4 {
                out[o + k] = clamp8((ca[k] * (8 - m) + cb[k] * m) / 8);
            }
            if zero_alpha {
                out[o + 3] = 0;
            }
        }
    }
    Some(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn px(out: &[u8], w: u32, x: u32, y: u32) -> [u8; 4] {
        let o = ((y * w + x) * 4) as usize;
        [out[o], out[o + 1], out[o + 2], out[o + 3]]
    }

    #[test]
    fn packed_quantisation() {
        let mut rgba = vec![255, 128, 7, 10];
        quantize_rgb565(&mut rgba);
        // 128 -> g 32 -> 128+2 = 130; 7 -> b 0; alpha opaque
        assert_eq!(rgba, vec![255, 130, 0, 255]);
        let mut rgba = vec![255, 128, 7, 10];
        quantize_rgba4444(&mut rgba);
        assert_eq!(rgba, vec![255, 136, 0, 0]);
        // Packed byte layouts: 0xF800 (red 565) little-endian; 0xF0F0 (alpha
        // 15, red 0, green 15, blue 0) little-endian.
        assert_eq!(rgb565_le_to_rgba(&[0x00, 0xF8]), vec![255, 0, 0, 255]);
        assert_eq!(rgb565_le_to_rgba(&[0x1F, 0x00]), vec![0, 0, 255, 255]);
        assert_eq!(argb4444_le_to_rgba(&[0xF0, 0xF0]), vec![0, 255, 0, 255]);
        assert_eq!(argb4444_le_to_rgba(&[0x0F, 0x80]), vec![0, 0, 255, 136]);
    }

    #[test]
    fn dxt1_four_color_and_punch_through() {
        // c0 = pure red (0xF800) > c1 = pure blue (0x001F): 4-colour mode.
        // Indices: pixel 0 -> 0, pixel 1 -> 1, pixel 2 -> 2, pixel 3 -> 3, rest 0.
        let block = [0x00, 0xF8, 0x1F, 0x00, 0b11100100, 0, 0, 0];
        let out = decode_dxt1(&block, 4, 4).unwrap();
        assert_eq!(px(&out, 4, 0, 0), [255, 0, 0, 255]);
        assert_eq!(px(&out, 4, 1, 0), [0, 0, 255, 255]);
        assert_eq!(px(&out, 4, 2, 0), [170, 0, 85, 255]);
        assert_eq!(px(&out, 4, 3, 0), [85, 0, 170, 255]);
        assert_eq!(px(&out, 4, 3, 3), [255, 0, 0, 255]);
        // c0 <= c1: 3-colour mode, index 3 is transparent black.
        let block = [0x1F, 0x00, 0x00, 0xF8, 0b11100100, 0, 0, 0];
        let out = decode_dxt1(&block, 4, 4).unwrap();
        assert_eq!(px(&out, 4, 0, 0), [0, 0, 255, 255]);
        assert_eq!(px(&out, 4, 2, 0), [127, 0, 127, 255]);
        assert_eq!(px(&out, 4, 3, 0), [0, 0, 0, 0]);
        // Two blocks across, 8x4.
        let two = [block, [0x00, 0xF8, 0x00, 0xF8, 0, 0, 0, 0]].concat();
        let out = decode_dxt1(&two, 8, 4).unwrap();
        assert_eq!(px(&out, 8, 7, 3), [255, 0, 0, 255]);
        assert!(decode_dxt1(&block, 8, 4).is_none());
    }

    #[test]
    fn dxt5_alpha_modes() {
        // 8-step alpha: a0 = 255 > a1 = 0; pixel i uses index i & 7.
        let mut idx = 0u64;
        for i in 0..16u64 {
            idx |= (i & 7) << (i * 3);
        }
        let mut block = vec![255, 0];
        block.extend_from_slice(&idx.to_le_bytes()[..6]);
        // Colour part: green endpoints, all index 0 (BC3 colour is always 4-colour).
        block.extend_from_slice(&[0xE0, 0x07, 0x00, 0x00, 0, 0, 0, 0]);
        let out = decode_dxt5(&block, 4, 4).unwrap();
        let alphas: Vec<u8> = (0..8).map(|i| px(&out, 4, i % 4, i / 4)[3]).collect();
        assert_eq!(alphas, vec![255, 0, 219, 182, 146, 109, 73, 36]);
        assert_eq!(px(&out, 4, 0, 0)[..3], [0, 255, 0]);
        // 6-step alpha: a0 = 0 <= a1 = 250; index 6 -> 0, 7 -> 255.
        let mut block = vec![0, 250];
        block.extend_from_slice(&idx.to_le_bytes()[..6]);
        block.extend_from_slice(&[0xE0, 0x07, 0x00, 0x00, 0, 0, 0, 0]);
        let out = decode_dxt5(&block, 4, 4).unwrap();
        let alphas: Vec<u8> = (0..8).map(|i| px(&out, 4, i % 4, i / 4)[3]).collect();
        assert_eq!(alphas, vec![0, 250, 50, 100, 150, 200, 0, 255]);
    }

    #[test]
    fn dxt_encode_round_trip() {
        // A flat block survives exactly (565-quantised), alpha too.
        let rgba: Vec<u8> = (0..16).flat_map(|_| [247, 251, 8, 136]).collect();
        let dxt5 = encode_dxt5(&rgba, 4, 4);
        assert_eq!(decode_dxt5(&dxt5, 4, 4).unwrap(), rgba);
        let dxt1 = encode_dxt1(&rgba, 4, 4);
        let back = decode_dxt1(&dxt1, 4, 4).unwrap();
        assert_eq!(&back[..4], &[247, 251, 8, 255]);
        // Two colours map to the two endpoints.
        let mut rgba = vec![0u8; 64];
        for (i, p) in rgba.chunks_exact_mut(4).enumerate() {
            p.copy_from_slice(if i % 2 == 0 {
                &[255, 0, 0, 255]
            } else {
                &[0, 0, 255, 255]
            });
        }
        let back = decode_dxt1(&encode_dxt1(&rgba, 4, 4), 4, 4).unwrap();
        assert_eq!(back, rgba);
    }

    #[test]
    fn etc1_individual_and_differential() {
        // Individual mode, no flip: sub-block 1 (x < 2) base 0xF0 red -> 255,
        // sub-block 2 base 0x0 ; tables 0 and 0; pixel 0 index "01" (+8),
        // pixel 1 index "11" (-8), others "00" (+2).
        // byte3: table1 = 0 (bits 7..5), table2 = 0 (bits 4..2), diff = 0, flip = 0.
        let lsb: u16 = 0b11;
        let msb: u16 = 0b10;
        let low = ((msb as u32) << 16) | lsb as u32;
        let mut b = vec![0xF0, 0x00, 0x00, 0x00];
        b.extend_from_slice(&low.to_be_bytes());
        let out = decode_etc2_rgb(&b, 4, 4).unwrap();
        assert_eq!(px(&out, 4, 0, 0), [255, 8, 8, 255]); // 255+8 clamps
        assert_eq!(px(&out, 4, 0, 1), [247, 0, 0, 255]); // -8 clamps at 0
        assert_eq!(px(&out, 4, 1, 0), [255, 2, 2, 255]);
        assert_eq!(px(&out, 4, 2, 0), [2, 2, 2, 255]);
        // Differential mode with flip: base1 = (16,16,16) 5-bit -> 132, delta
        // (+1,-1,0) -> base2 = (17,15,16) -> (140,123,132); table1 = 2 (9/29),
        // table2 = 7 (47/183); all indices "00".
        let b = [
            (16 << 3) | 1,
            (16 << 3) | 7,
            16 << 3,
            (2 << 5) | (7 << 2) | 2 | 1,
            0,
            0,
            0,
            0,
        ];
        let out = decode_etc2_rgb(&b, 4, 4).unwrap();
        assert_eq!(px(&out, 4, 3, 0), [141, 141, 141, 255]); // y < 2: base1 + 9
        assert_eq!(px(&out, 4, 0, 3), [187, 170, 179, 255]); // y >= 2: base2 + 47
    }

    #[test]
    fn etc2_t_h_planar_modes() {
        // T mode: differential with R overflow. byte0: R1 = 0b11111 (31), dR =
        // 0b011 (+3) -> 34 overflows. In T mode byte0 bits 4..3 | 1..0 = R1a|R1b.
        // byte0 = 0b11111011: R = ((0b11111011 >> 1) & 0xc) | (0b11) = 0b1100 | 0b11 = 0xF.
        // byte1 = 0x00 (G1 = 0, B1 = 0) -> c1 = (255, 0, 0).
        // byte2 = 0x88 -> R2 = 8, G2 = 8; byte3 = 0x8E -> B2 = 8, da = 3, db = 0
        // -> distance index 6 -> 41; c2 = (136,136,136). diff bit (byte3 & 2) set.
        let mut b = vec![0b11111011, 0x00, 0x88, 0x8E];
        let low: u32 = (0b11 << 16) | 0b0001; // pixel 0 idx 3, pixel 1 idx 2
        b.extend_from_slice(&low.to_be_bytes());
        let out = decode_etc2_rgb(&b, 4, 4).unwrap();
        assert_eq!(px(&out, 4, 0, 0), [95, 95, 95, 255]); // c2 - 41
        assert_eq!(px(&out, 4, 0, 1), [136, 136, 136, 255]); // c2
        assert_eq!(px(&out, 4, 1, 0), [255, 0, 0, 255]); // c1
        // H mode: G overflow (R stays in range). byte0 = 0b00000_000 R1=0, dR=0;
        // byte1 = 0b11111_011 G1 = 31, dG = +3 -> overflow. H fields:
        // R1 = (b0 >> 3) & 15 = 0; G1 = ((b0 & 7) << 1) | ((b1 >> 4) & 1) = 1;
        // B1 = (b1 & 8) | ((b1 & 3) << 1) | (b2 >> 7) ; choose b2 = 0x00 -> B1 = 8|6 = 14;
        // R2 = (b2 >> 3) & 15 = 0; G2 = ((b2 & 7) << 1) | (b3 >> 7); b3 = 0b0000_0010
        // (diff set, da = 0, db = 0) -> G2 = 0; B2 = (b3 >> 3) & 15 = 0.
        // c1 = (0, 17, 238), c2 = (0, 0, 0): v1 >= v2 -> d index 1 -> 6.
        let mut b = vec![0x00, 0b11111011, 0x00, 0b00000010];
        let low: u32 = (0b01 << 16) | 0b0010; // pixel 0 idx 2 (c2 + d), pixel 1 idx 1 (c1 - d)
        b.extend_from_slice(&low.to_be_bytes());
        let out = decode_etc2_rgb(&b, 4, 4).unwrap();
        assert_eq!(px(&out, 4, 0, 0), [6, 6, 6, 255]);
        assert_eq!(px(&out, 4, 0, 1), [0, 11, 232, 255]);
        // Planar: B overflow. byte0 = RO(6)=0b111111, GO1 = 0 -> 0xFC;
        // byte1: GO2 (bits 6..1) = 0, BO1 (bit 0) = 0 -> 0x00; byte2: dB must
        // overflow: B1 = b2 >> 3 = 0 and dB = b2 & 7 = 0b100 (-4) -> b2 = 0x04
        // -> BO2 = 0, BO3 = 4 -> BO = 4; byte3: RH1 = 0, RH2 = 0, diff = 1 -> 0x02;
        // byte4..7 = 0 -> GH = BH = RV = GV = BV = 0.
        // RO = 255, GO = 0, BO = x6(4) = 16; RH = 0, RV = 0.
        let b = [0xFC, 0x00, 0x04, 0x02, 0, 0, 0, 0];
        let out = decode_etc2_rgb(&b, 4, 4).unwrap();
        assert_eq!(px(&out, 4, 0, 0), [255, 0, 16, 255]);
        // R(x=2, y=0) = (2*(0-255) + 4*255 + 2) >> 2 = (-510 + 1022) >> 2 = 128
        assert_eq!(px(&out, 4, 2, 0), [128, 0, 8, 255]);
        assert_eq!(
            px(&out, 4, 3, 3),
            [(-1530 + 1022) >> 2, 0, 0, 255].map(|v: i32| clamp8(v))
        );
    }

    #[test]
    fn eac_alpha_and_rgba() {
        // base 100, multiplier 2, table 13 ([-1,-2,-3,-10,0,1,2,9]); pixel 0
        // index 7 (+9*2 = 118), pixel 1 index 3 (-10*2 = 80), rest 0 (98).
        let mut b = vec![100, (2 << 4) | 13];
        let bits: u64 = (7 << 45) | (3 << 42);
        b.extend_from_slice(&bits.to_be_bytes()[2..8]);
        // Opaque white ETC1 block: individual, bases 0xF, table 0, all "00".
        b.extend_from_slice(&[0xFF, 0xFF, 0xFF, 0x00, 0, 0, 0, 0]);
        let out = decode_etc2_rgba(&b, 4, 4).unwrap();
        assert_eq!(px(&out, 4, 0, 0), [255, 255, 255, 118]);
        assert_eq!(px(&out, 4, 0, 1), [255, 255, 255, 80]);
        assert_eq!(px(&out, 4, 1, 0), [255, 255, 255, 98]);
        // Wrapping an RGB block in an opaque EAC block.
        let rgba = etc2_rgb_to_rgba_opaque(&[0xFF, 0xFF, 0xFF, 0x00, 0, 0, 0, 0]);
        let out = decode_etc2_rgba(&rgba, 4, 4).unwrap();
        assert!(out.chunks_exact(4).all(|p| p == [255, 255, 255, 255]));
    }

    #[test]
    fn pvrtc_single_block() {
        // One 4x4 block: all four neighbours are the block itself, so the
        // upscaled planes are exactly A and B.
        // Colour B opaque RGB555 (31, 0, 0) -> bit 31 set, red bits 30..26.
        // Colour A opaque RGB554 (0, 0, 15) -> bit 15 set, blue bits 4..1.
        let colors: u32 = 0x8000_0000 | (31 << 26) | 0x8000 | (15 << 1);
        // Modulation: pixel 0 -> 0 (A), pixel 1 -> 1, pixel 2 -> 2, pixel 3 -> 3 (B).
        let modulation: u32 = 0b11100100;
        let mut data = modulation.to_le_bytes().to_vec();
        data.extend_from_slice(&colors.to_le_bytes());
        let out = decode_pvrtc_4bpp(&data, 4, 4).unwrap();
        assert_eq!(px(&out, 4, 0, 0), [0, 0, 255, 255]);
        assert_eq!(px(&out, 4, 3, 0), [255, 0, 0, 255]);
        // (5A + 3B) / 8 and (3A + 5B) / 8
        assert_eq!(px(&out, 4, 1, 0), [95, 0, 159, 255]);
        assert_eq!(px(&out, 4, 2, 0), [159, 0, 95, 255]);
        // Punch-through mode: bit 0 set; value 2 is (A + B) / 2 with alpha 0.
        let colors = colors | 1;
        let mut data = modulation.to_le_bytes().to_vec();
        data.extend_from_slice(&colors.to_le_bytes());
        let out = decode_pvrtc_4bpp(&data, 4, 4).unwrap();
        assert_eq!(px(&out, 4, 1, 0), [127, 0, 127, 255]);
        assert_eq!(px(&out, 4, 2, 0), [127, 0, 127, 0]);
        // Translucent colour A (ARGB 3443): alpha 3 -> 6 (4-bit) -> 102.
        let colors: u32 = 0x8000_0000 | (3 << 12);
        let mut data = 0u32.to_le_bytes().to_vec();
        data.extend_from_slice(&colors.to_le_bytes());
        let out = decode_pvrtc_4bpp(&data, 4, 4).unwrap();
        assert_eq!(px(&out, 4, 0, 0), [0, 0, 0, 102]);
    }

    #[test]
    fn pvrtc_interpolation_and_morton() {
        // 8x8 texture, 2x2 blocks. Morton order: (0,0)=0, (0,1)=1, (1,0)=2, (1,1)=3.
        // Block (1,0) is white (B = 0xFFFF_FFFF? use A = B = opaque white),
        // the others black; all modulation 0 (colour A only).
        let white: u32 = 0x8000_0000 | (31 << 26) | (31 << 21) | (31 << 16) | 0x8000 | 0x7FFE;
        let black: u32 = 0x8000_0000 | 0x8000;
        let mut data = vec![];
        for c in [black, black, white, black] {
            data.extend_from_slice(&0u32.to_le_bytes());
            data.extend_from_slice(&c.to_le_bytes());
        }
        assert_eq!(pvr_twiddle(2, 2, 1, 0), 2);
        assert_eq!(pvr_twiddle(4, 2, 3, 1), 0b1_11);
        let out = decode_pvrtc_4bpp(&data, 8, 8).unwrap();
        // Pixel (6, 2): P = block (1, 0) centre (6, 2) -> weights all on P -> white.
        assert_eq!(px(&out, 8, 6, 2), [255, 255, 255, 255]);
        // Pixel (2, 2): block (0,0) centre -> black.
        assert_eq!(px(&out, 8, 2, 2), [0, 0, 0, 255]);
        // Pixel (4, 2): halfway between (0,0) and (1,0) horizontally:
        // 5-bit 31 * 8 (wp = wq = 8) = 248 -> (248 >> 6) + (248 >> 1) = 3 + 124.
        assert_eq!(px(&out, 8, 4, 2), [127, 127, 127, 255]);
    }
}
