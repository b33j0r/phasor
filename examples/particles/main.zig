pub const std_options = phasor.common.logging.stdOptions(.debug);

const ParticleTag = struct {
    index: u16,
};

const OrbitCamera = struct {};

const ParticleKind = enum {
    flame,
    spark,
    smoke,
};

const Particle = struct {
    kind: ParticleKind = .flame,
    alive: bool = false,
    position: Vec3 = .{},
    velocity: Vec3 = .{},
    age: f32 = 0.0,
    lifetime: f32 = 0.8,
    size: f32 = 0.24,
    stretch: f32 = 1.5,
    drag: f32 = 1.2,
    buoyancy: f32 = 1.0,
    swirl: f32 = 0.0,
    spin: f32 = 0.0,
    spin_speed: f32 = 0.0,
    noise_phase: f32 = 0.0,
};

const DemoState = struct {
    particles: [max_particles]Particle = undefined,
    next_spawn: usize = 0,
    spawn_accumulator: f32 = 0.0,
    rng_state: u64 = 0x9e37_79b9_7f4a_7c15,
    emitter_position: Vec3 = .{ .x = 0.0, .y = 0.10, .z = 0.0 },
};

const SceneAssets = struct {
    particle_mesh: render.MeshHandle = render.MeshHandle.invalid(),
    ground_mesh: render.MeshHandle = render.MeshHandle.invalid(),
    particle_shader: render.ShaderHandle = render.ShaderHandle.invalid(),
    ground_shader: render.ShaderHandle = render.ShaderHandle.invalid(),
};

const App = struct {
    pub const options = platform.Options{
        .vsync = true,
        .window = .{
            .title = "Phasor Lite - Particles",
            .width = 1400,
            .height = 900,
        },
    };

    pub fn configure(app: *ecs.App) !void {
        try platform.installDefaultModules(app);
        try app.installModule(modules.MetricsModuleLayered(render.Layer(1000)){
            .font_size = 26.0,
            .text_color = Color.WHITE,
        });

        try app.addSystemTo("Startup", setupScene);
        try app.addSystemTo("Update", updateCamera);
        try app.addSystemTo("Update", updateParticles);
    }
};

pub const main = platform.main(App);

fn setupScene(commands: *ecs.Commands, build_ctx: ResMut(render.BuildContext)) !void {
    const build = build_ctx.ptr;
    const particle_mesh = try createParticleQuad(build);
    const ground_mesh = try createGroundPlane(build);
    const particle_shader = try build.createShader(.{
        .wgsl = @embedFile("shaders/particle_fountain.wgsl"),
        .vertex_layout = .pos3_color4,
        .binding_mode = .none,
    });
    const ground_shader = try build.createShader(.{
        .wgsl = @embedFile("shaders/ground_plane.wgsl"),
        .vertex_layout = .pos3_color4,
        .binding_mode = .none,
    });

    var state = DemoState{};
    for (&state.particles) |*particle| particle.* = .{};

    try commands.insertResource(ClearColor{ .color = Color.rgb(2, 2, 4) });
    try commands.insertResource(SceneAssets{
        .particle_mesh = particle_mesh,
        .ground_mesh = ground_mesh,
        .particle_shader = particle_shader,
        .ground_shader = ground_shader,
    });
    try commands.insertResource(state);

    _ = try commands.createEntity(.{
        Transform{},
        render.MeshInstance{
            .mesh_handle = ground_mesh,
            .shader_handle = ground_shader,
            .material = render.Material.default,
            .color = Color.rgb(42, 34, 30),
        },
        render.Layer(0){},
        render.LayerSortKey{ .value = 0 },
    });

    _ = try commands.createEntity(.{
        OrbitCamera{},
        Transform{
            .translation = .{ .x = 8.2, .y = 5.4, .z = 10.8 },
            .rotation = Quat.lookAt(
                .{ .x = 8.2, .y = 5.4, .z = 10.8 },
                .{ .x = 0.0, .y = 1.65, .z = 0.0 },
                .{ .x = 0.0, .y = 1.0, .z = 0.0 },
            ),
        },
        Camera3d{ .Perspective = .{
            .fov = std.math.pi / 3.1,
            .near = 0.1,
            .far = 120.0,
        } },
        CameraLayer(0){},
    });

    _ = try commands.createEntity(.{
        Transform{},
        Camera3d{ .Viewport = .{ .mode = .TopLeft } },
        CameraLayer(1000){},
    });

    var i: usize = 0;
    while (i < max_particles) : (i += 1) {
        _ = try commands.createEntity(.{
            ParticleTag{ .index = @intCast(i) },
            Transform{
                .translation = hidden_position,
                .scale = .{ .x = 0.001, .y = 0.001, .z = 0.001 },
            },
            render.MeshInstance{
                .mesh_handle = particle_mesh,
                .shader_handle = particle_shader,
                .material = render.Material.default,
                .color = Color.rgba(0, 0, 0, 0),
            },
            render.Layer(0){},
            render.LayerSortKey{ .value = 500 },
        });
    }
}

