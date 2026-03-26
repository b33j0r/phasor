pub const std_options = phasor.common.logging.stdOptions(.debug);

const Player = struct {};
const PlayerCamera = struct {};
const SunLight = struct {};

const FpsPhysics = modules.FpsPhysicsModule(Player);
const FpsController = FpsPhysics.FpsController;

const DayNightCycle = struct {
    start_hour: f32 = 17.0,
    day_length_seconds: f32 = 24.0,
    latitude_deg: f32 = 42.0,
    cloud_coverage: f32 = 0.32,
    cloud_density: f32 = 0.56,
    haze: f32 = 0.18,
    wind_speed: f32 = 0.9,
    weather_cycle_seconds: f32 = 80.0,
};

const DayNightState = struct {
    sun: Vec3,
    shadow_sun: Vec3,
    daylight: f32,
    night: f32,
    twilight: f32,
    light_color: Color.F32,
    illuminance_lux: f32,
    ambient_color: Color.F32,
    ambient_intensity: f32,
    environment_color: Color.F32,
    environment_intensity: f32,
    environment_diffuse_strength: f32,
    environment_specular_strength: f32,
    environment_average_luminance: f32,
    exposure_auto_key_value: f32,
    exposure_min: f32,
    exposure_max: f32,
};

const App = struct {
    pub const options = platform.Options{
        .vsync = true,
        .window = .{
            .title = "Phasor Lite - Shadows",
            .width = 1440,
            .height = 900,
        },
    };

    pub fn configure(app: *ecs.App) !void {
        try app.installModule(modules.SkyModule);
        try app.addSystemTo("BeforeFrame", updateDayNightCycle);
        try app.addSystemTo("BeforeFrame", updateProceduralSkyMeshParams);

        try platform.installDefaultModules(app);
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
        try app.installModule(modules.FpsKeyBindingModule{});
        try app.installModule(modules.AssetsModule(Assets));
        try app.installModule(modules.MetricsModuleLayered(render.Layer(1000)){
            .font_size = 24.0,
            .text_color = Color.WHITE,
            .extra_builtin_lines = &.{
                modules.builtinLine(.mouse_look),
                modules.builtinLine(.scene_stats),
                modules.builtinLine(.light_stats),
            },
        });

        try app.addSystemTo("Startup", setupScene);
        try app.addSystemTo("Update", updateMouseCaptureToggle);
        try app.addSystemTo("Update", updatePlayerCamera);
    }
};

pub const main = platform.main(App);

