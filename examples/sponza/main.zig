const std = @import("std");
const phasor = @import("phasor");

pub const std_options = phasor.common.logging.stdOptions(.debug);

const Player = struct {};
const PlayerCamera = struct {};
const SceneReady = struct {};
const SceneRoot = struct {};
const StatusTextTag = struct {};
const LightingReady = struct {};
const SceneSpawnPlan = struct {
    scene_size: Vec3,
};
const SceneMetrics = struct {
    scene_size: Vec3,
};
const FpsPhysics = modules.FpsPhysicsModule(Player);
const FpsController = FpsPhysics.FpsController;

const sponza_scene_path = "local/cache/sponza/source/Models/Sponza/glTF/Sponza.gltf";
const sponza_panorama_bytes = @embedFile("assets/hdr/furstenstein_2k.hdr");
const StatusOverlay = struct {
    buffer: [512]u8 = [_]u8{0} ** 512,
};

const SceneBake = struct {
    bounds: SceneBounds,
    collision_blob: []u8,
};

const SpawnChoice = struct {
    position: Vec3,
    yaw: f32,
};

const AnimatedLight = struct {
    center: Vec3,
    orbit_radius: f32 = 0.0,
    angular_speed: f32 = 0.0,
    phase: f32 = 0.0,
    base_height: f32,
    pulse_base: f32,
    pulse_amplitude: f32 = 0.0,
    pulse_speed: f32 = 0.0,
};

const SceneBounds = struct {
    min: Vec3 = .{},
    max: Vec3 = .{},
    valid: bool = false,

    fn include(self: *SceneBounds, point: Vec3) void {
        if (!self.valid) {
            self.min = point;
            self.max = point;
            self.valid = true;
            return;
        }
        self.min.x = @min(self.min.x, point.x);
        self.min.y = @min(self.min.y, point.y);
        self.min.z = @min(self.min.z, point.z);
        self.max.x = @max(self.max.x, point.x);
        self.max.y = @max(self.max.y, point.y);
        self.max.z = @max(self.max.z, point.z);
    }

    fn center(self: SceneBounds) Vec3 {
        if (!self.valid) return .{};
        return .{
            .x = (self.min.x + self.max.x) * 0.5,
            .y = (self.min.y + self.max.y) * 0.5,
            .z = (self.min.z + self.max.z) * 0.5,
        };
    }

    fn size(self: SceneBounds) Vec3 {
        if (!self.valid) return .{};
        return .{
            .x = self.max.x - self.min.x,
            .y = self.max.y - self.min.y,
            .z = self.max.z - self.min.z,
        };
    }
};

const App = struct {
    pub const options = platform.Options{
        .vsync = true,
        .window = .{
            .title = "Phasor Lite - Sponza",
            .width = 1440,
            .height = 900,
        },
    };

    pub fn configure(app: *ecs.App) !void {
        try platform.installDefaultModules(app);
        try app.installModule(modules.ParentModule);
        try app.installModule(modules.SkyModule);
        try app.installModule(modules.LightingModule);
        try app.installModule(physics.PhysicsModule{
            .config = .{
                .backend = .Jolt,
                .fixed_dt = 1.0 / 60.0,
                .max_substeps = 8,
                .gravity = .{ .x = 0.0, .y = -18.0, .z = 0.0 },
            },
        });
        try app.installModule(FpsPhysics{});
        try app.installModule(modules.AssetsModule(Assets));
        try app.installModule(modules.MetricsModuleLayered(render.Layer(1000)){
            .font_size = 28.0,
            .text_color = Color.WHITE,
        });

        try app.addSystemTo("Startup", ensureStatusOverlay);
        try app.addSystemTo("BeforeFrame", ensureStatusOverlay);
        try app.addSystemTo("Startup", setupScene);
        try app.addSystemTo("BeforeFrame", setupScene);
        try app.addSystemTo("Startup", setupLighting);
        try app.addSystemTo("BeforeFrame", setupLighting);
        try app.addSystemTo("Update", spawnPlayerFromCollision);
        try app.addSystemTo("Update", updateMouseCaptureToggle);
        try app.addSystemTo("Update", updatePlayerCamera);
        try app.addSystemTo("Update", logPlayerBookmark);
        try app.addSystemTo("Update", animateLights);
        try app.addSystemTo("Update", updateStatusOverlay);
        try app.addSystemTo("Shutdown", unloadImportedScene);
    }
};

pub const main = platform.main(App);

fn ensureStatusOverlay(commands: *ecs.Commands, existing: Query(.{StatusTextTag})) !void {
    if (!commands.hasResource(StatusOverlay)) {
        try commands.insertResource(StatusOverlay{});
    }
    var it = existing.iterator();
    if (it.next() != null) return;

    _ = try commands.createEntity(.{
        Transform{
            .translation = .{ .x = 24.0, .y = 24.0, .z = 0.0 },
        },
        render.Text{
            .content = "Sponza: preparing...",
            .font_size = 22.0,
            .color = Color.rgb(230, 232, 236),
            .horizontal_alignment = .Left,
            .vertical_alignment = .Top,
        },
        render.Layer(1000){},
        StatusTextTag{},
    });
}

