struct SceneUniforms {
    view_proj: mat4x4<f32>,
    camera_position: vec4<f32>,
    ambient_color: vec4<f32>,
    exposure_settings: vec4<f32>,
    color_grading: vec4<f32>,
    environment_dominant_direction: vec4<f32>,
    environment_dominant_color: vec4<f32>,
    light_counts: vec4<u32>,
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
    @location(1) color: vec4<f32>,
};

@group(0) @binding(0) var mesh_sampler: sampler;
@group(0) @binding(1) var mesh_texture: texture_2d<f32>;
@group(0) @binding(2) var<uniform> scene: SceneUniforms;

fn toneMapFilmic(color: vec3<f32>) -> vec3<f32> {
    let shifted = max(vec3<f32>(0.0), color - vec3<f32>(0.004));
    return
        (shifted * (6.2 * shifted + vec3<f32>(0.5))) /
        (shifted * (6.2 * shifted + vec3<f32>(1.7)) + vec3<f32>(0.06));
}

fn rrtAndOdtFit(v: vec3<f32>) -> vec3<f32> {
    let a = v * (v + vec3<f32>(0.0245786)) - vec3<f32>(0.000090537);
    let b = v * (vec3<f32>(0.983729) * v + vec3<f32>(0.4329510)) + vec3<f32>(0.238081);
    return a / b;
}

fn toneMapAcesFitted(color: vec3<f32>) -> vec3<f32> {
    let aces_input = mat3x3<f32>(
        vec3<f32>(0.59719, 0.35458, 0.04823),
        vec3<f32>(0.07600, 0.90834, 0.01566),
        vec3<f32>(0.02840, 0.13383, 0.83777),
    );
    let aces_output = mat3x3<f32>(
        vec3<f32>(1.60475, -0.53108, -0.07367),
        vec3<f32>(-0.10208, 1.10813, -0.00605),
        vec3<f32>(-0.00327, -0.07276, 1.07602),
    );
    let fitted = rrtAndOdtFit(aces_input * (color / 0.6));
    return clamp(aces_output * fitted, vec3<f32>(0.0), vec3<f32>(1.0));
}

fn agxDefaultContrastApprox(x: vec3<f32>) -> vec3<f32> {
    let x2 = x * x;
    let x4 = x2 * x2;
    return
        15.5 * x4 * x2 -
        40.14 * x4 * x +
        31.96 * x4 -
        6.868 * x2 * x +
        0.4298 * x2 +
        0.1191 * x -
        0.00232;
}

fn toneMapAgX(color: vec3<f32>) -> vec3<f32> {
    let linear_rec2020_to_linear_srgb = mat3x3<f32>(
        vec3<f32>(1.6605, -0.5876, -0.0728),
        vec3<f32>(-0.1246, 1.1329, -0.0083),
        vec3<f32>(-0.0182, -0.1006, 1.1187),
    );
    let linear_srgb_to_linear_rec2020 = mat3x3<f32>(
        vec3<f32>(0.6274, 0.3293, 0.0433),
        vec3<f32>(0.0691, 0.9195, 0.0113),
        vec3<f32>(0.0164, 0.0880, 0.8956),
    );
    let agx_inset = mat3x3<f32>(
        vec3<f32>(0.856627153315983, 0.0951212405381588, 0.0482516061458583),
        vec3<f32>(0.137318972929847, 0.761241990602591, 0.101439036467562),
        vec3<f32>(0.11189821299995, 0.0767994186031903, 0.811302368396859),
    );
    let agx_outset = mat3x3<f32>(
        vec3<f32>(1.1271005818144368, -0.11060664309660323, -0.016493938717834573),
        vec3<f32>(-0.1413297634984383, 1.157823702216272, -0.016493938717834257),
        vec3<f32>(-0.14132976349843826, -0.11060664309660294, 1.2519364065950405),
    );
    let agx_min_ev = -12.47393;
    let agx_max_ev = 4.026069;

    var mapped = linear_srgb_to_linear_rec2020 * color;
    mapped = agx_inset * mapped;
    mapped = max(mapped, vec3<f32>(1e-10));
    mapped = log2(mapped);
    mapped = clamp((mapped - vec3<f32>(agx_min_ev)) / vec3<f32>(agx_max_ev - agx_min_ev), vec3<f32>(0.0), vec3<f32>(1.0));
    mapped = agxDefaultContrastApprox(mapped);
    mapped = agx_outset * mapped;
    mapped = max(vec3<f32>(0.0), mapped);
    return clamp(linear_rec2020_to_linear_srgb * mapped, vec3<f32>(0.0), vec3<f32>(1.0));
}

fn toneMapPbrNeutral(color: vec3<f32>) -> vec3<f32> {
    let start_compression = 0.8 - 0.04;
    let desaturation = 0.15;

    var mapped = color;
    let x = min(mapped.r, min(mapped.g, mapped.b));
    let offset = select(0.04, x - 6.25 * x * x, x < 0.08);
    mapped -= vec3<f32>(offset);

    let peak = max(mapped.r, max(mapped.g, mapped.b));
    if (peak < start_compression) {
        return mapped;
    }

    let d = 1.0 - start_compression;
    let new_peak = 1.0 - d * d / (peak + d - start_compression);
    mapped *= new_peak / peak;

    let g = 1.0 - 1.0 / (desaturation * (peak - new_peak) + 1.0);
    return mix(mapped, vec3<f32>(new_peak), g);
}

fn applyColorGrade(color: vec3<f32>) -> vec3<f32> {
    let grade_mode = u32(scene.color_grading.x + 0.5);
    let amount = clamp(scene.color_grading.y, 0.0, 1.0);
    var graded = max(color, vec3<f32>(0.0));

    switch (grade_mode) {
        case 1u: {
            graded = toneMapFilmic(graded);
        }
        case 2u: {
            graded = toneMapAcesFitted(graded);
        }
        case 3u: {
            graded = toneMapAgX(graded);
        }
        case 4u: {
            graded = toneMapPbrNeutral(graded);
        }
        default: {}
    }

    return mix(max(color, vec3<f32>(0.0)), graded, amount);
}

@vertex
fn vs_main(input: VertexIn) -> VertexOut {
    let clip_model = mat4x4<f32>(input.clip0, input.clip1, input.clip2, input.clip3);
    var out: VertexOut;
    out.position = clip_model * vec4<f32>(input.position, 1.0);
    out.uv = input.uv;
    out.color = input.color;
    return out;
}

@fragment
fn fs_main(input: VertexOut) -> @location(0) vec4<f32> {
    var color = textureSample(mesh_texture, mesh_sampler, input.uv).rgb * input.color.rgb;
    if (scene.exposure_settings.y > 0.5) {
        // Keep sky from over-brightening when scene auto-exposure lifts interiors.
        color *= scene.exposure_settings.x * 0.55;
    }
    return vec4<f32>(applyColorGrade(color), input.color.a);
}
