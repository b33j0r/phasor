pub fn setupColorGrading(commands: *ecs.Commands) !void {
    if (commands.hasResource(render.ColorGradingSettings)) return;
    try commands.insertResource(render.ColorGradingSettings{
        .grade = .filmic,
    });
}

pub fn setupLighting(
    commands: *ecs.Commands,
    scene_ready: HasResource(SceneReady),
    lighting_ready: HasResource(LightingReady),
    scene_assets: ResOpt(Assets),
) !void {
    if (lighting_ready.value) return;
    if (!scene_ready.value) return;
    const assets = scene_assets.ptr orelse return;
    if (!assets.sky_panorama.texture_handle.isValid()) return;

    const scene_size = if (commands.getResource(SceneSpawnPlan)) |spawn_plan|
        spawn_plan.scene_size
    else
        Vec3{ .x = 40.0, .y = 20.0, .z = 40.0 };

    try commands.insertResource(lighting.AmbientLight{
        .color = .{ .r = 0.65, .g = 0.68, .b = 0.74, .a = 1.0 },
        .intensity = 0.01,
    });
    try commands.insertResource(lighting.ExposureSettings{
        .enabled = true,
        .auto_enabled = true,
        .auto_key_value = 0.12,
        .min_exposure = 0.12,
        .max_exposure = 0.45,
    });
    try commands.insertResource(try lighting.buildEnvironmentLightFromHdrBytes(
        commands.allocator,
        sponza_panorama_bytes,
        .{
            .intensity = 0.55,
            .diffuse_strength = 1.35,
            .specular_strength = 0.03,
        },
    ));
    try commands.insertResource(render.SceneEnvironmentMap{
        .texture_handle = assets.sky_panorama.texture_handle,
    });

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
            .illuminance_lux = 180.0,
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
        // Soft white fill at scene origin to keep the center corridor readable.
        .{ .pos = .{ .x = 0.0, .y = 1.9, .z = 0.0 }, .color = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 }, .intensity = 150.0, .range = 18.0, .dynamic = false },
        // Main corridor: keep the negative-Z half moodier so emissive fire reads against darker stone.
        .{ .pos = .{ .x = 0.0, .y = 2.8, .z = scene_size.z * 0.30 }, .color = .{ .r = 1.0, .g = 0.42, .b = 0.28, .a = 1.0 }, .intensity = 120.0, .range = 9.0, .dynamic = false },
        .{ .pos = .{ .x = 0.0, .y = 2.8, .z = scene_size.z * 0.12 }, .color = .{ .r = 0.22, .g = 0.75, .b = 1.0, .a = 1.0 }, .intensity = 92.0, .range = 8.5, .dynamic = false },
        .{ .pos = .{ .x = 0.0, .y = 2.8, .z = -scene_size.z * 0.12 }, .color = .{ .r = 1.0, .g = 0.8, .b = 0.3, .a = 1.0 }, .intensity = 125.0, .range = 9.5, .dynamic = false },
        .{ .pos = .{ .x = 0.0, .y = 2.6, .z = -scene_size.z * 0.30 }, .color = .{ .r = 0.3, .g = 0.55, .b = 1.0, .a = 1.0 }, .intensity = 42.0, .range = 6.2, .dynamic = false },
        // Side corridors: dynamic/patrolling lights centered at +/- x_extent/3, z ~ 0.
        .{ .pos = .{ .x = -scene_size.x * 0.33, .y = 3.2, .z = 0.0 }, .color = .{ .r = 0.82, .g = 0.34, .b = 1.0, .a = 1.0 }, .intensity = 140.0, .range = 10.0, .dynamic = true },
        .{ .pos = .{ .x = scene_size.x * 0.33, .y = 3.2, .z = 0.0 }, .color = .{ .r = 0.24, .g = 1.0, .b = 0.66, .a = 1.0 }, .intensity = 135.0, .range = 10.0, .dynamic = true },
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
            } },
            lighting.LightVisibility{
                .enabled = true,
                .casts_shadows = false,
                .is_static = !spec.dynamic,
            },
        });

        if (spec.dynamic) {
            try commands.addComponent(entity, AnimatedLight{
                .center = spec.pos,
                .orbit_radius = if (i % 2 == 0) 1.1 else 0.9,
                .angular_speed = if (i % 2 == 0) 0.65 else -0.75,
                .phase = @as(f32, @floatFromInt(i)) * 0.7,
                .base_height = spec.pos.y,
                .pulse_base = spec.intensity * 0.75,
                .pulse_amplitude = spec.intensity * 0.35,
                .pulse_speed = 1.2 + @as(f32, @floatFromInt(i)) * 0.08,
            });
        }
    }

    try commands.insertResource(LightingReady{});
}