fn setupScene(
    commands: *ecs.Commands,
    build_ctx: ResOpt(render.BuildContext),
    assets_ctx: ResOpt(assets.AssetsContext),
    collision_store: ResMut(physics.CollisionMeshStore),
    scene_assets: ResMut(Assets),
) !void {
    if (commands.hasResource(SceneReady)) return;

    const build_ctx_res = build_ctx.ptr orelse return;
    const assets_ctx_res = assets_ctx.ptr orelse return;
    const scene_asset = &scene_assets.ptr.sponza;
    const scene_data = scene_asset.scene_data orelse return;
    if (!scene_assets.ptr.scene_shader.handle.isValid()) return error.SceneShaderMissing;
    if (!scene_assets.ptr.sky_panorama.material_handle.isValid()) return error.SkyPanoramaMissing;
    if (!scene_assets.ptr.sky_shader.handle.isValid()) return error.SkyShaderMissing;

    const baked = try bakeSceneCollision(commands.allocator, &scene_data);
    defer commands.allocator.free(baked.collision_blob);
    try logCollisionBakeStats(commands.allocator, baked);

    const bounds = baked.bounds;
    const center = bounds.center();
    const root_translation = Vec3{
        .x = -center.x,
        .y = -bounds.min.y,
        .z = -center.z,
    };
    const scene_size = bounds.size();
    try commands.insertResource(ClearColor{ .color = Color.rgb(8, 10, 14) });
    try commands.insertResource(MouseCapture{ .enabled = true });

    const root = try commands.createEntity(.{
        Transform{
            .translation = root_translation,
        },
        SceneRoot{},
        render.Layer(0){},
    });

    _ = try commands.createEntity(.{
        Transform{
            .translation = .{
                .x = 0.0,
                .y = scene_size.y * 0.35,
                .z = 0.0,
            },
        },
        modules.SkyModule.PanoramaSky{
            .material = scene_assets.ptr.sky_panorama.material,
            .shader_handle = scene_assets.ptr.sky_shader.handle,
            .size = @max(@max(scene_size.x, scene_size.y), scene_size.z) * 4.0,
            .follow_camera = true,
            .face_segments = 56,
        },
        render.Layer(-1){},
    });

    var parsed_collision = try physics.CollisionBake.mesh_formats.parseAlloc(commands.allocator, baked.collision_blob);
    defer parsed_collision.deinit(commands.allocator);
    try instantiateCollisionBodies(commands, collision_store.ptr, parsed_collision, root_translation);

    const imported = try assets.ImportedScene.instantiate(
        commands.allocator,
        assets_ctx_res.io,
        commands,
        build_ctx_res,
        scene_asset.resolved_path,
        &scene_data,
        .{
            .parent = root,
            .shader_handle = scene_assets.ptr.scene_shader.handle,
            .mesh_layout = .Pos3NormUv,
        },
    );
    try commands.insertResource(imported);
    try commands.insertResource(SceneSpawnPlan{
        .scene_size = scene_size,
    });
    try commands.insertResource(SceneMetrics{
        .scene_size = scene_size,
    });
    try commands.insertResource(SceneReady{});

    _ = try commands.createEntity(.{
        Transform{},
        Camera3d{ .Viewport = .{ .mode = .TopLeft } },
        CameraLayer(1000){},
    });
}

fn spawnPlayerFromCollision(
    commands: *ecs.Commands,
    world: ResMut(physics.BackendWorld),
    physics_stats: Res(physics.Stats),
    spawn_plan: ResOpt(SceneSpawnPlan),
    players: Query(.{Player}),
) !void {
    if (spawn_plan.ptr == null) return;
    if (physics_stats.ptr.body_count == 0) return;
    var it = players.iterator();
    if (it.next() != null) return;

    const plan = spawn_plan.ptr.?;
    var controller = FpsController{
        .eye_offset_y = 0.6,
        .move_speed = 6.5,
        .jump_speed = 7.0,
        .pitch = -0.18,
    };
    const spawn_choice = findSpawnPoint(world.ptr, plan.scene_size, controller) orelse return;
    controller.yaw = spawn_choice.yaw;
    const spawn = spawn_choice.position;
    const body_facing = Quat.fromAxisAngle(.{ .x = 0.0, .y = 1.0, .z = 0.0 }, spawn_choice.yaw);
    const camera_facing = quatFromEuler(controller.pitch, controller.yaw, 0.0);

    std.log.debug(
        "sponza spawn: pos=({d:.2}, {d:.2}, {d:.2}) yaw={d:.2} rad",
        .{ spawn.x, spawn.y, spawn.z, spawn_choice.yaw },
    );

    _ = try commands.createEntity(.{
        Player{},
        controller,
        Transform{
            .translation = spawn,
            .rotation = body_facing,
        },
        physics.Character{},
        physics.Collider{
            .shape = .{ .Capsule = .{
                .radius = controller.radius,
                .half_height = FpsPhysics.capsuleHalfHeight(controller),
            } },
            .collision = .{
                .layer = 1,
                .mask = 1 << 0,
            },
        },
        physics.CharacterVelocity{},
        physics.CharacterState{},
    });

    _ = try commands.createEntity(.{
        PlayerCamera{},
        Transform{
            .translation = spawn.add(.{ .x = 0.0, .y = controller.eye_offset_y, .z = 0.0 }),
            .rotation = camera_facing,
        },
        Camera3d{ .Perspective = .{
            .fov = std.math.pi / 3.0,
            .near = 0.05,
            .far = 250.0,
        } },
        CameraLayer(-1){},
        CameraLayer(0){},
    });

    _ = commands.removeResource(SceneSpawnPlan);
}

