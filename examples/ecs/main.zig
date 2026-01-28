const std = @import("std");
const phasor = @import("phasor");
const ecs = phasor.ecs;
const resources = ecs.resources;

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

const ParticleTable = struct { index: usize };
const SpawnCounter = struct { value: u64 = 0 };

fn setupResources(commands: *ecs.Commands) !void {
    if (!commands.hasResource(SpawnCounter)) {
        try commands.insertResource(SpawnCounter{ .value = 0 });
    }
}

fn spawnParticles(commands: *ecs.Commands) !void {
    const counter = commands.getResourceMut(SpawnCounter) orelse return;
    if (counter.value >= 10) return;
    counter.value += 1;

    _ = try commands.createEntity(.{
        Position{ .x = @floatFromInt(counter.value), .y = 0 },
        Velocity{ .dx = 1, .dy = 0 },
        Lifetime{ .seconds = 3 },
    });
}

fn exitWhenDone(commands: *ecs.Commands) !void {
    const counter = commands.getResource(SpawnCounter) orelse return;
    if (counter.value >= 10) {
        std.log.debug("All particles spawned, exiting.", .{});
        try commands.insertResource(resources.Exit{ .code = 0 });
    }
}

pub fn main(init: std.process.Init) !u8 {
    const allocator = std.heap.c_allocator;

    var app = ecs.App.init(allocator, &init.io);
    defer app.deinit();

    try app.addSystem(setupResources);
    try app.addSystem(spawnParticles);
    try app.addSystem(exitWhenDone);

    return try app.run();
}
