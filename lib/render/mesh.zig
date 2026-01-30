const std = @import("std");
const builtin = @import("builtin");
const common = @import("common");

const backend = if (builtin.target.cpu.arch.isWasm())
    @import("backend_web.zig")
else
    @import("backend_native.zig");

pub const MeshHandle = u32;

pub const MeshInstance = struct {
    mesh_handle: MeshHandle,
    transform: common.Mat4 = common.Mat4.identity(),
    color: common.Color = common.Color.WHITE,
};

pub const MeshLibrary = struct {
    allocator: std.mem.Allocator,
    meshes: std.ArrayListUnmanaged(backend.Mesh) = .empty,

    pub fn init(allocator: std.mem.Allocator) MeshLibrary {
        return .{
            .allocator = allocator,
            .meshes = .empty,
        };
    }

    pub fn deinit(self: *MeshLibrary) void {
        self.meshes.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn destroyMeshes(self: *MeshLibrary, renderer: *backend.Renderer) void {
        for (self.meshes.items) |*mesh| {
            renderer.destroyMesh(mesh);
        }
    }

    pub fn addMesh(
        self: *MeshLibrary,
        renderer: *backend.Renderer,
        vertices: []const backend.VertexUv,
        indices: []const u16,
    ) !MeshHandle {
        const mesh = try renderer.createMesh(vertices, indices);
        try self.meshes.append(self.allocator, mesh);
        return @intCast(self.meshes.items.len - 1);
    }

    pub fn get(self: *MeshLibrary, handle: MeshHandle) ?*backend.Mesh {
        if (handle >= self.meshes.items.len) return null;
        return &self.meshes.items[handle];
    }
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
