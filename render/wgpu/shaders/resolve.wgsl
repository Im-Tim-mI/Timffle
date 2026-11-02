/// Timffle: resolves (averages the samples of) a rectangle of a multisampled
/// texture into a single-sampled one of the same size. Used instead of the
/// render pass's whole-texture resolve when a blend only needs a small part
/// of the parent; the pass is scissored to that part.

// NOTE: `const sample_count = N;` is prepended to this before compilation.

@group(0) @binding(0) var source: texture_multisampled_2d<f32>;

struct VertexOutput {
    @builtin(position) position: vec4<f32>,
};

@vertex
fn main_vertex(@builtin(vertex_index) index: u32) -> VertexOutput {
    // One triangle covering the whole target.
    let x = f32(i32(index & 1u) * 4 - 1);
    let y = f32(i32(index >> 1u) * 4 - 1);
    return VertexOutput(vec4<f32>(x, y, 0.0, 1.0));
}

@fragment
fn main_fragment(in: VertexOutput) -> @location(0) vec4<f32> {
    let coord = vec2<i32>(in.position.xy);
    var sum = vec4<f32>(0.0);
    for (var i = 0; i < sample_count; i += 1) {
        sum += textureLoad(source, coord, i);
    }
    return sum / f32(sample_count);
}
