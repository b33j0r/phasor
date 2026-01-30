pub const RenderItem = union(enum) {
    triangle: backend.Triangle,
    mesh: MeshDraw,
};

pub const MeshDraw = struct {
    mesh_handle: mesh.MeshHandle,
    transform: common.Mat4,
    color: common.Color,
    material: ?backend.Material = null,
    blend: bool = false,
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

    pub fn pushMeshInstance(self: *RenderQueue, instance: mesh.MeshInstance, transform: common.Mat4) !void {
        try self.items.append(self.allocator, .{
            .mesh = .{
                .mesh_handle = instance.mesh_handle,
                .transform = transform,
                .color = instance.color,
                .material = null,
                .blend = instance.color.a < 255,
            },
        });
    }

    pub fn pushMeshInstanceWithMaterial(
        self: *RenderQueue,
        instance: mesh.MeshInstance,
        transform: common.Mat4,
        material: backend.Material,
    ) !void {
        try self.items.append(self.allocator, .{
            .mesh = .{
                .mesh_handle = instance.mesh_handle,
                .transform = transform,
                .color = instance.color,
                .material = material,
                .blend = true,
            },
        });
    }
};

const builtin = @import("builtin");
const std = @import("std");
const common = @import("common");
const mesh = @import("mesh.zig");
const backend = if (builtin.target.cpu.arch.isWasm())
    @import("backend_web.zig")
else
    @import("backend_native.zig");
