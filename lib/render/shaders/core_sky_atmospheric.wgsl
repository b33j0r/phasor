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
    @location(1) color: vec4<f32>,
};

struct AtmosphereResult {
    color: vec3<f32>,
    transmittance: vec3<f32>,
};

@group(0) @binding(0) var mesh_sampler: sampler;
@group(0) @binding(1) var mesh_texture: texture_2d<f32>;
@group(0) @binding(2) var<uniform> scene: SceneUniforms;

const PI: f32 = 3.141592653589793;
const earth_radius: f32 = 6360000.0;
const atmosphere_radius: f32 = 6420000.0;
const viewer_height: f32 = 2.0;
const cloud_bottom: f32 = 1400.0;
const cloud_top: f32 = 3100.0;
const rayleigh_scale_height: f32 = 8000.0;
const mie_scale_height: f32 = 1200.0;
const beta_rayleigh: vec3<f32> = vec3<f32>(5.8e-6, 13.5e-6, 33.1e-6);
const beta_mie: vec3<f32> = vec3<f32>(2.1e-5);
const atmosphere_view_samples: i32 = 12;
const atmosphere_light_samples: i32 = 4;
const cloud_samples: i32 = 10;

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
    let lon = (wrapped_u - 0.5) * (2.0 * PI);
    let lat = (0.5 - clamped_v) * PI;
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
    for (var i: i32 = 0; i < 5; i += 1) {
        value += noise2(p * freq) * amp;
        freq *= 2.03;
        amp *= 0.52;
    }
    return value;
}

fn raySphereIntersect(origin: vec3<f32>, dir: vec3<f32>, radius: f32) -> vec2<f32> {
    let b = dot(origin, dir);
    let c = dot(origin, origin) - radius * radius;
    let h = b * b - c;
    if (h < 0.0) {
        return vec2<f32>(-1.0, -1.0);
    }
    let s = sqrt(h);
    return vec2<f32>(-b - s, -b + s);
}

fn phaseRayleigh(mu: f32) -> f32 {
    return 3.0 / (16.0 * PI) * (1.0 + mu * mu);
}

fn phaseMie(mu: f32, g: f32) -> f32 {
    let g2 = g * g;
    let denom = pow(max(1.0 + g2 - 2.0 * g * mu, 1e-3), 1.5);
    return 3.0 / (8.0 * PI) * ((1.0 - g2) * (1.0 + mu * mu)) / ((2.0 + g2) * denom);
}

fn opticalDepthToSun(sample_pos: vec3<f32>, sun_dir: vec3<f32>, haze: f32) -> vec2<f32> {
    let hit = raySphereIntersect(sample_pos, sun_dir, atmosphere_radius);
    if (hit.y <= 0.0) {
        return vec2<f32>(0.0);
    }

    let ground_hit = raySphereIntersect(sample_pos, sun_dir, earth_radius);
    if (ground_hit.y > 0.0) {
        return vec2<f32>(1e9, 1e9);
    }

    let step_len = hit.y / f32(atmosphere_light_samples);
    var depth_r = 0.0;
    var depth_m = 0.0;
    for (var i: i32 = 0; i < atmosphere_light_samples; i += 1) {
        let t = (f32(i) + 0.5) * step_len;
        let p = sample_pos + sun_dir * t;
        let h = max(length(p) - earth_radius, 0.0);
        depth_r += exp(-h / rayleigh_scale_height) * step_len;
        depth_m += exp(-h / mix(mie_scale_height, mie_scale_height * 1.6, haze)) * step_len;
    }
    return vec2<f32>(depth_r, depth_m);
}

