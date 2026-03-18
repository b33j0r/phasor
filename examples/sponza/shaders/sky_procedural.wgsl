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
    @location(2) world_position: vec3<f32>,
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
    let phi = (uv.x - 0.5) * (2.0 * 3.141592653589793);
    let theta = (0.5 - uv.y) * 3.141592653589793;
    let cos_theta = cos(theta);
    return normalize(vec3<f32>(
        sin(phi) * cos_theta,
        sin(theta),
        cos(phi) * cos_theta,
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
    var amp = 0.55;
    var freq = 1.0;
    for (var i: i32 = 0; i < 5; i += 1) {
        value += noise2(p * freq) * amp;
        freq *= 2.09;
        amp *= 0.53;
    }
    return value;
}

fn noise3Approx(p: vec3<f32>) -> f32 {
    let n0 = noise2(p.xz);
    let n1 = noise2(p.xy * 1.31 + vec2<f32>(3.2, 1.7));
    let n2 = noise2(p.yz * 0.83 + vec2<f32>(7.9, 2.4));
    return (n0 + n1 + n2) * (1.0 / 3.0);
}

fn fbm3Approx(p: vec3<f32>) -> f32 {
    var value = 0.0;
    var amp = 0.56;
    var freq = 1.0;
    for (var i: i32 = 0; i < 4; i += 1) {
        value += noise3Approx(p * freq) * amp;
        freq *= 2.05;
        amp *= 0.52;
    }
    return value;
}

fn fbm3Low(p: vec3<f32>) -> f32 {
    var value = 0.0;
    var amp = 0.65;
    var freq = 1.0;
    for (var i: i32 = 0; i < 2; i += 1) {
        value += noise3Approx(p * freq) * amp;
        freq *= 2.02;
        amp *= 0.50;
    }
    return value;
}

fn remap01(v: f32, min_v: f32, max_v: f32) -> f32 {
    return saturate((v - min_v) / max(max_v - min_v, 1e-5));
}

fn cloudHeightProfile(h: f32) -> f32 {
    if (h <= 0.0 || h >= 1.0) {
        return 0.0;
    }
    let base = smoothstep(0.12, 0.36, h);
    let top_falloff = 1.0 - smoothstep(0.70, 1.0, h);
    let mid = 1.0 - abs(h - 0.52) * 1.55;
    return base * top_falloff * saturate(mid);
}

fn cloudDensitySample(
    p: vec3<f32>,
    dir_hint: vec3<f32>,
    cloud_coverage: f32,
    cloud_density: f32,
    wind_phase: f32,
    weather_phase: f32,
) -> f32 {
    let planet_radius = 1000.0;
    let cloud_base = 70.0;
    let cloud_top = 240.0;
    let altitude = length(p) - planet_radius;
    let h = saturate((altitude - cloud_base) / (cloud_top - cloud_base));
    let vertical = cloudHeightProfile(h);
    if (vertical <= 0.0) {
        return 0.0;
    }

    let sphere_dir = normalize(p);
    let weather_coord = sphere_dir * vec3<f32>(4.1, 2.4, 4.1) +
        vec3<f32>(wind_phase * 0.025, weather_phase * 0.020, -wind_phase * 0.018);
    let macro_weather = fbm3Low(weather_coord);
    let macro_breaks = fbm3Low(
        sphere_dir * vec3<f32>(8.2, 5.0, 8.2) +
            vec3<f32>(weather_phase * 0.032, -wind_phase * 0.022, weather_phase * 0.015),
    );
    let weather_mix = macro_weather - (macro_breaks - 0.5) * 0.36;
    let weather_threshold = 0.74 - cloud_coverage * 0.44;
    let weather_mask = remap01(weather_mix, weather_threshold, weather_threshold + 0.20);
    if (weather_mask <= 0.001) {
        return 0.0;
    }

    // Volume body with domain warp and erosion for stronger structure/voids.
    let wind_dir = normalize(vec3<f32>(0.78, 0.0, 0.62));
    let flow = wind_dir * wind_phase * 0.9;
    let warp = (fbm3Approx(p * 0.015 + flow * 0.035) - 0.5) * 26.0;
    let warp_p = p + wind_dir * warp;

    let base = fbm3Approx(warp_p * vec3<f32>(1.0, 0.92, 1.0) * 0.040 + flow * 0.08);
    let detail = fbm3Approx(warp_p * vec3<f32>(1.0, 1.45, 1.0) * 0.12 + vec3<f32>(4.3, 2.1, 1.9) + flow * 0.17);
    let erosion = fbm3Approx(warp_p * vec3<f32>(1.0, 2.0, 1.0) * 0.34 + vec3<f32>(11.4, 3.8, 7.6) - flow * 0.22);
    let directional_break = fbm3Approx(dir_hint * 13.0 + vec3<f32>(weather_phase * 0.6, 0.0, -weather_phase * 0.5));

    var body = mix(base, detail, 0.48);
    body -= (erosion - 0.5) * 0.56;
    body -= (directional_break - 0.5) * 0.26;
    let density_threshold = 0.60 - cloud_density * 0.24;
    body = remap01(body, density_threshold, density_threshold + 0.28);
    body = pow(body, 1.55);

    return body * weather_mask * vertical * (0.58 + 0.98 * cloud_density);
}

fn cloudDensityShadow(
    p: vec3<f32>,
    dir_hint: vec3<f32>,
    cloud_coverage: f32,
    cloud_density: f32,
    wind_phase: f32,
    weather_phase: f32,
) -> f32 {
    let planet_radius = 1000.0;
    let altitude = length(p) - planet_radius;
    let h = saturate((altitude - 70.0) / (240.0 - 70.0));
    let vertical = cloudHeightProfile(h);
    if (vertical <= 0.0) {
        return 0.0;
    }

    let sphere_dir = normalize(p);
    let weather = fbm3Low(
        sphere_dir * vec3<f32>(4.1, 2.4, 4.1) +
            vec3<f32>(wind_phase * 0.025, weather_phase * 0.020, -wind_phase * 0.018),
    );
    let weather_threshold = 0.74 - cloud_coverage * 0.44;
    let weather_mask = remap01(weather, weather_threshold, weather_threshold + 0.22);
    if (weather_mask <= 0.001) {
        return 0.0;
    }

    let body = fbm3Low(
        p * vec3<f32>(1.0, 1.0, 1.0) * 0.052 +
            dir_hint * 0.35 +
            vec3<f32>(wind_phase * 0.12, 0.0, -wind_phase * 0.09),
    );
    let density = remap01(body, 0.58 - cloud_density * 0.16, 0.92);
    return density * weather_mask * vertical * (0.52 + 0.74 * cloud_density);
}

fn raySphereInterval(origin: vec3<f32>, dir: vec3<f32>, radius: f32) -> vec2<f32> {
    let b = dot(origin, dir);
    let c = dot(origin, origin) - radius * radius;
    let h = b * b - c;
    if (h < 0.0) {
        return vec2<f32>(1e9, -1e9);
    }
    let s = sqrt(h);
    return vec2<f32>(-b - s, -b + s);
}

fn renderVolumetricClouds(
    dir: vec3<f32>,
    sun_dir: vec3<f32>,
    cloud_coverage: f32,
    cloud_density: f32,
    day_amount: f32,
) -> vec4<f32> {
    // Avoid wasting work looking down.
    if (dir.y <= -0.03) {
        return vec4<f32>(0.0);
    }

    // Raymarch inside a spherical cloud shell to avoid planar perspective artifacts.
    let planet_radius = 1000.0;
    let camera_height = 2.0;
    let cloud_base = 70.0;
    let cloud_top = 240.0;
    let camera_pos = vec3<f32>(0.0, planet_radius + camera_height, 0.0);
    let inner_r = planet_radius + cloud_base;
    let outer_r = planet_radius + cloud_top;

    let outer_hit = raySphereInterval(camera_pos, dir, outer_r);
    let inner_hit = raySphereInterval(camera_pos, dir, inner_r);
    if (outer_hit.y <= 0.0 || inner_hit.y <= 0.0) {
        return vec4<f32>(0.0);
    }

    var t_enter = max(inner_hit.y, 0.0);
    var t_exit = outer_hit.y;
    if (t_exit <= t_enter) {
        return vec4<f32>(0.0);
    }

    // Clamp near-horizon distances to keep steps stable/perf.
    t_exit = min(t_exit, 900.0);
    if (t_exit <= t_enter) {
        return vec4<f32>(0.0);
    }

    let march_dist = t_exit - t_enter;
    let step_len = march_dist / 13.0;
    let sun_azimuth = atan2(sun_dir.x, sun_dir.z);
    let wind_phase = sun_azimuth * 4.0;
    let weather_phase = sun_azimuth * 0.20 + sun_dir.y * 0.65;
    let jitter = hash21(dir.xz * 157.3 + dir.yy * 97.1);

    var transmittance = 1.0;
    var accum = vec3<f32>(0.0);
    for (var i: i32 = 0; i < 13; i += 1) {
        let t = t_enter + step_len * (f32(i) + jitter);
        let p = camera_pos + dir * t;
        let density = cloudDensitySample(p, dir, cloud_coverage, cloud_density, wind_phase, weather_phase);
        if (density <= 0.0008) {
            continue;
        }

        // Approximate light marching with several taps toward sun.
        var shadow_density = 0.0;
        for (var j: i32 = 0; j < 2; j += 1) {
            let lt = step_len * (1.8 + 2.4 * f32(j));
            shadow_density += cloudDensityShadow(p + sun_dir * lt, sun_dir, cloud_coverage, cloud_density, wind_phase, weather_phase);
        }
        let shadow = exp(-shadow_density * 0.78);
        let silver = pow(saturate(dot(dir, sun_dir)), 16.0) * 0.72;
        let phase = 0.35 + 0.65 * saturate(dot(sun_dir, vec3<f32>(0.0, 1.0, 0.0)) * 0.7 + 0.3);
        let lighting = shadow * phase + silver;
        let core_occlusion = exp(-density * 3.0);

        let dark_col = mix(vec3<f32>(0.18, 0.22, 0.29), vec3<f32>(0.14, 0.17, 0.23), day_amount);
        let bright_col = mix(vec3<f32>(0.84, 0.88, 0.93), vec3<f32>(0.99, 0.99, 0.995), day_amount);
        var sample_col = mix(dark_col, bright_col, saturate(lighting));
        sample_col *= mix(0.62, 1.0, core_occlusion);

        let alpha = saturate(1.0 - exp(-density * step_len * 6.9));
        accum += transmittance * sample_col * alpha;
        transmittance *= 1.0 - alpha;
        if (transmittance < 0.035) {
            break;
        }
    }

    return vec4<f32>(accum, 1.0 - transmittance);
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
    let model = mat4x4<f32>(input.model0, input.model1, input.model2, input.model3);
    let world_position = model * vec4<f32>(input.position, 1.0);
    var out: VertexOut;
    out.position = clip_model * vec4<f32>(input.position, 1.0);
    out.uv = input.uv;
    out.color = input.color;
    out.world_position = world_position.xyz;
    return out;
}

@fragment
fn fs_main(input: VertexOut) -> @location(0) vec4<f32> {
    let dir = directionFromEquirectUv(input.uv);
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

    let cloud_coverage = saturate(1.02 - scene.exposure_settings.w * 11.0);
    let cloud_density = saturate(0.30 + cloud_coverage * 0.72);

    let mie_glow = pow(sun_dot, mix(24.0, 320.0, day_amount));
    let sun_disc = smoothstep(0.997, 0.9996, sun_dot);
    let sun_color = mix(vec3<f32>(0.65, 0.72, 0.90), scene.environment_dominant_color.rgb, day_amount);

    let star_uv = vec2<f32>(
        dot(dir, normalize(vec3<f32>(0.34, 0.87, -0.36))),
        dot(dir, normalize(vec3<f32>(-0.71, 0.21, 0.67))),
    ) * vec2<f32>(430.0, 260.0);
    let stars = pow(saturate(noise2(star_uv) - 0.985), 14.0) * (1.0 - day_amount) * saturate(dir.y * 2.0 + 0.2);

    var color = sky_base;
    color += sun_color * mie_glow * (0.22 + 0.45 * day_amount);
    color += sun_color * sun_disc * 6.5;
    color += vec3<f32>(stars);
    let cloud_vol = renderVolumetricClouds(dir, sun_dir, cloud_coverage, cloud_density, day_amount);
    color = mix(color, cloud_vol.rgb, cloud_vol.a);
    color *= input.color.rgb;

    if (scene.exposure_settings.y > 0.5) {
        color *= scene.exposure_settings.x * 0.55;
    }
    return vec4<f32>(applyColorGrade(color), input.color.a);
}