pub fn setupSkyCycle(
    commands: *ecs.Commands,
    scene_ready: HasResource(SceneReady),
    lighting_ready: HasResource(LightingReady),
    sky_cycle_ready: HasResource(SkyCycleReady),
    scene_assets: ResOpt(Assets),
    core_shaders: ResOpt(render.CoreShaders),
    ambient: Res(lighting.AmbientLight),
    environment: Res(lighting.EnvironmentLight),
    panorama_faces: Query(.{ render.MeshInstance, render.Layer(-1), render.LayerSortKey }),
) !void {
    if (!scene_ready.value) return;
    if (sky_cycle_ready.value) return;
    if (!lighting_ready.value) return;

    try commands.insertResource(SkyCycleState{
        .mode = .panorama,
        .panorama_ambient = ambient.ptr.*,
        .panorama_environment = environment.ptr.*,
    });
    const assets = scene_assets.ptr orelse return;
    if (core_shaders.ptr) |shaders| applySkyVisualMode(panorama_faces, shaders, assets, .panorama, .layered);
    try commands.insertResource(SkyCycleReady{});
}

pub fn toggleSkyModeInput(
    keyboard_opt: ResOpt(Keyboard),
    commands: *ecs.Commands,
    cycle_state: ResMut(SkyCycleState),
    core_shaders: ResOpt(render.CoreShaders),
    scene_assets: ResOpt(Assets),
    current_phase: ResOpt(phases.SponzaPhases.CurrentPhase),
    panorama_faces: Query(.{ render.MeshInstance, render.Layer(-1), render.LayerSortKey }),
) !void {
    if (!phases.isPlayingPhase(current_phase.ptr) and !phases.isPausedPhase(current_phase.ptr)) return;
    const keyboard = keyboard_opt.ptr orelse return;
    if (!keyboard.isKeyPressed(.h)) return;

    const shaders = core_shaders.ptr orelse return;
    const assets = scene_assets.ptr orelse return;
    const state = cycle_state.ptr;
    state.mode = switch (state.mode) {
        .procedural => .panorama,
        .panorama => .procedural,
    };

    switch (state.mode) {
        .procedural => applySkyVisualMode(panorama_faces, shaders, assets, .procedural, state.procedural_algorithm),
        .panorama => {
            applySkyVisualMode(panorama_faces, shaders, assets, .panorama, state.procedural_algorithm);
            if (state.panorama_ambient) |ambient| try commands.insertResource(ambient);
            if (state.panorama_environment) |environment| try commands.insertResource(environment);
        },
    }
}