fn setupScene(
    commands: *ecs.Commands,
    build_ctx: ResMut(render.BuildContext),
    assets_res: ResMut(Assets),
    core_shaders: ResMut(render.CoreShaders),
) !void {
    const build = build_ctx.deref();
    const scene_assets = assets_res.deref();
    try build_ctx.ptr.ensureCoreSimpleShadowLitShader(&core_shaders.ptr.simple_shadow_lit);
    try build_ctx.ptr.ensureCoreSkyProceduralAtmosphericShader(&core_shaders.ptr.sky_procedural_atmospheric);
    const player_spawn = Vec3{ .x = 9.0, .y = 0.9, .z = 14.5 };
    const pillar_center = Vec3{ .x = 0.0, .y = 4.0, .z = 0.0 };
    var player_controller = FpsController{
        .fly_toggle_enabled = true,
        .fly_speed_multiplier = 1.0,
    };
    const camera_spawn = player_spawn.add(FpsPhysics.cameraOffset(player_controller));
    const look_angles = Quat.yawPitchFromForward(pillar_center.sub(camera_spawn));
    player_controller.yaw = look_angles.yaw;
    player_controller.pitch = look_angles.pitch;
    const look_rotation = Quat.lookAt(camera_spawn, pillar_center, .{ .x = 0.0, .y = 1.0, .z = 0.0 });

    if (!scene_assets.floor_tex.material_handle.isValid()) return error.FloorTextureMissing;
    if (!scene_assets.pillar_tex.material_handle.isValid()) return error.PillarTextureMissing;
    if (!scene_assets.sky_moon_overlay.material_handle.isValid()) return error.SkyTextureMissing;
    if (!core_shaders.ptr.simple_shadow_lit.isValid()) return error.CoreShadowShaderMissing;
    if (!core_shaders.ptr.sky_procedural_atmospheric.isValid()) return error.CoreSkyShaderMissing;

    const cycle = DayNightCycle{};
    const initial_state = evaluateDayNightState(&cycle, 0.0);

    try commands.insertResource(cycle);
    try commands.insertResource(render.SceneStatsMode{ .enabled = true });
    try modules.TimeModule.setPaused(commands, false);
    try commands.insertResource(ClearColor{ .color = Color.rgb(145, 190, 235) });
    try commands.insertResource(MouseCapture{ .enabled = true });
    try commands.insertResource(lighting.AmbientLight{
        .color = initial_state.ambient_color,
        .intensity = initial_state.ambient_intensity,
    });
    try commands.insertResource(lighting.ExposureSettings{
        .enabled = true,
        .auto_enabled = true,
        .exposure = 0.22,
        .auto_key_value = initial_state.exposure_auto_key_value,
        .min_exposure = initial_state.exposure_min,
        .max_exposure = initial_state.exposure_max,
    });
    try commands.insertResource(lighting.EnvironmentLight{
        .enabled = true,
        .intensity = initial_state.environment_intensity,
        .diffuse_strength = initial_state.environment_diffuse_strength,
        .specular_strength = initial_state.environment_specular_strength,
        .average_luminance = initial_state.environment_average_luminance,
        .dominant_direction = initial_state.sun,
        .dominant_color = initial_state.environment_color,
    });
    try commands.insertResource(modules.RenderModule.ShadowSettings{
        .technique = .directional_shadow_map,
        .map_resolution = 2048,
        .strength = 1.0,
        .depth_bias = 0.00010,
        .normal_bias = 0.00120,
        .max_distance = 52.0,
        .frustum_padding = 6.0,
        .depth_padding = 40.0,
        .caster_range = 18.0,
        .stabilize = true,
    });

    _ = try commands.createEntity(.{
        Transform{
            .translation = .{ .x = 0.0, .y = 18.0, .z = 0.0 },
            .rotation = quatFromTo(.{ .x = 0.0, .y = 0.0, .z = -1.0 }, initial_state.shadow_sun.scale(-1.0).normalize()),
        },
        SunLight{},
        lighting.Light{ .directional = .{
            .color = initial_state.light_color,
            .illuminance_lux = initial_state.illuminance_lux,
        } },
        lighting.LightVisibility{
            .enabled = true,
            .casts_shadows = true,
            .is_static = false,
        },
    });

    const plane_mesh = try createPlaneMesh(build, 80.0, 80.0, 12.0, 12.0);
    _ = try commands.createEntity(.{
        Transform{},
        MeshInstance{
            .mesh_handle = plane_mesh,
            .shader_handle = core_shaders.ptr.simple_shadow_lit,
            .material = scene_assets.floor_tex.material,
            .color = Color.rgb(165, 172, 180),
        },
        render.Layer(0){},
    });
    try addStaticCollider(commands, .{ .x = 0.0, .y = -0.5, .z = 0.0 }, .{ .x = 40.0, .y = 0.5, .z = 40.0 });

    const pillar_mesh = try createBoxMesh(build, .{ .x = 1.25, .y = 4.0, .z = 1.25 }, 1.0, 1.0);
    _ = try commands.createEntity(.{
        Transform{
            .translation = pillar_center,
        },
        MeshInstance{
            .mesh_handle = pillar_mesh,
            .shader_handle = core_shaders.ptr.simple_shadow_lit,
            .material = scene_assets.pillar_tex.material,
            .color = Color.WHITE,
        },
        render.Layer(0){},
    });
    try addStaticCollider(commands, pillar_center, .{ .x = 1.25, .y = 4.0, .z = 1.25 });

    _ = try commands.createEntity(.{
        Transform{
            .translation = .{ .x = 0.0, .y = 8.0, .z = 0.0 },
        },
        modules.SkyModule.ProceduralSky{
            .material = scene_assets.sky_moon_overlay.material,
            .algorithm = .atmospheric,
            .shader_handle = core_shaders.ptr.sky_procedural_atmospheric,
            .size = 180.0,
            .follow_camera = true,
            .face_segments = 36,
        },
        render.Layer(-1){},
    });

    _ = try commands.createEntity(.{
        Player{},
        player_controller,
        Transform{
            .translation = player_spawn,
            .rotation = Quat.fromAxisAngle(.{ .x = 0.0, .y = 1.0, .z = 0.0 }, look_angles.yaw),
        },
        physics.Character{},
        physics.Collider{
            .shape = .{ .Capsule = .{
                .radius = player_controller.radius,
                .half_height = FpsPhysics.capsuleHalfHeight(player_controller),
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
            .translation = player_spawn.add(FpsPhysics.cameraOffset(player_controller)),
            .rotation = look_rotation,
        },
        Camera3d{ .Perspective = .{
            .fov = std.math.pi / 3.0,
            .near = 0.2,
            .far = 220.0,
        } },
        CameraLayer(-1){},
        CameraLayer(0){},
    });

    _ = try commands.createEntity(.{
        Transform{},
        Camera3d{ .Viewport = .{ .mode = .TopLeft } },
        CameraLayer(1000){},
    });
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
        try modules.TimeModule.setPaused(commands, true);
        try commands.insertResource(capture);
        return;
    }
    if (keyboard.isKeyPressed(.enter)) {
        capture.enabled = true;
        try modules.TimeModule.setPaused(commands, false);
        try commands.insertResource(capture);
    }
}

fn updatePlayerCamera(
    players: ecs.system_params.Query(.{ Transform, FpsController, Player }),
    cameras: ecs.system_params.Query(.{ Transform, PlayerCamera }),
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
        transform.translation = player_transform.?.translation.add(FpsPhysics.cameraOffset(controller));
        transform.rotation = camera_rotation;
    }
}

