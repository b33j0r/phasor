const db = @import("db");

const Self = @This();

allocator: std.mem.Allocator,
database: db.Database,
resources_map: std.AutoHashMapUnmanaged(db.meta.TypeId, resources.ResourceEntry) = .empty,

pub fn init(allocator: std.mem.Allocator) Self {
    return .{
        .allocator = allocator,
        .database = db.Database.init(allocator),
        .resources_map = .empty,
    };
}

pub fn deinit(self: *Self) void {
    var it = self.resources_map.iterator();
    while (it.next()) |entry| {
        if (entry.value_ptr.deinit_fn) |f| {
            f(self.allocator, entry.value_ptr.ptr);
        }
    }
    self.resources_map.deinit(self.allocator);
    self.database.deinit();
    self.* = undefined;
}

pub fn insertResource(self: *Self, value: anytype) !void {
    const T = @TypeOf(value);
    const id = resources.resourceTypeId(T);
    if (self.resources_map.getPtr(id)) |existing| {
        self.database.notifyResourceRemoved(id);
        if (existing.deinit_fn) |f| f(self.allocator, existing.ptr);
        _ = self.resources_map.remove(id);
    }

    const entry = try resources.resourceEntry(T, self.allocator, value);
    try self.resources_map.put(self.allocator, id, entry);
    self.database.notifyResourceInserted(id);
}

pub fn registerEvent(self: *Self, io: *const std.Io, comptime T: type, capacity: usize) !void {
    try self.insertResource(try events.Events(T).init(self.allocator, io, capacity));
}

pub fn getResource(self: *Self, comptime T: type) ?*const T {
    const id = resources.resourceTypeId(T);
    const entry = self.resources_map.get(id) orelse return null;
    return @ptrCast(@alignCast(entry.ptr));
}

pub fn getResourceMut(self: *Self, comptime T: type) ?*T {
    const id = resources.resourceTypeId(T);
    const entry = self.resources_map.get(id) orelse return null;
    return @ptrCast(@alignCast(entry.ptr));
}

pub fn removeResource(self: *Self, comptime T: type) bool {
    const id = resources.resourceTypeId(T);
    const entry = self.resources_map.getPtr(id) orelse return false;
    if (entry.deinit_fn) |f| f(self.allocator, entry.ptr);
    _ = self.resources_map.remove(id);
    self.database.notifyResourceRemoved(id);
    return true;
}

pub fn hasResource(self: *Self, comptime T: type) bool {
    return self.resources_map.contains(resources.resourceTypeId(T));
}

pub fn dbMut(self: *Self) *db.Database {
    return &self.database;
}

pub fn dbConst(self: *const Self) *const db.Database {
    return &self.database;
}

// Imports
const std = @import("std");
const resources = @import("resources.zig");
const events = @import("events.zig");
