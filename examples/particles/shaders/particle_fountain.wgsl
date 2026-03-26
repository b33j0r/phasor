struct VertexIn {
    @location(0) position: vec3<f32>,
    @location(1) uv: vec2<f32>,
    @location(2) clip0: vec4<f32>,
    @location(3) clip1: vec4<f32>,
    @location(4) clip2: vec4<f32>,
    @location(5) clip3: vec4<f32>,
    @location(6) instance_color: vec4<f32>,
};

struct VertexOut {
    @builtin(position) position: vec4<f32>,
    @location(0) local_pos: vec2<f32>,
    @location(1) color: vec4<f32>,
};

@vertex
fn vs_main(in: VertexIn) -> VertexOut {
    let clip = mat4x4<f32>(in.clip0, in.clip1, in.clip2, in.clip3);
    var out: VertexOut;
    out.position = clip * vec4<f32>(in.position, 1.0);
    out.local_pos = in.uv * 2.0 - vec2<f32>(1.0, 1.0);
    out.color = in.instance_color;
    return out;
}

@fragment
fn fs_main(in: VertexOut) -> @location(0) vec4<f32> {
    let p = in.local_pos;
    let stretch = vec2<f32>(p.x * 0.72, p.y * (1.12 - 0.24 * p.y));
    let halo = smoothstep(1.08, 0.14, length(stretch));
    let core = smoothstep(0.56, 0.0, length(stretch * vec2<f32>(1.05, 0.78)));
    let top_bias = smoothstep(-0.95, 0.92, p.y);
    let alpha = in.color.a * max(halo * top_bias, core * 0.95);
    let hotness = 0.62 + core * 1.15 + halo * 0.18;
    let rgb = min(in.color.rgb * hotness, vec3<f32>(1.0, 1.0, 1.0));
    return vec4<f32>(rgb, alpha);
}