fn computeAtmosphere(dir: vec3<f32>, world_pos: vec3<f32>, sun_dir: vec3<f32>, haze: f32) -> AtmosphereResult {
    let camera = vec3<f32>(
        world_pos.x,
        earth_radius + viewer_height + max(world_pos.y, 0.0),
        world_pos.z,
    );
    let atmosphere_hit = raySphereIntersect(camera, dir, atmosphere_radius);
    if (atmosphere_hit.y <= 0.0) {
        return AtmosphereResult(vec3<f32>(0.0), vec3<f32>(1.0));
    }

    var start_t = max(atmosphere_hit.x, 0.0);
    var end_t = atmosphere_hit.y;
    let ground_hit = raySphereIntersect(camera, dir, earth_radius);
    if (ground_hit.x > 0.0) {
        end_t = min(end_t, ground_hit.x);
    }

    let step_len = max((end_t - start_t) / f32(atmosphere_view_samples), 1.0);
    let beta_mie_tinted = mix(beta_mie, beta_mie * vec3<f32>(0.92, 0.95, 1.0), haze * 0.35);
    var optical_depth_r = 0.0;
    var optical_depth_m = 0.0;
    var sum_r = vec3<f32>(0.0);
    var sum_m = vec3<f32>(0.0);
    let mu = dot(dir, sun_dir);

    for (var i: i32 = 0; i < atmosphere_view_samples; i += 1) {
        let t = start_t + (f32(i) + 0.5) * step_len;
        let sample_pos = camera + dir * t;
        let height = max(length(sample_pos) - earth_radius, 0.0);
        let hr = exp(-height / rayleigh_scale_height) * step_len;
        let hm = exp(-height / mix(mie_scale_height, mie_scale_height * 1.6, haze)) * step_len;

        optical_depth_r += hr;
        optical_depth_m += hm;

        let light_depth = opticalDepthToSun(sample_pos, sun_dir, haze);
        if (light_depth.x >= 1e8) {
            continue;
        }

        let tau = beta_rayleigh * (optical_depth_r + light_depth.x) + beta_mie_tinted * (optical_depth_m + light_depth.y);
        let attenuation = exp(-tau);
        sum_r += attenuation * hr;
        sum_m += attenuation * hm;
    }

    let sky = phaseRayleigh(mu) * beta_rayleigh * sum_r + phaseMie(mu, mix(0.72, 0.82, haze)) * beta_mie_tinted * sum_m;
    let view_tau = beta_rayleigh * optical_depth_r + beta_mie_tinted * optical_depth_m;
    return AtmosphereResult(sky, exp(-view_tau));
}

fn moonUv(dir: vec3<f32>, sun_dir: vec3<f32>, radius: f32) -> vec3<f32> {
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
        return vec3<f32>(-1.0);
    }
    let local = vec2<f32>(dot(dir, moon_right), dot(dir, moon_up)) / max(forward, 1e-4);
    let uv = local / (radius * 2.0) + vec2<f32>(0.5, 0.5);
    return vec3<f32>(uv, length(local) / radius);
}

fn renderMoon(dir: vec3<f32>, sun_dir: vec3<f32>, day_amount: f32, transmittance: vec3<f32>) -> vec4<f32> {
    let night_visibility = smoothstep(0.28, 0.0, day_amount);
    if (night_visibility <= 0.0) {
        return vec4<f32>(0.0);
    }

    let moon = moonUv(dir, sun_dir, 0.088);
    if (moon.x < 0.0 || moon.x > 1.0 || moon.y < 0.0 || moon.y > 1.0) {
        return vec4<f32>(0.0);
    }

    var moon_sample = textureSampleLevel(mesh_texture, mesh_sampler, moon.xy, 0.0);
    let edge_soften = smoothstep(1.0, 0.84, moon.z);
    let moon_tint = mix(vec3<f32>(1.10, 0.72, 0.52), vec3<f32>(0.95, 0.98, 1.05), smoothstep(-0.06, 0.14, sun_dir.y));
    moon_sample = vec4<f32>(
        moon_sample.rgb * moon_tint * transmittance,
        moon_sample.a * edge_soften * night_visibility,
    );
    return moon_sample;
}

fn cloudShape(world_pos: vec3<f32>, coverage: f32, density: f32, wind_phase: f32) -> f32 {
    let wind_angle = wind_phase * (2.0 * PI);
    let wind_vec = vec2<f32>(cos(wind_angle), sin(wind_angle));
    let uv = world_pos.xz * 0.00016 + wind_vec * 0.015;
    let macro_shape = fbm2(uv * 0.85);
    let detail = fbm2(uv * 2.1 + vec2<f32>(1.7, -2.9));
    let erosion = fbm2(uv * 5.0 + vec2<f32>(world_pos.y * 0.0012, -world_pos.y * 0.0017));
    let height01 = saturate((world_pos.y - cloud_bottom) / max(cloud_top - cloud_bottom, 1.0));
    let vertical = smoothstep(0.02, 0.20, height01) * (1.0 - smoothstep(0.62, 0.98, height01));
    var shape = macro_shape * 0.70 + detail * 0.38 - erosion * 0.36;
    shape = saturate((shape - (0.58 - coverage * 0.35)) / max(0.32 - density * 0.10, 0.08));
    return shape * vertical;
}

fn cloudSegment(world_pos: vec3<f32>, dir: vec3<f32>) -> vec2<f32> {
    if (abs(dir.y) < 1e-4) {
        return vec2<f32>(-1.0, -1.0);
    }
    let t0 = (cloud_bottom - world_pos.y) / dir.y;
    let t1 = (cloud_top - world_pos.y) / dir.y;
    let entry = min(t0, t1);
    let exit = max(t0, t1);
    if (exit <= 0.0) {
        return vec2<f32>(-1.0, -1.0);
    }
    return vec2<f32>(max(entry, 0.0), exit);
}

