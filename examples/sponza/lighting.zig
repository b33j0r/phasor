pub fn setupColorGrading(commands: *ecs.Commands) !void {
    if (commands.hasResource(render.ColorGradingSettings)) return;
    try commands.insertResource(render.ColorGradingSettings{
        .grade = .filmic,
    });
}

pub fn setupLighting(
    commands: *ecs.Commands,
    scene_ready: ResOpt(SceneReady),
    scene_metrics: ResOpt(SceneMetrics),
) !void {
    if (commands.hasResource(LightingReady)) return;
    if (scene_ready.ptr == null) return;

    const scene_size = if (scene_metrics.ptr) |scene_metrics_res|
        scene_metrics_res.scene_size
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
        // Soft neutral fill at scene origin to lift extreme center-corridor contrast.
        .{ .pos = .{ .x = 0.0, .y = 1.9, .z = 0.0 }, .color = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 }, .intensity = 90.0, .range = 14.0, .dynamic = false },
        // Main corridor: static colored lights along Z (x = 0), leaving origin unlit.
        .{ .pos = .{ .x = 0.0, .y = 2.8, .z = scene_size.z * 0.30 }, .color = .{ .r = 1.0, .g = 0.42, .b = 0.28, .a = 1.0 }, .intensity = 120.0, .range = 9.0, .dynamic = false },
        .{ .pos = .{ .x = 0.0, .y = 2.8, .z = scene_size.z * 0.12 }, .color = .{ .r = 0.22, .g = 0.75, .b = 1.0, .a = 1.0 }, .intensity = 105.0, .range = 9.0, .dynamic = false },
        .{ .pos = .{ .x = 0.0, .y = 2.8, .z = -scene_size.z * 0.12 }, .color = .{ .r = 1.0, .g = 0.8, .b = 0.3, .a = 1.0 }, .intensity = 125.0, .range = 9.5, .dynamic = false },
        .{ .pos = .{ .x = 0.0, .y = 2.6, .z = -scene_size.z * 0.30 }, .color = .{ .r = 0.3, .g = 0.55, .b = 1.0, .a = 1.0 }, .intensity = 100.0, .range = 8.5, .dynamic = false },
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

// Imports
const std = @import("std");
const phasor = @import("phasor");
const shared = @import("shared.zig");

const common = phasor.common;
const ecs = phasor.ecs;
const lighting = phasor.lighting;
const modules = phasor.modules;
const render = phasor.renderer;

const Query = ecs.system_params.Query;
const Res = ecs.system_params.Res;
const ResOpt = ecs.system_params.ResOpt;

const AnimatedLight = shared.AnimatedLight;
const Color = common.Color;
const ElapsedTime = modules.TimeModule.ElapsedTime;
const LightingReady = shared.LightingReady;
const SceneMetrics = shared.SceneMetrics;
const SceneReady = shared.SceneReady;
const Transform = common.Transform;
const Vec3 = common.Vec3;
const quatFromEuler = shared.quatFromEuler;
const sponza_panorama_bytes = shared.sponza_panorama_bytes;
