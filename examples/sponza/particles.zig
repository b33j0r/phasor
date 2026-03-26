pub fn setupLionFire(
    commands: *ecs.Commands,
    build_ctx_opt: ResOpt(render.BuildContext),
    scene_ready: HasResource(SceneReady),
    lion_fire_ready: HasResource(LionFireState),
    scene_assets: ResOpt(Assets),
) !void {
    if (!scene_ready.value) return;
    if (lion_fire_ready.value) return;

    const build_ctx = build_ctx_opt.ptr orelse return;
    const assets = scene_assets.ptr orelse return;
    if (!assets.lion_fire_shader.handle.isValid()) return;

    const fire_geometry = try render.buildParticleGeometry(build_ctx, .{ .sphere = .{
        .latitude_segments = 7,
        .longitude_segments = 12,
    } });
    var state = LionFireState{};
    state.rng_state = 0x89ab_cdef_1234_5678;
    state.mouth_position = lionMouthBasePosition();
    state.core_geometry = fire_geometry;
    state.smoke_geometry = fire_geometry;
    // Bookmark camera looked toward the lion mouth, so emit opposite that vector (outward from mouth).
    state.mouth_direction = Vec3.init(1.0, 0.0, 0.0);

    var i: usize = 0;
    while (i < max_particles) : (i += 1) {
        _ = try commands.createEntity(.{
            LionFireBillboard{ .index = @as(u16, @intCast(i)) },
            Transform{
                .translation = hidden_position,
            },
            render.MeshInstance{
                .mesh_handle = fire_geometry.mesh_handle,
                .shader_handle = assets.lion_fire_shader.handle,
                .material = render.Material.default,
                .color = common.Color.rgba(0, 0, 0, 0),
            },
            render.Layer(0){},
            render.LayerSortKey{ .value = lion_fire_layer_sort },
        });
        state.particles[i] = .{};
    }

    try commands.insertResource(state);
}

pub fn updateLionFire(
    dt: Res(SimulationDeltaTime),
    elapsed: Res(ElapsedTime),
    state_res: ResMut(LionFireState),
    cameras: Query(.{ Transform, PlayerCamera }),
    billboards: Query(.{ Transform, render.MeshInstance, LionFireBillboard }),
    current_phase: ResOpt(phases.SponzaPhases.CurrentPhase),
) void {
    const state = state_res.ptr;
    if (!phases.isPlayingPhase(current_phase.ptr)) return;

    var camera_rotation: ?Quat = null;
    var camera_position: ?Vec3 = null;
    var camera_it = cameras.iterator();
    while (camera_it.next()) |row| {
        const transform = row.get(Transform) orelse continue;
        camera_rotation = transform.rotation;
        camera_position = transform.translation;
        break;
    }
    const cam_rot = camera_rotation orelse return;
    const cam_pos = camera_position orelse return;

    _ = cam_pos;

    const step: f32 = @floatCast(std.math.clamp(dt.ptr.seconds, 0.0, 0.05));
    if (!(step > 0.0)) return;
    const t: f32 = @floatCast(elapsed.ptr.seconds);

    const emission_scale = 0.78 + 0.22 * std.math.sin(t * 4.7);
    const spawn_rate = 220.0 * emission_scale;
    state.spawn_accumulator += step * spawn_rate;
    while (state.spawn_accumulator >= 1.0) : (state.spawn_accumulator -= 1.0) {
        spawnOneParticle(state, t);
    }

    var i: usize = 0;
    while (i < max_particles) : (i += 1) {
        var p = &state.particles[i];
        if (!p.alive) continue;
        p.age += step;
        if (p.age >= p.lifetime) {
            p.alive = false;
            continue;
        }

        const drag_mul = std.math.exp(-p.drag * step);
        p.velocity = p.velocity.scale(drag_mul);
        p.velocity.y += p.buoyancy * step;

        const gust = std.math.sin(t * (4.4 + p.turbulence * 1.7) + p.noise_phase);
        const sway = std.math.cos(t * (6.3 + p.turbulence * 2.1) + p.noise_phase * 1.9);
        p.velocity.x += gust * p.turbulence * step * 0.85;
        p.velocity.z += sway * p.turbulence * step * 0.68;
        p.position = p.position.add(p.velocity.scale(step));
        p.spin += p.spin_speed * step;
    }

    var bb_it = billboards.iterator();
    while (bb_it.next()) |row| {
        const marker = row.get(LionFireBillboard) orelse continue;
        const transform = row.get(Transform) orelse continue;
        const instance = row.get(render.MeshInstance) orelse continue;
        const idx: usize = marker.index;
        if (idx >= max_particles) continue;
        const p = state.particles[idx];
        if (!p.alive) {
            transform.translation = hidden_position;
            transform.scale = .{ .x = 0.001, .y = 0.001, .z = 0.001 };
            instance.color = common.Color.rgba(0, 0, 0, 0);
            continue;
        }

        const life_t = std.math.clamp(p.age / p.lifetime, 0.0, 1.0);
        const size = p.base_size * lerp(0.70, 1.96, life_t);
        const gradient_color = sampleGradient(p.kind, life_t);
        const noise = std.math.clamp(0.5 + 0.5 * std.math.sin(p.noise_phase + t * 2.8), 0.0, 1.0);

        const geometry = particleGeometryForKind(state, p.kind);
        transform.translation = p.position;
        _ = cam_rot;
        instance.mesh_handle = geometry.mesh_handle;
        transform.rotation = worldParticleRotation(p.spin);
        transform.scale = switch (p.kind) {
            .core => .{ .x = size * 0.62, .y = size * 1.46, .z = size * 0.62 },
            .smoke => .{ .x = size * 1.36, .y = size * 0.86, .z = size * 1.36 },
        };
        instance.color = floatColorToU8(gradient_color, noise);
    }
}

