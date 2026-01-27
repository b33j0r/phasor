world: World,

pub const Error = error{
    NotImplemented,
};

pub fn error_message(err: Error) []const u8 {
    return switch (err) {
        Error.NotImplemented => "Not implemented",
    };
}

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
    return error.NotImplemented;
}

// Imports
const std = @import("std");

const phasor = @import("../root.zig");
const World = phasor.ecs.World;