fn updateDayNightCycle(
    elapsed: Res(ElapsedTime),
    cycle_opt: ResOpt(DayNightCycle),
    ambient_res: ResMut(lighting.AmbientLight),
    environment_res: ResMut(lighting.EnvironmentLight),
    exposure_res: ResMut(lighting.ExposureSettings),
    sun_query: Query(.{ Transform, lighting.Light, SunLight }),
) void {
    const cycle = cycle_opt.ptr orelse return;
    const state = evaluateDayNightState(cycle, @floatCast(elapsed.ptr.seconds));

    var it = sun_query.iterator();
    while (it.next()) |row| {
        const transform = row.get(Transform) orelse continue;
        const light = row.get(lighting.Light) orelse continue;
        switch (light.*) {
            .directional => |*dir| {
                const light_forward = state.shadow_sun.scale(-1.0).normalize();
                transform.rotation = quatFromTo(.{ .x = 0.0, .y = 0.0, .z = -1.0 }, light_forward);
                dir.color = state.light_color;
                dir.illuminance_lux = state.illuminance_lux;
            },
            else => {},
        }
    }

    const ambient = ambient_res.ptr;
    ambient.color = state.ambient_color;
    ambient.intensity = state.ambient_intensity;

    const environment = environment_res.ptr;
    environment.enabled = true;
    environment.dominant_direction = state.sun;
    environment.dominant_color = state.environment_color;
    environment.intensity = state.environment_intensity;
    environment.diffuse_strength = state.environment_diffuse_strength;
    environment.specular_strength = state.environment_specular_strength;
    environment.average_luminance = state.environment_average_luminance;

    const exposure = exposure_res.ptr;
    exposure.enabled = true;
    exposure.auto_enabled = true;
    exposure.auto_key_value = state.exposure_auto_key_value;
    exposure.min_exposure = state.exposure_min;
    exposure.max_exposure = state.exposure_max;
}

