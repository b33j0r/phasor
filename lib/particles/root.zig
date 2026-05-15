pub const std_options = @import("common").logging.moduleStdOptions();

pub const max_profiles: usize = 16;
pub const default_hidden_position = Vec3{ .x = -9999.0, .y = -9999.0, .z = -9999.0 };

pub const ParticleModuleConfig = struct {
    update_schedule: []const u8 = "Update",
    build_schedule: []const u8 = "BeforeFrame",
};

pub const ParticleSlot = struct {
    index: u32,
};

pub const ParticleSlotsBuilt = struct {};

pub const ParticleProfile = struct {
    geometry: render.ParticleGeometry = .billboard,
    resolved_geometry: render.ResolvedParticleGeometry = .{
        .mesh_handle = render.MeshHandle.invalid(),
        .facing = .billboard,
    },
    mesh_instance: render.MeshInstance = .{
        .material = render.Material{ .alpha_mode = .Blend },
    },
    base_scale: Vec3 = .{ .x = 1.0, .y = 1.0, .z = 1.0 },
    end_scale: Vec3 = .{ .x = 1.0, .y = 1.0, .z = 1.0 },
    color_gradient: ?Gradient = null,
    emissive_gradient: ?Gradient = null,
    occlusion_strength: f32 = 1.0,
    align_to_velocity: bool = false,
};

pub const ParticleSystemConfig = struct {
    capacity: usize,
    profiles: [max_profiles]ParticleProfile = @splat(.{}),
    profile_count: usize = 1,
    hidden_position: Vec3 = default_hidden_position,
    layer: i32 = 0,
    sort_key: i32 = 500,

    pub fn normalizedCapacity(self: ParticleSystemConfig, comptime max_particles: usize) usize {
        return @min(self.capacity, max_particles);
    }
};

pub const Range = struct {
    min: f32,
    max: f32,

    pub fn constant(value: f32) Range {
        return .{ .min = value, .max = value };
    }
};

pub const ParticleEmitter = struct {
    enabled: bool = true,
    profile_index: u16 = 0,
    position: Vec3 = .{},
    direction: Vec3 = .{ .x = 0.0, .y = 1.0, .z = 0.0 },
    rate: f32 = 32.0,
    accumulator: f32 = 0.0,
    burst: u16 = 0,
    radius: f32 = 0.0,
    spread_radians: f32 = 0.18,
    speed: Range = .{ .min = 1.0, .max = 2.0 },
    lifetime: Range = .{ .min = 0.75, .max = 1.25 },
    size: Range = .{ .min = 0.2, .max = 0.4 },
    stretch: Range = .{ .min = 1.0, .max = 1.0 },
    drag: Range = .{ .min = 0.0, .max = 0.0 },
    acceleration: Vec3 = .{},
    turbulence: f32 = 0.0,
    spin_speed: Range = .{ .min = -1.0, .max = 1.0 },
    rng_state: u64 = 0x9e37_79b9_7f4a_7c15,
};

pub const Particle = struct {
    alive: bool = false,
    profile_index: u16 = 0,
    position: Vec3 = .{},
    velocity: Vec3 = .{},
    acceleration: Vec3 = .{},
    age: f32 = 0.0,
    lifetime: f32 = 1.0,
    size: f32 = 1.0,
    stretch: f32 = 1.0,
    drag: f32 = 0.0,
    turbulence: f32 = 0.0,
    spin: f32 = 0.0,
    spin_speed: f32 = 0.0,
    noise_phase: f32 = 0.0,
};

pub fn ParticleState(comptime max_particles: usize) type {
    return struct {
        particles: [max_particles]Particle = @splat(.{}),
        next_spawn: usize = 0,
        slots_built: bool = false,

        const Self = @This();

        pub fn spawn(self: *Self, particle: Particle, capacity: usize) void {
            if (capacity == 0) return;
            const capped_capacity = @min(capacity, max_particles);
            self.particles[self.next_spawn] = particle;
            self.next_spawn = (self.next_spawn + 1) % capped_capacity;
        }

        pub fn clear(self: *Self) void {
            for (&self.particles) |*particle| particle.* = .{};
            self.next_spawn = 0;
            self.slots_built = false;
        }
    };
}

pub fn ParticlesModule(comptime max_particles: usize) type {
    return ParticlesModuleConfigured(max_particles, .{});
}

