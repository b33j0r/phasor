const ecs = phasor.ecs;
const resources = ecs.resources;
const modules = phasor.modules;
const DeltaTime = modules.TimeModule.DeltaTime;
const CountdownTimer = modules.TimerModule.CountdownTimer;
const StopwatchTimer = modules.TimerModule.StopwatchTimer;
const system_params = ecs.system_params;
const Query = system_params.Query;
const Res = system_params.Res;

const std_options = std.Options{
    .log_level = std.log.Level.debug,
};

const Position = struct { x: f64, y: f64 };
const Velocity = struct {
    dx: f64,
    dy: f64,
    pub const default = @This(){ .dx = 0, .dy = 0 };
};

const SpawnerTag = struct {};
const ParticleTag = struct {};
const ParticleTable = struct { index: usize };
const SpawnCounter = struct { value: u64 = 0 };

fn setupResources(commands: *ecs.Commands) !void {
    if (!commands.hasResource(SpawnCounter)) {
        try commands.insertResource(SpawnCounter{ .value = 0 });
        _ = try commands.createEntity(.{
            SpawnerTag{},
            StopwatchTimer{},
            CountdownTimer{ .remaining = 3.0 },
        });
    }
}

fn spawnParticles(commands: *ecs.Commands, spawner_query: Query(.{ SpawnerTag, StopwatchTimer })) !void {
    const counter = commands.getResourceMut(SpawnCounter) orelse return;
    var spawner_it = spawner_query.iterator();
    const spawner_row = spawner_it.next() orelse return;

    counter.value += 1;
    const stopwatch = spawner_row.get(StopwatchTimer).?;
    if (counter.value % 100 == 0) {
        std.log.debug("Spawning particle #{d} ({d})", .{ counter.value, stopwatch.elapsed });
    }

    _ = try commands.createEntity(.{
        ParticleTag{},
        Position{ .x = @floatFromInt(counter.value), .y = 0 },
        Velocity{ .dx = 1, .dy = 0 },
    });
}

fn integratePhysics(dt: Res(DeltaTime), query: Query(.{ Position, Velocity, ParticleTag })) !void {
    const step = dt.deref().seconds;
    var it = query.iterator();
    while (it.next()) |row| {
        const pos = row.get(Position).?;
        const vel = row.get(Velocity).?;
        pos.x += vel.dx * step;
        pos.y += vel.dy * step;
    }
}

fn exitAfterCountdown(commands: *ecs.Commands, spawners: Query(.{ SpawnerTag, CountdownTimer })) !void {
    var spawner_it = spawners.iterator();
    const spawner_row = spawner_it.next() orelse return;
    const spawner_timer = spawner_row.get(CountdownTimer).?;
    if (spawner_timer.finished) {
        std.log.debug("Exit countdown finished, exiting.", .{});
        try commands.insertResource(resources.Exit{ .code = 0 });
    }
}

pub fn main(init: std.process.Init) !u8 {
    const allocator = std.heap.c_allocator;

    var app = try ecs.App.init(allocator, &init.io);
    defer app.deinit();

    try app.installModule(modules.TimeModule);
    try app.installModule(modules.TimerModule);
    try app.addSystem(setupResources);
    try app.addSystem(spawnParticles);
    try app.addSystem(integratePhysics);
    try app.addSystem(exitAfterCountdown);

    return try app.run();
}

// Imports
const std = @import("std");
const phasor = @import("phasor");
