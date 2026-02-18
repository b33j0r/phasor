pub const MeshHandle = struct {
    index: u32,
    generation: u32,

    pub fn invalid() MeshHandle {
        return .{ .index = std.math.maxInt(u32), .generation = 0 };
    }

    pub fn isValid(self: MeshHandle) bool {
        return self.index != std.math.maxInt(u32);
    }
};

pub const ShaderHandle = struct {
    index: u32,
    generation: u32,

    pub fn invalid() ShaderHandle {
        return .{ .index = std.math.maxInt(u32), .generation = 0 };
    }

    pub fn isValid(self: ShaderHandle) bool {
        return self.index != std.math.maxInt(u32);
    }
};

pub const MeshInstance = struct {
    mesh_handle: MeshHandle = MeshHandle.invalid(),
    color: common.Color = common.Color.WHITE,
    material: MaterialRef = .default,

    pub const default: MeshInstance = .{
        .mesh_handle = MeshHandle.invalid(),
        .color = common.Color.WHITE,
        .material = .default,
    };
};

pub const MaterialRef = union(enum) {
    default,
    textured: backend.Material,
    shader: ShaderHandle,
};

pub const ShaderInstance = struct {
    shader_handle: ShaderHandle = ShaderHandle.invalid(),

    pub const default: ShaderInstance = .{
        .shader_handle = ShaderHandle.invalid(),
    };
};