fn updateMouseCaptureToggle(
    keyboard_opt: ResOpt(Keyboard),
    capture_opt: ResOpt(MouseCapture),
    commands: *ecs.Commands,
) !void {
    const keyboard = keyboard_opt.ptr orelse return;
    var capture = if (capture_opt.ptr) |existing| existing.* else MouseCapture{};

    if (keyboard.isKeyPressed(.escape)) {
        capture.enabled = false;
        try commands.insertResource(capture);
        return;
    }
    if (keyboard.isKeyPressed(.enter)) {
        capture.enabled = true;
        try commands.insertResource(capture);
    }
}

fn updatePlayerCamera(
    players: Query(.{ Transform, FpsController, Player }),
    cameras: Query(.{ Transform, PlayerCamera }),
) void {
    var player_transform: ?Transform = null;
    var player_controller: ?FpsController = null;

    var pit = players.iterator();
    while (pit.next()) |row| {
        player_transform = row.get(Transform).?.*;
        player_controller = row.get(FpsController).?.*;
        break;
    }

    if (player_transform == null or player_controller == null) return;
    const controller = player_controller.?;
    const camera_rotation = quatFromEuler(controller.pitch, controller.yaw, 0.0);

    var cit = cameras.iterator();
    while (cit.next()) |row| {
        const transform = row.get(Transform) orelse continue;
        transform.translation = player_transform.?.translation.add(.{ .x = 0.0, .y = controller.eye_offset_y, .z = 0.0 });
        transform.rotation = camera_rotation;
    }
}

fn logPlayerBookmark(
    keyboard_opt: ResOpt(Keyboard),
    players: Query(.{ Transform, FpsController, Player }),
) void {
    const keyboard = keyboard_opt.ptr orelse return;
    if (!keyboard.isKeyPressed(.m)) return;

    var it = players.iterator();
    const row = it.next() orelse return;
    const transform = row.get(Transform) orelse return;
    const controller = row.get(FpsController) orelse return;

    const camera_translation = transform.translation.add(.{ .x = 0.0, .y = controller.eye_offset_y, .z = 0.0 });

    std.log.debug(
        "sponza bookmark player_transform = Transform{{ .translation = .{{ .x = {d:.3}, .y = {d:.3}, .z = {d:.3} }}, .rotation = quatFromEuler(0.0, {d:.4}, 0.0) }}; camera_transform = Transform{{ .translation = .{{ .x = {d:.3}, .y = {d:.3}, .z = {d:.3} }}, .rotation = quatFromEuler({d:.4}, {d:.4}, 0.0) }};",
        .{
            transform.translation.x,
            transform.translation.y,
            transform.translation.z,
            controller.yaw,
            camera_translation.x,
            camera_translation.y,
            camera_translation.z,
            controller.pitch,
            controller.yaw,
        },
    );
}

fn updateStatusOverlay(
    elapsed: Res(ElapsedTime),
    capture_opt: ResOpt(MouseCapture),
    mouse_opt: ResOpt(Mouse),
    scene_assets: Res(Assets),
    scene_ready: ResOpt(SceneReady),
    spawn_plan: ResOpt(SceneSpawnPlan),
    scene_metrics: ResOpt(SceneMetrics),
    imported: ResOpt(assets.ImportedScene),
    lighting_stats: ResOpt(lighting.AuthoringStats),
    overlay: ResMut(StatusOverlay),
    texts: Query(.{ render.Text, Transform, StatusTextTag }),
) void {
    const loading_active = scene_assets.ptr.sponza.scene_data == null or scene_ready.ptr == null or spawn_plan.ptr != null;
    const phase = if (scene_assets.ptr.sponza.scene_data == null)
        "1/3 cache"
    else if (scene_ready.ptr == null)
        "2/3 setup"
    else
        "3/3 ready";
    const spinner = if (loading_active) spinnerFrame(elapsed.ptr.seconds) else ' ';
    const mouse_state = if (mouse_opt.ptr) |mouse|
        if (mouse.captured) "mouse look: on (Esc releases)"
        else if (capture_opt.ptr) |capture|
            if (capture.enabled) "mouse look: pending capture"
            else "mouse look: off (Enter captures)"
        else
            "mouse look: off (Enter captures)"
    else
        "mouse look: unavailable";

    const message = if (scene_ready.ptr == null)
        std.fmt.bufPrint(
            &overlay.ptr.buffer,
            "Sponza {c}  stage {s}\nPreparing scene and collision\n{s}",
            .{ spinner, phase, mouse_state },
        ) catch "Sponza: loading..."
    else if (spawn_plan.ptr != null)
        std.fmt.bufPrint(
            &overlay.ptr.buffer,
            "Sponza {c}  stage {s}\nProbing runtime spawn point\n{s}",
            .{ spinner, phase, mouse_state },
        ) catch "Sponza: spawning..."
    else blk: {
        const imported_scene = imported.ptr orelse break :blk "Sponza: ready";
        const scene_size = if (scene_metrics.ptr) |metrics| metrics.scene_size else imported_scene.bounds.size();
        const light_stats = if (lighting_stats.ptr) |stats| stats.* else lighting.AuthoringStats{};
        break :blk std.fmt.bufPrint(
            &overlay.ptr.buffer,
            "Sponza {c}  stage {s}\nWASD move, mouse look, Space jump\n{s}\nScene: {d} meshes  {d:.1}m x {d:.1}m x {d:.1}m\nLights: {d} total  {d} dynamic  {d} point  {d} spot",
            .{
                spinner,
                phase,
                mouse_state,
                imported_scene.mesh_handles.len,
                scene_size.x,
                scene_size.y,
                scene_size.z,
                light_stats.total_lights,
                light_stats.dynamic_lights,
                light_stats.point_lights,
                light_stats.spot_lights,
            },
        ) catch "Sponza: ready";
    };

    var it = texts.iterator();
    while (it.next()) |row| {
        const text = row.get(render.Text) orelse continue;
        const transform = row.get(Transform) orelse continue;
        transform.translation.x = 24.0;
        transform.translation.y = 24.0;
        text.content = message;
        text.font_size = 22.0;
        text.color = Color.rgb(230, 232, 236);
        text.horizontal_alignment = .Left;
        text.vertical_alignment = .Top;
    }
}

