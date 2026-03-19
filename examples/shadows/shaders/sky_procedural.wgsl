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

fn directionFromEquirectUv(uv: vec2<f32>) -> vec3<f32> {
    let wrapped_u = fract(uv.x);
    let clamped_v = clamp(uv.y, 0.0, 1.0);
    let lon = (wrapped_u - 0.5) * (2.0 * 3.141592653589793);
    let lat = (0.5 - clamped_v) * 3.141592653589793;
    let cos_lat = cos(lat);
    return normalize(vec3<f32>(
        sin(lon) * cos_lat,
        sin(lat),
        cos(lon) * cos_lat,
    ));
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
    var amp = 0.58;
    var freq = 1.0;
    for (var i: i32 = 0; i < 4; i += 1) {
        value += noise2(p * freq) * amp;
        freq *= 2.03;
        amp *= 0.52;
    }
    return value;
}

fn remap01(v: f32, lo: f32, hi: f32) -> f32 {
    return saturate((v - lo) / max(hi - lo, 1e-5));
}

fn cloudField(uv: vec2<f32>, coverage: f32, density: f32) -> f32 {
    let macro_shape = fbm2(uv * 0.75);
    let body = fbm2(uv * 1.7 + vec2<f32>(2.1, -1.4));
    let erosion = fbm2(uv * 4.9 + vec2<f32>(7.3, 3.6));
    var v = macro_shape * 0.60 + body * 0.55 - erosion * 0.46;
    v = remap01(v, 0.72 - coverage * 0.44, 0.95);
    return pow(v, 1.45) * (0.22 + 0.72 * density);
}

fn renderClouds(
    dir: vec3<f32>,
    sun_dir: vec3<f32>,
    day_amount: f32,
    coverage: f32,
    density: f32,
    wind_phase: f32,
) -> vec4<f32> {
    let sky_mask = smoothstep(-0.06, 0.22, dir.y);
    if (sky_mask <= 0.0) {
        return vec4<f32>(0.0);
    }

    let wind_angle = wind_phase * (2.0 * 3.141592653589793);
    let wind_vec = vec2<f32>(cos(wind_angle), sin(wind_angle));
    let dome = dir.xz / (dir.y + 0.32);
    let jitter = hash21(dome * 61.7) - 0.5;

    var transmittance = 1.0;
    var accum = vec3<f32>(0.0);
    let light_wrap = saturate(dot(dir, sun_dir) * 0.5 + 0.5);
    let silver = pow(saturate(dot(dir, sun_dir)), 18.0) * 0.65;
    let dark_col = mix(vec3<f32>(0.42, 0.47, 0.55), vec3<f32>(0.58, 0.63, 0.70), day_amount);
    let bright_col = mix(vec3<f32>(0.72, 0.77, 0.84), vec3<f32>(0.97, 0.99, 1.0), day_amount);
    let cloud_col = mix(dark_col, bright_col, saturate(light_wrap * 0.72 + silver));

    let uv0 = dome * 0.62 + wind_vec * (0.011 + jitter * 0.0015);
    let uv1 = dome * 0.95 + wind_vec * (0.018 + jitter * 0.0015) + vec2<f32>(1.7, -2.4);
    let uv2 = dome * 1.41 + wind_vec * (0.026 + jitter * 0.0015) + vec2<f32>(5.3, 3.2);

    let d0 = cloudField(uv0, coverage, density) * sky_mask;
    let d1 = cloudField(uv1, coverage * 0.94, density * 0.92) * sky_mask * 0.82;
    let d2 = cloudField(uv2, coverage * 0.90, density * 0.88) * sky_mask * 0.60;

    let a0 = saturate(d0 * 0.72);
    let a1 = saturate(d1 * 0.62);
    let a2 = saturate(d2 * 0.52);
    accum += transmittance * cloud_col * a0;
    transmittance *= 1.0 - a0;
    accum += transmittance * cloud_col * a1;
    transmittance *= 1.0 - a1;
    accum += transmittance * cloud_col * a2;
    transmittance *= 1.0 - a2;

    return vec4<f32>(accum, 1.0 - transmittance);
}