fn evaluateDayNightState(cycle: *const DayNightCycle, elapsed_seconds: f32) DayNightState {
    const day_phase = fract(cycle.start_hour / 24.0 + elapsed_seconds / @max(cycle.day_length_seconds, 3.0));
    const sun = sunDirection(day_phase, cycle.latitude_deg);
    const shadow_sun = shadowLightDirection(sun);
    const daylight = smoothstep(-0.14, 0.10, sun.y);
    const night = 1.0 - daylight;
    const twilight = std.math.exp(-@abs(sun.y) * 16.0);

    const clear_sun_color = Color.F32{ .r = 1.0, .g = 0.95, .b = 0.84, .a = 1.0 };
    const dusk_sun_color = Color.F32{ .r = 1.0, .g = 0.58, .b = 0.33, .a = 1.0 };
    const moon_color = Color.F32{ .r = 0.44, .g = 0.52, .b = 0.70, .a = 1.0 };
    const light_color = mixColor(moon_color, mixColor(clear_sun_color, dusk_sun_color, twilight), daylight);

    const day_ambient = Color.F32{ .r = 0.72, .g = 0.78, .b = 0.88, .a = 1.0 };
    const dusk_ambient = Color.F32{ .r = 0.70, .g = 0.46, .b = 0.38, .a = 1.0 };
    const night_ambient = Color.F32{ .r = 0.21, .g = 0.28, .b = 0.43, .a = 1.0 };
    const ambient_color = mixColor(night_ambient, mixColor(dusk_ambient, day_ambient, daylight), daylight + twilight * 0.45);

    return .{
        .sun = sun,
        .shadow_sun = shadow_sun,
        .daylight = daylight,
        .night = night,
        .twilight = twilight,
        .light_color = light_color,
        .illuminance_lux = lerp(300.0, 95_000.0, daylight) + twilight * 12_000.0,
        .ambient_color = ambient_color,
        .ambient_intensity = lerp(0.05, 0.20, daylight) * lerp(1.0, 1.18, twilight),
        .environment_color = light_color,
        .environment_intensity = lerp(0.08, 0.55, daylight),
        .environment_diffuse_strength = lerp(0.3, 1.15, daylight),
        .environment_specular_strength = lerp(0.1, 0.22, daylight),
        .environment_average_luminance = std.math.clamp(lerp(0.04, 0.9, daylight), 0.01, 2.0),
        .exposure_auto_key_value = lerp(0.12, 0.17, daylight),
        .exposure_min = lerp(0.03, 0.11, daylight) * lerp(1.0, 1.16, night),
        .exposure_max = lerp(0.32, 0.62, daylight),
    };
}

fn updateProceduralSkyMeshParams(
    elapsed: Res(ElapsedTime),
    cycle_opt: ResOpt(DayNightCycle),
    panorama_faces: Query(.{ render.MeshInstance, render.Layer(-1), render.LayerSortKey }),
) void {
    const cycle = cycle_opt.ptr orelse return;
    const t: f32 = @floatCast(elapsed.ptr.seconds);
    const weather_phase = (t / @max(cycle.weather_cycle_seconds, 10.0)) * (2.0 * std.math.pi);

    const raw_coverage = cycle.cloud_coverage +
        0.22 * std.math.sin(weather_phase * 0.43) +
        0.16 * std.math.sin(weather_phase * 1.17 + 1.2);
    const coverage = std.math.clamp(raw_coverage, 0.03, 0.95);
    const density = std.math.clamp(cycle.cloud_density + 0.18 * std.math.sin(weather_phase * 0.77 - 0.4), 0.08, 1.0);
    const storminess = std.math.clamp((coverage - 0.45) * 1.5 + density * 0.25, 0.0, 1.0);
    const haze = std.math.clamp(cycle.haze + 0.30 * storminess, 0.0, 1.0);
    const wind_phase = fract(t * std.math.clamp(cycle.wind_speed, 0.0, 4.0) * 0.006);

    var it = panorama_faces.iterator();
    while (it.next()) |row| {
        const sort_key = row.get(render.LayerSortKey) orelse continue;
        if (sort_key.value != sky_layer_sort_background) continue;
        const instance = row.get(render.MeshInstance) orelse continue;
        instance.color = Color.rgba(
            @as(u8, @intFromFloat(std.math.clamp(coverage, 0.0, 1.0) * 255.0)),
            @as(u8, @intFromFloat(std.math.clamp(density, 0.0, 1.0) * 255.0)),
            @as(u8, @intFromFloat(std.math.clamp(haze, 0.0, 1.0) * 255.0)),
            @as(u8, @intFromFloat(std.math.clamp(wind_phase, 0.0, 1.0) * 255.0)),
        );
    }
}