fn unloadImportedScene(commands: *ecs.Commands) void {
    _ = commands.removeResource(assets.ImportedScene);
    _ = commands.removeResource(SceneReady);
    _ = commands.removeResource(SceneSpawnPlan);
    _ = commands.removeResource(SceneMetrics);
    _ = commands.removeResource(LightingReady);
    _ = commands.removeResource(StatusOverlay);
}

fn setupLighting(
    commands: *ecs.Commands,
    scene_ready: ResOpt(SceneReady),
    scene_metrics: ResOpt(SceneMetrics),
) !void {
    if (commands.hasResource(LightingReady)) return;
    if (scene_ready.ptr == null) return;

    const scene_size = if (scene_metrics.ptr) |metrics|
        metrics.scene_size
    else
        Vec3{ .x = 40.0, .y = 20.0, .z = 40.0 };

    try commands.insertResource(lighting.AmbientLight{
        .color = .{ .r = 0.65, .g = 0.68, .b = 0.74, .a = 1.0 },
        .intensity = 0.001,
    });
    try commands.insertResource(lighting.ExposureSettings{
        .enabled = true,
        .exposure = 0.9,
    });
    try commands.insertResource(try lighting.buildEnvironmentLightFromHdrBytes(
        commands.allocator,
        sponza_panorama_bytes,
        .{
            .intensity = 0.05,
            .diffuse_strength = 0.8,
            .specular_strength = 0.18,
        },
    ));

    _ = try commands.createEntity(.{
        Transform{
            .translation = .{
                .x = 0.0,
                .y = scene_size.y * 0.65,
                .z = 0.0,
            },
            .rotation = quatFromEuler(-0.95, 0.65, 0.0),
        },
        lighting.Light{ .directional = .{
            .color = .{ .r = 1.0, .g = 0.95, .b = 0.86, .a = 1.0 },
            .illuminance_lux = 16000.0,
        } },
        lighting.LightVisibility{
            .enabled = true,
            .casts_shadows = false,
            .is_static = true,
        },
    });

    const point_positions = [_]struct {
        pos: Vec3,
        color: Color.F32,
        intensity: f32,
        range: f32,
        dynamic: bool,
    }{
        .{ .pos = .{ .x = -scene_size.x * 0.18, .y = 2.8, .z = scene_size.z * 0.18 }, .color = .{ .r = 1.0, .g = 0.42, .b = 0.28, .a = 1.0 }, .intensity = 1400.0, .range = 10.0, .dynamic = false },
        .{ .pos = .{ .x = scene_size.x * 0.18, .y = 2.8, .z = scene_size.z * 0.18 }, .color = .{ .r = 0.22, .g = 0.75, .b = 1.0, .a = 1.0 }, .intensity = 1250.0, .range = 10.5, .dynamic = false },
        .{ .pos = .{ .x = -scene_size.x * 0.2, .y = 3.2, .z = -scene_size.z * 0.16 }, .color = .{ .r = 0.82, .g = 0.34, .b = 1.0, .a = 1.0 }, .intensity = 1600.0, .range = 11.5, .dynamic = true },
        .{ .pos = .{ .x = scene_size.x * 0.2, .y = 3.2, .z = -scene_size.z * 0.16 }, .color = .{ .r = 0.24, .g = 1.0, .b = 0.66, .a = 1.0 }, .intensity = 1500.0, .range = 11.5, .dynamic = true },
        .{ .pos = .{ .x = 0.0, .y = 4.4, .z = 0.0 }, .color = .{ .r = 1.0, .g = 0.8, .b = 0.3, .a = 1.0 }, .intensity = 1900.0, .range = 13.0, .dynamic = false },
        .{ .pos = .{ .x = 0.0, .y = 2.6, .z = -scene_size.z * 0.26 }, .color = .{ .r = 0.3, .g = 0.55, .b = 1.0, .a = 1.0 }, .intensity = 1350.0, .range = 9.5, .dynamic = false },
    };

    for (point_positions, 0..) |spec, i| {
        const entity = try commands.createEntity(.{
            Transform{
                .translation = spec.pos,
            },
            lighting.Light{ .point = .{
                .color = spec.color,
                .intensity_candela = spec.intensity,
                .range = spec.range,
                .radius = 0.1,
            } },
            lighting.LightVisibility{
                .enabled = true,
                .casts_shadows = false,
                .is_static = !spec.dynamic,
            },
        });

        if (!spec.dynamic) continue;
        try commands.addComponent(entity, AnimatedLight{
            .center = spec.pos,
            .orbit_radius = 0.8 + @as(f32, @floatFromInt(i)) * 0.15,
            .angular_speed = 0.22 + @as(f32, @floatFromInt(i)) * 0.04,
            .phase = @as(f32, @floatFromInt(i)) * 0.9,
            .base_height = spec.pos.y,
            .pulse_base = spec.intensity,
            .pulse_amplitude = spec.intensity * 0.3,
            .pulse_speed = 1.2 + @as(f32, @floatFromInt(i)) * 0.15,
        });
    }

    _ = try commands.createEntity(.{
        Transform{
            .translation = .{ .x = -scene_size.x * 0.12, .y = 5.8, .z = scene_size.z * 0.04 },
            .rotation = quatFromEuler(-0.55, 0.8, 0.0),
        },
        lighting.Light{ .spot = .{
            .color = .{ .r = 1.0, .g = 0.88, .b = 0.7, .a = 1.0 },
            .intensity_candela = 2400.0,
            .range = 22.0,
            .inner_angle_rad = 0.24,
            .outer_angle_rad = 0.42,
            .radius = 0.08,
        } },
        lighting.LightVisibility{
            .enabled = true,
            .casts_shadows = false,
            .is_static = true,
        },
    });

    const moving_spot = try commands.createEntity(.{
        Transform{
            .translation = .{ .x = scene_size.x * 0.14, .y = 5.0, .z = -scene_size.z * 0.02 },
            .rotation = quatFromEuler(-0.5, -0.9, 0.0),
        },
        lighting.Light{ .spot = .{
            .color = .{ .r = 0.55, .g = 0.8, .b = 1.0, .a = 1.0 },
            .intensity_candela = 2100.0,
            .range = 20.0,
            .inner_angle_rad = 0.22,
            .outer_angle_rad = 0.38,
            .radius = 0.08,
        } },
        lighting.LightVisibility{
            .enabled = true,
            .casts_shadows = false,
            .is_static = false,
        },
    });
    try commands.addComponent(moving_spot, AnimatedLight{
        .center = .{ .x = scene_size.x * 0.14, .y = 5.0, .z = -scene_size.z * 0.02 },
        .orbit_radius = 1.2,
        .angular_speed = -0.18,
        .phase = 0.4,
        .base_height = 5.0,
        .pulse_base = 2100.0,
        .pulse_amplitude = 320.0,
        .pulse_speed = 0.9,
    });

    try commands.insertResource(LightingReady{});
}

