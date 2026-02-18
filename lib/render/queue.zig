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
    shader_handle: ?mesh.ShaderHandle = null,
    material_handle: ?mesh.MaterialHandle = null,
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
        var material: ?backend.Material = null;
        var material_handle: ?mesh.MaterialHandle = null;
        var shader_handle: ?mesh.ShaderHandle = null;
        var blend = instance.color.a < 255 or instance.material.alpha_mode == .Blend;
        switch (instance.material.binding) {
            .default => {},
            .textured => |mat| {
                material_handle = mat;
                blend = true;
            },
            .backend => |mat| {
                material = mat;
                blend = true;
            },
            .shader => |shader| {
                shader_handle = shader;
            },
        }
        try self.items.append(self.allocator, .{
            .mesh = .{
                .mesh_handle = instance.mesh_handle,
                .shader_handle = shader_handle,
                .material_handle = material_handle,
                .transform = transform,
                .color = instance.color,
                .material = material,
                .blend = blend,
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
                .shader_handle = null,
                .material_handle = null,
                .transform = transform,
                .color = instance.color,
                .material = material,
                .blend = true,
                .layer = layer,
                .entity_id = entity_id,
            },
        });
    }

    pub fn pushMeshInstanceWithShader(
        self: *RenderQueue,
        instance: mesh.MeshInstance,
        shader_handle: mesh.ShaderHandle,
        transform: common.Mat4,
        layer: i32,
        entity_id: u64,
    ) !void {
        try self.items.append(self.allocator, .{
            .mesh = .{
                .mesh_handle = instance.mesh_handle,
                .shader_handle = shader_handle,
                .material_handle = null,
                .transform = transform,
                .color = instance.color,
                .material = null,
                .blend = instance.color.a < 255,
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
