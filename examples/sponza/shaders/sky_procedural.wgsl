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

fn fbm2(p: vec2<f32>) -> f32 {
    var value = 0.0;
    var amp = 0.55;
    var freq = 1.0;
    for (var i: i32 = 0; i < 3; i += 1) {
        value += noise2(p * freq) * amp;
        freq *= 2.03;
        amp *= 0.5;
    }
    return value;
}

fn directionFromUv(uv_in: vec2<f32>) -> vec3<f32> {
    let uv = vec2<f32>(fract(uv_in.x), clamp(uv_in.y, 0.0, 1.0));
    let longitude = (uv.x - 0.5) * (2.0 * 3.14159265359);
    let latitude = (0.5 - uv.y) * 3.14159265359;
    let cos_lat = cos(latitude);
    return normalize(vec3<f32>(
        sin(longitude) * cos_lat,
        sin(latitude),
        cos(longitude) * cos_lat
    ));
}

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
    let dir = directionFromUv(input.uv);
    let sun_dir = normalize(scene.environment_dominant_direction.xyz);

    let sun_dot = saturate(dot(dir, sun_dir));
    let day_amount = smoothstep(-0.08, 0.10, sun_dir.y);
    let horizon = pow(1.0 - saturate(abs(dir.y)), 1.7);

    let zenith_day = vec3<f32>(0.20, 0.44, 0.86);
    let horizon_day = vec3<f32>(0.80, 0.66, 0.46);
    let zenith_night = vec3<f32>(0.02, 0.04, 0.10);
    let horizon_night = vec3<f32>(0.06, 0.08, 0.13);

    let clear_zenith = mix(zenith_night, zenith_day, day_amount);
    let clear_horizon = mix(horizon_night, horizon_day, day_amount);
    let sky_base = mix(clear_zenith, clear_horizon, horizon);

    let cloud_coverage = saturate(1.04 - scene.exposure_settings.w * 12.0);
    let cloud_density = saturate(0.25 + cloud_coverage * 0.75);
    let cloud_uv = vec2<f32>(input.uv.x * 5.0 + sun_dir.x * 1.7, input.uv.y * 7.0 + sun_dir.z * 1.7);
    let cloud_noise = fbm2(cloud_uv);
    let cloud_mask = smoothstep(1.0 - cloud_coverage, 1.0 - cloud_coverage + (0.28 + 0.35 * (1.0 - cloud_density)), cloud_noise) * saturate(1.0 - abs(dir.y) * 0.35);
    let cloud_color = mix(vec3<f32>(0.30, 0.34, 0.42), vec3<f32>(0.93, 0.94, 0.97), day_amount);

    let mie_glow = pow(sun_dot, mix(24.0, 320.0, day_amount));
    let sun_disc = smoothstep(0.997, 0.9996, sun_dot);
    let sun_color = mix(vec3<f32>(0.65, 0.72, 0.90), scene.environment_dominant_color.rgb, day_amount);

    let stars = pow(saturate(noise2(input.uv * vec2<f32>(420.0, 260.0)) - 0.985), 14.0) * (1.0 - day_amount) * saturate(dir.y * 2.0 + 0.2);

    var color = sky_base;
    color += sun_color * mie_glow * (0.22 + 0.45 * day_amount);
    color += sun_color * sun_disc * 6.5;
    color = mix(color, cloud_color, cloud_mask * (0.42 + 0.45 * day_amount));
    color += vec3<f32>(stars);
    color *= input.color.rgb;

    if (scene.exposure_settings.y > 0.5) {
        color *= scene.exposure_settings.x * 0.55;
    }
    return vec4<f32>(applyColorGrade(color), input.color.a);
}
