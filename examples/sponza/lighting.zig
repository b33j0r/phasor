const std = @import("std");
const s = @import("shared.zig");

pub fn setupLighting(
    commands: *s.ecs.Commands,
    scene_ready: s.ResOpt(s.SceneReady),
    scene_metrics: s.ResOpt(s.SceneMetrics),
) !void {
    if (commands.hasResource(s.LightingReady)) return;
    if (scene_ready.ptr == null) return;

    const scene_size = if (scene_metrics.ptr) |scene_metrics_res|
        scene_metrics_res.scene_size
    else
        s.Vec3{ .x = 40.0, .y = 20.0, .z = 40.0 };

    try commands.insertResource(s.lighting.AmbientLight{
        .color = .{ .r = 0.65, .g = 0.68, .b = 0.74, .a = 1.0 },
        .intensity = 0.001,
    });
    try commands.insertResource(s.lighting.ExposureSettings{
        .enabled = true,
        .exposure = 0.9,
    });
    try commands.insertResource(try s.lighting.buildEnvironmentLightFromHdrBytes(
        commands.allocator,
        s.sponza_panorama_bytes,
        .{
            .intensity = 0.05,
            .diffuse_strength = 0.8,
            .specular_strength = 0.18,
        },
    ));

    _ = try commands.createEntity(.{
        s.Transform{
            .translation = .{
                .x = 0.0,
                .y = scene_size.y * 0.65,
                .z = 0.0,
            },
            .rotation = s.quatFromEuler(-0.95, 0.65, 0.0),
        },
        s.lighting.Light{ .directional = .{
            .color = .{ .r = 1.0, .g = 0.95, .b = 0.86, .a = 1.0 },
            .illuminance_lux = 16000.0,
        } },
        s.lighting.LightVisibility{
            .enabled = true,
            .casts_shadows = false,
            .is_static = true,
        },
    });

    const point_positions = [_]struct {
        pos: s.Vec3,
        color: s.Color.F32,
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
            s.Transform{
                .translation = spec.pos,
            },
            s.lighting.Light{ .point = .{
                .color = spec.color,
                .intensity_candela = spec.intensity,
                .range = spec.range,
            } },
            s.lighting.LightVisibility{
                .enabled = true,
                .casts_shadows = false,
                .is_static = !spec.dynamic,
            },
        });

        if (spec.dynamic) {
            try commands.addComponent(entity, s.AnimatedLight{
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

    _ = try commands.createEntity(.{
        s.Transform{
            .translation = .{
                .x = 0.0,
                .y = scene_size.y * 0.48,
                .z = scene_size.z * 0.08,
            },
            .rotation = s.quatFromEuler(-0.65, std.math.pi, 0.0),
        },
        s.lighting.Light{ .spot = .{
            .color = .{ .r = 1.0, .g = 0.94, .b = 0.8, .a = 1.0 },
            .intensity_candela = 5500.0,
            .range = 24.0,
            .inner_angle_rad = 0.22,
            .outer_angle_rad = 0.45,
        } },
        s.lighting.LightVisibility{
            .enabled = true,
            .casts_shadows = false,
            .is_static = false,
        },
        s.AnimatedLight{
            .center = .{
                .x = 0.0,
                .y = scene_size.y * 0.48,
                .z = scene_size.z * 0.08,
            },
            .orbit_radius = 2.4,
            .angular_speed = 0.35,
            .phase = 0.0,
            .base_height = scene_size.y * 0.48,
            .pulse_base = 4600.0,
            .pulse_amplitude = 1200.0,
            .pulse_speed = 1.5,
        },
    });

    try commands.insertResource(s.LightingReady{});
}

pub fn animateLights(
    elapsed: s.Res(s.ElapsedTime),
    animated_lights: s.Query(.{ s.Transform, s.lighting.Light, s.AnimatedLight }),
) void {
    const t: f32 = @floatCast(elapsed.ptr.seconds);

    var it = animated_lights.iterator();
    while (it.next()) |row| {
        const transform = row.get(s.Transform) orelse continue;
        const light = row.get(s.lighting.Light) orelse continue;
        const motion = row.get(s.AnimatedLight) orelse continue;

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
                transform.rotation = s.quatFromEuler(-0.45, -orbit_phase - std.math.pi * 0.5, 0.0);
            },
            .directional => {},
        }
    }
}
