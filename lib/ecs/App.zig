world: World,

pub const Error = error{
    NotImplemented,
};

const Self = @This();

pub fn init() Self {
    return Self{
        .world = World.init(),
    };
}

pub fn deinit(self: *Self) void {
    self.world.deinit();
}

pub fn run(_: *Self) !void {
    return Error.NotImplemented;
}

// Imports
const std = @import("std");

const phasor = @import("../root.zig");
const World = phasor.ecs.World;
