const std = @import("std");
const s = @import("shared.zig");
const phases = @import("phases.zig");

pub fn spawnPlayerFromCollision(
    commands: *s.ecs.Commands,
    world: s.ResMut(s.physics.BackendWorld),
    physics_stats: s.Res(s.physics.Stats),
    spawn_plan: s.ResOpt(s.SceneSpawnPlan),
    players: s.Query(.{s.Player}),
    current_phase: s.ResOpt(phases.SponzaPhases.CurrentPhase),
) !void {
    if (!phases.isPlayingPhase(current_phase.ptr)) return;
    if (spawn_plan.ptr == null) return;
    if (physics_stats.ptr.body_count == 0) return;
    var it = players.iterator();
    if (it.next() != null) return;

    const plan = spawn_plan.ptr.?;
    var controller = s.FpsController{
        .eye_offset_y = 0.6,
        .move_speed = 6.5,
        .jump_speed = 7.0,
        .pitch = -0.18,
    };
    const spawn_choice = findSpawnPoint(world.ptr, plan.scene_size, controller) orelse return;
    controller.yaw = spawn_choice.yaw;
    const spawn = spawn_choice.position;
    const body_facing = s.Quat.fromAxisAngle(.{ .x = 0.0, .y = 1.0, .z = 0.0 }, spawn_choice.yaw);
    const camera_facing = s.quatFromEuler(controller.pitch, controller.yaw, 0.0);

    std.log.debug(
        "sponza spawn: pos=({d:.2}, {d:.2}, {d:.2}) yaw={d:.2} rad",
        .{ spawn.x, spawn.y, spawn.z, spawn_choice.yaw },
    );

    _ = try commands.createEntity(.{
        s.Player{},
        controller,
        s.Transform{
            .translation = spawn,
            .rotation = body_facing,
        },
        s.physics.Character{},
        s.physics.Collider{
            .shape = .{ .Capsule = .{
                .radius = controller.radius,
                .half_height = s.FpsPhysics.capsuleHalfHeight(controller),
            } },
            .collision = .{
                .layer = 1,
                .mask = 1 << 0,
            },
        },
        s.physics.CharacterVelocity{},
        s.physics.CharacterState{},
    });

    _ = try commands.createEntity(.{
        s.PlayerCamera{},
        s.Transform{
            .translation = spawn.add(.{ .x = 0.0, .y = controller.eye_offset_y, .z = 0.0 }),
            .rotation = camera_facing,
        },
        s.Camera3d{ .Perspective = .{
            .fov = std.math.pi / 3.0,
            .near = 0.05,
            .far = 250.0,
        } },
        s.CameraLayer(-1){},
        s.CameraLayer(0){},
    });

    _ = commands.removeResource(s.SceneSpawnPlan);
}

pub fn handlePhaseInput(
    keyboard_opt: s.ResOpt(s.Keyboard),
    capture_opt: s.ResOpt(s.MouseCapture),
    commands: *s.ecs.Commands,
    current_phase: s.ResOpt(phases.SponzaPhases.CurrentPhase),
) !void {
    const keyboard = keyboard_opt.ptr orelse return;
    var capture = if (capture_opt.ptr) |existing| existing.* else s.MouseCapture{};

    if (phases.isPlayingPhase(current_phase.ptr) and keyboard.isKeyPressed(.escape)) {
        capture.enabled = false;
        try commands.insertResource(capture);
        try commands.insertResource(phases.SponzaPhases.NextPhase{ .phase = .{ .InGame = .{ .Paused = .{} } } });
        return;
    }
    if (phases.isPausedPhase(current_phase.ptr) and (keyboard.isKeyPressed(.enter) or keyboard.isKeyPressed(.escape))) {
        capture.enabled = true;
        try commands.insertResource(capture);
        try commands.insertResource(phases.SponzaPhases.NextPhase{ .phase = .{ .InGame = .{ .Playing = .{} } } });
    }
}

pub fn updatePlayerCamera(
    players: s.Query(.{ s.Transform, s.FpsController, s.Player }),
    cameras: s.Query(.{ s.Transform, s.PlayerCamera }),
    current_phase: s.ResOpt(phases.SponzaPhases.CurrentPhase),
) void {
    if (!phases.isPlayingPhase(current_phase.ptr)) return;
    var player_transform: ?s.Transform = null;
    var player_controller: ?s.FpsController = null;

    var pit = players.iterator();
    while (pit.next()) |row| {
        player_transform = row.get(s.Transform).?.*;
        player_controller = row.get(s.FpsController).?.*;
        break;
    }

    if (player_transform == null or player_controller == null) return;
    const controller = player_controller.?;
    const camera_rotation = s.quatFromEuler(controller.pitch, controller.yaw, 0.0);

    var cit = cameras.iterator();
    while (cit.next()) |row| {
        const transform = row.get(s.Transform) orelse continue;
        transform.translation = player_transform.?.translation.add(.{ .x = 0.0, .y = controller.eye_offset_y, .z = 0.0 });
        transform.rotation = camera_rotation;
    }
}

