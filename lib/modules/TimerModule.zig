//! `TimerModule` updates `CountdownTimer` and `StopwatchTimer` components each frame.
pub const CountdownTimer = struct {
    remaining: f64,
    finished: bool = false,
};

pub const StopwatchTimer = struct {
    elapsed: f64 = 0.0,
    running: bool = true,
};

pub fn install(app: *AppCommands, cmds: *Commands) !void {
    if (!cmds.hasResource(TimeModule.DeltaTime) or !cmds.hasResource(TimeModule.ElapsedTime)) {
        return error.MissingTimeModule;
    }
    try app.addSystem(schedule.DefaultSchedule.BeforeFrame, updateTimers);
}

pub fn uninstall(app: *AppCommands) void {
    app.removeSystem(updateTimers);
}

fn updateTimers(dt_res: Res(TimeModule.DeltaTime), countdowns: Query(.{CountdownTimer}), stopwatches: Query(.{StopwatchTimer})) void {
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

// Imports
const ecs = @import("ecs");
const AppCommands = ecs.AppCommands;
const Commands = ecs.Commands;
const Query = ecs.system_params.Query;
const Res = ecs.system_params.Res;
const schedule = ecs.schedule;
const TimeModule = @import("TimeModule.zig");