fn spawnOneParticle(state: *LionFireState, time_s: f32) void {
    const idx = state.next_spawn;
    state.next_spawn = (state.next_spawn + 1) % max_particles;
    var p = &state.particles[idx];

    const core_roll = random01(state);
    const is_core = core_roll > 0.34;
    const spread: f32 = if (is_core) 0.12 else 0.22;
    const yaw = (random01(state) * 2.0 - 1.0) * spread;
    const pitch = (random01(state) * 2.0 - 1.0) * spread * 0.65;
    const dir = quatFromEuler(pitch, yaw, 0.0).rotateVec3(state.mouth_direction).normalize();

    const jitter = Vec3{
        .x = (random01(state) * 2.0 - 1.0) * 0.07,
        .y = (random01(state) * 2.0 - 1.0) * 0.05,
        .z = (random01(state) * 2.0 - 1.0) * 0.07,
    };
    const speed = if (is_core) lerp(3.1, 5.2, random01(state)) else lerp(1.5, 2.8, random01(state));
    const up_kick = if (is_core) lerp(0.8, 1.8, random01(state)) else lerp(0.6, 1.2, random01(state));

    p.alive = true;
    p.kind = if (is_core) .core else .smoke;
    p.position = state.mouth_position.add(jitter);
    p.velocity = dir.scale(speed).add(.{ .x = 0.0, .y = up_kick, .z = 0.0 });
    p.age = 0.0;
    p.lifetime = if (is_core) lerp(0.40, 0.78, random01(state)) else lerp(0.95, 1.75, random01(state));
    p.base_size = if (is_core) lerp(0.09, 0.18, random01(state)) else lerp(0.16, 0.30, random01(state));
    p.buoyancy = if (is_core) lerp(1.7, 3.1, random01(state)) else lerp(0.45, 1.25, random01(state));
    p.drag = if (is_core) lerp(1.5, 2.8, random01(state)) else lerp(0.55, 1.35, random01(state));
    p.turbulence = if (is_core) lerp(0.35, 0.75, random01(state)) else lerp(0.55, 1.05, random01(state));
    p.spin = random01(state) * (2.0 * std.math.pi);
    p.spin_speed = (random01(state) * 2.0 - 1.0) * 3.1;
    p.noise_phase = random01(state) * (2.0 * std.math.pi) + time_s * 0.7;
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

fn worldParticleRotation(spin: f32) Quat {
    return Quat.fromAxisAngle(.{ .x = 1.0, .y = 0.0, .z = 0.0 }, spin * 0.37)
        .mul(Quat.fromAxisAngle(.{ .x = 0.0, .y = 1.0, .z = 0.0 }, spin * 0.81))
        .mul(Quat.fromAxisAngle(.{ .x = 0.0, .y = 0.0, .z = 1.0 }, spin));
}

fn particleGeometryForKind(state: *const LionFireState, kind: ParticleKind) render.ResolvedParticleGeometry {
    return switch (kind) {
        .core => state.core_geometry,
        .smoke => state.smoke_geometry,
    };
}

fn sampleGradient(kind: ParticleKind, life_t: f32) common.Color.F32 {
    return switch (kind) {
        .core => FlameGradient.sample(life_t),
        .smoke => EmberGradient.sample(life_t),
    };
}

fn random01(state: *LionFireState) f32 {
    var x = state.rng_state;
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;
    state.rng_state = x;
    const bits: u32 = @truncate((x *% 0x2545F4914F6CDD1D) >> 40);
    return @as(f32, @floatFromInt(bits)) / 16777216.0;
}

fn lerp(a: f32, b: f32, t: f32) f32 {
    return a + (b - a) * std.math.clamp(t, 0.0, 1.0);
}

fn floatColorToU8(color: common.Color.F32, noise: f32) common.Color {
    const r8: u8 = @intFromFloat(std.math.clamp(color.r, 0.0, 1.0) * 255.0);
    const g8: u8 = @intFromFloat(std.math.clamp(color.g, 0.0, 1.0) * 255.0);
    const b_mix = std.math.clamp(color.b * 0.76 + noise * 0.24, 0.0, 1.0);
    const b8: u8 = @intFromFloat(b_mix * 255.0);
    const a8: u8 = @intFromFloat(std.math.clamp(color.a, 0.0, 1.0) * 255.0);
    return common.Color.rgba(r8, g8, b8, a8);
}

const max_particles: usize = 256;
const lion_fire_layer_sort: i32 = 840;
const hidden_position = Vec3{ .x = -9999.0, .y = -9999.0, .z = -9999.0 };
const LionFireBillboard = struct {
    index: u16,
};

const ParticleKind = enum { core, smoke };

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

const Particle = struct {
    alive: bool = false,
    kind: ParticleKind = .core,
    position: Vec3 = .{},
    velocity: Vec3 = .{},
    age: f32 = 0.0,
    lifetime: f32 = 1.0,
    base_size: f32 = 0.1,
    buoyancy: f32 = 1.0,
    drag: f32 = 1.0,
    turbulence: f32 = 0.6,
    spin: f32 = 0.0,
    spin_speed: f32 = 0.0,
    noise_phase: f32 = 0.0,
};

const LionFireState = struct {
    particles: [max_particles]Particle = undefined,
    next_spawn: usize = 0,
    spawn_accumulator: f32 = 0.0,
    rng_state: u64 = 0,
    mouth_position: Vec3 = .{},
    mouth_direction: Vec3 = .{ .x = 0.0, .y = 0.0, .z = -1.0 },
    core_geometry: render.ResolvedParticleGeometry = undefined,
    smoke_geometry: render.ResolvedParticleGeometry = undefined,
};

const std = @import("std");
const phasor = @import("phasor");
const phases = @import("phases.zig");
const shared = @import("shared.zig");

const common = phasor.common;
const ecs = phasor.ecs;
const modules = phasor.modules;
const render = phasor.renderer;

const Query = ecs.system_params.Query;
const Res = ecs.system_params.Res;
const ResMut = ecs.system_params.ResMut;
const ResOpt = ecs.system_params.ResOpt;

const Assets = shared.Assets;
const ElapsedTime = modules.TimeModule.ElapsedTime;
const HasResource = ecs.system_params.HasResource;
const SimulationDeltaTime = modules.TimeModule.SimulationDeltaTime;
const PlayerCamera = shared.PlayerCamera;
const Quat = common.Quat;
const SceneReady = shared.SceneReady;
const Transform = common.Transform;
const Vec3 = common.Vec3;
const quatFromEuler = shared.quatFromEuler;