pub fn ParticlesModuleConfigured(comptime max_particles: usize, comptime config: ParticleModuleConfig) type {
    return struct {
        pub fn install(app: *AppCommands, commands: *Commands) !void {
            if (!commands.hasResource(ParticleState(max_particles))) {
                try commands.insertResource(ParticleState(max_particles){});
            }
            try app.addSystem(config.build_schedule, buildParticleSlots);
            try app.addSystem(config.update_schedule, emitParticles);
            try app.addSystem(config.update_schedule, simulateParticles);
            try app.addSystem(config.update_schedule, syncParticleSlots);
        }

        pub fn uninstall(app: *AppCommands) void {
            app.removeSystem(buildParticleSlots);
            app.removeSystem(emitParticles);
            app.removeSystem(simulateParticles);
            app.removeSystem(syncParticleSlots);
        }

        fn buildParticleSlots(
            commands: *Commands,
            build_ctx_opt: ResOpt(render.BuildContext),
            config_res: ResMutOpt(ParticleSystemConfig),
            state_res: ResMut(ParticleState(max_particles)),
        ) !void {
            const build_ctx = build_ctx_opt.ptr orelse return;
            const particle_config = config_res.ptr orelse return;
            const state = state_res.ptr;
            if (state.slots_built) return;

            const capacity = particle_config.normalizedCapacity(max_particles);
            if (capacity == 0) return;
            particle_config.profile_count = std.math.clamp(particle_config.profile_count, 1, max_profiles);
            for (particle_config.profiles[0..particle_config.profile_count]) |*profile| {
                profile.resolved_geometry = try render.buildParticleGeometry(build_ctx, profile.geometry);
                if (!profile.mesh_instance.mesh_handle.isValid()) {
                    profile.mesh_instance.mesh_handle = profile.resolved_geometry.mesh_handle;
                }
            }

            const first_profile = particle_config.profiles[0];
            var i: usize = 0;
            while (i < capacity) : (i += 1) {
                _ = try commands.createEntity(.{
                    ParticleSlot{ .index = @intCast(i) },
                    Transform{
                        .translation = particle_config.hidden_position,
                        .scale = .{ .x = 0.001, .y = 0.001, .z = 0.001 },
                    },
                    first_profile.mesh_instance,
                    render.Layer(0){},
                    render.LayerOverride{ .value = particle_config.layer },
                    render.LayerSortKey{ .value = particle_config.sort_key },
                });
            }
            state.slots_built = true;
        }

        fn emitParticles(
            dt: Res(TimeModule.SimulationDeltaTime),
            elapsed: Res(TimeModule.ElapsedTime),
            config_res: ResOpt(ParticleSystemConfig),
            state_res: ResMut(ParticleState(max_particles)),
            emitters: Query(.{ParticleEmitter}),
        ) void {
            const particle_config = config_res.ptr orelse return;
            const capacity = particle_config.normalizedCapacity(max_particles);
            if (capacity == 0) return;
            const step = dt.ptr.clampedSeconds32(0.05);
            if (!(step > 0.0)) return;
            const time_s = elapsed.ptr.seconds32();

            var it = emitters.iterator();
            while (it.next()) |row| {
                const emitter = row.get(ParticleEmitter) orelse continue;
                if (!emitter.enabled) continue;
                if (emitter.profile_index >= particle_config.profile_count) continue;

                var spawn_count: u32 = emitter.burst;
                emitter.burst = 0;
                emitter.accumulator += emitter.rate * step;
                while (emitter.accumulator >= 1.0) : (emitter.accumulator -= 1.0) {
                    spawn_count += 1;
                }
                var i: u32 = 0;
                while (i < spawn_count) : (i += 1) {
                    state_res.ptr.spawn(makeParticle(emitter, time_s), capacity);
                }
            }
        }

        fn simulateParticles(
            dt: Res(TimeModule.SimulationDeltaTime),
            elapsed: Res(TimeModule.ElapsedTime),
            state_res: ResMut(ParticleState(max_particles)),
        ) void {
            const step = dt.ptr.clampedSeconds32(0.05);
            if (!(step > 0.0)) return;
            const time_s = elapsed.ptr.seconds32();

            for (&state_res.ptr.particles) |*particle| {
                if (!particle.alive) continue;
                particle.age += step;
                if (particle.age >= particle.lifetime) {
                    particle.alive = false;
                    continue;
                }

                if (particle.drag > 0.0) {
                    particle.velocity = particle.velocity.scale(std.math.exp(-particle.drag * step));
                }
                particle.velocity = particle.velocity.add(particle.acceleration.scale(step));
                if (particle.turbulence > 0.0) {
                    const gust = std.math.sin(time_s * (4.7 + particle.turbulence) + particle.noise_phase);
                    const sway = std.math.cos(time_s * (6.1 + particle.turbulence * 0.7) + particle.noise_phase * 1.7);
                    particle.velocity.x += gust * particle.turbulence * step;
                    particle.velocity.z += sway * particle.turbulence * step;
                }
                particle.position = particle.position.add(particle.velocity.scale(step));
                particle.spin += particle.spin_speed * step;
            }
        }

        fn syncParticleSlots(
            config_res: ResOpt(ParticleSystemConfig),
            state_res: Res(ParticleState(max_particles)),
            cameras: Query(.{ Transform, Camera3d }),
            slots: Query(.{ ParticleSlot, Transform, render.MeshInstance }),
        ) void {
            const particle_config = config_res.ptr orelse return;
            const state = state_res.ptr;
            const camera_rotation = activeCameraRotation(cameras);

            var it = slots.iterator();
            while (it.next()) |row| {
                const slot = row.get(ParticleSlot) orelse continue;
                const transform = row.get(Transform) orelse continue;
                const instance = row.get(render.MeshInstance) orelse continue;
                if (slot.index >= max_particles) continue;

                const particle = state.particles[slot.index];
                if (!particle.alive or particle.profile_index >= particle_config.profile_count) {
                    hideSlot(transform, instance, particle_config.hidden_position);
                    continue;
                }

                const profile = particle_config.profiles[particle.profile_index];
                const life_t = std.math.clamp(particle.age / particle.lifetime, 0.0, 1.0);
                const scale_t = lerpVec3(profile.base_scale, profile.end_scale, life_t).scale(particle.size);
                const color = if (profile.color_gradient) |gradient| gradient.sampleColor(life_t) else profile.mesh_instance.color;
                const emissive = if (profile.emissive_gradient) |gradient| gradient.sample(life_t) else profile.mesh_instance.scene_material.emissive_factor;

                transform.translation = particle.position;
                transform.rotation = particleRotation(profile, particle, camera_rotation);
                transform.scale = .{
                    .x = scale_t.x,
                    .y = scale_t.y * particle.stretch,
                    .z = scale_t.z,
                };
                instance.* = profile.mesh_instance;
                instance.mesh_handle = profile.resolved_geometry.mesh_handle;
                instance.color = color;
                instance.scene_material.emissive_factor = emissive;
                instance.scene_material.occlusion_strength = profile.occlusion_strength;
            }
        }
    };
}

