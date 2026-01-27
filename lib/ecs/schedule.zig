const std = @import("std");
const World = @import("World.zig");

/// Minimal system scheduler for headless runs.
pub const Schedule = struct {
    systems: std.ArrayListUnmanaged(SystemFn) = .empty,

    const Self = @This();
    pub const SystemFn = *const fn (*World) anyerror!void;

    pub fn init() Self {
        return .{ .systems = .empty };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        self.systems.deinit(allocator);
        self.* = undefined;
    }

    pub fn addSystem(self: *Self, allocator: std.mem.Allocator, system: SystemFn) !void {
        try self.systems.append(allocator, system);
    }

    pub fn run(self: *const Self, world: *World) !void {
        for (self.systems.items) |system| {
            try system(world);
        }
    }
};
