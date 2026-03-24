struct VertexIn {
    @location(0) position: vec3<f32>,
    @location(1) color: vec4<f32>,
    @location(2) clip0: vec4<f32>,
    @location(3) clip1: vec4<f32>,
    @location(4) clip2: vec4<f32>,
    @location(5) clip3: vec4<f32>,
    @location(6) instance_color: vec4<f32>,
};

struct VertexOut {
    @builtin(position) position: vec4<f32>,
    @location(0) world_pos: vec3<f32>,
    @location(1) color: vec4<f32>,
};

@vertex
fn vs_main(in: VertexIn) -> VertexOut {
    let clip = mat4x4<f32>(in.clip0, in.clip1, in.clip2, in.clip3);
    var out: VertexOut;
    out.position = clip * vec4<f32>(in.position, 1.0);
    out.world_pos = in.position;
    out.color = in.color * in.instance_color;
    return out;
}

fn ringPulse(radius: f32, scale: f32, width: f32) -> f32 {
    let wave = 0.5 + 0.5 * cos(radius * scale);
    return pow(wave, width);
}

@fragment
fn fs_main(in: VertexOut) -> @location(0) vec4<f32> {
    let radius = length(in.world_pos.xz);
    let rings = ringPulse(radius, 7.0, 4.0) * exp(-radius * 0.18);
    let outer = ringPulse(radius + 0.85, 3.1, 7.0) * exp(-radius * 0.05);
    let center_glow = exp(-radius * radius * 0.58);
    let base = in.color.rgb * (0.18 + rings * 0.12 + outer * 0.08);
    let ember = vec3<f32>(0.95, 0.42, 0.10) * center_glow * 0.26;
    let cool = vec3<f32>(0.06, 0.09, 0.12) * outer * 0.35;
    return vec4<f32>(base + ember + cool, 1.0);
}
