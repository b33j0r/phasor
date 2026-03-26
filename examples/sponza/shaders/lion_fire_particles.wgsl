struct SceneUniforms {
    view_proj: mat4x4<f32>,
    camera_position: vec4<f32>,
    ambient_color: vec4<f32>,
    exposure_settings: vec4<f32>,
    color_grading: vec4<f32>,
    environment_dominant_direction: vec4<f32>,
    environment_dominant_color: vec4<f32>,
    light_counts: vec4<u32>,
    debug_view: vec4<u32>,
    environment_flags: vec4<u32>,
    environment_irradiance_sh: array<vec4<f32>, 9>,
};

struct VertexIn {
    @location(0) position: vec3<f32>,
    @location(1) uv: vec2<f32>,
    @location(2) clip0: vec4<f32>,
    @location(3) clip1: vec4<f32>,
    @location(4) clip2: vec4<f32>,
    @location(5) clip3: vec4<f32>,
    @location(6) model0: vec4<f32>,
    @location(7) model1: vec4<f32>,
    @location(8) model2: vec4<f32>,
    @location(9) model3: vec4<f32>,
    @location(10) color: vec4<f32>,
};

struct VertexOut {
    @builtin(position) position: vec4<f32>,
    @location(0) uv: vec2<f32>,
    @location(1) local_pos: vec3<f32>,
    @location(2) color: vec4<f32>,
};

@group(0) @binding(0) var mesh_sampler: sampler;
@group(0) @binding(1) var mesh_texture: texture_2d<f32>;
@group(0) @binding(2) var<uniform> scene: SceneUniforms;

fn saturate(v: f32) -> f32 {
    return clamp(v, 0.0, 1.0);
}

fn hash21(p: vec2<f32>) -> f32 {
    let n = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(n) * 43758.5453123);
}

fn noise2(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let a = hash21(i);
    let b = hash21(i + vec2<f32>(1.0, 0.0));
    let c = hash21(i + vec2<f32>(0.0, 1.0));
    let d = hash21(i + vec2<f32>(1.0, 1.0));
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

@vertex
fn vs_main(input: VertexIn) -> VertexOut {
    let clip_model = mat4x4<f32>(input.clip0, input.clip1, input.clip2, input.clip3);
    var out: VertexOut;
    out.position = clip_model * vec4<f32>(input.position, 1.0);
    out.uv = input.uv;
    out.local_pos = input.position;
    out.color = input.color;
    return out;
}

@fragment
fn fs_main(input: VertexOut) -> @location(0) vec4<f32> {
    let local = input.local_pos;
    let uv = input.uv;
    let radius = length(local);
    let shell = 1.0 - smoothstep(0.18, 0.96, radius);
    let vertical = saturate(local.y * 1.25 + 0.48);
    let core = 1.0 - smoothstep(0.0, 0.72, radius);
    let edge_breakup = noise2(vec2<f32>(uv.x * 7.5 + input.color.b * 6.0, uv.y * 8.5 + input.color.r * 5.0));
    let breakup = saturate(0.52 + edge_breakup * 0.64);
    let alpha = input.color.a * shell * vertical * breakup;
    if (alpha <= 0.001) {
        discard;
    }

    var color = input.color.rgb;
    let ember = smoothstep(0.18, 0.88, 1.0 - vertical) * (1.0 - core);
    color = mix(color, vec3<f32>(0.22, 0.05, 0.02), ember * 0.36);
    color *= (0.78 + 0.95 * core + 0.22 * vertical);

    if (scene.exposure_settings.y > 0.5) {
        color *= scene.exposure_settings.x * 0.55;
    }
    return vec4<f32>(color, alpha);
}