fn addStaticCollider(commands: *ecs.Commands, center: Vec3, half: Vec3) !void {
    _ = try commands.createEntity(.{
        Transform{ .translation = center },
        physics.Body{ .kind = .Static },
        physics.Collider{
            .shape = .{ .Box = .{ .half_extents = half } },
            .material = .{ .friction = 0.85, .restitution = 0.0 },
            .collision = .{ .layer = 0, .mask = 0xffff_ffff },
        },
    });
}

fn createPlaneMesh(build: *render.BuildContext, width: f32, depth: f32, u_scale: f32, v_scale: f32) !render.MeshHandle {
    const hx = width * 0.5;
    const hz = depth * 0.5;

    const vertices = [_]render.VertexPos3NormUv{
        .{ .position = .{ -hx, 0.0, -hz }, .normal = .{ 0.0, 1.0, 0.0 }, .uv = .{ 0.0, 0.0 } },
        .{ .position = .{ hx, 0.0, -hz }, .normal = .{ 0.0, 1.0, 0.0 }, .uv = .{ u_scale, 0.0 } },
        .{ .position = .{ hx, 0.0, hz }, .normal = .{ 0.0, 1.0, 0.0 }, .uv = .{ u_scale, v_scale } },
        .{ .position = .{ -hx, 0.0, hz }, .normal = .{ 0.0, 1.0, 0.0 }, .uv = .{ 0.0, v_scale } },
    };
    const indices = [_]u16{ 0, 1, 2, 2, 3, 0 };
    return build.addMeshPos3NormUv(vertices[0..], indices[0..]);
}