fn animateLights(
    elapsed: Res(ElapsedTime),
    animated_lights: Query(.{ Transform, lighting.Light, AnimatedLight }),
) void {
    const t: f32 = @floatCast(elapsed.ptr.seconds);

    var it = animated_lights.iterator();
    while (it.next()) |row| {
        const transform = row.get(Transform) orelse continue;
        const light = row.get(lighting.Light) orelse continue;
        const motion = row.get(AnimatedLight) orelse continue;

        const orbit_phase = t * motion.angular_speed + motion.phase;
        transform.translation = .{
            .x = motion.center.x + std.math.cos(orbit_phase) * motion.orbit_radius,
            .y = motion.base_height + std.math.sin(orbit_phase * 0.7) * 0.35,
            .z = motion.center.z + std.math.sin(orbit_phase) * motion.orbit_radius,
        };

        const pulse = motion.pulse_base + motion.pulse_amplitude * (0.5 + 0.5 * std.math.sin(t * motion.pulse_speed + motion.phase));
        switch (light.*) {
            .point => |*point| point.intensity_candela = pulse,
            .spot => |*spot| {
                spot.intensity_candela = pulse;
                transform.rotation = quatFromEuler(-0.45, -orbit_phase - std.math.pi * 0.5, 0.0);
            },
            .directional => {},
        }
    }
}

fn findSpawnPoint(world: *physics.BackendWorld, scene_size: Vec3, controller: FpsController) ?SpawnChoice {
    const probe_filter = physics.CollisionFilter{
        .layer = 1,
        .mask = 1 << 0,
    };
    const probe_start_y = @max(scene_size.y + 8.0, 16.0);
    const max_x = @max(4.0, scene_size.x * 0.48);
    const max_z = @max(4.0, scene_size.z * 0.48);
    const step = 1.5;
    const forward_bias = @min(max_z, 3.0);

    var best: ?SpawnChoice = null;
    var best_score: f32 = -1.0;
    var z: f32 = forward_bias;

    while (z >= -max_z) : (z -= step) {
        var x: f32 = -max_x;
        while (x <= max_x) : (x += step) {
            const ray = physics.RayCast{
                .origin = .{ .x = x, .y = probe_start_y, .z = z },
                .direction = .{ .x = 0.0, .y = -1.0, .z = 0.0 },
                .max_distance = probe_start_y + 8.0,
                .collision = probe_filter,
            };
            const floor_hit = world.castRay(ray) orelse continue;
            if (@abs(floor_hit.normal.y) < 0.8) continue;

            const spawn = Vec3{
                .x = x,
                .y = floor_hit.position.y + controller.radius + FpsPhysics.capsuleHalfHeight(controller) + 0.08,
                .z = z,
            };
            if (!hasHeadroom(world, spawn, controller, probe_filter)) continue;

            const facing = chooseFacingYaw(world, spawn, controller, probe_filter);
            const score = facing.score;
                if (score > best_score) {
                    best_score = score;
                    best = .{
                        .position = spawn,
                        .yaw = facing.yaw,
                };
            }
        }
    }
    if (best) |choice| return choice;
    std.log.debug(
        "sponza spawn probe fell back: scene_size=({d:.2}, {d:.2}, {d:.2})",
        .{ scene_size.x, scene_size.y, scene_size.z },
    );
    return .{
        .position = .{
            .x = 0.0,
            .y = @max(1.4, scene_size.y * 0.08),
            .z = 0.0,
        },
        .yaw = 0.0,
    };
}

