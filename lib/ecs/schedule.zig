const std = @import("std");
const World = @import("World.zig");
const System = @import("system.zig").System;
const Commands = @import("Commands.zig");
const CommandBatch = @import("Commands.zig").CommandBatch;

/// Minimal system scheduler for headless runs.
pub const Schedule = struct {
    systems: std.ArrayListUnmanaged(System) = .empty,

    const Self = @This();

    pub fn init() Self {
        return .{ .systems = .empty };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator, world: *World) void {
        for (self.systems.items) |*system| {
            system.unregister(world) catch |err| {
                std.log.err("system unregister failed: {any}", .{err});
            };
        }
        self.systems.deinit(allocator);
        self.* = undefined;
    }

    pub fn addSystem(self: *Self, allocator: std.mem.Allocator, world: *World, comptime system_fn: anytype) !void {
        const system = try System.from(system_fn);
        try system.register(world);
        try self.systems.append(allocator, system);
    }

    pub fn run(
        self: *const Self,
        io: *const std.Io,
        world: *World,
        command_queue: *std.Io.Queue(CommandBatch),
    ) !void {
        for (self.systems.items) |system| {
            var commands = Commands.init(world.allocator, world);
            defer commands.deinit();

            try system.run(&commands);
            if (!commands.isEmpty()) {
                try commands.flushToQueue(io, command_queue);
                var batch = try command_queue.getOneUncancelable(io.*);
                defer batch.deinit();
                try batch.apply(world);
            }
        }
    }
};