fn createBoxMesh(build: *render.BuildContext, half: Vec3, u_scale: f32, v_scale: f32) !render.MeshHandle {
    const hx = half.x;
    const hy = half.y;
    const hz = half.z;

    const vertices = [_]render.VertexPos3NormUv{
        .{ .position = .{ -hx, -hy, hz }, .normal = .{ 0.0, 0.0, 1.0 }, .uv = .{ 0.0, v_scale } },
        .{ .position = .{ hx, -hy, hz }, .normal = .{ 0.0, 0.0, 1.0 }, .uv = .{ u_scale, v_scale } },
        .{ .position = .{ hx, hy, hz }, .normal = .{ 0.0, 0.0, 1.0 }, .uv = .{ u_scale, 0.0 } },
        .{ .position = .{ -hx, hy, hz }, .normal = .{ 0.0, 0.0, 1.0 }, .uv = .{ 0.0, 0.0 } },

        .{ .position = .{ hx, -hy, -hz }, .normal = .{ 0.0, 0.0, -1.0 }, .uv = .{ 0.0, v_scale } },
        .{ .position = .{ -hx, -hy, -hz }, .normal = .{ 0.0, 0.0, -1.0 }, .uv = .{ u_scale, v_scale } },
        .{ .position = .{ -hx, hy, -hz }, .normal = .{ 0.0, 0.0, -1.0 }, .uv = .{ u_scale, 0.0 } },
        .{ .position = .{ hx, hy, -hz }, .normal = .{ 0.0, 0.0, -1.0 }, .uv = .{ 0.0, 0.0 } },

        .{ .position = .{ -hx, -hy, -hz }, .normal = .{ -1.0, 0.0, 0.0 }, .uv = .{ 0.0, v_scale } },
        .{ .position = .{ -hx, -hy, hz }, .normal = .{ -1.0, 0.0, 0.0 }, .uv = .{ u_scale, v_scale } },
        .{ .position = .{ -hx, hy, hz }, .normal = .{ -1.0, 0.0, 0.0 }, .uv = .{ u_scale, 0.0 } },
        .{ .position = .{ -hx, hy, -hz }, .normal = .{ -1.0, 0.0, 0.0 }, .uv = .{ 0.0, 0.0 } },

        .{ .position = .{ hx, -hy, hz }, .normal = .{ 1.0, 0.0, 0.0 }, .uv = .{ 0.0, v_scale } },
        .{ .position = .{ hx, -hy, -hz }, .normal = .{ 1.0, 0.0, 0.0 }, .uv = .{ u_scale, v_scale } },
        .{ .position = .{ hx, hy, -hz }, .normal = .{ 1.0, 0.0, 0.0 }, .uv = .{ u_scale, 0.0 } },
        .{ .position = .{ hx, hy, hz }, .normal = .{ 1.0, 0.0, 0.0 }, .uv = .{ 0.0, 0.0 } },

        .{ .position = .{ -hx, hy, hz }, .normal = .{ 0.0, 1.0, 0.0 }, .uv = .{ 0.0, v_scale } },
        .{ .position = .{ hx, hy, hz }, .normal = .{ 0.0, 1.0, 0.0 }, .uv = .{ u_scale, v_scale } },
        .{ .position = .{ hx, hy, -hz }, .normal = .{ 0.0, 1.0, 0.0 }, .uv = .{ u_scale, 0.0 } },
        .{ .position = .{ -hx, hy, -hz }, .normal = .{ 0.0, 1.0, 0.0 }, .uv = .{ 0.0, 0.0 } },

        .{ .position = .{ -hx, -hy, -hz }, .normal = .{ 0.0, -1.0, 0.0 }, .uv = .{ 0.0, v_scale } },
        .{ .position = .{ hx, -hy, -hz }, .normal = .{ 0.0, -1.0, 0.0 }, .uv = .{ u_scale, v_scale } },
        .{ .position = .{ hx, -hy, hz }, .normal = .{ 0.0, -1.0, 0.0 }, .uv = .{ u_scale, 0.0 } },
        .{ .position = .{ -hx, -hy, hz }, .normal = .{ 0.0, -1.0, 0.0 }, .uv = .{ 0.0, 0.0 } },
    };

    const indices = [_]u16{
        0,  1,  2,  2,  3,  0,
        4,  5,  6,  6,  7,  4,
        8,  9,  10, 10, 11, 8,
        12, 13, 14, 14, 15, 12,
        16, 17, 18, 18, 19, 16,
        20, 21, 22, 22, 23, 20,
    };

    return build.addMeshPos3NormUv(vertices[0..], indices[0..]);
}

fn quatFromEuler(pitch: f32, yaw: f32, roll: f32) Quat {
    const qx = Quat.fromAxisAngle(.{ .x = 1.0, .y = 0.0, .z = 0.0 }, pitch);
    const qy = Quat.fromAxisAngle(.{ .x = 0.0, .y = 1.0, .z = 0.0 }, yaw);
    const qz = Quat.fromAxisAngle(.{ .x = 0.0, .y = 0.0, .z = 1.0 }, roll);
    return qy.mul(qx).mul(qz).normalize();
}

fn quatFromTo(from: Vec3, to: Vec3) Quat {
    const a = from.normalize();
    const b = to.normalize();
    const dot = std.math.clamp(a.dot(b), -1.0, 1.0);
    if (dot > 0.9999) return Quat.identity();
    if (dot < -0.9999) {
        const fallback_axis = if (@abs(a.y) < 0.99)
            a.cross(.{ .x = 0.0, .y = 1.0, .z = 0.0 })
        else
            a.cross(.{ .x = 1.0, .y = 0.0, .z = 0.0 });
        return Quat.fromAxisAngle(fallback_axis.normalize(), std.math.pi).normalize();
    }
    const axis = a.cross(b);
    return (Quat{
        .w = 1.0 + dot,
        .x = axis.x,
        .y = axis.y,
        .z = axis.z,
    }).normalize();
}