fn hasHeadroom(
    world: *physics.BackendWorld,
    spawn: Vec3,
    controller: FpsController,
    filter: physics.CollisionFilter,
) bool {
    const clearance = controller.height + 0.2;
    const hit = world.castShape(.{
        .shape = .{ .Capsule = .{
            .radius = controller.radius,
            .half_height = FpsPhysics.capsuleHalfHeight(controller),
        } },
        .start = .{
            .translation = spawn,
        },
        .translation = .{ .x = 0.0, .y = clearance, .z = 0.0 },
        .collision = filter,
    });
    return hit == null;
}

fn chooseFacingYaw(
    world: *physics.BackendWorld,
    spawn: Vec3,
    controller: FpsController,
    filter: physics.CollisionFilter,
) struct { yaw: f32, score: f32 } {
    const eye = spawn.add(.{ .x = 0.0, .y = controller.eye_offset_y, .z = 0.0 });
    const directions = [_]Vec3{
        .{ .x = 0.0, .y = 0.0, .z = -1.0 },
        .{ .x = 1.0, .y = 0.0, .z = 0.0 },
        .{ .x = 0.0, .y = 0.0, .z = 1.0 },
        .{ .x = -1.0, .y = 0.0, .z = 0.0 },
        .{ .x = 0.7071, .y = 0.0, .z = -0.7071 },
        .{ .x = -0.7071, .y = 0.0, .z = -0.7071 },
    };

    var best_yaw: f32 = std.math.pi;
    var best_score: f32 = -1.0;
    for (directions) |dir| {
        const hit = world.castRay(.{
            .origin = eye,
            .direction = dir,
            .max_distance = 24.0,
            .collision = filter,
        });
        const score = if (hit) |h|
            if (h.distance > 3.0) 100.0 - @abs(h.distance - 10.0) * 5.0 else -1.0
        else
            5.0;
        if (score > best_score) {
            best_score = score;
            best_yaw = std.math.atan2(dir.x, -dir.z);
        }
    }
    return .{ .yaw = best_yaw, .score = best_score };
}

fn bakeSceneCollision(allocator: std.mem.Allocator, scene_data: *const assets.SceneData) !SceneBake {
    var builder = physics.CollisionBake.Builder.init(allocator);
    defer builder.deinit();

    var bounds: SceneBounds = .{};
    const roots = sceneRootNodes(scene_data);
    for (roots) |root_node_index| {
        try appendNodeCollision(allocator, scene_data, root_node_index, Transform.identity(), &builder, &bounds);
    }

    return .{
        .bounds = bounds,
        .collision_blob = try builder.finish(),
    };
}

fn logCollisionBakeStats(allocator: std.mem.Allocator, baked: SceneBake) !void {
    var parsed = try physics.CollisionBake.mesh_formats.parseAlloc(allocator, baked.collision_blob);
    defer parsed.deinit(allocator);

    var max_index: u32 = 0;
    for (parsed.indices) |index| {
        max_index = @max(max_index, index);
    }

    std.log.debug(
        "sponza collision bake: meshes={} vertices={} indices={} max_index={} bounds=({d:.2}, {d:.2}, {d:.2})",
        .{
            parsed.meshes.len,
            parsed.vertices.len,
            parsed.indices.len,
            max_index,
            baked.bounds.size().x,
            baked.bounds.size().y,
            baked.bounds.size().z,
        },
    );

    if (parsed.vertices.len == 0 or parsed.indices.len < 3) return error.InvalidCollisionBake;
    if (max_index >= parsed.vertices.len) return error.InvalidCollisionBake;
    try validateCollisionMeshes(parsed);
}

fn validateCollisionMeshes(parsed: physics.CollisionBake.File) !void {
    for (parsed.meshes, 0..) |mesh, mesh_index| {
        if (mesh.index_count == 0) continue;

        const vertex_start: u32 = mesh.first_vertex;
        const vertex_end: u32 = mesh.first_vertex + mesh.vertex_count;
        var local_min: u32 = std.math.maxInt(u32);
        var local_max: u32 = 0;

        for (parsed.indices[mesh.first_index .. mesh.first_index + mesh.index_count]) |index| {
            local_min = @min(local_min, index);
            local_max = @max(local_max, index);
            if (index < vertex_start or index >= vertex_end) {
                std.log.warn(
                    "sponza collision mesh {} invalid range: vertex_range=[{}, {}) bad_index={} local_min={} local_max={}",
                    .{ mesh_index, vertex_start, vertex_end, index, local_min, local_max },
                );
                return error.InvalidCollisionBake;
            }
        }
    }
}

