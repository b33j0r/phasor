//! `TimerModule` updates `CountdownTimer` and `StopwatchTimer` components each frame.
pub const CountdownTimer = struct {
    remaining: f64,
    finished: bool = false,

    pub fn remainingAs(self: CountdownTimer, comptime T: type) T {
        return @floatCast(self.remaining);
    }

    pub fn remaining32(self: CountdownTimer) f32 {
        return self.remainingAs(f32);
    }
};

pub const StopwatchTimer = struct {
    elapsed: f64 = 0.0,
    running: bool = true,

    pub fn elapsedAs(self: StopwatchTimer, comptime T: type) T {
        return @floatCast(self.elapsed);
    }

    pub fn elapsed32(self: StopwatchTimer) f32 {
        return self.elapsedAs(f32);
    }
};

pub fn install(app: *AppCommands, cmds: *Commands) !void {
    if (!cmds.hasResource(TimeModule.SimulationDeltaTime)) {
        return error.MissingTimeModule;
    }
    try app.addSystem("BeforeFrame", updateTimers);
}

pub fn uninstall(app: *AppCommands) void {
    app.removeSystem(updateTimers);
}

fn updateTimers(dt_res: Res(TimeModule.SimulationDeltaTime), countdowns: Query(.{CountdownTimer}), stopwatches: Query(.{StopwatchTimer})) void {
    const dt = dt_res.deref().seconds;

    var countdown_it = countdowns.iterator();
    while (countdown_it.next()) |row| {
        const timer = row.get(CountdownTimer).?;
        if (timer.finished) continue;
        timer.remaining -= dt;
        if (timer.remaining <= 0.0) {
            timer.remaining = 0.0;
            timer.finished = true;
        }
    }

    var stopwatch_it = stopwatches.iterator();
    while (stopwatch_it.next()) |row| {
        const timer = row.get(StopwatchTimer).?;
        if (!timer.running) continue;
        timer.elapsed += dt;
    }
}

test "timer components expose f32 conversion helpers" {
    const countdown = CountdownTimer{ .remaining = 1.25 };
    try std.testing.expectEqual(@as(f64, 1.25), countdown.remainingAs(f64));
    try std.testing.expectEqual(@as(f32, 1.25), countdown.remaining32());

    const stopwatch = StopwatchTimer{ .elapsed = 2.5 };
    try std.testing.expectEqual(@as(f64, 2.5), stopwatch.elapsedAs(f64));
    try std.testing.expectEqual(@as(f32, 2.5), stopwatch.elapsed32());
}

// Imports
const std = @import("std");
const ecs = @import("ecs");
const AppCommands = ecs.AppCommands;
const Commands = ecs.Commands;
const Query = ecs.system_params.Query;
const Res = ecs.system_params.Res;
const schedule = ecs.schedule;
const TimeModule = @import("TimeModule.zig");