pub fn random01(rng_state: *u64) f32 {
    rng_state.* ^= rng_state.* >> 12;
    rng_state.* ^= rng_state.* << 25;
    rng_state.* ^= rng_state.* >> 27;
    const value = rng_state.* *% 0x2545_f491_4f6c_dd1d;
    const top: u24 = @truncate(value >> 40);
    return @as(f32, @floatFromInt(top)) / 16_777_215.0;
}

pub fn randomRange(rng_state: *u64, range: Range) f32 {
    return range.min + (range.max - range.min) * random01(rng_state);
}

fn makeParticle(emitter: *ParticleEmitter, time_s: f32) Particle {
    const direction = randomDirection(emitter);
    const speed = randomRange(&emitter.rng_state, emitter.speed);
    const radius = emitter.radius * @sqrt(random01(&emitter.rng_state));
    const angle = random01(&emitter.rng_state) * 2.0 * std.math.pi;
    const offset = Vec3{
        .x = std.math.cos(angle) * radius,
        .y = 0.0,
        .z = std.math.sin(angle) * radius,
    };
    return .{
        .alive = true,
        .profile_index = emitter.profile_index,
        .position = emitter.position.add(offset),
        .velocity = direction.scale(speed),
        .acceleration = emitter.acceleration,
        .age = 0.0,
        .lifetime = randomRange(&emitter.rng_state, emitter.lifetime),
        .size = randomRange(&emitter.rng_state, emitter.size),
        .stretch = randomRange(&emitter.rng_state, emitter.stretch),
        .drag = randomRange(&emitter.rng_state, emitter.drag),
        .turbulence = emitter.turbulence,
        .spin = random01(&emitter.rng_state) * 2.0 * std.math.pi,
        .spin_speed = randomRange(&emitter.rng_state, emitter.spin_speed),
        .noise_phase = random01(&emitter.rng_state) * 2.0 * std.math.pi + time_s * 0.7,
    };
}

