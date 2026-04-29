pub fn setupLionFire(
    commands: *ecs.Commands,
    scene_ready: HasResource(SceneReady),
    lion_fire_ready: HasResource(LionFireState),
    scene_assets: ResOpt(Assets),
) !void {
    if (!scene_ready.value) return;
    if (lion_fire_ready.value) return;

    const assets = scene_assets.ptr orelse return;
    if (!assets.lion_fire_shader.handle.isValid()) return;

    try commands.insertResource(particle_lib.ParticleSystemConfig{
        .capacity = max_particles,
        .profiles = lionFireProfiles(assets.lion_fire_shader.handle),
        .profile_count = 2,
        .hidden_position = hidden_position,
        .layer = 0,
        .sort_key = lion_fire_layer_sort,
    });
    try commands.insertResource(LionFireState{});

    inline for (lion_emitter_specs, 0..) |spec, i| {
        _ = try commands.createEntity(.{
            LionFireEmitter{ .index = @intCast(i) },
            particle_lib.ParticleEmitter{
                .enabled = false,
                .profile_index = 0,
                .position = spec.mouth_position,
                .direction = spec.mouth_direction.normalize(),
                .rate = 170.0 * spec.emission_scale,
                .radius = 0.07,
                .spread_radians = 0.13,
                .speed = .{ .min = 3.1, .max = 5.2 },
                .lifetime = .{ .min = 0.40, .max = 0.78 },
                .size = .{ .min = 0.09, .max = 0.18 },
                .stretch = .{ .min = 1.20, .max = 1.55 },
                .drag = .{ .min = 1.5, .max = 2.8 },
                .acceleration = .{ .x = 0.0, .y = 2.2, .z = 0.0 },
                .turbulence = 0.55,
                .spin_speed = .{ .min = -3.1, .max = 3.1 },
                .rng_state = 0x1000_0000 + @as(u64, i) * 0x9e37_79b9,
            },
        });
        _ = try commands.createEntity(.{
            LionFireEmitter{ .index = @intCast(i) },
            particle_lib.ParticleEmitter{
                .enabled = false,
                .profile_index = 1,
                .position = spec.mouth_position,
                .direction = spec.mouth_direction.normalize(),
                .rate = 58.0 * spec.emission_scale,
                .radius = 0.10,
                .spread_radians = 0.23,
                .speed = .{ .min = 1.5, .max = 2.8 },
                .lifetime = .{ .min = 0.95, .max = 1.75 },
                .size = .{ .min = 0.16, .max = 0.30 },
                .stretch = .{ .min = 0.78, .max = 0.95 },
                .drag = .{ .min = 0.55, .max = 1.35 },
                .acceleration = .{ .x = 0.0, .y = 0.85, .z = 0.0 },
                .turbulence = 0.80,
                .spin_speed = .{ .min = -2.1, .max = 2.1 },
                .rng_state = 0x2000_0000 + @as(u64, i) * 0x85eb_ca6b,
            },
        });
    }
}

pub fn updateLionFire(
    elapsed: Res(ElapsedTime),
    emitters: Query(.{ LionFireEmitter, particle_lib.ParticleEmitter }),
    current_phase: Res(phases.SponzaPhases.CurrentPhase),
) void {
    const playing = phases.isPlayingPhase(current_phase.ptr);
    const t: f32 = @floatCast(elapsed.ptr.seconds);
    const emission_scale = 0.78 + 0.22 * std.math.sin(t * 4.7);
    var it = emitters.iterator();
    while (it.next()) |row| {
        const marker = row.get(LionFireEmitter) orelse continue;
        const emitter = row.get(particle_lib.ParticleEmitter) orelse continue;
        const spec = lion_emitter_specs[marker.index];
        const base_rate: f32 = if (emitter.profile_index == 0) 170.0 else 58.0;
        emitter.enabled = playing;
        emitter.position = spec.mouth_position;
        emitter.direction = spec.mouth_direction.normalize();
        emitter.rate = base_rate * emission_scale * spec.emission_scale;
    }
}

fn lionFireProfiles(shader: render.ShaderHandle) [particle_lib.max_profiles]particle_lib.ParticleProfile {
    var profiles = [_]particle_lib.ParticleProfile{.{}} ** particle_lib.max_profiles;
    profiles[0] = .{
        .geometry = .{ .ellipsoid = .{ .latitude_segments = 7, .longitude_segments = 12 } },
        .mesh_instance = lionFireMesh(shader, common.Color.rgba(255, 176, 48, 230)),
        .base_scale = .{ .x = 0.62, .y = 1.02, .z = 0.62 },
        .end_scale = .{ .x = 1.22, .y = 2.86, .z = 1.22 },
        .color_gradient = FlameGradient,
        .emissive_gradient = FlameBrightnessGradient,
        .occlusion_strength = 5.0,
    };
    profiles[1] = .{
        .geometry = .{ .sphere = .{ .latitude_segments = 7, .longitude_segments = 12 } },
        .mesh_instance = lionFireMesh(shader, common.Color.rgba(130, 44, 24, 72)),
        .base_scale = .{ .x = 1.36, .y = 0.78, .z = 1.36 },
        .end_scale = .{ .x = 2.66, .y = 1.68, .z = 2.66 },
        .color_gradient = EmberGradient,
        .emissive_gradient = EmberBrightnessGradient,
        .occlusion_strength = 0.7,
    };
    return profiles;
}

