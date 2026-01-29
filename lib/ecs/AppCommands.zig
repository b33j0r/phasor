pub const AppCommands = struct {
    allocator: std.mem.Allocator,
    io: *const std.Io,
    world: *World,
    schedule_manager: *schedule.ScheduleManager,
    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        io: *const std.Io,
        world: *World,
        schedule_manager: *schedule.ScheduleManager,
    ) Self {
        return .{
            .allocator = allocator,
            .io = io,
            .world = world,
            .schedule_manager = schedule_manager,
        };
    }

    pub fn addSystem(self: *const Self, schedule_label: []const u8, comptime system_fn: anytype) !void {
        try self.schedule_manager.addSystem(self.world, schedule_label, system_fn);
    }

    pub fn removeSystem(self: *const Self, comptime system_fn: anytype) void {
        self.schedule_manager.removeSystem(self.world, system_fn);
    }

    pub fn addSchedule(self: *const Self, label: []const u8) !void {
        try self.schedule_manager.addSchedule(label);
    }

    pub fn insertScheduleBetween(
        self: *const Self,
        before_label: []const u8,
        label: []const u8,
        after_label: []const u8,
    ) !void {
        try self.schedule_manager.insertScheduleBetween(before_label, label, after_label);
    }

};

// Imports
const std = @import("std");
const schedule = @import("schedule.zig");
const World = @import("World.zig");