pub fn updateDayNightWeather(
    elapsed: Res(ElapsedTime),
    cycle_state: ResMut(SkyCycleState),
    ambient_opt: ResMut(lighting.AmbientLight),
    environment_opt: ResMut(lighting.EnvironmentLight),
    exposure_opt: ResMut(lighting.ExposureSettings),
    directional_lights: Query(.{ Transform, lighting.Light, lighting.LightVisibility }),
) void {
    const state = cycle_state.ptr;
    const t: f32 = @floatCast(elapsed.ptr.seconds);
    if (state.mode != .procedural) return;
    const ambient = ambient_opt.ptr;
    const environment = environment_opt.ptr;
    const base_ambient = state.panorama_ambient orelse ambient.*;
    const base_environment = state.panorama_environment orelse environment.*;
    const day_length = @max(30.0, state.day_night.day_length_seconds);
    const start_phase = state.day_night.start_hour / 24.0;
    const day_phase = fract(start_phase + t / day_length);
    const weather_phase = (t / @max(20.0, state.weather.weather_cycle_seconds)) * (2.0 * std.math.pi);

    const sun = sunDirection(day_phase, state.day_night.latitude_deg);
    const daylight = smoothstep(-0.14, 0.10, sun.y);
    const night = 1.0 - daylight;
    const twilight = std.math.exp(-@abs(sun.y) * 16.0);

    const raw_coverage = state.weather.cloud_coverage +
        0.26 * std.math.sin(weather_phase * 0.43) +
        0.18 * std.math.sin(weather_phase * 1.17 + 1.2);
    const coverage = std.math.clamp(raw_coverage, 0.02, 0.98);
    const density = std.math.clamp(state.weather.cloud_density + 0.20 * std.math.sin(weather_phase * 0.77 - 0.4), 0.05, 1.0);
    const storminess = std.math.clamp((coverage - 0.45) * 1.5 + density * 0.25, 0.0, 1.0);
    const haze = std.math.clamp(state.weather.haze + 0.30 * storminess, 0.0, 1.0);

    const clear_sun_color = common.Color.F32{ .r = 1.0, .g = 0.92, .b = 0.78, .a = 1.0 };
    const golden_sun_color = common.Color.F32{ .r = 1.0, .g = 0.56, .b = 0.28, .a = 1.0 };
    const storm_sun_color = common.Color.F32{ .r = 0.64, .g = 0.70, .b = 0.78, .a = 1.0 };
    const moon_color = common.Color.F32{ .r = 0.44, .g = 0.52, .b = 0.70, .a = 1.0 };

    // Keep procedural mode energy anchored to the original panorama tuning so
    // scene lighting/exposure remain close to pre-procedural behavior.
    const ambient_day_tint = common.Color.F32{ .r = 1.00, .g = 1.00, .b = 0.98, .a = 1.0 };
    const ambient_twilight_tint = common.Color.F32{ .r = 1.00, .g = 0.62, .b = 0.40, .a = 1.0 };
    const ambient_night_tint = common.Color.F32{ .r = 0.28, .g = 0.35, .b = 0.56, .a = 1.0 };
    const weather_tint = common.Color.F32{ .r = 0.84, .g = 0.89, .b = 0.96, .a = 1.0 };
    const ambient_tint = mulColor(
        mixColor(
            ambient_night_tint,
            mixColor(ambient_twilight_tint, ambient_day_tint, daylight),
            std.math.clamp(daylight + twilight * 0.45, 0.0, 1.0),
        ),
        mixColor(common.Color.F32{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 }, weather_tint, storminess * 0.55),
    );
    const ambient_weather = mulColor(base_ambient.color, ambient_tint);
    ambient.color = ambient_weather;
    ambient.intensity = base_ambient.intensity *
        lerp(0.55, 1.10, daylight) *
        lerp(1.0, 1.28, twilight) *
        lerp(1.0, 0.88, haze);

    environment.enabled = true;
    environment.intensity = base_environment.intensity *
        lerp(0.55, 1.12, daylight) *
        lerp(1.0, 1.24, twilight) *
        lerp(1.0, 0.90, storminess);
    environment.diffuse_strength = base_environment.diffuse_strength *
        lerp(0.78, 1.05, daylight) *
        lerp(1.0, 1.15, twilight) *
        lerp(1.0, 0.90, storminess);
    environment.specular_strength = base_environment.specular_strength *
        lerp(0.72, 1.15, daylight) *
        lerp(1.0, 1.14, twilight) *
        lerp(1.0, 0.88, storminess);
    environment.average_luminance = std.math.clamp(
        base_environment.average_luminance *
            lerp(0.18, 1.10, daylight) *
            lerp(1.0, 1.28, twilight) *
            lerp(1.0, 0.92, coverage),
        0.01,
        8.0,
    );
    environment.dominant_direction = sun;
    environment.dominant_color = mixColor(
        moon_color,
        mixColor(
            mixColor(clear_sun_color, golden_sun_color, twilight),
            storm_sun_color,
            storminess,
        ),
        daylight,
    );

    const exposure = exposure_opt.ptr;
    exposure.enabled = true;
    exposure.auto_enabled = true;
    exposure.auto_key_value = lerp(0.13, 0.17, daylight) * lerp(1.0, 0.85, storminess);
    exposure.min_exposure = lerp(0.14, 0.13, daylight) * lerp(1.0, 1.08, night);
    exposure.max_exposure = lerp(0.92, 0.58, daylight) * lerp(1.0, 0.90, storminess);

    updateDirectionalSun(directional_lights, sun, daylight, storminess);
}