fn instantiateCollisionBodies(
    commands: *ecs.Commands,
    collision_store: *physics.CollisionMeshStore,
    parsed: physics.CollisionBake.File,
    translation: Vec3,
) !void {
    for (parsed.meshes) |mesh| {
        if (mesh.index_count < 3 or mesh.vertex_count == 0) continue;
        const handle = try addCollisionSubmesh(commands.allocator, collision_store, parsed, mesh);
        _ = try commands.createEntity(.{
            Transform{
                .translation = translation,
            },
            physics.Body{ .kind = .Static },
            physics.Collider{
                .shape = .{ .TriangleMesh = handle },
                .material = .{ .friction = 0.85, .restitution = 0.0 },
                .collision = .{
                    .layer = mesh.layer,
                    .mask = mesh.mask,
                },
            },
        });
    }
}

fn addCollisionSubmesh(
    allocator: std.mem.Allocator,
    collision_store: *physics.CollisionMeshStore,
    parsed: physics.CollisionBake.File,
    mesh: physics.CollisionBake.Mesh,
) !physics.CollisionMeshHandle {
    var builder = physics.CollisionBake.Builder.init(allocator);
    defer builder.deinit();

    const vertex_start: usize = mesh.first_vertex;
    const vertex_end: usize = mesh.first_vertex + mesh.vertex_count;
    const index_start: usize = mesh.first_index;
    const index_end: usize = mesh.first_index + mesh.index_count;

    var positions = try allocator.alloc(Vec3, mesh.vertex_count);
    defer allocator.free(positions);
    for (parsed.vertices[vertex_start..vertex_end], 0..) |vertex, i| {
        positions[i] = vertex.position;
    }

    var indices = try allocator.alloc(u32, mesh.index_count);
    defer allocator.free(indices);
    for (parsed.indices[index_start..index_end], 0..) |index, i| {
        indices[i] = index - mesh.first_vertex;
    }

    try builder.addTriangleSoup(positions, indices, .{
        .layer = mesh.layer,
        .mask = mesh.mask,
    });
    const bytes = try builder.finish();
    defer allocator.free(bytes);
    return collision_store.add(.{
        .bytes = bytes,
        .format = .PhysicsMeshV1,
    });
}

fn sceneRootNodes(scene_data: *const assets.SceneData) []const u32 {
    if (scene_data.default_scene) |scene_index| {
        if (scene_index < scene_data.scenes.len) {
            return scene_data.scenes[scene_index].root_nodes;
        }
    }
    if (scene_data.scenes.len > 0) return scene_data.scenes[0].root_nodes;
    return &.{};
}

fn appendNodeCollision(
    allocator: std.mem.Allocator,
    scene_data: *const assets.SceneData,
    node_index: u32,
    parent_transform: Transform,
    builder: *physics.CollisionBake.Builder,
    bounds: *SceneBounds,
) !void {
    if (node_index >= scene_data.nodes.len) return;
    const node = scene_data.nodes[node_index];
    const world_transform = combineTransform(parent_transform, localToWorld(node.local_transform));

    if (node.mesh_index) |mesh_index| {
        if (mesh_index < scene_data.meshes.len) {
            const mesh = scene_data.meshes[mesh_index];
            for (mesh.primitives) |primitive| {
                try appendPrimitiveCollision(allocator, scene_data, primitive, world_transform, builder, bounds);
            }
        }
    }

    for (node.children) |child_index| {
        try appendNodeCollision(allocator, scene_data, child_index, world_transform, builder, bounds);
    }
}

fn appendPrimitiveCollision(
    allocator: std.mem.Allocator,
    scene_data: *const assets.SceneData,
    primitive: assets.scene.PrimitiveData,
    world_transform: Transform,
    builder: *physics.CollisionBake.Builder,
    bounds: *SceneBounds,
) !void {
    if (primitive.topology != .Triangles) return;
    if (primitive.material_index) |material_index| {
        if (material_index < scene_data.materials.len) {
            const material = scene_data.materials[material_index];
            if (material.alpha_mode != .Opaque or material.double_sided) return;
        }
    }
    const position_accessor = primitive.position_accessor orelse return;
    if (position_accessor.element_type != .Vec3 or position_accessor.component_type != 5126) return;

    const position_meta = scene_data.accessors[position_accessor.accessor_index];
    const position_bytes = scene_data.accessorByteSlice(position_accessor.accessor_index) orelse return;
    const vertex_count = position_accessor.count;

    var positions = try allocator.alloc(Vec3, vertex_count);
    defer allocator.free(positions);
    for (0..vertex_count) |i| {
        const local = readVec3(position_bytes, positionMetaStride(position_meta), i);
        const world = transformPoint(world_transform, local);
        positions[i] = world;
        bounds.include(world);
    }

    const indices = try buildTriangleIndicesU32(allocator, scene_data, primitive.indices_accessor, vertex_count);
    defer allocator.free(indices);
    for (0..(indices.len / 3)) |tri| {
        const i = tri * 3;
        std.mem.swap(u32, &indices[i + 1], &indices[i + 2]);
    }

    try builder.addTriangleSoup(positions, indices, .{
        .layer = 0,
        .mask = 0xffff_ffff,
    });
}

