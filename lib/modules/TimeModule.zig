//! `TimeModule` updates `DeltaTime` and `ElapsedTime` resources each frame.
pub const DeltaTime = struct {
    seconds: f64 = 0.0,
};

pub const ElapsedTime = struct {
    seconds: f64 = 0.0,
};

const LastInstant = struct {
    value: std.time.Instant,
};

pub fn install(app: *AppCommands, cmds: *Commands) !void {
    try cmds.insertResource(DeltaTime{});
    try cmds.insertResource(ElapsedTime{});
    try cmds.insertResource(LastInstant{ .value = try std.time.Instant.now() });
    try app.addSystem(schedule.DefaultSchedule.BeforeFrame, updateTimeSystem);
}

pub fn uninstall(app: *AppCommands) void {
    app.removeSystem(updateTimeSystem);
}

fn updateTimeSystem(
    res_delta_time: ResMut(DeltaTime),
    res_elapsed_time: ResMut(ElapsedTime),
    res_last_instant: ResMut(LastInstant),
) void {
    const delta_time = res_delta_time.deref();
    const elapsed_time = res_elapsed_time.deref();
    const last_instant = res_last_instant.deref();
    const now = std.time.Instant.now() catch {
        std.log.debug("Failed to get current time instant", .{});
        return;
    };
    const dt_nanos = now.since(last_instant.value);
    const dt = @as(f64, @floatFromInt(dt_nanos)) / std.time.ns_per_s;
    last_instant.value = now;
    delta_time.seconds = dt;
    elapsed_time.seconds += dt;
}

// Imports
const std = @import("std");
const ecs = @import("ecs");
const AppCommands = ecs.AppCommands;
const Commands = ecs.Commands;
const ResMut = ecs.system_params.ResMut;
const schedule = ecs.schedule;