fn sunDirection(day_phase: f32, latitude_deg: f32) Vec3 {
    const theta = (day_phase - 0.25) * (2.0 * std.math.pi);
    const latitude = latitude_deg * (std.math.pi / 180.0);
    const axial_tilt = 0.41;
    const declination = std.math.sin(theta) * axial_tilt;
    const elevation = std.math.sin(latitude) * std.math.sin(declination) +
        std.math.cos(latitude) * std.math.cos(declination) * std.math.cos(theta);
    const horizon_radius = std.math.sqrt(@max(0.0001, 1.0 - elevation * elevation));
    const az = theta + std.math.pi * 0.18;
    return (Vec3{
        .x = std.math.cos(az) * horizon_radius,
        .y = elevation,
        .z = std.math.sin(az) * horizon_radius,
    }).normalize();
}

fn shadowLightDirection(sun: Vec3) Vec3 {
    const blend = smoothstep(-0.22, 0.12, sun.y);
    if (blend >= 0.999) return sun;

    const min_elevation: f32 = 0.08;
    const horiz = Vec3{ .x = sun.x, .y = 0.0, .z = sun.z };
    const horiz_len_sq = horiz.length_squared();
    if (horiz_len_sq <= 0.00001) return sun;

    const horiz_dir = horiz.scale(1.0 / std.math.sqrt(horiz_len_sq));
    const horiz_scale = std.math.sqrt(@max(0.0001, 1.0 - min_elevation * min_elevation));
    const clamped = Vec3{
        .x = horiz_dir.x * horiz_scale,
        .y = min_elevation,
        .z = horiz_dir.z * horiz_scale,
    };
    return sun.scale(blend).add(clamped.scale(1.0 - blend)).normalize();
}

fn fract(value: f32) f32 {
    return value - @floor(value);
}

fn smoothstep(edge0: f32, edge1: f32, x: f32) f32 {
    const t = std.math.clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
}

fn lerp(a: f32, b: f32, t: f32) f32 {
    return a + (b - a) * t;
}

fn mixColor(a: Color.F32, b: Color.F32, t: f32) Color.F32 {
    return .{
        .r = lerp(a.r, b.r, t),
        .g = lerp(a.g, b.g, t),
        .b = lerp(a.b, b.b, t),
        .a = lerp(a.a, b.a, t),
    };
}

const sky_layer_sort_background: i32 = -1000;

const Assets = struct {
    floor_tex: assets.Texture = assets.Texture.embedded(@embedFile("assets/textures/Concrete011_Color.png")).asOpaque().tiledLinear(),
    pillar_tex: assets.Texture = assets.Texture.embedded(@embedFile("assets/textures/Wood049_Color.png")).asOpaque(),
    sky_moon_overlay: assets.Texture = assets.Texture.embedded(@embedFile("assets/textures/moon_overlay_cc0.png")).asBlended(),
};

// Imports
const std = @import("std");
const phasor = @import("phasor");

const ecs = phasor.ecs;
const modules = phasor.modules;
const physics = phasor.physics;
const render = phasor.renderer;
const common = phasor.common;
const platform = phasor.platform;
const assets = phasor.assets;
const lighting = phasor.lighting;

const Res = ecs.system_params.Res;
const ResOpt = ecs.system_params.ResOpt;
const ResMut = ecs.system_params.ResMut;
const Query = ecs.system_params.Query;

const Keyboard = modules.InputModule.Keyboard;
const MouseCapture = modules.InputModule.MouseCapture;

const Vec3 = common.Vec3;
const Quat = common.Quat;
const Color = common.Color;
const Transform = common.Transform;
const Camera3d = common.Camera3d;
const ClearColor = common.ClearColor;
const ElapsedTime = modules.TimeModule.ElapsedTime;

const MeshInstance = render.MeshInstance;
const CameraLayer = render.CameraLayer;