pub const MeshLibrary = struct {
    allocator: std.mem.Allocator,
    slots: std.ArrayListUnmanaged(MeshSlot) = .empty,
    free_list: std.ArrayListUnmanaged(u32) = .empty,

    pub fn init(allocator: std.mem.Allocator) MeshLibrary {
        return .{
            .allocator = allocator,
            .slots = .empty,
            .free_list = .empty,
        };
    }

    pub fn deinit(self: *MeshLibrary) void {
        self.slots.deinit(self.allocator);
        self.free_list.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn destroyMeshes(self: *MeshLibrary, renderer: *backend.Renderer) void {
        self.free_list.clearRetainingCapacity();
        for (self.slots.items, 0..) |*slot, index| {
            if (!slot.alive) continue;
            renderer.destroyMesh(&slot.mesh);
            slot.alive = false;
            slot.generation +%= 1;
            _ = self.free_list.append(self.allocator, @intCast(index)) catch {};
        }
    }

    pub fn addMesh(
        self: *MeshLibrary,
        renderer: *backend.Renderer,
        vertices: []const backend.VertexUv,
        indices: []const u16,
    ) !MeshHandle {
        const mesh = try renderer.createMeshUv(vertices, indices);
        if (self.free_list.items.len > 0) {
            const index = self.free_list.pop() orelse unreachable;
            var slot = &self.slots.items[@intCast(index)];
            slot.mesh = mesh;
            slot.alive = true;
            return .{ .index = index, .generation = slot.generation };
        }

        const index: u32 = @intCast(self.slots.items.len);
        try self.slots.append(self.allocator, .{
            .mesh = mesh,
            .generation = 1,
            .alive = true,
        });
        return .{ .index = index, .generation = 1 };
    }

    pub fn addMeshPos3Color(
        self: *MeshLibrary,
        renderer: *backend.Renderer,
        vertices: []const backend.VertexPos3Color,
        indices: []const u16,
    ) !MeshHandle {
        const mesh = try renderer.createMeshPos3Color(vertices, indices);
        if (self.free_list.items.len > 0) {
            const index = self.free_list.pop() orelse unreachable;
            var slot = &self.slots.items[@intCast(index)];
            slot.mesh = mesh;
            slot.alive = true;
            return .{ .index = index, .generation = slot.generation };
        }

        const index: u32 = @intCast(self.slots.items.len);
        try self.slots.append(self.allocator, .{
            .mesh = mesh,
            .generation = 1,
            .alive = true,
        });
        return .{ .index = index, .generation = 1 };
    }

    pub fn get(self: *MeshLibrary, handle: MeshHandle) ?*backend.Mesh {
        const slot = self.slotPtr(handle) orelse return null;
        return &slot.mesh;
    }

    pub fn destroyMesh(self: *MeshLibrary, renderer: *backend.Renderer, handle: MeshHandle) bool {
        const slot = self.slotPtr(handle) orelse return false;
        renderer.destroyMesh(&slot.mesh);
        slot.alive = false;
        slot.generation +%= 1;
        _ = self.free_list.append(self.allocator, handle.index) catch {};
        return true;
    }

    pub fn updateMesh(
        self: *MeshLibrary,
        renderer: *backend.Renderer,
        handle: MeshHandle,
        vertices: []const backend.VertexUv,
        indices: []const u16,
    ) !bool {
        const slot = self.slotPtr(handle) orelse return false;
        try renderer.updateMeshUv(&slot.mesh, vertices, indices);
        return true;
    }

    pub fn updateMeshPos3Color(
        self: *MeshLibrary,
        renderer: *backend.Renderer,
        handle: MeshHandle,
        vertices: []const backend.VertexPos3Color,
        indices: []const u16,
    ) !bool {
        const slot = self.slotPtr(handle) orelse return false;
        try renderer.updateMeshPos3Color(&slot.mesh, vertices, indices);
        return true;
    }

    fn slotPtr(self: *MeshLibrary, handle: MeshHandle) ?*MeshSlot {
        if (!handle.isValid()) return null;
        const index: usize = @intCast(handle.index);
        if (index >= self.slots.items.len) return null;
        const slot = &self.slots.items[index];
        if (!slot.alive or slot.generation != handle.generation) return null;
        return slot;
    }
};

pub const ShaderLibrary = struct {
    allocator: std.mem.Allocator,
    slots: std.ArrayListUnmanaged(ShaderSlot) = .empty,
    free_list: std.ArrayListUnmanaged(u32) = .empty,

    pub fn init(allocator: std.mem.Allocator) ShaderLibrary {
        return .{
            .allocator = allocator,
            .slots = .empty,
            .free_list = .empty,
        };
    }

    pub fn deinit(self: *ShaderLibrary) void {
        self.slots.deinit(self.allocator);
        self.free_list.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn destroyShaders(self: *ShaderLibrary, renderer: *backend.Renderer) void {
        self.free_list.clearRetainingCapacity();
        for (self.slots.items, 0..) |*slot, index| {
            if (!slot.alive) continue;
            renderer.destroyShader(&slot.shader);
            slot.alive = false;
            slot.generation +%= 1;
            _ = self.free_list.append(self.allocator, @intCast(index)) catch {};
        }
    }

    pub fn addShader(self: *ShaderLibrary, shader: backend.Shader) !ShaderHandle {
        if (self.free_list.items.len > 0) {
            const index = self.free_list.pop() orelse unreachable;
            var slot = &self.slots.items[@intCast(index)];
            slot.shader = shader;
            slot.alive = true;
            return .{ .index = index, .generation = slot.generation };
        }

        const index: u32 = @intCast(self.slots.items.len);
        try self.slots.append(self.allocator, .{
            .shader = shader,
            .generation = 1,
            .alive = true,
        });
        return .{ .index = index, .generation = 1 };
    }

    pub fn get(self: *ShaderLibrary, handle: ShaderHandle) ?*backend.Shader {
        const slot = self.slotPtr(handle) orelse return null;
        return &slot.shader;
    }

    pub fn destroyShader(self: *ShaderLibrary, renderer: *backend.Renderer, handle: ShaderHandle) bool {
        const slot = self.slotPtr(handle) orelse return false;
        renderer.destroyShader(&slot.shader);
        slot.alive = false;
        slot.generation +%= 1;
        _ = self.free_list.append(self.allocator, handle.index) catch {};
        return true;
    }

    fn slotPtr(self: *ShaderLibrary, handle: ShaderHandle) ?*ShaderSlot {
        if (!handle.isValid()) return null;
        const index: usize = @intCast(handle.index);
        if (index >= self.slots.items.len) return null;
        const slot = &self.slots.items[index];
        if (!slot.alive or slot.generation != handle.generation) return null;
        return slot;
    }
};

const MeshSlot = struct {
    mesh: backend.Mesh,
    generation: u32,
    alive: bool,
};

const ShaderSlot = struct {
    shader: backend.Shader,
    generation: u32,
    alive: bool,
};

pub const MeshFactory = struct {
    allocator: std.mem.Allocator,
    library: *MeshLibrary,

    pub fn init(allocator: std.mem.Allocator, library: *MeshLibrary) MeshFactory {
        return .{ .allocator = allocator, .library = library };
    }

    pub fn triangle(self: *MeshFactory, renderer: *backend.Renderer) !MeshHandle {
        const vertices = [_]backend.VertexUv{
            .{ .position = .{ 0.0, 0.6 }, .uv = .{ 0.5, 0.0 } },
            .{ .position = .{ -0.6, -0.6 }, .uv = .{ 0.0, 1.0 } },
            .{ .position = .{ 0.6, -0.6 }, .uv = .{ 1.0, 1.0 } },
        };
        const indices = [_]u16{ 0, 1, 2 };
        return self.library.addMesh(renderer, vertices[0..], indices[0..]);
    }

    pub fn quad(self: *MeshFactory, renderer: *backend.Renderer) !MeshHandle {
        const vertices = [_]backend.VertexUv{
            .{ .position = .{ -0.5, -0.5 }, .uv = .{ 0.0, 1.0 } },
            .{ .position = .{ 0.5, -0.5 }, .uv = .{ 1.0, 1.0 } },
            .{ .position = .{ 0.5, 0.5 }, .uv = .{ 1.0, 0.0 } },
            .{ .position = .{ -0.5, 0.5 }, .uv = .{ 0.0, 0.0 } },
        };
        const indices = [_]u16{ 0, 1, 2, 2, 3, 0 };
        return self.library.addMesh(renderer, vertices[0..], indices[0..]);
    }

    pub fn circle(self: *MeshFactory, renderer: *backend.Renderer, radius: f32, segments: u32) !MeshHandle {
        if (segments < 3) return error.InvalidSegments;
        if (radius <= 0.0) return error.InvalidRadius;
        if (segments + 1 > std.math.maxInt(u16)) return error.TooManyVertices;

        const vertex_count: usize = @intCast(segments + 1);
        const index_count: usize = @intCast(segments * 3);

        var vertices = try self.allocator.alloc(backend.VertexUv, vertex_count);
        defer self.allocator.free(vertices);
        var indices = try self.allocator.alloc(u16, index_count);
        defer self.allocator.free(indices);

        vertices[0] = .{ .position = .{ 0.0, 0.0 }, .uv = .{ 0.5, 0.5 } };

        const step = (2.0 * std.math.pi) / @as(f32, @floatFromInt(segments));
        var i: u32 = 0;
        while (i < segments) : (i += 1) {
            const angle = step * @as(f32, @floatFromInt(i));
            const x = std.math.cos(angle) * radius;
            const y = std.math.sin(angle) * radius;
            const u = (x / (radius * 2.0)) + 0.5;
            const v = (y / (radius * 2.0)) + 0.5;
            vertices[@intCast(i + 1)] = .{ .position = .{ x, y }, .uv = .{ u, v } };
        }

        i = 0;
        var idx: usize = 0;
        while (i < segments) : (i += 1) {
            const next = if (i + 1 == segments) 1 else i + 2;
            indices[idx + 0] = 0;
            indices[idx + 1] = @intCast(i + 1);
            indices[idx + 2] = @intCast(next);
            idx += 3;
        }

        return self.library.addMesh(renderer, vertices, indices);
    }

    pub fn cube(_: *MeshFactory, _: *backend.Renderer) !MeshHandle {
        return error.UnsupportedShape;
    }

    pub fn sphere(_: *MeshFactory, _: *backend.Renderer) !MeshHandle {
        return error.UnsupportedShape;
    }

    pub fn cylinder(_: *MeshFactory, _: *backend.Renderer) !MeshHandle {
        return error.UnsupportedShape;
    }
};

// Imports
const std = @import("std");
const builtin = @import("builtin");
const common = @import("common");
const backend = if (builtin.target.cpu.arch.isWasm())
    @import("backend_web.zig")
else
    @import("backend_native.zig");