fn renderMoon(
    dir: vec3<f32>,
    sun_dir: vec3<f32>,
    day_amount: f32,
) -> vec4<f32> {
    let night_visibility = smoothstep(0.35, 0.0, day_amount);
    if (night_visibility <= 0.0) {
        return vec4<f32>(0.0);
    }

    let moon_dir = normalize(-sun_dir + vec3<f32>(0.0, 0.08, 0.0));
    let up_ref = select(
        vec3<f32>(1.0, 0.0, 0.0),
        vec3<f32>(0.0, 1.0, 0.0),
        abs(moon_dir.y) < 0.95,
    );
    let moon_right = normalize(cross(up_ref, moon_dir));
    let moon_up = cross(moon_dir, moon_right);

    let forward = dot(dir, moon_dir);
    if (forward <= 0.0) {
        return vec4<f32>(0.0);
    }

    // Slightly enlarged angular radius for readability and drama.
    let moon_radius = 0.022;
    let local = vec2<f32>(dot(dir, moon_right), dot(dir, moon_up)) / max(forward, 1e-4);
    let uv = local / (moon_radius * 2.0) + vec2<f32>(0.5, 0.5);
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        return vec4<f32>(0.0);
    }

    var moon_sample = textureSample(mesh_texture, mesh_sampler, uv);
    let edge_soften = smoothstep(1.0, 0.84, length(local) / moon_radius);
    moon_sample.a *= edge_soften * night_visibility;
    return moon_sample;
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
        case 1u: { graded = toneMapFilmic(graded); }
        case 2u: { graded = toneMapAcesFitted(graded); }
        case 3u: { graded = toneMapAgX(graded); }
        case 4u: { graded = toneMapPbrNeutral(graded); }
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
    let dir = directionFromEquirectUv(input.uv);
    let sun_dir = normalize(scene.environment_dominant_direction.xyz);
    let day_amount = smoothstep(-0.14, 0.10, sun_dir.y);
    let twilight = exp(-abs(sun_dir.y) * 16.0);
    let horizon = pow(1.0 - saturate(abs(dir.y)), 2.5);

    let zenith_day = vec3<f32>(0.18, 0.43, 0.82);
    let horizon_day = vec3<f32>(0.64, 0.76, 0.89);
    let zenith_twilight = vec3<f32>(0.24, 0.12, 0.30);
    let horizon_twilight = vec3<f32>(0.99, 0.46, 0.20);
    let zenith_night = vec3<f32>(0.015, 0.03, 0.09);
    let horizon_night = vec3<f32>(0.03, 0.05, 0.12);
    let zenith_base = mix(mix(zenith_night, zenith_twilight, twilight), zenith_day, day_amount);
    let horizon_base = mix(mix(horizon_night, horizon_twilight, twilight), horizon_day, day_amount);
    var color = mix(zenith_base, horizon_base, horizon);

    let sun_dot = saturate(dot(dir, sun_dir));
    let sun_disc = smoothstep(0.9982, 0.9997, sun_dot);
    color += mix(vec3<f32>(0.62, 0.70, 0.90), scene.environment_dominant_color.rgb, day_amount) * sun_disc * (3.7 + twilight * 2.2);

    let coverage = saturate(input.color.r);
    let density = saturate(input.color.g);
    let haze = saturate(input.color.b);
    let wind_phase = input.color.a;

    let clouds = renderClouds(dir, sun_dir, day_amount, coverage, density, wind_phase);
    color = mix(color, clouds.rgb, clouds.a);

    let moon = renderMoon(dir, sun_dir, day_amount);
    color = mix(color, moon.rgb * vec3<f32>(0.95, 0.98, 1.05), moon.a);

    let haze_col = mix(vec3<f32>(0.24, 0.29, 0.38), vec3<f32>(0.68, 0.74, 0.82), day_amount);
    color = mix(color, haze_col, haze * horizon * 0.10);

    if (scene.exposure_settings.y > 0.5) {
        color *= scene.exposure_settings.x * 0.55;
    }
    return vec4<f32>(applyColorGrade(color), 1.0);
}