pub fn logPlayerBookmark(
    keyboard_opt: s.ResOpt(s.Keyboard),
    players: s.Query(.{ s.Transform, s.FpsController, s.Player }),
    current_phase: s.ResOpt(phases.SponzaPhases.CurrentPhase),
) void {
    if (!phases.isPlayingPhase(current_phase.ptr)) return;
    const keyboard = keyboard_opt.ptr orelse return;
    if (!keyboard.isKeyPressed(.m)) return;

    var it = players.iterator();
    const row = it.next() orelse return;
    const transform = row.get(s.Transform) orelse return;
    const controller = row.get(s.FpsController) orelse return;

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

pub fn emitSponzaHudMetrics(
    bus: s.ResMut(s.metrics.Bus),
    capture_opt: s.ResOpt(s.MouseCapture),
    mouse_opt: s.ResOpt(s.Mouse),
    scene_metrics: s.ResOpt(s.SceneMetrics),
    imported: s.ResOpt(s.assets.ImportedScene),
    lighting_stats: s.ResOpt(s.lighting.AuthoringStats),
    players: s.Query(.{ s.Transform, s.Player }),
    current_phase: s.ResOpt(phases.SponzaPhases.CurrentPhase),
) void {
    if (!phases.isPlayingPhase(current_phase.ptr) and !phases.isPausedPhase(current_phase.ptr)) return;
    var it = players.iterator();
    const row = it.next() orelse return;
    const transform = row.get(s.Transform) orelse return;
    const imported_scene = imported.ptr;
    const scene_size = if (scene_metrics.ptr) |scene_metrics_res|
        scene_metrics_res.scene_size
    else if (imported_scene) |scene|
        scene.bounds.size()
    else
        s.Vec3{};
    const light_stats = if (lighting_stats.ptr) |stats| stats.* else s.lighting.AuthoringStats{};
    const mouse_captured = if (mouse_opt.ptr) |mouse| mouse.captured else false;
    const mouse_capture_enabled = if (capture_opt.ptr) |capture| capture.enabled else false;
    const mouse_available = mouse_opt.ptr != null;
    const mesh_count: usize = if (imported_scene) |scene| scene.mesh_handles.len else 0;

    s.metrics.emitBus(true, bus.ptr, .{
        .player_x = s.metrics.gauge(transform.translation.x),
        .player_y = s.metrics.gauge(transform.translation.y),
        .player_z = s.metrics.gauge(transform.translation.z),
        .mouse_look_available = s.metrics.gauge(mouse_available),
        .mouse_look_captured = s.metrics.gauge(mouse_captured),
        .mouse_look_capture_enabled = s.metrics.gauge(mouse_capture_enabled),
        .scene_mesh_count = s.metrics.gauge(mesh_count),
        .scene_size_x = s.metrics.gauge(scene_size.x),
        .scene_size_y = s.metrics.gauge(scene_size.y),
        .scene_size_z = s.metrics.gauge(scene_size.z),
        .lights_total = s.metrics.gauge(light_stats.total_lights),
        .lights_dynamic = s.metrics.gauge(light_stats.dynamic_lights),
        .lights_point = s.metrics.gauge(light_stats.point_lights),
        .lights_spot = s.metrics.gauge(light_stats.spot_lights),
    });
}

pub fn formatPlayerPositionLine(ctx: *const s.modules.MetricContext, out: []u8) []const u8 {
    const x = if (ctx.store.get("player_x")) |sample| sample.value.asF64() else 0.0;
    const y = if (ctx.store.get("player_y")) |sample| sample.value.asF64() else 0.0;
    const z = if (ctx.store.get("player_z")) |sample| sample.value.asF64() else 0.0;
    return std.fmt.bufPrint(out, "Player XYZ: {d:.2}, {d:.2}, {d:.2}", .{ x, y, z }) catch "Player XYZ: ERR";
}

fn findSpawnPoint(world: *s.physics.BackendWorld, scene_size: s.Vec3, controller: s.FpsController) ?s.SpawnChoice {
    const probe_filter = s.physics.CollisionFilter{
        .layer = 1,
        .mask = 1 << 0,
    };
    const probe_start_y = @max(scene_size.y + 8.0, 16.0);
    const max_x = @max(4.0, scene_size.x * 0.48);
    const max_z = @max(4.0, scene_size.z * 0.48);
    const step = 1.5;
    const forward_bias = @min(max_z, 3.0);

    var best: ?s.SpawnChoice = null;
    var best_score: f32 = -1.0;
    var z: f32 = forward_bias;

    while (z >= -max_z) : (z -= step) {
        var x: f32 = -max_x;
        while (x <= max_x) : (x += step) {
            const ray = s.physics.RayCast{
                .origin = .{ .x = x, .y = probe_start_y, .z = z },
                .direction = .{ .x = 0.0, .y = -1.0, .z = 0.0 },
                .max_distance = probe_start_y + 8.0,
                .collision = probe_filter,
            };
            const floor_hit = world.castRay(ray) orelse continue;
            if (@abs(floor_hit.normal.y) < 0.8) continue;

            const spawn = s.Vec3{
                .x = x,
                .y = floor_hit.position.y + controller.radius + s.FpsPhysics.capsuleHalfHeight(controller) + 0.08,
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
    world: *s.physics.BackendWorld,
    spawn: s.Vec3,
    controller: s.FpsController,
    filter: s.physics.CollisionFilter,
) bool {
    const clearance = controller.height + 0.2;
    const hit = world.castShape(.{
        .shape = .{ .Capsule = .{
            .radius = controller.radius,
            .half_height = s.FpsPhysics.capsuleHalfHeight(controller),
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
    world: *s.physics.BackendWorld,
    spawn: s.Vec3,
    controller: s.FpsController,
    filter: s.physics.CollisionFilter,
) struct { yaw: f32, score: f32 } {
    const eye = spawn.add(.{ .x = 0.0, .y = controller.eye_offset_y, .z = 0.0 });
    const directions = [_]s.Vec3{
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