fn randomDirection(emitter: *ParticleEmitter) Vec3 {
    const base = emitter.direction.normalize();
    const yaw = (random01(&emitter.rng_state) * 2.0 - 1.0) * emitter.spread_radians;
    const pitch = (random01(&emitter.rng_state) * 2.0 - 1.0) * emitter.spread_radians;
    return Quat.fromAxisAngle(.{ .x = 0.0, .y = 1.0, .z = 0.0 }, yaw)
        .mul(Quat.fromAxisAngle(.{ .x = 1.0, .y = 0.0, .z = 0.0 }, pitch))
        .rotateVec3(base)
        .normalize();
}

fn hideSlot(transform: *Transform, instance: *render.MeshInstance, hidden_position: Vec3) void {
    transform.translation = hidden_position;
    transform.scale = .{ .x = 0.001, .y = 0.001, .z = 0.001 };
    instance.color = Color.rgba(0, 0, 0, 0);
    instance.scene_material.occlusion_strength = 0.0;
    instance.scene_material.emissive_factor = .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0 };
}

fn particleRotation(profile: ParticleProfile, particle: Particle, camera_rotation: ?Quat) Quat {
    if (profile.align_to_velocity and particle.velocity.length() > 0.0001) {
        return Quat.lookAt(.{}, particle.velocity.normalize(), .{ .x = 0.0, .y = 1.0, .z = 0.0 });
    }
    return switch (profile.resolved_geometry.facing) {
        .billboard => (camera_rotation orelse Quat{}).mul(Quat.fromAxisAngle(.{ .x = 0.0, .y = 0.0, .z = 1.0 }, particle.spin)),
        .world => Quat.fromAxisAngle(.{ .x = 1.0, .y = 0.0, .z = 0.0 }, particle.spin * 0.37)
            .mul(Quat.fromAxisAngle(.{ .x = 0.0, .y = 1.0, .z = 0.0 }, particle.spin * 0.81))
            .mul(Quat.fromAxisAngle(.{ .x = 0.0, .y = 0.0, .z = 1.0 }, particle.spin)),
    };
}

fn activeCameraRotation(cameras: Query(.{ Transform, Camera3d })) ?Quat {
    var it = cameras.iterator();
    while (it.next()) |row| {
        const transform = row.get(Transform) orelse continue;
        const camera = row.get(Camera3d) orelse continue;
        switch (camera.*) {
            .Viewport => continue,
            else => return transform.rotation,
        }
    }
    return null;
}

fn lerpVec3(a: Vec3, b: Vec3, t: f32) Vec3 {
    const u = std.math.clamp(t, 0.0, 1.0);
    return .{
        .x = std.math.lerp(a.x, b.x, u),
        .y = std.math.lerp(a.y, b.y, u),
        .z = std.math.lerp(a.z, b.z, u),
    };
}

test "random01 returns normalized values" {
    var rng: u64 = 0x1234;
    var i: usize = 0;
    while (i < 32) : (i += 1) {
        const value = random01(&rng);
        try std.testing.expect(value >= 0.0);
        try std.testing.expect(value <= 1.0);
    }
}

const std = @import("std");
const common = @import("common");
const ecs = @import("ecs");
const render = @import("render");

const AppCommands = ecs.AppCommands;
const Camera3d = common.Camera3d;
const Color = common.Color;
const Commands = ecs.Commands;
const Gradient = common.Gradient;
const Quat = common.Quat;
const Query = ecs.system_params.Query;
const Res = ecs.system_params.Res;
const ResMut = ecs.system_params.ResMut;
const ResMutOpt = ecs.system_params.ResMutOpt;
const ResOpt = ecs.system_params.ResOpt;
const TimeModule = @import("modules").TimeModule;
const Transform = common.Transform;
const Vec3 = common.Vec3;
