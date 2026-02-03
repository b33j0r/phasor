pub const RenderItem = union(enum) {
    triangle: TriangleDraw,
    mesh: MeshDraw,
};

pub const TriangleDraw = struct {
    triangle: backend.Triangle,
    layer: i32,
};

pub const MeshDraw = struct {
    mesh_handle: mesh.MeshHandle,
    transform: common.Mat4,
    color: common.Color,
    material: ?backend.Material = null,
    blend: bool = false,
    layer: i32 = 0,
    entity_id: u64 = 0,
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

    pub fn pushTriangle(self: *RenderQueue, tri: backend.Triangle, layer: i32) !void {
        try self.items.append(self.allocator, .{ .triangle = .{ .triangle = tri, .layer = layer } });
    }

    pub fn pushMeshInstance(
        self: *RenderQueue,
        instance: mesh.MeshInstance,
        transform: common.Mat4,
        layer: i32,
        entity_id: u64,
    ) !void {
        try self.items.append(self.allocator, .{
            .mesh = .{
                .mesh_handle = instance.mesh_handle,
                .transform = transform,
                .color = instance.color,
                .material = null,
                .blend = instance.color.a < 255,
                .layer = layer,
                .entity_id = entity_id,
            },
        });
    }

    pub fn pushMeshInstanceWithMaterial(
        self: *RenderQueue,
        instance: mesh.MeshInstance,
        transform: common.Mat4,
        material: backend.Material,
        layer: i32,
        entity_id: u64,
    ) !void {
        try self.items.append(self.allocator, .{
            .mesh = .{
                .mesh_handle = instance.mesh_handle,
                .transform = transform,
                .color = instance.color,
                .material = material,
                .blend = true,
                .layer = layer,
                .entity_id = entity_id,
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