fn buildTriangleIndicesU32(
    allocator: std.mem.Allocator,
    scene_data: *const assets.SceneData,
    indices_accessor: ?assets.scene.AccessorRef,
    vertex_count: usize,
) ![]u32 {
    if (indices_accessor) |accessor| {
        const meta = scene_data.accessors[accessor.accessor_index];
        const bytes = scene_data.accessorByteSlice(accessor.accessor_index) orelse return error.MissingIndexBytes;
        const stride = positionMetaStride(meta);
        var out = try allocator.alloc(u32, accessor.count);
        for (0..accessor.count) |i| {
            out[i] = switch (meta.component_type) {
                5121 => readU8(bytes, stride, i),
                5123 => readU16(bytes, stride, i),
                5125 => readU32(bytes, stride, i),
                else => return error.UnsupportedIndexAccessor,
            };
        }
        return out;
    }

    const out = try allocator.alloc(u32, vertex_count);
    for (out, 0..) |*dst, i| dst.* = @intCast(i);
    return out;
}

fn localToWorld(local: common.LocalTransform) Transform {
    return .{
        .translation = local.translation,
        .rotation = local.rotation,
        .scale = local.scale,
    };
}

fn combineTransform(parent: Transform, local: Transform) Transform {
    const scaled_translation = mulVec3Components(local.translation, parent.scale);
    return .{
        .translation = parent.translation.add(parent.rotation.rotateVec3(scaled_translation)),
        .rotation = parent.rotation.mul(local.rotation).normalize(),
        .scale = mulVec3Components(parent.scale, local.scale),
    };
}

fn transformPoint(transform: Transform, point: Vec3) Vec3 {
    return transform.translation.add(transform.rotation.rotateVec3(mulVec3Components(point, transform.scale)));
}

fn mulVec3Components(a: Vec3, b: Vec3) Vec3 {
    return .{
        .x = a.x * b.x,
        .y = a.y * b.y,
        .z = a.z * b.z,
    };
}

fn positionMetaStride(meta: assets.scene.AccessorData) usize {
    return if (meta.byte_stride != 0) meta.byte_stride else switch (meta.element_type) {
        .Scalar => switch (meta.component_type) {
            5121 => 1,
            5123 => 2,
            5125, 5126 => 4,
            else => 0,
        },
        .Vec2 => 8,
        .Vec3 => 12,
        .Vec4 => 16,
        .Mat2 => 16,
        .Mat3 => 36,
        .Mat4 => 64,
    };
}

fn readVec3(bytes: []const u8, stride: usize, index: usize) Vec3 {
    const base = index * stride;
    return .{
        .x = readF32(bytes, base + 0),
        .y = readF32(bytes, base + 4),
        .z = readF32(bytes, base + 8),
    };
}

fn readF32(bytes: []const u8, offset: usize) f32 {
    return @bitCast(std.mem.readInt(u32, bytes[offset .. offset + 4][0..4], .little));
}

fn readU8(bytes: []const u8, stride: usize, index: usize) u32 {
    return bytes[index * stride];
}

fn readU16(bytes: []const u8, stride: usize, index: usize) u32 {
    const base = index * stride;
    return std.mem.readInt(u16, bytes[base .. base + 2][0..2], .little);
}

fn readU32(bytes: []const u8, stride: usize, index: usize) u32 {
    const base = index * stride;
    return std.mem.readInt(u32, bytes[base .. base + 4][0..4], .little);
}

fn quatFromEuler(pitch: f32, yaw: f32, roll: f32) Quat {
    const qx = Quat.fromAxisAngle(.{ .x = 1.0, .y = 0.0, .z = 0.0 }, pitch);
    const qy = Quat.fromAxisAngle(.{ .x = 0.0, .y = 1.0, .z = 0.0 }, yaw);
    const qz = Quat.fromAxisAngle(.{ .x = 0.0, .y = 0.0, .z = 1.0 }, roll);
    return qy.mul(qx).mul(qz).normalize();
}

fn spinnerFrame(seconds: f64) u8 {
    const frames = [_]u8{ '|', '/', '-', '\\' };
    const frame_index = @as(usize, @intFromFloat(@floor(seconds * 4.0)));
    return frames[frame_index % frames.len];
}


const Assets = struct {
    sponza: assets.Scene = .file(sponza_scene_path),
    sky_panorama: assets.Texture = assets.Texture.embedded(sponza_panorama_bytes).asHdr().asOpaque().equirectangularLinear(),
    scene_shader: assets.Shader = .{
        .wgsl_source = @embedFile("shaders/scene_passthrough.wgsl"),
        .vertex_layout = .pos3_norm_uv2,
        .binding_mode = .material_scene,
    },
    sky_shader: assets.Shader = .{
        .wgsl_source = @embedFile("shaders/sky_panorama_hdr.wgsl"),
        .vertex_layout = .pos3_uv2,
        .binding_mode = .material_scene,
    },
};

const ecs = phasor.ecs;
const assets = phasor.assets;
const common = phasor.common;
const lighting = phasor.lighting;
const modules = phasor.modules;
const physics = phasor.physics;
const platform = phasor.platform;
const render = phasor.renderer;

const Query = ecs.system_params.Query;
const Res = ecs.system_params.Res;
const ResMut = ecs.system_params.ResMut;
const ResOpt = ecs.system_params.ResOpt;

const Keyboard = modules.InputModule.Keyboard;
const MouseCapture = modules.InputModule.MouseCapture;
const Mouse = modules.InputModule.Mouse;
const ElapsedTime = modules.TimeModule.ElapsedTime;

const Camera3d = common.Camera3d;
const CameraLayer = render.CameraLayer;
const ClearColor = common.ClearColor;
const Color = common.Color;
const Quat = common.Quat;
const Transform = common.Transform;
const Vec3 = common.Vec3;
