struct SceneLight {
    position_range: vec4<f32>,
    direction_kind: vec4<f32>,
    color_intensity: vec4<f32>,
    spot_params: vec4<f32>,
};

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
    lights: array<SceneLight, 32>,
};

struct VertexIn {
    @location(0) position: vec3<f32>,
    @location(1) normal: vec3<f32>,
    @location(2) uv: vec2<f32>,
    @location(3) clip0: vec4<f32>,
    @location(4) clip1: vec4<f32>,
    @location(5) clip2: vec4<f32>,
    @location(6) clip3: vec4<f32>,
    @location(7) model0: vec4<f32>,
    @location(8) model1: vec4<f32>,
    @location(9) model2: vec4<f32>,
    @location(10) model3: vec4<f32>,
    @location(11) color: vec4<f32>,
    @location(12) pbr_params: vec4<f32>,
};

struct VertexOut {
    @builtin(position) position: vec4<f32>,
    @location(0) world_position: vec3<f32>,
    @location(1) world_normal: vec3<f32>,
    @location(2) uv: vec2<f32>,
    @location(3) color: vec4<f32>,
    @location(4) pbr_params: vec4<f32>,
};

@group(0) @binding(0) var mesh_sampler: sampler;
@group(0) @binding(1) var mesh_texture: texture_2d<f32>;
@group(0) @binding(2) var<uniform> scene: SceneUniforms;
@group(0) @binding(3) var metallic_roughness_texture: texture_2d<f32>;
@group(0) @binding(4) var occlusion_texture: texture_2d<f32>;

fn saturate(value: f32) -> f32 {
    return clamp(value, 0.0, 1.0);
}