fn updateCamera(elapsed: Res(ElapsedTime), query: Query(.{ Transform, OrbitCamera })) void {
    const t: f32 = @floatCast(elapsed.ptr.seconds);
    const radius = 11.0 + std.math.sin(t * 0.19) * 1.2;
    const angle = t * 0.22 + 0.35;
    const height = 5.0 + std.math.sin(t * 0.31) * 0.8;
    const target = Vec3{ .x = 0.0, .y = 1.85 + std.math.sin(t * 1.35) * 0.12, .z = 0.0 };

    var it = query.iterator();
    while (it.next()) |row| {
        const transform = row.get(Transform) orelse continue;
        transform.translation = .{
            .x = std.math.cos(angle) * radius,
            .y = height,
            .z = std.math.sin(angle) * radius,
        };
        transform.rotation = Quat.lookAt(transform.translation, target, .{ .x = 0.0, .y = 1.0, .z = 0.0 });
    }
}

fn updateParticles(
    dt: Res(DeltaTime),
    elapsed: Res(ElapsedTime),
    demo_state: ResMut(DemoState),
    cameras: Query(.{ Transform, OrbitCamera }),
    particle_rows: Query(.{ ParticleTag, Transform, render.MeshInstance }),
) void {
    const state = demo_state.ptr;
    const step: f32 = @floatCast(std.math.clamp(dt.ptr.seconds, 0.0, 0.05));
    if (!(step > 0.0)) return;

    var camera_rotation: ?Quat = null;
    var cam_it = cameras.iterator();
    while (cam_it.next()) |row| {
        const transform = row.get(Transform) orelse continue;
        camera_rotation = transform.rotation;
        break;
    }
    const billboard = camera_rotation orelse return;

    const t: f32 = @floatCast(elapsed.ptr.seconds);
    const pulse = 0.72 + 0.22 * std.math.sin(t * 3.2) + 0.06 * std.math.sin(t * 11.0);
    const spawn_rate = 160.0 + pulse * 120.0;
    state.spawn_accumulator += spawn_rate * step;
    while (state.spawn_accumulator >= 1.0) : (state.spawn_accumulator -= 1.0) {
        spawnParticle(state, t);
    }

    var i: usize = 0;
    while (i < max_particles) : (i += 1) {
        var particle = &state.particles[i];
        if (!particle.alive) continue;

        particle.age += step;
        if (particle.age >= particle.lifetime) {
            particle.alive = false;
            continue;
        }

        const drag_scale = std.math.exp(-particle.drag * step);
        particle.velocity = particle.velocity.scale(drag_scale);
        particle.velocity.y += particle.buoyancy * step;

        const radial = Vec3{
            .x = particle.position.x - state.emitter_position.x,
            .y = 0.0,
            .z = particle.position.z - state.emitter_position.z,
        };
        const radial_len_sq = radial.x * radial.x + radial.z * radial.z;
        if (radial_len_sq > 0.00001) {
            const inv_radial_len = 1.0 / @sqrt(radial_len_sq);
            const tangent = Vec3{
                .x = -radial.z * inv_radial_len,
                .y = 0.0,
                .z = radial.x * inv_radial_len,
            };
            particle.velocity = particle.velocity.add(tangent.scale(particle.swirl * step));
        }

        const gust = std.math.sin(t * (3.6 + particle.swirl * 0.22) + particle.noise_phase);
        const sway = std.math.cos(t * (5.4 + particle.swirl * 0.31) + particle.noise_phase * 1.7);
        particle.velocity.x += gust * step * 0.55;
        particle.velocity.z += sway * step * 0.45;
        particle.position = particle.position.add(particle.velocity.scale(step));
        particle.spin += particle.spin_speed * step;
    }

    var row_it = particle_rows.iterator();
    while (row_it.next()) |row| {
        const tag = row.get(ParticleTag) orelse continue;
        const transform = row.get(Transform) orelse continue;
        const instance = row.get(render.MeshInstance) orelse continue;
        const idx: usize = tag.index;
        if (idx >= max_particles) continue;

        const particle = state.particles[idx];
        if (!particle.alive) {
            transform.translation = hidden_position;
            transform.scale = .{ .x = 0.001, .y = 0.001, .z = 0.001 };
            instance.color = Color.rgba(0, 0, 0, 0);
            continue;
        }

        const life_t = std.math.clamp(particle.age / particle.lifetime, 0.0, 1.0);
        var alpha: f32 = 0.0;
        var size = particle.size;
        var stretch = particle.stretch;
        var tint = Vec3{ .x = 1.0, .y = 0.5, .z = 0.12 };

        switch (particle.kind) {
            .flame => {
                const flare = 0.5 + 0.5 * std.math.sin(particle.noise_phase + t * 16.0);
                alpha = std.math.clamp((1.0 - life_t) * (1.0 - life_t * 0.18) * 0.95, 0.0, 0.95);
                size *= lerp(0.85, 1.65, life_t);
                stretch *= lerp(1.15, 1.70, life_t);
                tint = mixColor(
                    .{ .x = 1.0, .y = 0.97, .z = 0.88 },
                    .{ .x = 1.0, .y = 0.44, .z = 0.08 },
                    std.math.clamp(life_t * 0.86 + flare * 0.08, 0.0, 1.0),
                );
            },
            .spark => {
                const flicker = 0.5 + 0.5 * std.math.sin(particle.noise_phase * 1.3 + t * 22.0);
                alpha = std.math.clamp((1.0 - life_t) * 0.78, 0.0, 0.78);
                size *= lerp(0.55, 0.92, life_t);
                stretch *= lerp(1.55, 2.30, life_t);
                tint = mixColor(
                    .{ .x = 0.48, .y = 0.88, .z = 1.0 },
                    .{ .x = 1.0, .y = 0.72, .z = 0.24 },
                    flicker * 0.42 + life_t * 0.24,
                );
            },
            .smoke => {
                const fade_in = std.math.clamp(life_t / 0.16, 0.0, 1.0);
                const fade_out = std.math.clamp((1.0 - life_t) / 0.8, 0.0, 1.0);
                alpha = 0.32 * fade_in * fade_out;
                size *= lerp(1.25, 2.85, life_t);
                stretch *= lerp(1.0, 1.45, life_t);
                tint = mixColor(
                    .{ .x = 0.28, .y = 0.26, .z = 0.25 },
                    .{ .x = 0.08, .y = 0.08, .z = 0.09 },
                    std.math.clamp(life_t * 0.9, 0.0, 1.0),
                );
            },
        }

        transform.translation = particle.position;
        transform.rotation = billboardRotation(billboard, particle.spin);
        transform.scale = .{ .x = size, .y = size * stretch, .z = 1.0 };
        instance.color = floatColorToU8(tint.x, tint.y, tint.z, alpha);
    }
}

