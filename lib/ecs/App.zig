allocator: std.mem.Allocator,
io: *const std.Io,
world: World,
schedule: Schedule,
command_queue: ?std.Io.Queue(CommandBatch) = null,
command_queue_buffer: ?[]CommandBatch = null,
command_queue_capacity: usize = 64,

const Self = @This();

pub const Error = error{
    NotImplemented,
};

pub fn error_message(err: Error) []const u8 {
    return switch (err) {
        Error.NotImplemented => "Not implemented",
    };
}

pub const InitConfig = struct {
    command_queue_capacity: usize = 64,
};

pub fn init(allocator: std.mem.Allocator, io: *const std.Io) Self {
    return initWithConfig(allocator, io, .{});
}

pub fn initWithConfig(allocator: std.mem.Allocator, io: *const std.Io, config: InitConfig) Self {
    return .{
        .allocator = allocator,
        .io = io,
        .world = World.init(allocator),
        .schedule = Schedule.init(),
        .command_queue = null,
        .command_queue_buffer = null,
        .command_queue_capacity = config.command_queue_capacity,
    };
}

pub fn deinit(self: *Self) void {
    self.schedule.deinit(self.allocator, &self.world);
    if (self.command_queue_buffer) |buffer| {
        self.allocator.free(buffer);
    }
    self.world.deinit();
    self.* = undefined;
}

pub fn addSystem(self: *Self, comptime system_fn: anytype) !void {
    try self.schedule.addSystem(self.allocator, &self.world, system_fn);
}

pub fn run(self: *Self) !u8 {
    if (self.command_queue == null) {
        const buffer = try self.allocator.alloc(CommandBatch, self.command_queue_capacity);
        self.command_queue_buffer = buffer;
        self.command_queue = std.Io.Queue(CommandBatch).init(buffer);
    }
    const command_queue = &self.command_queue.?;

    while (true) {
        try self.schedule.run(self.io, &self.world, command_queue);
        if (self.world.getResource(resources.Exit)) |exit| {
            return exit.code;
        }
    }
}

// Imports
const std = @import("std");
const phasor = @import("../root.zig");
const World = @import("World.zig");
const Schedule = @import("schedule.zig").Schedule;
const resources = @import("resources.zig");
const CommandBatch = @import("Commands.zig").CommandBatch;
