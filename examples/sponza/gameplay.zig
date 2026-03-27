pub fn spawnPlayerFromCollision(
    commands: *ecs.Commands,
    world: ResMut(physics.BackendWorld),
    physics_stats: Res(physics.Stats),
    spawn_plan: ResOpt(SceneSpawnPlan),
    players: Query(.{Player}),
    current_phase: Res(phases.SponzaPhases.CurrentPhase),
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
        .fly_toggle_enabled = true,
    };
    if (debug_start_bookmark) |bookmark| {
        controller.pitch = bookmark.camera_pitch;
    }
    const real_spawn_choice = findSpawnPoint(world.ptr, plan.scene_size, controller) orelse return;
    const spawn_choice = if (debug_start_bookmark) |bookmark|
        SpawnChoice{
            .position = bookmark.player_transform.translation,
            .yaw = bookmark.player_yaw,
        }
    else if (debug_spawn_outside_enabled)
        outsideSkySpawnPoint(plan.scene_size, controller)
    else
        real_spawn_choice;
    if (debug_spawn_outside_enabled) {
        controller.pitch = 0.48;
        controller.fly_enabled = true;
    }
    controller.yaw = spawn_choice.yaw;
    const spawn = spawn_choice.position;
    const body_facing = Quat.fromAxisAngle(.{ .x = 0.0, .y = 1.0, .z = 0.0 }, spawn_choice.yaw);
    const camera_facing = quatFromEuler(controller.pitch, controller.yaw, 0.0);

    std.log.debug(
        "sponza spawn real=({d:.2}, {d:.2}, {d:.2}) active=({d:.2}, {d:.2}, {d:.2}) yaw={d:.2} rad override_outside={}",
        .{
            real_spawn_choice.position.x,
            real_spawn_choice.position.y,
            real_spawn_choice.position.z,
            spawn.x,
            spawn.y,
            spawn.z,
            spawn_choice.yaw,
            debug_spawn_outside_enabled,
        },
    );

    try commands.insertResource(SpawnDebugState{
        .real_spawn = real_spawn_choice,
        .active_spawn = spawn_choice,
        .override_outside = debug_spawn_outside_enabled,
    });
    const player_entity = try commands.createEntity(.{
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
    if (debug_spawn_outside_enabled) {
        try commands.addComponent(player_entity, physics.PhysicsDisabled{});
    }

    const camera_translation = if (debug_start_bookmark) |bookmark|
        bookmark.camera_transform.translation
    else
        spawn.add(FpsPhysics.cameraOffset(controller));
    const camera_rotation = if (debug_start_bookmark) |bookmark|
        bookmark.camera_transform.rotation
    else
        camera_facing;

    _ = try commands.createEntity(.{
        PlayerCamera{},
        Transform{
            .translation = camera_translation,
            .rotation = camera_rotation,
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

pub fn captureScreenshotInput(
    keyboard_opt: ResOpt(Keyboard),
    elapsed: Res(modules.TimeModule.ElapsedTime),
    screenshot_state_opt: ResOpt(ScreenshotCaptureState),
    commands: *ecs.Commands,
    current_phase: Res(phases.SponzaPhases.CurrentPhase),
) void {
    if (!phases.isPlayingPhase(current_phase.ptr) and !phases.isPausedPhase(current_phase.ptr)) return;
    if (builtin.os.tag == .wasi) return;

    const keyboard = keyboard_opt.ptr orelse return;
    var state = if (screenshot_state_opt.ptr) |existing| existing.* else ScreenshotCaptureState{};

    if (keyboard.isKeyPressed(.o)) {
        state.auto_enabled = !state.auto_enabled;
        state.next_capture_at_seconds = elapsed.ptr.seconds + state.auto_interval_seconds;
        std.log.info("screenshot auto capture: {}", .{state.auto_enabled});
    }
    if (keyboard.isKeyPressed(.p)) {
        captureScreenshot(commands, &state, elapsed.ptr.seconds, "manual") catch |err| {
            std.log.warn("screenshot capture failed ({s})", .{@errorName(err)});
        };
    }

    if (state.auto_enabled and state.auto_count < state.auto_max_count and elapsed.ptr.seconds >= state.next_capture_at_seconds) {
        captureScreenshot(commands, &state, elapsed.ptr.seconds, "auto") catch |err| {
            std.log.warn("auto screenshot capture failed ({s})", .{@errorName(err)});
        };
        state.next_capture_at_seconds = elapsed.ptr.seconds + state.auto_interval_seconds;
    }

    commands.insertResource(state) catch |err| {
        std.log.warn("failed to persist screenshot state ({s})", .{@errorName(err)});
    };
}

pub fn handlePhaseInput(
    keyboard_opt: ResOpt(Keyboard),
    capture_opt: ResOpt(MouseCapture),
    commands: *ecs.Commands,
    current_phase: Res(phases.SponzaPhases.CurrentPhase),
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
    current_phase: Res(phases.SponzaPhases.CurrentPhase),
) !void {
    if (!phases.isPlayingPhase(current_phase.ptr) and !phases.isPausedPhase(current_phase.ptr)) return;
    const keyboard = keyboard_opt.ptr orelse return;
    if (!keyboard.isKeyPressed(.c)) return;

    var settings = if (color_grading_opt.ptr) |existing| existing.* else render.ColorGradingSettings{};
    settings.grade = nextColorGrade(settings.grade);
    settings.amount = 1.0;
    try commands.insertResource(settings);
}

pub fn cycleDebugViewInput(
    keyboard_opt: ResOpt(Keyboard),
    commands: *ecs.Commands,
    debug_view_opt: ResOpt(render.SceneDebugView),
    current_phase: Res(phases.SponzaPhases.CurrentPhase),
) !void {
    if (!phases.isPlayingPhase(current_phase.ptr) and !phases.isPausedPhase(current_phase.ptr)) return;
    const keyboard = keyboard_opt.ptr orelse return;
    if (!keyboard.isKeyPressed(.v)) return;

    const current = if (debug_view_opt.ptr) |view| view.* else render.SceneDebugView.off;
    try commands.insertResource(nextDebugView(current));
}

pub fn toggleEnvironmentSpecularInput(
    keyboard_opt: ResOpt(Keyboard),
    commands: *ecs.Commands,
    environment_specular_mode_opt: ResOpt(render.EnvironmentSpecularMode),
    current_phase: Res(phases.SponzaPhases.CurrentPhase),
) !void {
    if (!phases.isPlayingPhase(current_phase.ptr) and !phases.isPausedPhase(current_phase.ptr)) return;
    const keyboard = keyboard_opt.ptr orelse return;
    if (!keyboard.isKeyPressed(.b)) return;

    const current = if (environment_specular_mode_opt.ptr) |mode| mode.* else render.EnvironmentSpecularMode.on;
    const next: render.EnvironmentSpecularMode = switch (current) {
        .on => .off,
        .off => .on,
    };
    try commands.insertResource(next);
}

pub fn cycleNormalMapScaleInput(
    keyboard_opt: ResOpt(Keyboard),
    commands: *ecs.Commands,
    normal_map_scale_opt: ResOpt(render.NormalMapScale),
    current_phase: Res(phases.SponzaPhases.CurrentPhase),
) !void {
    if (!phases.isPlayingPhase(current_phase.ptr) and !phases.isPausedPhase(current_phase.ptr)) return;
    const keyboard = keyboard_opt.ptr orelse return;
    if (!keyboard.isKeyPressed(.n)) return;

    var settings = if (normal_map_scale_opt.ptr) |scale| scale.* else render.NormalMapScale{};
    settings.multiplier = nextNormalMapScale(settings.multiplier);
    try commands.insertResource(settings);
}

pub fn updatePlayerCamera(
    players: Query(.{ Transform, FpsController, Player }),
    cameras: Query(.{ Transform, PlayerCamera }),
    current_phase: Res(phases.SponzaPhases.CurrentPhase),
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
    current_phase: Res(phases.SponzaPhases.CurrentPhase),
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
    color_grading_opt: ResOpt(render.ColorGradingSettings),
    environment_specular_mode_opt: ResOpt(render.EnvironmentSpecularMode),
    normal_map_scale_opt: ResOpt(render.NormalMapScale),
    debug_view_opt: ResOpt(render.SceneDebugView),
    players: Query(.{ Transform, FpsController, Player }),
    current_phase: Res(phases.SponzaPhases.CurrentPhase),
) void {
    if (!phases.isPlayingPhase(current_phase.ptr) and !phases.isPausedPhase(current_phase.ptr)) return;
    var it = players.iterator();
    const row = it.next() orelse return;
    const transform = row.get(Transform) orelse return;
    const controller = row.get(FpsController) orelse return;
    const mouse_captured = if (mouse_opt.ptr) |mouse| mouse.captured else false;
    const mouse_capture_enabled = if (capture_opt.ptr) |capture| capture.enabled else false;
    const mouse_available = mouse_opt.ptr != null;
    const color_grade: render.ColorGrade = if (color_grading_opt.ptr) |settings| settings.grade else .none;
    const environment_specular_mode = if (environment_specular_mode_opt.ptr) |mode| mode.* else render.EnvironmentSpecularMode.on;
    const normal_map_scale = if (normal_map_scale_opt.ptr) |scale| scale.multiplier else 1.0;
    const debug_view = if (debug_view_opt.ptr) |view| view.* else render.SceneDebugView.off;
    const fly_mode_enabled = controller.fly_enabled;

    metrics.emitBus(true, bus.ptr, .{
        .player_x = metrics.gauge(transform.translation.x),
        .player_y = metrics.gauge(transform.translation.y),
        .player_z = metrics.gauge(transform.translation.z),
        .mouse_look_available = metrics.gauge(mouse_available),
        .mouse_look_captured = metrics.gauge(mouse_captured),
        .mouse_look_capture_enabled = metrics.gauge(mouse_capture_enabled),
        .color_grade = metrics.gauge(@intFromEnum(color_grade)),
        .environment_specular_mode = metrics.gauge(@as(u32, switch (environment_specular_mode) {
            .on => 1,
            .off => 0,
        })),
        .normal_map_scale = metrics.gauge(normal_map_scale),
        .scene_debug_view = metrics.gauge(@intFromEnum(debug_view)),
        .fly_mode = metrics.gauge(fly_mode_enabled),
    });
}

pub fn formatNormalMapScaleLine(ctx: *const modules.MetricContext, out: []u8) []const u8 {
    const scale = if (ctx.store.get("normal_map_scale")) |sample| sample.value.asF64() else 1.0;
    return std.fmt.bufPrint(out, "Normal Scale: {d:.1}x", .{scale}) catch "Normal Scale";
}

pub fn formatEnvironmentSpecularLine(ctx: *const modules.MetricContext, out: []u8) []const u8 {
    const enabled = if (ctx.store.get("environment_specular_mode")) |sample| sample.value.asF64() >= 0.5 else true;
    return std.fmt.bufPrint(out, "Env Specular: {s}", .{if (enabled) "On" else "Off"}) catch "Env Specular";
}

pub fn formatDebugViewLine(ctx: *const modules.MetricContext, out: []u8) []const u8 {
    const value = if (ctx.store.get("scene_debug_view")) |sample| @as(u32, @intFromFloat(sample.value.asF64())) else @intFromEnum(render.SceneDebugView.off);
    const debug_view: render.SceneDebugView = @enumFromInt(value);
    return std.fmt.bufPrint(out, "Debug View: {s}", .{debugViewLabel(debug_view)}) catch "Debug View";
}

pub fn formatPlayerPositionLine(ctx: *const modules.MetricContext, out: []u8) []const u8 {
    const x = if (ctx.store.get("player_x")) |sample| sample.value.asF64() else 0.0;
    const y = if (ctx.store.get("player_y")) |sample| sample.value.asF64() else 0.0;
    const z = if (ctx.store.get("player_z")) |sample| sample.value.asF64() else 0.0;
    return std.fmt.bufPrint(out, "XYZ: {d:.2}, {d:.2}, {d:.2}", .{ x, y, z }) catch "Player XYZ: ERR";
}

pub fn formatControlsMoveLine(_: *const modules.MetricContext, out: []u8) []const u8 {
    return std.fmt.bufPrint(out, "Move/Look", .{}) catch "Move/Look";
}

pub fn formatControlsActionLine(_: *const modules.MetricContext, out: []u8) []const u8 {
    return std.fmt.bufPrint(out, "Actions", .{}) catch "Actions";
}

pub fn formatControlsModeLine(_: *const modules.MetricContext, out: []u8) []const u8 {
    return std.fmt.bufPrint(out, "Modes", .{}) catch "Modes";
}

pub fn formatControlsCaptureLine(_: *const modules.MetricContext, out: []u8) []const u8 {
    return std.fmt.bufPrint(out, "Capture", .{}) catch "Capture";
}

pub fn formatControlsPauseLine(_: *const modules.MetricContext, out: []u8) []const u8 {
    return std.fmt.bufPrint(out, "Session", .{}) catch "Session";
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

fn outsideSkySpawnPoint(scene_size: Vec3, controller: FpsController) SpawnChoice {
    const y = @max(scene_size.y * 1.3, 42.0);
    const z = @max(scene_size.z * 0.95, 36.0);
    const spawn = Vec3{
        .x = 0.0,
        .y = y + controller.radius + FpsPhysics.capsuleHalfHeight(controller),
        .z = z,
    };
    const to_center = (Vec3{ .x = -spawn.x, .y = 0.0, .z = -spawn.z }).normalize();
    return .{
        .position = spawn,
        .yaw = std.math.atan2(to_center.x, -to_center.z),
    };
}

fn captureScreenshot(
    commands: *ecs.Commands,
    state: *ScreenshotCaptureState,
    elapsed_seconds: f64,
    reason: []const u8,
) !void {
    try std.Io.Dir.cwd().createDirPath(commands.io.*, state.output_dir);
    const elapsed_ms: u64 = @intFromFloat(@max(elapsed_seconds, 0.0) * 1000.0);
    const path = try std.fmt.allocPrint(
        commands.allocator,
        "{s}/sponza_{d:0>6}_{d:0>3}_{s}.png",
        .{ state.output_dir, elapsed_ms, state.capture_index, reason },
    );
    defer commands.allocator.free(path);

    const capture_cmd = try std.fmt.allocPrint(
        commands.allocator,
        "window_id=$(swift -e 'import CoreGraphics; import Foundation; let opts = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements); if let info = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] {{ for w in info {{ let owner = (w[kCGWindowOwnerName as String] as? String ?? \"\").lowercased(); if owner.contains(\"sponza\") {{ if let id = w[kCGWindowNumber as String] as? Int {{ print(id); break }} }} }} }}'); if [ -n \"$window_id\" ]; then screencapture -x -l \"$window_id\" \"{s}\"; else screencapture -x \"{s}\"; fi",
        .{ path, path },
    );
    defer commands.allocator.free(capture_cmd);

    const argv = [_][]const u8{ "/bin/zsh", "-c", capture_cmd };
    var child = try std.process.spawn(commands.io.*, .{
        .argv = &argv,
        .stdin = .ignore,
        .stdout = .inherit,
        .stderr = .inherit,
    });
    const term = try child.wait(commands.io.*);
    switch (term) {
        .exited => |code| if (code != 0) return error.ScreenshotCaptureFailed,
        else => return error.ScreenshotCaptureFailed,
    }

    state.capture_index += 1;
    if (std.mem.eql(u8, reason, "auto")) state.auto_count += 1;
    std.log.info("saved screenshot: {s}", .{path});
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

fn nextNormalMapScale(current: f32) f32 {
    if (current < 0.5) return 1.0;
    if (current < 1.5) return 2.0;
    if (current < 3.0) return 4.0;
    return 0.0;
}

fn nextDebugView(view: render.SceneDebugView) render.SceneDebugView {
    return switch (view) {
        .off => .base_color,
        .base_color => .normal,
        .normal => .metallic,
        .metallic => .roughness,
        .roughness => .ao,
        .ao => .ndotl,
        .ndotl => .ndotv,
        .ndotv => .specular,
        .specular => .off,
    };
}

fn debugViewLabel(view: render.SceneDebugView) []const u8 {
    return switch (view) {
        .off => "Off",
        .base_color => "BaseColor",
        .normal => "Normal",
        .metallic => "Metallic",
        .roughness => "Roughness",
        .ao => "AO",
        .ndotl => "NdotL",
        .ndotv => "NdotV",
        .specular => "Specular",
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
const FpsPhysics = shared.FpsPhysics;
const Keyboard = modules.InputModule.Keyboard;
const Mouse = modules.InputModule.Mouse;
const MouseCapture = modules.InputModule.MouseCapture;
const Player = shared.Player;
const PlayerCamera = shared.PlayerCamera;
const SceneSpawnPlan = shared.SceneSpawnPlan;
const SpawnChoice = shared.SpawnChoice;
const Transform = common.Transform;
const Vec3 = common.Vec3;
const Quat = common.Quat;
const quatFromEuler = shared.quatFromEuler;

const debug_spawn_outside_enabled = false;
const DebugStartBookmark = struct {
    player_transform: Transform,
    camera_transform: Transform,
    player_yaw: f32,
    camera_pitch: f32,
};
const debug_start_bookmark: ?DebugStartBookmark = null;
// Enable this temporarily for reproducible curtain-seal close-up checks:
// .{
//     .player_transform = Transform{
//         .translation = .{ .x = -5.093, .y = 1.891, .z = -0.331 },
//         .rotation = quatFromEuler(0.0, 2.7306, 0.0),
//     },
//     .camera_transform = Transform{
//         .translation = .{ .x = -5.093, .y = 2.491, .z = -0.331 },
//         .rotation = quatFromEuler(-0.1501, 2.7306, 0.0),
//     },
//     .player_yaw = 2.7306,
//     .camera_pitch = -0.1501,
// };

const SpawnDebugState = struct {
    real_spawn: SpawnChoice,
    active_spawn: SpawnChoice,
    override_outside: bool = false,
};

const ScreenshotCaptureState = struct {
    output_dir: []const u8 = "local/screenshots",
    auto_enabled: bool = false,
    auto_interval_seconds: f64 = 2.0,
    auto_max_count: u32 = 5,
    next_capture_at_seconds: f64 = 2.0,
    auto_count: u32 = 0,
    capture_index: u32 = 0,
};

const builtin = @import("builtin");