pub fn updateProceduralSkyMeshParams(
    elapsed: Res(ElapsedTime),
    cycle_state: ResOpt(SkyCycleState),
    panorama_faces: Query(.{ render.MeshInstance, render.Layer(-1), render.LayerSortKey }),
) void {
    const state = cycle_state.ptr orelse return;
    var it = panorama_faces.iterator();
    const t: f32 = @floatCast(elapsed.ptr.seconds);
    const weather_phase = (t / @max(20.0, state.weather.weather_cycle_seconds)) * (2.0 * std.math.pi);
    const raw_coverage = state.weather.cloud_coverage +
        0.26 * std.math.sin(weather_phase * 0.43) +
        0.18 * std.math.sin(weather_phase * 1.17 + 1.2);
    const coverage = std.math.clamp(raw_coverage, 0.02, 0.98);
    const density = std.math.clamp(state.weather.cloud_density + 0.20 * std.math.sin(weather_phase * 0.77 - 0.4), 0.05, 1.0);
    const storminess = std.math.clamp((coverage - 0.45) * 1.5 + density * 0.25, 0.0, 1.0);
    const haze = std.math.clamp(state.weather.haze + 0.30 * storminess, 0.0, 1.0);
    const wind_phase = fract(t * std.math.clamp(state.weather.wind_speed, 0.0, 4.0) * 0.006);

    while (it.next()) |row| {
        const sort_key = row.get(render.LayerSortKey) orelse continue;
        if (sort_key.value != sky_layer_sort_background) continue;
        const instance = row.get(render.MeshInstance) orelse continue;
        if (state.mode == .procedural) {
            instance.color = Color.rgba(
                @as(u8, @intFromFloat(std.math.clamp(coverage, 0.0, 1.0) * 255.0)),
                @as(u8, @intFromFloat(std.math.clamp(density, 0.0, 1.0) * 255.0)),
                @as(u8, @intFromFloat(std.math.clamp(haze, 0.0, 1.0) * 255.0)),
                @as(u8, @intFromFloat(std.math.clamp(wind_phase, 0.0, 1.0) * 255.0)),
            );
        } else {
            instance.color = common.Color.WHITE;
        }
    }
}

