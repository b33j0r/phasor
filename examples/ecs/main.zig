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
const ParticleTable = struct { index: usize };
const SpawnCounter = struct { value: u64 = 0 };

fn setupResources(commands: *ecs.Commands) !void {
    if (!commands.hasResource(SpawnCounter)) {
        try commands.insertResource(SpawnCounter{ .value = 0 });
        _ = try commands.createEntity(.{
            SpawnerTag{},
            StopwatchTimer{},
        });
    }
}

fn spawnParticles(commands: *ecs.Commands, spawner_query: Query(.{ SpawnerTag, StopwatchTimer })) !void {
    const counter = commands.getResourceMut(SpawnCounter) orelse return;
    if (counter.value >= 10) return;
    counter.value += 1;

    var spawner_it = spawner_query.iterator();
    const spawner_row = spawner_it.next();
    if (spawner_row) |row| {
        const stopwatch = row.get(StopwatchTimer).?;
        std.log.debug("Spawning particle #{d} ({d})", .{ counter.value, stopwatch.elapsed });
    }

    _ = try commands.createEntity(.{
        Position{ .x = @floatFromInt(counter.value), .y = 0 },
        Velocity{ .dx = 1, .dy = 0 },
        CountdownTimer{ .remaining = 3.0 },
    });
}

fn integratePhysics(dt: Res(DeltaTime), query: Query(.{ Position, Velocity, CountdownTimer })) !void {
    const step = dt.deref().seconds;
    var it = query.iterator();
    while (it.next()) |row| {
        const pos = row.get(Position).?;
        const vel = row.get(Velocity).?;
        pos.x += vel.dx * step;
        pos.y += vel.dy * step;
    }
}

fn cullExpired(commands: *ecs.Commands, query: Query(.{CountdownTimer})) !void {
    var to_remove: std.ArrayListUnmanaged(phasor.db.Entity.Id) = .empty;
    defer to_remove.deinit(commands.allocator);

    var it = query.iterator();
    while (it.next()) |row| {
        const timer = row.get(CountdownTimer).?;
        if (timer.finished) {
            try to_remove.append(commands.allocator, row.entity_id);
        }
    }

    for (to_remove.items) |entity_id| {
        try commands.removeEntity(entity_id);
    }
}

fn exitWhenAllDone(commands: *ecs.Commands, query: Query(.{CountdownTimer})) !void {
    const counter = commands.getResource(SpawnCounter) orelse return;
    if (counter.value >= 10 and query.count() == 0) {
        std.log.debug("All particles expired, exiting.", .{});
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
    try app.addSystem(cullExpired);
    try app.addSystem(exitWhenAllDone);

    return try app.run();
}

// Imports
const std = @import("std");
const phasor = @import("phasor");
