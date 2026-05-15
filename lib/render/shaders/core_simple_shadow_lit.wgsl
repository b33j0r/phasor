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

struct ShadowUniforms {
    light_view_proj: mat4x4<f32>,
    params0: vec4<f32>,
    params1: vec4<f32>,
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
    @location(0) world_pos: vec3<f32>,
    @location(1) world_normal: vec3<f32>,
    @location(2) uv: vec2<f32>,
    @location(3) color: vec4<f32>,
};

@group(0) @binding(0) var mesh_sampler: sampler;
@group(0) @binding(1) var mesh_texture: texture_2d<f32>;
@group(0) @binding(2) var<uniform> scene: SceneUniforms;
@group(0) @binding(3) var metallic_roughness_texture: texture_2d<f32>;
@group(0) @binding(4) var occlusion_texture: texture_2d<f32>;

@group(1) @binding(0) var<uniform> shadow: ShadowUniforms;
@group(1) @binding(1) var shadow_sampler: sampler_comparison;
@group(1) @binding(2) var shadow_map: texture_depth_2d;

fn saturate(v: f32) -> f32 {
    return clamp(v, 0.0, 1.0);
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
    return mat3x3<f32>(
        vec3<f32>(r0.x, r1.x, r2.x) * inv_det,
        vec3<f32>(r0.y, r1.y, r2.y) * inv_det,
        vec3<f32>(r0.z, r1.z, r2.z) * inv_det,
    );
}

fn sampleDirectionalShadow(world_pos: vec3<f32>, normal: vec3<f32>, ndotl: f32) -> f32 {
    if (shadow.params1.y < 0.5) {
        return 1.0;
    }
    let normal_offset = shadow.params0.w * (1.0 - ndotl);
    let shadow_world_pos = world_pos + normal * normal_offset;
    let clip = shadow.light_view_proj * vec4<f32>(shadow_world_pos, 1.0);
    if (clip.w <= 0.0) {
        return 1.0;
    }
    let ndc = clip.xyz / clip.w;
    let uv = vec2<f32>(ndc.x * 0.5 + 0.5, -ndc.y * 0.5 + 0.5);
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        return 1.0;
    }
    if (ndc.z < 0.0 || ndc.z > 1.0) {
        return 1.0;
    }
    let receiver_depth = clamp(ndc.z - shadow.params0.z, 0.0, 1.0);

    var visibility = 0.0;
    for (var y: i32 = -1; y <= 1; y += 1) {
        for (var x: i32 = -1; x <= 1; x += 1) {
            let offset = vec2<f32>(f32(x), f32(y)) * shadow.params0.xy;
            visibility += textureSampleCompareLevel(shadow_map, shadow_sampler, uv + offset, receiver_depth);
        }
    }
    return mix(1.0, visibility / 9.0, clamp(shadow.params1.x, 0.0, 1.0));
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

    var out: VertexOut;
    out.position = clip_model * vec4<f32>(input.position, 1.0);
    out.world_pos = (model * vec4<f32>(input.position, 1.0)).xyz;
    out.world_normal = normalize(normal_matrix * input.normal);
    out.uv = input.uv;
    out.color = input.color;
    return out;
}

@fragment
fn fs_main(input: VertexOut) -> @location(0) vec4<f32> {
    let texel = textureSample(mesh_texture, mesh_sampler, input.uv) * input.color;
    let albedo = texel.rgb;
    let n = normalize(input.world_normal);
    var l = vec3<f32>(0.0, 1.0, 0.0);
    var sun_energy = vec3<f32>(0.0);
    let light_count = min(scene.light_counts.x, 32u);
    for (var i: u32 = 0u; i < light_count; i += 1u) {
        let light = scene.lights[i];
        if (u32(light.direction_kind.w + 0.5) != 0u) {
            continue;
        }
        l = normalize(-light.direction_kind.xyz);
        sun_energy = light.color_intensity.rgb * light.color_intensity.w;
        break;
    }
    let ndotl = saturate(dot(n, l));
    let shadow_factor = sampleDirectionalShadow(input.world_pos, n, ndotl);
    let ambient = scene.ambient_color.rgb * 0.10 + vec3<f32>(0.02, 0.022, 0.024);
    let direct = sun_energy * (ndotl * 0.24) * shadow_factor;
    let lit = albedo * (ambient + direct);
    return vec4<f32>(lit, texel.a);
}