pub fn animateLights(
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

fn applySkyVisualMode(
    panorama_faces: Query(.{ render.MeshInstance, render.Layer(-1), render.LayerSortKey }),
    core_shaders: *const render.CoreShaders,
    scene_assets: *const Assets,
    mode: SkyMode,
    algorithm: modules.SkyModule.ProceduralSkyAlgorithm,
) void {
    const shader = switch (mode) {
        .procedural => modules.SkyModule.proceduralSkyShader(core_shaders, algorithm),
        .panorama => core_shaders.sky_panorama_hdr,
    };
    const material = switch (mode) {
        .procedural => scene_assets.sky_moon_overlay.material,
        .panorama => scene_assets.sky_panorama.material,
    };

    var it = panorama_faces.iterator();
    while (it.next()) |row| {
        const sort_key = row.get(render.LayerSortKey) orelse continue;
        if (sort_key.value != sky_layer_sort_background) continue;
        const instance = row.get(render.MeshInstance) orelse continue;
        instance.shader_handle = shader;
        instance.material = material;
    }
}

fn updateDirectionalSun(
    directional_lights: Query(.{ Transform, lighting.Light, lighting.LightVisibility }),
    sun_dir: Vec3,
    daylight: f32,
    storminess: f32,
) void {
    var it = directional_lights.iterator();
    while (it.next()) |row| {
        const transform = row.get(Transform) orelse continue;
        const light = row.get(lighting.Light) orelse continue;
        const visibility = row.get(lighting.LightVisibility) orelse continue;
        switch (light.*) {
            .directional => |*dir| {
                const light_forward = sun_dir.scale(-1.0).normalize();
                const yaw = std.math.atan2(light_forward.x, -light_forward.z);
                const pitch = -std.math.asin(std.math.clamp(light_forward.y, -1.0, 1.0));
                transform.rotation = quatFromEuler(pitch, yaw, 0.0);

                const clear_color = common.Color.F32{ .r = 1.0, .g = 0.95, .b = 0.84, .a = 1.0 };
                const dusk_color = common.Color.F32{ .r = 1.0, .g = 0.58, .b = 0.33, .a = 1.0 };
                const storm_color = common.Color.F32{ .r = 0.66, .g = 0.72, .b = 0.78, .a = 1.0 };
                const twilight = std.math.exp(-@abs(sun_dir.y) * 16.0);
                dir.color = mixColor(mixColor(clear_color, dusk_color, twilight), storm_color, storminess);
                dir.illuminance_lux = (lerp(20.0, 220.0, daylight) + twilight * 46.0) * lerp(1.0, 0.42, storminess);
                visibility.enabled = true;
            },
            else => {},
        }
    }
}

fn sunDirection(day_phase: f32, latitude_deg: f32) Vec3 {
    const theta = (day_phase - 0.25) * (2.0 * std.math.pi);
    const latitude = latitude_deg * (std.math.pi / 180.0);
    const lat_tilt = std.math.sin(latitude) * 0.35;
    const elevation = std.math.sin(theta) * 0.92 + lat_tilt;
    const horizon_radius = std.math.sqrt(@max(0.0001, 1.0 - elevation * elevation));
    const az = theta + std.math.pi * 0.18;
    return (Vec3{
        .x = std.math.cos(az) * horizon_radius,
        .y = elevation,
        .z = std.math.sin(az) * horizon_radius,
    }).normalize();
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

fn mixColor(a: common.Color.F32, b: common.Color.F32, t: f32) common.Color.F32 {
    return .{
        .r = lerp(a.r, b.r, t),
        .g = lerp(a.g, b.g, t),
        .b = lerp(a.b, b.b, t),
        .a = lerp(a.a, b.a, t),
    };
}

fn mulColor(a: common.Color.F32, b: common.Color.F32) common.Color.F32 {
    return .{
        .r = a.r * b.r,
        .g = a.g * b.g,
        .b = a.b * b.b,
        .a = a.a * b.a,
    };
}

// Imports
const std = @import("std");
const phasor = @import("phasor");
const phases = @import("phases.zig");
const shared = @import("shared.zig");

const common = phasor.common;
const ecs = phasor.ecs;
const lighting = phasor.lighting;
const modules = phasor.modules;
const render = phasor.renderer;

const Query = ecs.system_params.Query;
const HasResource = ecs.system_params.HasResource;
const Res = ecs.system_params.Res;
const ResMut = ecs.system_params.ResMut;
const ResOpt = ecs.system_params.ResOpt;

const Assets = shared.Assets;
const AnimatedLight = shared.AnimatedLight;
const Color = common.Color;
const ElapsedTime = modules.TimeModule.ElapsedTime;
const Keyboard = modules.InputModule.Keyboard;
const LightingReady = shared.LightingReady;
const SceneReady = shared.SceneReady;
const SceneSpawnPlan = shared.SceneSpawnPlan;
const SkyCycleReady = shared.SkyCycleReady;
const SkyCycleState = shared.SkyCycleState;
const SkyMode = shared.SkyMode;
const Transform = common.Transform;
const Vec3 = common.Vec3;
const quatFromEuler = shared.quatFromEuler;
const sponza_panorama_bytes = shared.sponza_panorama_bytes;

const sky_layer_sort_background: i32 = -1000;
