const ecs = phasor.ecs;
const resources = ecs.resources;
const system_params = ecs.system_params;
const Query = system_params.Query;
const Res = system_params.Res;

const std_options = std.Options{
    .log_level = std.log.Level.debug,
};

const Position = struct { x: f32, y: f32 };
const Velocity = struct {
    dx: f32,
    dy: f32,
    pub const default = @This(){ .dx = 0, .dy = 0 };
};
const Lifetime = struct {
    seconds: f32,
    pub const default = @This(){ .seconds = 0 };
};
const DeltaTime = struct { seconds: f32 };

const ParticleTable = struct { index: usize };
const SpawnCounter = struct { value: u64 = 0 };

fn setupResources(commands: *ecs.Commands) !void {
    if (!commands.hasResource(SpawnCounter)) {
        try commands.insertResource(SpawnCounter{ .value = 0 });
    }
    if (!commands.hasResource(DeltaTime)) {
        try commands.insertResource(DeltaTime{ .seconds = 1.0 / 60.0 });
    }
}

fn spawnParticles(commands: *ecs.Commands) !void {
    const counter = commands.getResourceMut(SpawnCounter) orelse return;
    if (counter.value >= 10) return;
    counter.value += 1;

    std.log.debug("Spawning particle #{d}", .{counter.value});

    _ = try commands.createEntity(.{
        Position{ .x = @floatFromInt(counter.value), .y = 0 },
        Velocity{ .dx = 1, .dy = 0 },
        Lifetime{ .seconds = 3 },
    });
}

fn integratePhysics(dt: Res(DeltaTime), query: Query(.{ Position, Velocity, Lifetime })) !void {
    const step = dt.deref().seconds;
    var it = query.iterator();
    while (it.next()) |row| {
        const pos = row.get(Position).?;
        const vel = row.get(Velocity).?;
        const life = row.get(Lifetime).?;
        pos.x += vel.dx * step;
        pos.y += vel.dy * step;
        life.seconds -= step;
    }
}

fn cullExpired(commands: *ecs.Commands, query: Query(.{ Lifetime })) !void {
    var to_remove: std.ArrayListUnmanaged(phasor.db.Entity.Id) = .empty;
    defer to_remove.deinit(commands.allocator);

    var it = query.iterator();
    while (it.next()) |row| {
        const life = row.get(Lifetime).?;
        if (life.seconds <= 0) {
            try to_remove.append(commands.allocator, row.entity_id);
        }
    }

    for (to_remove.items) |entity_id| {
        try commands.removeEntity(entity_id);
    }
}

fn exitWhenAllDone(commands: *ecs.Commands, query: Query(.{ Lifetime })) !void {
    const counter = commands.getResource(SpawnCounter) orelse return;
    if (counter.value >= 10 and query.count() == 0) {
        std.log.debug("All particles expired, exiting.", .{});
        try commands.insertResource(resources.Exit{ .code = 0 });
    }
}

pub fn main(init: std.process.Init) !u8 {
    const allocator = std.heap.c_allocator;

    var app = ecs.App.init(allocator, &init.io);
    defer app.deinit();

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
