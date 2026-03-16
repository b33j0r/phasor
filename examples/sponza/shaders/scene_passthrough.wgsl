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
    environment_dominant_direction: vec4<f32>,
    environment_dominant_color: vec4<f32>,
    light_counts: vec4<u32>,
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
};

struct VertexOut {
    @builtin(position) position: vec4<f32>,
    @location(0) world_position: vec3<f32>,
    @location(1) world_normal: vec3<f32>,
    @location(2) uv: vec2<f32>,
    @location(3) color: vec4<f32>,
};

@group(0) @binding(0) var mesh_sampler: sampler;
@group(0) @binding(1) var mesh_texture: texture_2d<f32>;
@group(0) @binding(2) var<uniform> scene: SceneUniforms;

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

fn toneMapAces(color: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((color * (a * color + b)) / (color * (c * color + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@vertex
fn vs_main(input: VertexIn) -> VertexOut {
    let clip_model = mat4x4<f32>(input.clip0, input.clip1, input.clip2, input.clip3);
    let model = mat4x4<f32>(input.model0, input.model1, input.model2, input.model3);
    let clip_position = clip_model * vec4<f32>(input.position, 1.0);
    let world_position = model * vec4<f32>(input.position, 1.0);
    let world_normal = normalize((model * vec4<f32>(input.normal, 0.0)).xyz);

    var out: VertexOut;
    out.position = clip_position;
    out.world_position = world_position.xyz;
    out.world_normal = world_normal;
    out.uv = input.uv;
    out.color = input.color;
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

    var lighting = scene.ambient_color.rgb;
    lighting += evaluateIrradiance(normal) * scene.exposure_settings.z;
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
            let min_radius = max(light.spot_params.z, 0.25);
            let distance_sq = max(dot(to_light, to_light), min_radius * min_radius);
            let distance = sqrt(distance_sq);
            if (distance > light.position_range.w) {
                i += 1u;
                continue;
            }

            light_dir = to_light / distance;
            let range_ratio = distance / max(light.position_range.w, 0.001);
            let range_falloff = saturate(1.0 - pow(range_ratio, 4.0));
            attenuation = (range_falloff * range_falloff) / distance_sq;

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
        let half_dir = normalize(light_dir + view_dir);
        let specular = pow(saturate(dot(normal, half_dir)), 32.0) * 0.08;
        lighting += (ndotl + specular) * light.color_intensity.rgb * light.color_intensity.w * attenuation;
        i += 1u;
    }

    let reflection = reflect(-view_dir, normal);
    let env_alignment = saturate(dot(reflection, normalize(scene.environment_dominant_direction.xyz)));
    let env_specular = scene.environment_dominant_color.rgb * pow(env_alignment, 32.0) * scene.exposure_settings.w;
    var lit_rgb = albedo.rgb * lighting + env_specular * 0.08;
    if (scene.exposure_settings.y > 0.5) {
        lit_rgb = toneMapAces(lit_rgb * scene.exposure_settings.x);
    }
    return vec4<f32>(lit_rgb, albedo.a);
}