fn spawnParticle(state: *DemoState, elapsed_s: f32) void {
    const idx = state.next_spawn;
    state.next_spawn = (state.next_spawn + 1) % max_particles;
    var particle = &state.particles[idx];

    const roll = rand01(state);
    const kind: ParticleKind = if (roll < 0.62)
        .flame
    else if (roll < 0.84)
        .spark
    else
        .smoke;

    const azimuth = randRange(state, 0.0, 2.0 * std.math.pi);
    const emitter_offset = Vec3{
        .x = std.math.cos(azimuth) * randRange(state, 0.0, 0.18),
        .y = randRange(state, -0.02, 0.05),
        .z = std.math.sin(azimuth) * randRange(state, 0.0, 0.18),
    };
    const radial = Vec3{
        .x = std.math.cos(azimuth),
        .y = 0.0,
        .z = std.math.sin(azimuth),
    };

    particle.alive = true;
    particle.kind = kind;
    particle.position = state.emitter_position.add(emitter_offset);
    particle.age = 0.0;
    particle.spin = randRange(state, 0.0, 2.0 * std.math.pi);
    particle.spin_speed = randRange(state, -2.8, 2.8);
    particle.noise_phase = randRange(state, 0.0, 2.0 * std.math.pi) + elapsed_s * 0.7;

    switch (kind) {
        .flame => {
            particle.velocity = radial.scale(randRange(state, 0.25, 1.0)).add(.{
                .x = 0.0,
                .y = randRange(state, 3.8, 6.4),
                .z = 0.0,
            });
            particle.lifetime = randRange(state, 0.48, 0.95);
            particle.size = randRange(state, 0.18, 0.34);
            particle.stretch = randRange(state, 1.2, 1.9);
            particle.drag = randRange(state, 1.8, 3.0);
            particle.buoyancy = randRange(state, 1.4, 2.8);
            particle.swirl = randRange(state, 2.2, 4.2);
        },
        .spark => {
            particle.velocity = radial.scale(randRange(state, 0.9, 2.2)).add(.{
                .x = 0.0,
                .y = randRange(state, 5.4, 8.2),
                .z = 0.0,
            });
            particle.lifetime = randRange(state, 0.34, 0.68);
            particle.size = randRange(state, 0.08, 0.15);
            particle.stretch = randRange(state, 1.8, 2.7);
            particle.drag = randRange(state, 2.4, 4.1);
            particle.buoyancy = randRange(state, 0.4, 1.0);
            particle.swirl = randRange(state, 3.8, 7.0);
        },
        .smoke => {
            particle.velocity = radial.scale(randRange(state, 0.15, 0.65)).add(.{
                .x = 0.0,
                .y = randRange(state, 1.3, 2.6),
                .z = 0.0,
            });
            particle.lifetime = randRange(state, 1.1, 2.2);
            particle.size = randRange(state, 0.18, 0.32);
            particle.stretch = randRange(state, 1.0, 1.35);
            particle.drag = randRange(state, 0.45, 1.0);
            particle.buoyancy = randRange(state, 0.18, 0.55);
            particle.swirl = randRange(state, 0.9, 2.0);
        },
    }
}

