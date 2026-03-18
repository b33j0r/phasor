pub fn spawnPlayerFromCollision(
    commands: *ecs.Commands,
    world: ResMut(physics.BackendWorld),
    physics_stats: Res(physics.Stats),
    spawn_plan: ResOpt(SceneSpawnPlan),
    players: Query(.{Player}),
    current_phase: ResOpt(phases.SponzaPhases.CurrentPhase),
) !void {
    if (!phases.isPlayingPhase(current_phase.ptr)) return;
    if (spawn_plan.ptr == null) return;
    if (physics_stats.ptr.body_count == 0) return;
    var it = players.iterator();
    if (it.next() != null) return;

    const plan = spawn_plan.ptr.?;
    var controller = FpsController{
        .eye_offset_y = 0.6,
        .move_speed = 2.0,
        .jump_speed = 4.0,
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
            .translation = spawn.add(FpsPhysics.cameraOffset(controller)),
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

pub fn handlePhaseInput(
    keyboard_opt: ResOpt(Keyboard),
    capture_opt: ResOpt(MouseCapture),
    commands: *ecs.Commands,
    current_phase: ResOpt(phases.SponzaPhases.CurrentPhase),
) !void {
    const keyboard = keyboard_opt.ptr orelse return;
    var capture = if (capture_opt.ptr) |existing| existing.* else MouseCapture{};

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

pub fn cycleColorGradeInput(
    keyboard_opt: ResOpt(Keyboard),
    commands: *ecs.Commands,
    color_grading_opt: ResOpt(render.ColorGradingSettings),
    current_phase: ResOpt(phases.SponzaPhases.CurrentPhase),
) !void {
    if (!phases.isPlayingPhase(current_phase.ptr) and !phases.isPausedPhase(current_phase.ptr)) return;
    const keyboard = keyboard_opt.ptr orelse return;
    if (!keyboard.isKeyPressed(.c)) return;

    var settings = if (color_grading_opt.ptr) |existing| existing.* else render.ColorGradingSettings{};
    settings.grade = nextColorGrade(settings.grade);
    settings.amount = 1.0;
    try commands.insertResource(settings);
}

pub fn toggleFlyModeInput(
    keyboard_opt: ResOpt(Keyboard),
    commands: *ecs.Commands,
    current_phase: ResOpt(phases.SponzaPhases.CurrentPhase),
    players: Query(.{
        Transform,
        FpsController,
        physics.CharacterVelocity,
        Player,
    }),
) !void {
    if (!phases.isPlayingPhase(current_phase.ptr) and !phases.isPausedPhase(current_phase.ptr)) return;
    const keyboard = keyboard_opt.ptr orelse return;
    if (!keyboard.isKeyPressed(.f)) return;

    var mode = if (commands.getResource(FlyModeState)) |existing| existing.* else FlyModeState{};
    mode.enabled = !mode.enabled;
    try commands.insertResource(mode);

    var it = players.iterator();
    while (it.next()) |row| {
        const entity_id = row.entity_id;
        const velocity = row.get(physics.CharacterVelocity) orelse continue;
        velocity.linear = .{};
        if (mode.enabled) {
            try commands.addComponent(entity_id, physics.PhysicsDisabled{});
        } else {
            commands.removeComponent(entity_id, physics.PhysicsDisabled) catch {};
        }
    }
}

pub fn updateFlyMovement(
    dt: Res(DeltaTime),
    input_opt: ResOpt(FpsControlInput),
    fly_mode_opt: ResOpt(FlyModeState),
    players: Query(.{ Transform, FpsController, Player }),
    current_phase: ResOpt(phases.SponzaPhases.CurrentPhase),
) void {
    if (!phases.isPlayingPhase(current_phase.ptr)) return;
    const fly_mode = fly_mode_opt.ptr orelse return;
    if (!fly_mode.enabled) return;
    const input = input_opt.ptr orelse return;

    const step: f32 = @floatCast(dt.ptr.seconds);
    if (!(step > 0.0)) return;

    var it = players.iterator();
    while (it.next()) |row| {
        const transform = row.get(Transform) orelse continue;
        const controller = row.get(FpsController) orelse continue;

        const rotation = quatFromEuler(controller.pitch, controller.yaw, 0.0);
        const forward = rotation.rotateVec3(.{ .x = 0.0, .y = 0.0, .z = -1.0 }).normalize();
        const right = rotation.rotateVec3(.{ .x = 1.0, .y = 0.0, .z = 0.0 }).normalize();

        const input_forward = std.math.clamp(input.move_forward, -1.0, 1.0);
        const input_right = std.math.clamp(input.move_right, -1.0, 1.0);
        var desired = forward.scale(input_forward).add(right.scale(input_right));
        if (desired.length_squared() <= 0.0001) continue;

        desired = desired.normalize();
        var speed = controller.move_speed * fly_mode.speed_multiplier;
        if (input.sprint_held and controller.sprint_enabled) {
            speed *= controller.sprint_multiplier;
        }

        transform.translation = transform.translation.add(desired.scale(speed * step));
    }
}

pub fn updatePlayerCamera(
    players: Query(.{ Transform, FpsController, Player }),
    cameras: Query(.{ Transform, PlayerCamera }),
    current_phase: ResOpt(phases.SponzaPhases.CurrentPhase),
) void {
    if (!phases.isPlayingPhase(current_phase.ptr)) return;
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

pub fn logPlayerBookmark(
    keyboard_opt: ResOpt(Keyboard),
    players: Query(.{ Transform, FpsController, Player }),
    current_phase: ResOpt(phases.SponzaPhases.CurrentPhase),
) void {
    if (!phases.isPlayingPhase(current_phase.ptr)) return;
    const keyboard = keyboard_opt.ptr orelse return;
    if (!keyboard.isKeyPressed(.m)) return;

    var it = players.iterator();
    const row = it.next() orelse return;
    const transform = row.get(Transform) orelse return;
    const controller = row.get(FpsController) orelse return;

    const camera_translation = transform.translation.add(FpsPhysics.cameraOffset(controller.*));

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
    bus: ResMut(metrics.Bus),
    capture_opt: ResOpt(MouseCapture),
    mouse_opt: ResOpt(Mouse),
    scene_metrics: ResOpt(SceneMetrics),
    imported: ResOpt(assets.ImportedScene),
    lighting_stats: ResOpt(lighting.AuthoringStats),
    color_grading_opt: ResOpt(render.ColorGradingSettings),
    fly_mode_opt: ResOpt(FlyModeState),
    players: Query(.{ Transform, Player }),
    current_phase: ResOpt(phases.SponzaPhases.CurrentPhase),
) void {
    if (!phases.isPlayingPhase(current_phase.ptr) and !phases.isPausedPhase(current_phase.ptr)) return;
    var it = players.iterator();
    const row = it.next() orelse return;
    const transform = row.get(Transform) orelse return;
    const imported_scene = imported.ptr;
    const scene_size = if (scene_metrics.ptr) |scene_metrics_res|
        scene_metrics_res.scene_size
    else if (imported_scene) |scene|
        scene.bounds.size()
    else
        Vec3{};
    const light_stats = if (lighting_stats.ptr) |stats| stats.* else lighting.AuthoringStats{};
    const mouse_captured = if (mouse_opt.ptr) |mouse| mouse.captured else false;
    const mouse_capture_enabled = if (capture_opt.ptr) |capture| capture.enabled else false;
    const mouse_available = mouse_opt.ptr != null;
    const mesh_count: usize = if (imported_scene) |scene| scene.mesh_handles.len else 0;
    const color_grade: render.ColorGrade = if (color_grading_opt.ptr) |settings| settings.grade else .none;
    const fly_mode_enabled = if (fly_mode_opt.ptr) |mode| mode.enabled else false;

    metrics.emitBus(true, bus.ptr, .{
        .player_x = metrics.gauge(transform.translation.x),
        .player_y = metrics.gauge(transform.translation.y),
        .player_z = metrics.gauge(transform.translation.z),
        .mouse_look_available = metrics.gauge(mouse_available),
        .mouse_look_captured = metrics.gauge(mouse_captured),
        .mouse_look_capture_enabled = metrics.gauge(mouse_capture_enabled),
        .scene_mesh_count = metrics.gauge(mesh_count),
        .scene_size_x = metrics.gauge(scene_size.x),
        .scene_size_y = metrics.gauge(scene_size.y),
        .scene_size_z = metrics.gauge(scene_size.z),
        .lights_total = metrics.gauge(light_stats.total_lights),
        .lights_dynamic = metrics.gauge(light_stats.dynamic_lights),
        .lights_point = metrics.gauge(light_stats.point_lights),
        .lights_spot = metrics.gauge(light_stats.spot_lights),
        .color_grade = metrics.gauge(@intFromEnum(color_grade)),
        .fly_mode = metrics.gauge(fly_mode_enabled),
    });
}

pub fn formatPlayerPositionLine(ctx: *const modules.MetricContext, out: []u8) []const u8 {
    const x = if (ctx.store.get("player_x")) |sample| sample.value.asF64() else 0.0;
    const y = if (ctx.store.get("player_y")) |sample| sample.value.asF64() else 0.0;
    const z = if (ctx.store.get("player_z")) |sample| sample.value.asF64() else 0.0;
    return std.fmt.bufPrint(out, "Player XYZ: {d:.2}, {d:.2}, {d:.2}", .{ x, y, z }) catch "Player XYZ: ERR";
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

fn nextColorGrade(grade: render.ColorGrade) render.ColorGrade {
    return switch (grade) {
        .none => .filmic,
        .filmic => .aces_fitted,
        .aces_fitted => .agx,
        .agx => .pbr_neutral,
        .pbr_neutral => .none,
    };
}

// Imports
const std = @import("std");
const phasor = @import("phasor");
const phases = @import("phases.zig");
const shared = @import("shared.zig");

const assets = phasor.assets;
const common = phasor.common;
const ecs = phasor.ecs;
const lighting = phasor.lighting;
const metrics = phasor.metrics;
const modules = phasor.modules;
const physics = phasor.physics;
const render = phasor.renderer;

const Query = ecs.system_params.Query;
const Res = ecs.system_params.Res;
const ResMut = ecs.system_params.ResMut;
const ResOpt = ecs.system_params.ResOpt;

const Camera3d = common.Camera3d;
const CameraLayer = render.CameraLayer;
const FpsController = shared.FpsController;
const FpsControlInput = modules.FpsControlInput;
const FpsPhysics = shared.FpsPhysics;
const FlyModeState = shared.FlyModeState;
const Keyboard = modules.InputModule.Keyboard;
const Mouse = modules.InputModule.Mouse;
const MouseCapture = modules.InputModule.MouseCapture;
const Player = shared.Player;
const PlayerCamera = shared.PlayerCamera;
const SceneMetrics = shared.SceneMetrics;
const SceneSpawnPlan = shared.SceneSpawnPlan;
const SpawnChoice = shared.SpawnChoice;
const Transform = common.Transform;
const Vec3 = common.Vec3;
const Quat = common.Quat;
const DeltaTime = modules.TimeModule.DeltaTime;
const quatFromEuler = shared.quatFromEuler;
