pub const RenderItem = union(enum) {
    triangle: backend.Triangle,
    mesh: mesh.MeshInstance,
};

pub const RenderQueue = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayListUnmanaged(RenderItem) = .empty,

    pub fn init(allocator: std.mem.Allocator) RenderQueue {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *RenderQueue) void {
        self.items.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn reset(self: *RenderQueue) void {
        self.items.clearRetainingCapacity();
    }

    pub fn pushTriangle(self: *RenderQueue, tri: backend.Triangle) !void {
        try self.items.append(self.allocator, .{ .triangle = tri });
    }

    pub fn pushMeshInstance(self: *RenderQueue, instance: mesh.MeshInstance) !void {
        try self.items.append(self.allocator, .{ .mesh = instance });
    }
};

const builtin = @import("builtin");
const std = @import("std");
const mesh = @import("mesh.zig");
const backend = if (builtin.target.cpu.arch.isWasm())
    @import("backend_web.zig")
else
    @import("backend_native.zig");
