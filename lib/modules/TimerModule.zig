//! `TimerModule` updates `CountdownTimer` and `StopwatchTimer` components each frame.
//! Timers use simulation time by default. Use `.clock = .real` for diagnostics
//! or UI work that should continue while simulation is paused.
pub const TimerClock = enum {
    simulation,
    real,
};

pub const CountdownTimer = struct {
    remaining: f64,
    finished: bool = false,
    clock: TimerClock = .simulation,

    pub fn remainingAs(self: CountdownTimer, comptime T: type) T {
        return @floatCast(self.remaining);
    }

    pub fn remaining32(self: CountdownTimer) f32 {
        return self.remainingAs(f32);
    }

    pub fn reset(self: *CountdownTimer, seconds: anytype) void {
        self.remaining = @as(f64, seconds);
        self.finished = self.remaining <= 0.0;
    }

    pub fn finish(self: *CountdownTimer) void {
        self.remaining = 0.0;
        self.finished = true;
    }
};

pub const StopwatchTimer = struct {
    elapsed: f64 = 0.0,
    running: bool = true,
    clock: TimerClock = .simulation,

    pub fn elapsedAs(self: StopwatchTimer, comptime T: type) T {
        return @floatCast(self.elapsed);
    }

    pub fn elapsed32(self: StopwatchTimer) f32 {
        return self.elapsedAs(f32);
    }

    pub fn reset(self: *StopwatchTimer) void {
        self.elapsed = 0.0;
    }
};

pub fn install(app: *AppCommands, cmds: *Commands) !void {
    if (!cmds.hasResource(TimeModule.DeltaTime) or !cmds.hasResource(TimeModule.SimulationDeltaTime)) {
        return error.MissingTimeModule;
    }
    try app.addSystem("BeforeFrame", updateTimers);
}

pub fn uninstall(app: *AppCommands) void {
    app.removeSystem(updateTimers);
}

fn updateTimers(
    real_dt_res: Res(TimeModule.DeltaTime),
    simulation_dt_res: Res(TimeModule.SimulationDeltaTime),
    countdowns: Query(.{CountdownTimer}),
    stopwatches: Query(.{StopwatchTimer}),
) void {
    const real_dt = real_dt_res.deref().seconds;
    const simulation_dt = simulation_dt_res.deref().seconds;

    var countdown_it = countdowns.iterator();
    while (countdown_it.next()) |row| {
        const timer = row.get(CountdownTimer).?;
        if (timer.finished) continue;
        const dt = deltaForClock(timer.clock, real_dt, simulation_dt);
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
        const dt = deltaForClock(timer.clock, real_dt, simulation_dt);
        timer.elapsed += dt;
    }
}

fn deltaForClock(clock: TimerClock, real_dt: f64, simulation_dt: f64) f64 {
    return switch (clock) {
        .simulation => simulation_dt,
        .real => real_dt,
    };
}

test "timer components expose f32 conversion helpers" {
    const countdown = CountdownTimer{ .remaining = 1.25 };
    try std.testing.expectEqual(@as(f64, 1.25), countdown.remainingAs(f64));
    try std.testing.expectEqual(@as(f32, 1.25), countdown.remaining32());

    const stopwatch = StopwatchTimer{ .elapsed = 2.5 };
    try std.testing.expectEqual(@as(f64, 2.5), stopwatch.elapsedAs(f64));
    try std.testing.expectEqual(@as(f32, 2.5), stopwatch.elapsed32());

    var mutable_countdown = CountdownTimer{ .remaining = 0.0, .finished = true };
    mutable_countdown.reset(3.0);
    try std.testing.expectEqual(@as(f64, 3.0), mutable_countdown.remaining);
    try std.testing.expect(!mutable_countdown.finished);
    mutable_countdown.finish();
    try std.testing.expectEqual(@as(f64, 0.0), mutable_countdown.remaining);
    try std.testing.expect(mutable_countdown.finished);

    var mutable_stopwatch = StopwatchTimer{ .elapsed = 4.0 };
    mutable_stopwatch.reset();
    try std.testing.expectEqual(@as(f64, 0.0), mutable_stopwatch.elapsed);

    try std.testing.expectEqual(@as(f64, 0.25), deltaForClock(.real, 0.25, 0.0));
    try std.testing.expectEqual(@as(f64, 0.0), deltaForClock(.simulation, 0.25, 0.0));
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