fn lionFireMesh(shader: render.ShaderHandle, color: common.Color) render.MeshInstance {
    return .{
        .shader_handle = shader,
        .material = render.Material.default,
        .color = color,
        .scene_material = .{
            .emissive_factor = .{ .r = 1.0, .g = 0.5, .b = 0.2, .a = 1.0 },
            .occlusion_strength = 1.0,
        },
    };
}

fn lionMouthBasePosition() Vec3 {
    const camera = Vec3{ .x = -9.967, .y = 2.492, .z = 0.0 };
    const rot = lionMouthBaseRotation();
    const forward = rot.rotateVec3(.{ .x = 0.0, .y = 0.0, .z = -1.0 }).normalize();
    const right = rot.rotateVec3(.{ .x = 1.0, .y = 0.0, .z = 0.0 }).normalize();
    const up = rot.rotateVec3(.{ .x = 0.0, .y = 1.0, .z = 0.0 }).normalize();
    // World-space lion mouth anchor derived from provided close-up bookmark.
    return camera
        .add(forward.scale(0.52))
        .add(right.scale(-0.07))
        .add(up.scale(-0.18));
}

fn lionMouthBaseRotation() Quat {
    return quatFromEuler(-0.2090, 7.7481, 0.0);
}

const max_particles_per_emitter: usize = 256;
pub const max_lion_fire_particles: usize = max_particles_per_emitter * lion_emitter_specs.len;
const max_particles: usize = max_lion_fire_particles;
const lion_fire_layer_sort: i32 = 840;
const hidden_position = Vec3{ .x = -9999.0, .y = -9999.0, .z = -9999.0 };
const LionFireEmitter = struct {
    index: u16,
};

const LionFireEmitterSpec = struct {
    mouth_position: Vec3,
    mouth_direction: Vec3,
    emission_scale: f32 = 1.0,
};

const lion_emitter_specs = [_]LionFireEmitterSpec{
    .{
        .mouth_position = lionMouthBasePosition(),
        .mouth_direction = Vec3.init(1.0, 0.0, 0.0),
        .emission_scale = 1.0,
    },
    .{
        .mouth_position = lionOppositeMouthPosition(),
        .mouth_direction = Vec3.init(-1.0, 0.0, 0.0),
        .emission_scale = 0.96,
    },
};

const FlameGradient = common.Gradient.initComptime(.{
    .stops = .{
        .{ .at = 0.0, .color = common.Color.rgba(255, 249, 238, 245) },
        .{ .at = 0.12, .color = common.Color.rgba(255, 222, 150, 235) },
        .{ .at = 0.34, .color = common.Color.rgba(255, 156, 52, 218) },
        .{ .at = 0.68, .color = common.Color.rgba(255, 66, 18, 132) },
        .{ .at = 1.0, .color = common.Color.rgba(34, 6, 2, 0) },
    },
});

const EmberGradient = common.Gradient.initComptime(.{
    .stops = .{
        .{ .at = 0.0, .color = common.Color.rgba(255, 173, 84, 82) },
        .{ .at = 0.22, .color = common.Color.rgba(196, 72, 26, 72) },
        .{ .at = 0.64, .color = common.Color.rgba(78, 22, 18, 34) },
        .{ .at = 1.0, .color = common.Color.rgba(10, 8, 12, 0) },
    },
});

const FlameBrightnessGradient = common.Gradient.initComptime(.{
    .stops = .{
        .{ .at = 0.0, .color = common.Color.F32{ .r = 8.0, .g = 8.0, .b = 8.0, .a = 1.0 } },
        .{ .at = 0.14, .color = common.Color.F32{ .r = 6.4, .g = 6.4, .b = 6.4, .a = 1.0 } },
        .{ .at = 0.42, .color = common.Color.F32{ .r = 3.2, .g = 3.2, .b = 3.2, .a = 1.0 } },
        .{ .at = 1.0, .color = common.Color.F32{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0 } },
    },
});

const EmberBrightnessGradient = common.Gradient.initComptime(.{
    .stops = .{
        .{ .at = 0.0, .color = common.Color.F32{ .r = 1.2, .g = 1.2, .b = 1.2, .a = 1.0 } },
        .{ .at = 0.32, .color = common.Color.F32{ .r = 0.55, .g = 0.55, .b = 0.55, .a = 1.0 } },
        .{ .at = 1.0, .color = common.Color.F32{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0 } },
    },
});

const LionFireState = struct {};

fn lionOppositeMouthPosition() Vec3 {
    const base = lionMouthBasePosition();
    return .{ .x = -base.x, .y = base.y, .z = base.z };
}

const std = @import("std");
const phasor = @import("phasor");
const phases = @import("phases.zig");
const shared = @import("shared.zig");

const common = phasor.common;
const ecs = phasor.ecs;
const modules = phasor.modules;
const particle_lib = phasor.particles;
const render = phasor.renderer;

const Query = ecs.system_params.Query;
const Res = ecs.system_params.Res;
const ResOpt = ecs.system_params.ResOpt;

const Assets = shared.Assets;
const ElapsedTime = modules.TimeModule.ElapsedTime;
const HasResource = ecs.system_params.HasResource;
const Quat = common.Quat;
const SceneReady = shared.SceneReady;
const Vec3 = common.Vec3;
const quatFromEuler = shared.quatFromEuler;