fn createParticleQuad(build: *const render.BuildContext) !render.MeshHandle {
    const vertices = [_]render.VertexPos3Color{
        .{ .position = .{ -0.5, -0.5, 0.0 }, .color = .{ 1.0, 1.0, 1.0, 1.0 } },
        .{ .position = .{ 0.5, -0.5, 0.0 }, .color = .{ 1.0, 1.0, 1.0, 1.0 } },
        .{ .position = .{ 0.5, 0.5, 0.0 }, .color = .{ 1.0, 1.0, 1.0, 1.0 } },
        .{ .position = .{ -0.5, 0.5, 0.0 }, .color = .{ 1.0, 1.0, 1.0, 1.0 } },
    };
    const indices = [_]u16{ 0, 1, 2, 2, 3, 0 };
    return build.addMeshPos3Color(vertices[0..], indices[0..]);
}

fn createGroundPlane(build: *const render.BuildContext) !render.MeshHandle {
    const size = 22.0;
    const vertices = [_]render.VertexPos3Color{
        .{ .position = .{ -size, 0.0, -size }, .color = .{ 0.34, 0.28, 0.26, 1.0 } },
        .{ .position = .{ size, 0.0, -size }, .color = .{ 0.30, 0.24, 0.22, 1.0 } },
        .{ .position = .{ size, 0.0, size }, .color = .{ 0.22, 0.18, 0.17, 1.0 } },
        .{ .position = .{ -size, 0.0, size }, .color = .{ 0.26, 0.22, 0.20, 1.0 } },
    };
    const indices = [_]u16{ 0, 1, 2, 2, 3, 0 };
    return build.addMeshPos3Color(vertices[0..], indices[0..]);
}

fn billboardRotation(camera_rotation: Quat, spin: f32) Quat {
    return camera_rotation.mul(Quat.fromAxisAngle(.{ .x = 0.0, .y = 0.0, .z = 1.0 }, spin));
}

fn rand01(state: *DemoState) f32 {
    state.rng_state ^= state.rng_state >> 12;
    state.rng_state ^= state.rng_state << 25;
    state.rng_state ^= state.rng_state >> 27;
    const value = state.rng_state *% 0x2545_f491_4f6c_dd1d;
    const top: u24 = @truncate(value >> 40);
    return @as(f32, @floatFromInt(top)) / 16_777_215.0;
}

fn randRange(state: *DemoState, min: f32, max: f32) f32 {
    return min + (max - min) * rand01(state);
}

fn lerp(a: f32, b: f32, t: f32) f32 {
    return a + (b - a) * t;
}

fn mixColor(a: Vec3, b: Vec3, t: f32) Vec3 {
    return .{
        .x = lerp(a.x, b.x, t),
        .y = lerp(a.y, b.y, t),
        .z = lerp(a.z, b.z, t),
    };
}

fn floatColorToU8(r: f32, g: f32, b: f32, a: f32) Color {
    return Color.rgba(
        @intFromFloat(std.math.clamp(r, 0.0, 1.0) * 255.0),
        @intFromFloat(std.math.clamp(g, 0.0, 1.0) * 255.0),
        @intFromFloat(std.math.clamp(b, 0.0, 1.0) * 255.0),
        @intFromFloat(std.math.clamp(a, 0.0, 1.0) * 255.0),
    );
}

const max_particles: usize = 480;
const hidden_position = Vec3{ .x = 0.0, .y = -2000.0, .z = 0.0 };

const std = @import("std");
const phasor = @import("phasor");

const ecs = phasor.ecs;
const modules = phasor.modules;
const render = phasor.renderer;
const common = phasor.common;
const platform = phasor.platform;

const DeltaTime = modules.TimeModule.DeltaTime;
const ElapsedTime = modules.TimeModule.ElapsedTime;
const Query = ecs.system_params.Query;
const Res = ecs.system_params.Res;
const ResMut = ecs.system_params.ResMut;

const Vec3 = common.Vec3;
const Quat = common.Quat;
const Color = common.Color;
const Transform = common.Transform;
const Camera3d = common.Camera3d;
const ClearColor = common.ClearColor;
const CameraLayer = render.CameraLayer;