fn renderVolumetricClouds(
    world_pos: vec3<f32>,
    dir: vec3<f32>,
    sun_dir: vec3<f32>,
    day_amount: f32,
    coverage: f32,
    density: f32,
    haze: f32,
    wind_phase: f32,
) -> vec4<f32> {
    if (dir.y <= 0.0) {
        return vec4<f32>(0.0);
    }

    let segment = cloudSegment(world_pos, dir);
    if (segment.y <= segment.x) {
        return vec4<f32>(0.0);
    }

    let step_len = min((segment.y - segment.x) / f32(cloud_samples), 900.0);
    if (step_len <= 0.0) {
        return vec4<f32>(0.0);
    }

    let mu = saturate(dot(dir, sun_dir));
    let silver = pow(mu, 10.0);
    let shadow_tint = mix(vec3<f32>(0.10, 0.12, 0.16), vec3<f32>(0.48, 0.52, 0.58), day_amount);
    let light_tint = mix(vec3<f32>(0.18, 0.21, 0.28), vec3<f32>(0.90, 0.93, 0.97), day_amount);
    let cloud_lighting = mix(shadow_tint, light_tint, saturate(mu * 0.45 + silver * 0.45));

    var transmittance = 1.0;
    var accum = vec3<f32>(0.0);
    for (var i: i32 = 0; i < cloud_samples; i += 1) {
        let t = segment.x + (f32(i) + 0.5) * step_len;
        let sample_pos = world_pos + dir * t;
        let shape = cloudShape(sample_pos, coverage, density, wind_phase);
        let alpha = saturate(shape * mix(0.16, 0.24, haze) * step_len * 0.0009);
        accum += transmittance * cloud_lighting * alpha;
        transmittance *= 1.0 - alpha;
        if (transmittance < 0.02) {
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
    let day_amount = smoothstep(-0.12, 0.10, sun_dir.y);
    let twilight = exp(-abs(sun_dir.y) * 16.0);
    let horizon = pow(1.0 - saturate(abs(dir.y)), 2.4);
    let coverage = input.color.r;
    let density = input.color.g;
    let haze = input.color.b;
    let wind_phase = input.color.a;

    let atmosphere = computeAtmosphere(dir, scene.camera_position.xyz, sun_dir, haze);
    let zenith_day = vec3<f32>(0.15, 0.36, 0.74);
    let horizon_day = vec3<f32>(0.62, 0.76, 0.92);
    let zenith_twilight = vec3<f32>(0.24, 0.14, 0.28);
    let horizon_twilight = vec3<f32>(0.98, 0.50, 0.22);
    let zenith_night = vec3<f32>(0.010, 0.015, 0.030);
    let horizon_night = vec3<f32>(0.030, 0.040, 0.070);
    let zenith_base = mix(mix(zenith_night, zenith_twilight, twilight), zenith_day, day_amount);
    let horizon_base = mix(mix(horizon_night, horizon_twilight, twilight), horizon_day, day_amount);
    var color = mix(zenith_base, horizon_base, horizon);

    let scattering_boost =
        atmosphere.color *
        mix(12.0, 42.0, day_amount) *
        mix(0.45, 0.68, haze) *
        mix(0.45, 1.0, horizon);
    color += scattering_boost;

    let sun_mu = saturate(dot(dir, sun_dir));
    let sun_disc = smoothstep(0.9994, 0.99994, sun_mu);
    let sun_halo = pow(sun_mu, 72.0);
    color += scene.environment_dominant_color.rgb * atmosphere.transmittance * (sun_halo * 1.2 + sun_disc * 6.0);

    let clouds = renderVolumetricClouds(scene.camera_position.xyz, dir, sun_dir, day_amount, coverage, density, haze, wind_phase);
    color = mix(color, color * (1.0 - clouds.a * 0.58) + clouds.rgb * mix(0.60, 0.82, day_amount), clouds.a);

    let moon = renderMoon(dir, sun_dir, day_amount, atmosphere.transmittance);
    color = mix(color, moon.rgb * 1.8, moon.a);

    let stars = pow(1.0 - day_amount, 3.0) * smoothstep(0.12, 0.95, dir.y) * saturate(1.0 - clouds.a * 1.3);
    let star_noise = hash21(dir.xz * 850.0 + dir.yx * 420.0);
    color += vec3<f32>(smoothstep(0.9972, 1.0, star_noise)) * stars * 0.05;

    let exposure = max(scene.exposure_settings.x * mix(0.22, 0.06, day_amount), scene.exposure_settings.z * 0.36);
    color *= max(exposure, 0.02);
    let dither = (hash21(input.uv * vec2<f32>(1536.0, 864.0)) - 0.5) / 255.0;
    color += vec3<f32>(dither) * mix(0.65, 0.18, day_amount);

    return vec4<f32>(applyColorGrade(color), 1.0);
}
