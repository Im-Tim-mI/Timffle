/// Timffle: synchronous GPU -> CPU readback on the browser's WebGPU backend.
///
/// WebGPU has no synchronous buffer mapping on the main thread, but an
/// `OffscreenCanvas` can be snapshotted synchronously
/// (`transferToImageBitmap` + 2D `getImageData`). That path only gives
/// 8-bit RGB with alpha forced to 1, so the texture's raw bytes are written
/// three per pass into the RGB channels of an opaque canvas: pass `p` writes
/// bytes `3p`, `3p + 1`, `3p + 2` of every texel. 8-bit formats need two
/// passes (RGB, then alpha), 32-bit float formats bit-cast each channel and
/// need up to six. The CPU side reassembles the bytes.

struct Params {
    /// Top-left texel of the region being read.
    origin: vec2<i32>,
    /// Which group of three bytes this pass writes.
    pass_index: u32,
    /// 0: 8-bit unorm texels (bytes = round(channel * 255));
    /// 1: 32-bit float texels (bytes = the IEEE-754 bits, little-endian).
    float_texels: u32,
};

@group(0) @binding(0) var source: texture_2d<f32>;
@group(0) @binding(1) var<uniform> params: Params;

struct VertexOutput {
    @builtin(position) position: vec4<f32>,
};

@vertex
fn main_vertex(@builtin(vertex_index) index: u32) -> VertexOutput {
    // One triangle covering the whole canvas.
    let x = f32(i32(index & 1u) * 4 - 1);
    let y = f32(i32(index >> 1u) * 4 - 1);
    return VertexOutput(vec4<f32>(x, y, 0.0, 1.0));
}

fn texel_byte(texel: vec4<f32>, index: u32) -> u32 {
    if params.float_texels == 1u {
        let bits = bitcast<u32>(texel[index / 4u]);
        return (bits >> ((index % 4u) * 8u)) & 0xffu;
    }
    if index > 3u {
        return 0u;
    }
    return u32(round(clamp(texel[index], 0.0, 1.0) * 255.0));
}

@fragment
fn main_fragment(in: VertexOutput) -> @location(0) vec4<f32> {
    let texel = textureLoad(source, vec2<i32>(in.position.xy) + params.origin, 0);
    let first = params.pass_index * 3u;
    return vec4<f32>(
        f32(texel_byte(texel, first)) / 255.0,
        f32(texel_byte(texel, min(first + 1u, 15u))) / 255.0,
        f32(texel_byte(texel, min(first + 2u, 15u))) / 255.0,
        1.0,
    );
}
