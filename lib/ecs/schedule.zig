pub const DefaultSchedule = struct {
    pub const WindowCreate = "WindowCreate";
    pub const AssetsLoad = "AssetsLoad";
    pub const Startup = "Startup";
    pub const BeforeFrame = "BeforeFrame";
    pub const Layout = "Layout";
    pub const Update = "Update";
    pub const Render = "Render";
    pub const AfterFrame = "AfterFrame";
    pub const Shutdown = "Shutdown";
    pub const AssetsUnload = "AssetsUnload";
    pub const WindowDestroy = "WindowDestroy";
};

pub const ScheduleAffinity = enum {
    Any,
    MainThreadOnly,
    BackgroundOnly,
};

pub const ScheduleManager = struct {
    allocator: std.mem.Allocator,
    graph: ScheduleGraph,
    labels: std.StringHashMapUnmanaged(usize) = .empty,
    schedule_order: []usize = &.{},
    schedule_order_allocated: bool = false,
    schedule_order_version: u64 = 0,
    schedule_order_from: []usize = &.{},
    schedule_order_from_allocated: bool = false,
    schedule_order_from_version: u64 = 0,
    schedule_order_from_start: ?usize = null,

    const Self = @This();

    pub const Error = error{
        ScheduleNotFound,
        ScheduleAlreadyExists,
    };

    pub fn init(allocator: std.mem.Allocator) !Self {
        var manager = Self{
            .allocator = allocator,
            .graph = ScheduleGraph.init(allocator),
            .labels = .empty,
            .schedule_order = &.{},
            .schedule_order_allocated = false,
            .schedule_order_version = 0,
            .schedule_order_from = &.{},
            .schedule_order_from_allocated = false,
            .schedule_order_from_version = 0,
            .schedule_order_from_start = null,
        };
        errdefer manager.deinit(null);

        try manager.addDefaultSchedules();
        return manager;
    }

    pub fn deinit(self: *Self, world: ?*World) void {
        for (self.graph.nodes.items) |*schedule| {
            schedule.deinit(self.allocator, world);
        }
        self.clearScheduleOrder();
        self.clearScheduleOrderFrom();
        self.graph.deinit();
        self.labels.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn addSchedule(self: *Self, label: []const u8) !void {
        _ = try self.addScheduleInternal(label);
    }

    pub fn insertScheduleBetween(
        self: *Self,
        before_label: []const u8,
        label: []const u8,
        after_label: []const u8,
    ) !void {
        const before_index = self.scheduleIndex(before_label) orelse return Error.ScheduleNotFound;
        const after_index = self.scheduleIndex(after_label) orelse return Error.ScheduleNotFound;
        const new_index = try self.addScheduleInternal(label);
        try self.graph.addEdge(before_index, new_index, {});
        try self.graph.addEdge(new_index, after_index, {});
    }

    pub fn addSystem(self: *Self, world: *World, schedule_label: []const u8, comptime system_fn: anytype) !void {
        const schedule = self.schedulePtr(schedule_label) orelse return Error.ScheduleNotFound;
        try schedule.addSystem(world, system_fn);
    }

    pub fn removeSystem(self: *Self, world: *World, comptime system_fn: anytype) void {
        for (self.graph.nodes.items) |*schedule| {
            _ = schedule.removeSystem(world, system_fn);
        }
    }

    pub fn executionOrder(self: *Self) ![]const usize {
        if (self.schedule_order_allocated and self.schedule_order_version == self.graph.versionId()) {
            return self.schedule_order;
        }
        self.clearScheduleOrder();
        const order = try self.graph.topologicalOrder(self.allocator);
        self.schedule_order = order;
        self.schedule_order_allocated = true;
        self.schedule_order_version = self.graph.versionId();
        return order;
    }

    pub fn executionOrderFrom(self: *Self, start_label: []const u8) ![]const usize {
        const start_index = self.scheduleIndex(start_label) orelse return Error.ScheduleNotFound;
        if (self.schedule_order_from_allocated and
            self.schedule_order_from_version == self.graph.versionId() and
            self.schedule_order_from_start != null and
            self.schedule_order_from_start.? == start_index)
        {
            return self.schedule_order_from;
        }
        self.clearScheduleOrderFrom();
        const order = try self.graph.topologicalOrderFrom(self.allocator, start_index);
        self.schedule_order_from = order;
        self.schedule_order_from_allocated = true;
        self.schedule_order_from_version = self.graph.versionId();
        self.schedule_order_from_start = start_index;
        return order;
    }

    pub fn scheduleIndex(self: *const Self, label: []const u8) ?usize {
        return self.labels.get(label);
    }

    pub fn scheduleCount(self: *const Self) usize {
        return self.graph.nodeCount();
    }

    pub fn scheduleAt(self: *Self, index: usize) *Schedule {
        return &self.graph.nodes.items[index];
    }

    pub fn schedulePtr(self: *Self, label: []const u8) ?*Schedule {
        const index = self.scheduleIndex(label) orelse return null;
        return self.scheduleAt(index);
    }

    pub fn setScheduleAffinity(self: *Self, label: []const u8, affinity: ScheduleAffinity) !void {
        const schedule = self.schedulePtr(label) orelse return Error.ScheduleNotFound;
        schedule.affinity = affinity;
    }

    pub fn scheduleAffinity(self: *Self, label: []const u8) !ScheduleAffinity {
        const schedule = self.schedulePtr(label) orelse return Error.ScheduleNotFound;
        return schedule.affinity;
    }

    fn addDefaultSchedules(self: *Self) !void {
        const default_order = [_][]const u8{
            DefaultSchedule.WindowCreate,
            DefaultSchedule.AssetsLoad,
            DefaultSchedule.Startup,
            DefaultSchedule.BeforeFrame,
            DefaultSchedule.Layout,
            DefaultSchedule.Update,
            DefaultSchedule.Render,
            DefaultSchedule.AfterFrame,
            DefaultSchedule.Shutdown,
            DefaultSchedule.AssetsUnload,
            DefaultSchedule.WindowDestroy,
        };

        for (default_order) |label| {
            _ = try self.addScheduleInternal(label);
        }

        const frame_order = [_][]const u8{
            DefaultSchedule.BeforeFrame,
            DefaultSchedule.Layout,
            DefaultSchedule.Update,
            DefaultSchedule.Render,
            DefaultSchedule.AfterFrame,
        };

        var i: usize = 0;
        while (i + 1 < frame_order.len) : (i += 1) {
            try self.addEdgeByLabel(frame_order[i], frame_order[i + 1]);
        }

        try self.addEdgeByLabel(DefaultSchedule.WindowCreate, DefaultSchedule.AssetsLoad);
        try self.addEdgeByLabel(DefaultSchedule.AssetsLoad, DefaultSchedule.Startup);
        try self.addEdgeByLabel(DefaultSchedule.Startup, DefaultSchedule.BeforeFrame);

        try self.addEdgeByLabel(DefaultSchedule.Shutdown, DefaultSchedule.AssetsUnload);
        try self.addEdgeByLabel(DefaultSchedule.AssetsUnload, DefaultSchedule.WindowDestroy);

        // Default frame/window schedules require root thread affinity for UI/GPU backends.
        try self.setScheduleAffinity(DefaultSchedule.WindowCreate, .MainThreadOnly);
        try self.setScheduleAffinity(DefaultSchedule.BeforeFrame, .MainThreadOnly);
        try self.setScheduleAffinity(DefaultSchedule.Layout, .MainThreadOnly);
        try self.setScheduleAffinity(DefaultSchedule.Update, .MainThreadOnly);
        try self.setScheduleAffinity(DefaultSchedule.Render, .MainThreadOnly);
        try self.setScheduleAffinity(DefaultSchedule.AfterFrame, .MainThreadOnly);
        try self.setScheduleAffinity(DefaultSchedule.WindowDestroy, .MainThreadOnly);
    }

    fn addEdgeByLabel(self: *Self, from_label: []const u8, to_label: []const u8) !void {
        const from_index = self.scheduleIndex(from_label) orelse return Error.ScheduleNotFound;
        const to_index = self.scheduleIndex(to_label) orelse return Error.ScheduleNotFound;
        try self.graph.addEdge(from_index, to_index, {});
    }

    fn addScheduleInternal(self: *Self, label: []const u8) !usize {
        if (self.labels.contains(label)) return Error.ScheduleAlreadyExists;

        var schedule = try Schedule.initOwned(self.allocator, label);
        errdefer schedule.deinit(self.allocator, null);

        const index = self.graph.nodeCount();
        try self.labels.put(self.allocator, schedule.label, index);
        errdefer _ = self.labels.remove(schedule.label);

        _ = try self.graph.addNode(schedule);
        return index;
    }

    fn clearScheduleOrder(self: *Self) void {
        if (self.schedule_order_allocated) {
            self.allocator.free(self.schedule_order);
        }
        self.schedule_order = &.{};
        self.schedule_order_allocated = false;
    }

    fn clearScheduleOrderFrom(self: *Self) void {
        if (self.schedule_order_from_allocated) {
            self.allocator.free(self.schedule_order_from);
        }
        self.schedule_order_from = &.{};
        self.schedule_order_from_allocated = false;
        self.schedule_order_from_start = null;
    }
};

pub const Schedule = struct {
    label: []const u8,
    label_owned: bool,
    affinity: ScheduleAffinity = .Any,
    systems: SystemGraph,
    system_order: []usize = &.{},
    system_order_allocated: bool = false,
    system_order_version: u64 = 0,

    const Self = @This();

    pub fn initOwned(allocator: std.mem.Allocator, label: []const u8) !Self {
        const owned = try allocator.dupe(u8, label);
        return Self{
            .label = owned,
            .label_owned = true,
            .systems = SystemGraph.init(allocator),
        };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator, world: ?*World) void {
        if (world) |w| {
            for (self.systems.nodes.items) |*node| {
                if (!node.enabled) continue;
                node.system.unregister(w) catch |err| {
                    std.log.err("system unregister failed: {any}", .{err});
                };
            }
        }
        self.clearSystemOrder(allocator);
        self.systems.deinit();
        if (self.label_owned) {
            allocator.free(self.label);
        }
        self.* = undefined;
    }

    pub fn addSystem(self: *Self, world: *World, comptime system_fn: anytype) !void {
        const system = try System.from(system_fn);
        try system.register(world);
        errdefer system.unregister(world) catch |err| {
            std.log.err("system unregister failed: {any}", .{err});
        };
        _ = try self.systems.addNode(.{ .system = system, .enabled = true });
    }

    pub fn removeSystem(self: *Self, world: *World, comptime system_fn: anytype) usize {
        const match_system = System.from(system_fn) catch @compileError("Invalid system function");
        var removed: usize = 0;
        for (self.systems.nodes.items) |*node| {
            if (!node.enabled) continue;
            if (node.system.run != match_system.run) continue;
            node.system.unregister(world) catch |err| {
                std.log.err("system unregister failed: {any}", .{err});
            };
            node.enabled = false;
            removed += 1;
        }
        return removed;
    }

    pub fn removeSystemBySystem(self: *Self, world: *World, system: System) usize {
        var removed: usize = 0;
        for (self.systems.nodes.items) |*node| {
            if (!node.enabled) continue;
            if (node.system.run != system.run) continue;
            node.system.unregister(world) catch |err| {
                std.log.err("system unregister failed: {any}", .{err});
            };
            node.enabled = false;
            removed += 1;
        }
        return removed;
    }

    pub fn systemCount(self: *const Self) usize {
        return self.systems.nodeCount();
    }

    pub fn systemOrder(self: *Self, allocator: std.mem.Allocator) ![]const usize {
        if (self.system_order_allocated and self.system_order_version == self.systems.versionId()) {
            return self.system_order;
        }
        self.clearSystemOrder(allocator);
        const order = try self.systems.topologicalOrder(allocator);
        self.system_order = order;
        self.system_order_allocated = true;
        self.system_order_version = self.systems.versionId();
        return order;
    }

    pub fn systemNodeAt(self: *Self, index: usize) *const SystemNode {
        return &self.systems.nodes.items[index];
    }

    fn clearSystemOrder(self: *Self, allocator: std.mem.Allocator) void {
        if (self.system_order_allocated) {
            allocator.free(self.system_order);
        }
        self.system_order = &.{};
        self.system_order_allocated = false;
    }
};

const SystemNode = struct {
    system: System,
    enabled: bool = true,
};

// Imports
const std = @import("std");
const graph = @import("graph");
const World = @import("World.zig");
const System = @import("system.zig").System;

// Tests
test "schedule manager orders default frame schedules" {
    const allocator = std.testing.allocator;
    var world = World.init(allocator);
    defer world.deinit();

    var manager = try ScheduleManager.init(allocator);
    defer manager.deinit(&world);

    const order = try manager.executionOrderFrom(DefaultSchedule.BeforeFrame);
    const expected = [_][]const u8{
        DefaultSchedule.BeforeFrame,
        DefaultSchedule.Layout,
        DefaultSchedule.Update,
        DefaultSchedule.Render,
        DefaultSchedule.AfterFrame,
    };

    try std.testing.expectEqual(@as(usize, expected.len), order.len);
    for (order, 0..) |schedule_index, i| {
        const label = manager.scheduleAt(schedule_index).label;
        try std.testing.expect(std.mem.eql(u8, label, expected[i]));
    }

    const start_order = try manager.executionOrderFrom(DefaultSchedule.WindowCreate);
    try std.testing.expect(std.mem.eql(u8, manager.scheduleAt(start_order[0]).label, DefaultSchedule.WindowCreate));
}

test "schedule manager inserts schedule between existing nodes" {
    const allocator = std.testing.allocator;
    var world = World.init(allocator);
    defer world.deinit();

    var manager = try ScheduleManager.init(allocator);
    defer manager.deinit(&world);

    try manager.insertScheduleBetween(
        DefaultSchedule.BeforeFrame,
        "Physics",
        DefaultSchedule.Update,
    );

    const order = try manager.executionOrderFrom(DefaultSchedule.BeforeFrame);
    var before_index: ?usize = null;
    var physics_index: ?usize = null;
    var after_index: ?usize = null;

    for (order, 0..) |schedule_index, i| {
        const label = manager.scheduleAt(schedule_index).label;
        if (std.mem.eql(u8, label, DefaultSchedule.BeforeFrame)) before_index = i;
        if (std.mem.eql(u8, label, "Physics")) physics_index = i;
        if (std.mem.eql(u8, label, DefaultSchedule.Update)) after_index = i;
    }

    try std.testing.expect(before_index != null);
    try std.testing.expect(physics_index != null);
    try std.testing.expect(after_index != null);
    try std.testing.expect(before_index.? < physics_index.?);
    try std.testing.expect(physics_index.? < after_index.?);
}

test "schedule removes system by disabling node" {
    const allocator = std.testing.allocator;
    var world = World.init(allocator);
    defer world.deinit();

    var manager = try ScheduleManager.init(allocator);
    defer manager.deinit(&world);

    const system_fn = struct {
        fn run(_: *Commands) void {}
    }.run;

    try manager.addSystem(&world, DefaultSchedule.Update, system_fn);
    const update_index = manager.scheduleIndex(DefaultSchedule.Update).?;
    var update_schedule = manager.scheduleAt(update_index);
    const order = try update_schedule.systemOrder(allocator);
    try std.testing.expectEqual(@as(usize, 1), order.len);

    manager.removeSystem(&world, system_fn);
    const node = update_schedule.systemNodeAt(order[0]);
    try std.testing.expect(!node.enabled);
}

const Commands = @import("Commands.zig");

const ScheduleGraph = graph.csr.Graph(Schedule, void);
const SystemGraph = graph.csr.Graph(SystemNode, void);