fn evaluateIrradiance(normal: vec3<f32>) -> vec3<f32> {
    let x = normal.x;
    let y = normal.y;
    let z = normal.z;
    let basis = array<f32, 9>(
        0.282095,
        0.488603 * y,
        0.488603 * z,
        0.488603 * x,
        1.092548 * x * y,
        1.092548 * y * z,
        0.315392 * (3.0 * z * z - 1.0),
        1.092548 * x * z,
        0.546274 * (x * x - y * y),
    );

    var irradiance = vec3<f32>(0.0, 0.0, 0.0);
    for (var i: u32 = 0u; i < 9u; i += 1u) {
        irradiance += scene.environment_irradiance_sh[i].rgb * basis[i];
    }
    return max(irradiance, vec3<f32>(0.0, 0.0, 0.0));
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

const PI: f32 = 3.14159265;

fn fresnelSchlick(cos_theta: f32, f0: vec3<f32>) -> vec3<f32> {
    return f0 + (vec3<f32>(1.0) - f0) * pow(1.0 - cos_theta, 5.0);
}

fn fresnelSchlickRoughness(cos_theta: f32, f0: vec3<f32>, roughness: f32) -> vec3<f32> {
    return f0 + (max(vec3<f32>(1.0 - roughness), f0) - f0) * pow(1.0 - cos_theta, 5.0);
}

// Split-sum environment BRDF fit used by UE/EEVEE-style IBL implementations.
fn environmentBrdfApprox(roughness: f32, ndotv: f32) -> vec2<f32> {
    let c0 = vec4<f32>(-1.0, -0.0275, -0.572, 0.022);
    let c1 = vec4<f32>(1.0, 0.0425, 1.04, -0.04);
    let r = roughness * c0 + c1;
    let a004 = min(r.x * r.x, exp2(-9.28 * ndotv)) * r.x + r.y;
    return vec2<f32>(-1.04, 1.04) * a004 + r.zw;
}

fn distributionGGX(n: vec3<f32>, h: vec3<f32>, roughness: f32) -> f32 {
    let a = roughness * roughness;
    let a2 = a * a;
    let ndoth = saturate(dot(n, h));
    let ndoth2 = ndoth * ndoth;
    let denom = ndoth2 * (a2 - 1.0) + 1.0;
    return a2 / max(PI * denom * denom, 0.0001);
}

fn geometrySchlickGGX(ndotv: f32, roughness: f32) -> f32 {
    let r = roughness + 1.0;
    let k = (r * r) * 0.125;
    return ndotv / max(ndotv * (1.0 - k) + k, 0.0001);
}

fn geometrySmith(n: vec3<f32>, v: vec3<f32>, l: vec3<f32>, roughness: f32) -> f32 {
    let ndotv = saturate(dot(n, v));
    let ndotl = saturate(dot(n, l));
    let ggx2 = geometrySchlickGGX(ndotv, roughness);
    let ggx1 = geometrySchlickGGX(ndotl, roughness);
    return ggx1 * ggx2;
}

fn inverseMat3(m: mat3x3<f32>) -> mat3x3<f32> {
    let a = m[0];
    let b = m[1];
    let c = m[2];
    let r0 = cross(b, c);
    let r1 = cross(c, a);
    let r2 = cross(a, b);
    let det = dot(a, r0);
    if (abs(det) < 1e-8) {
        return mat3x3<f32>(
            vec3<f32>(1.0, 0.0, 0.0),
            vec3<f32>(0.0, 1.0, 0.0),
            vec3<f32>(0.0, 0.0, 1.0),
        );
    }
    let inv_det = 1.0 / det;
    return mat3x3<f32>(r0 * inv_det, r1 * inv_det, r2 * inv_det);
}

@vertex
fn vs_main(input: VertexIn) -> VertexOut {
    let clip_model = mat4x4<f32>(input.clip0, input.clip1, input.clip2, input.clip3);
    let model = mat4x4<f32>(input.model0, input.model1, input.model2, input.model3);
    let normal_matrix = transpose(inverseMat3(mat3x3<f32>(
        model[0].xyz,
        model[1].xyz,
        model[2].xyz,
    )));
    let clip_position = clip_model * vec4<f32>(input.position, 1.0);
    let world_position = model * vec4<f32>(input.position, 1.0);
    let world_normal = normalize(normal_matrix * input.normal);

    var out: VertexOut;
    out.position = clip_position;
    out.world_position = world_position.xyz;
    out.world_normal = world_normal;
    out.uv = input.uv;
    out.color = input.color;
    out.pbr_params = input.pbr_params;
    return out;
}

@fragment
fn fs_main(input: VertexOut) -> @location(0) vec4<f32> {
    let albedo = textureSample(mesh_texture, mesh_sampler, input.uv) * input.color;
    if (albedo.a <= 0.01) {
        discard;
    }

    let normal = normalize(input.world_normal);
    let view_dir = normalize(scene.camera_position.xyz - input.world_position);
    let metallic_roughness_sample = textureSample(metallic_roughness_texture, mesh_sampler, input.uv);
    let occlusion_sample = textureSample(occlusion_texture, mesh_sampler, input.uv);
    let metallic = clamp(input.pbr_params.x * metallic_roughness_sample.b, 0.0, 1.0);
    let roughness = clamp(input.pbr_params.y * metallic_roughness_sample.g, 0.045, 1.0);
    let ao = clamp(mix(1.0, occlusion_sample.r, input.pbr_params.z), 0.0, 1.0);
    let f0 = mix(vec3<f32>(0.04), albedo.rgb, metallic);
    let ndotv = saturate(dot(normal, view_dir));
    let env_fresnel = fresnelSchlickRoughness(ndotv, f0, roughness);
    let kd_ibl = (vec3<f32>(1.0) - env_fresnel) * (1.0 - metallic);

    let irradiance = evaluateIrradiance(normal) * scene.exposure_settings.z;
    let ambient = (scene.ambient_color.rgb + irradiance) * albedo.rgb * kd_ibl * ao;
    var lighting = vec3<f32>(0.0);
    var direct_specular = vec3<f32>(0.0);
    var debug_ndotl = 0.0;
    let light_count = min(scene.light_counts.x, 32u);
    var i: u32 = 0u;
    loop {
        if (i >= light_count) {
            break;
        }

        let light = scene.lights[i];
        let kind = u32(light.direction_kind.w + 0.5);
        var light_dir = vec3<f32>(0.0, 0.0, -1.0);
        var attenuation = 1.0;

        if (kind == 0u) {
            light_dir = normalize(-light.direction_kind.xyz);
        } else {
            let to_light = light.position_range.xyz - input.world_position;
            let actual_distance_sq = max(dot(to_light, to_light), 1e-6);
            let actual_distance = sqrt(actual_distance_sq);
            if (actual_distance > light.position_range.w) {
                i += 1u;
                continue;
            }

            // Use true geometric distance for direction so N.L remains unit-consistent.
            light_dir = to_light / actual_distance;
            // Frostbite/Filament-style punctual attenuation: inverse square with a fixed 1 cm floor.
            let attenuation_distance_sq = max(actual_distance_sq, 1e-4);
            let range_ratio = actual_distance / max(light.position_range.w, 0.001);
            let range_falloff = saturate(1.0 - pow(range_ratio, 4.0));
            attenuation = (range_falloff * range_falloff) / attenuation_distance_sq;

            if (kind == 2u) {
                let cone = dot(normalize(-light.direction_kind.xyz), light_dir);
                let inner_cos = light.spot_params.x;
                let outer_cos = light.spot_params.y;
                let cone_range = max(inner_cos - outer_cos, 0.0001);
                let spot = saturate((cone - outer_cos) / cone_range);
                attenuation *= spot * spot;
            }
        }
        let ndotl = saturate(dot(normal, light_dir));
        debug_ndotl = max(debug_ndotl, ndotl);
        if (ndotl <= 0.0) {
            i += 1u;
            continue;
        }
        let half_dir = normalize(light_dir + view_dir);
        let ndf = distributionGGX(normal, half_dir, roughness);
        let g = geometrySmith(normal, view_dir, light_dir, roughness);
        let f = fresnelSchlick(saturate(dot(half_dir, view_dir)), f0);
        let numerator = ndf * g * f;
        let denominator = max(4.0 * ndotv * ndotl, 0.0001);
        let specular = numerator / denominator;
        let ks = f;
        let kd = (vec3<f32>(1.0) - ks) * (1.0 - metallic);
        let radiance = light.color_intensity.rgb * light.color_intensity.w * attenuation;
        direct_specular += specular * radiance * ndotl;
        lighting += (kd * albedo.rgb / PI + specular) * radiance * ndotl;
        i += 1u;
    }

    let reflection = reflect(-view_dir, normal);
    let env_alignment = saturate(dot(reflection, normalize(scene.environment_dominant_direction.xyz)));
    let prefiltered_env = scene.environment_dominant_color.rgb * pow(env_alignment, mix(96.0, 12.0, roughness));
    let env_brdf = environmentBrdfApprox(roughness, ndotv);
    // Damped because we currently use dominant-direction proxy instead of prefiltered env cubemap mip chain.
    let env_specular_enabled = f32(scene.environment_flags.x);
    let env_specular = prefiltered_env * (env_fresnel * env_brdf.x + vec3<f32>(env_brdf.y)) * scene.exposure_settings.w * 0.10 * env_specular_enabled;
    let specular_only = direct_specular + env_specular;
    let debug_view = scene.debug_view.x;
    if (debug_view == 1u) {
        return vec4<f32>(albedo.rgb, 1.0);
    }
    if (debug_view == 2u) {
        return vec4<f32>(normal * 0.5 + vec3<f32>(0.5), 1.0);
    }
    if (debug_view == 3u) {
        return vec4<f32>(vec3<f32>(metallic), 1.0);
    }
    if (debug_view == 4u) {
        return vec4<f32>(vec3<f32>(roughness), 1.0);
    }
    if (debug_view == 5u) {
        return vec4<f32>(vec3<f32>(ao), 1.0);
    }
    if (debug_view == 6u) {
        return vec4<f32>(vec3<f32>(debug_ndotl), 1.0);
    }
    if (debug_view == 7u) {
        return vec4<f32>(vec3<f32>(ndotv), 1.0);
    }
    if (debug_view == 8u) {
        return vec4<f32>(specular_only, 1.0);
    }
    var lit_rgb = ambient + lighting + env_specular;
    if (scene.exposure_settings.y > 0.5) {
        lit_rgb *= scene.exposure_settings.x;
    }
    return vec4<f32>(applyColorGrade(lit_rgb), albedo.a);
}
