const std = @import("std");
const mesh = @import("mesh.zig");
const build = @import("build.zig");
const backend = if (@import("builtin").target.cpu.arch.isWasm())
    @import("backend_web.zig")
else
    @import("backend_native.zig");

pub const ParticleFacing = enum {
    world,
    billboard,
};

pub const SphereDetail = struct {
    latitude_segments: u16 = 8,
    longitude_segments: u16 = 12,
};

pub const EllipsoidDetail = struct {
    latitude_segments: u16 = 8,
    longitude_segments: u16 = 12,
};

pub const SdfVolume = struct {
    id: u32 = 0,
};

pub const ParticleGeometry = union(enum) {
    quad,
    sprite,
    billboard,
    sphere: SphereDetail,
    ellipsoid: EllipsoidDetail,
    cube,
    custom_mesh: mesh.MeshHandle,
    sdf_volume: SdfVolume,

    pub fn facing(self: ParticleGeometry) ParticleFacing {
        return switch (self) {
            .billboard, .sprite => .billboard,
            else => .world,
        };
    }
};

pub const ResolvedParticleGeometry = struct {
    mesh_handle: mesh.MeshHandle,
    facing: ParticleFacing,
};

pub fn buildParticleGeometry(build_ctx: *const build.BuildContext, geometry: ParticleGeometry) !ResolvedParticleGeometry {
    const mesh_handle = switch (geometry) {
        .quad, .billboard, .sprite => try buildQuad(build_ctx),
        .sphere => |detail| try buildSphere(build_ctx, detail),
        .ellipsoid => |detail| try buildSphere(build_ctx, .{
            .latitude_segments = detail.latitude_segments,
            .longitude_segments = detail.longitude_segments,
        }),
        .cube => try buildCube(build_ctx),
        .custom_mesh => |handle| handle,
        .sdf_volume => return error.UnsupportedParticleGeometry,
    };
    return .{
        .mesh_handle = mesh_handle,
        .facing = geometry.facing(),
    };
}

fn buildQuad(build_ctx: *const build.BuildContext) !mesh.MeshHandle {
    const vertices = [_]backend.VertexPos3Uv{
        .{ .position = .{ -0.5, -0.5, 0.0 }, .uv = .{ 0.0, 1.0 } },
        .{ .position = .{ 0.5, -0.5, 0.0 }, .uv = .{ 1.0, 1.0 } },
        .{ .position = .{ 0.5, 0.5, 0.0 }, .uv = .{ 1.0, 0.0 } },
        .{ .position = .{ -0.5, 0.5, 0.0 }, .uv = .{ 0.0, 0.0 } },
    };
    const indices = [_]u16{ 0, 1, 2, 2, 3, 0 };
    return build_ctx.addMeshPos3Uv(vertices[0..], indices[0..]);
}

fn buildCube(build_ctx: *const build.BuildContext) !mesh.MeshHandle {
    const vertices = [_]backend.VertexPos3Uv{
        .{ .position = .{ -0.5, -0.5, 0.5 }, .uv = .{ 0.0, 1.0 } },
        .{ .position = .{ 0.5, -0.5, 0.5 }, .uv = .{ 1.0, 1.0 } },
        .{ .position = .{ 0.5, 0.5, 0.5 }, .uv = .{ 1.0, 0.0 } },
        .{ .position = .{ -0.5, 0.5, 0.5 }, .uv = .{ 0.0, 0.0 } },
        .{ .position = .{ 0.5, -0.5, -0.5 }, .uv = .{ 0.0, 1.0 } },
        .{ .position = .{ -0.5, -0.5, -0.5 }, .uv = .{ 1.0, 1.0 } },
        .{ .position = .{ -0.5, 0.5, -0.5 }, .uv = .{ 1.0, 0.0 } },
        .{ .position = .{ 0.5, 0.5, -0.5 }, .uv = .{ 0.0, 0.0 } },
        .{ .position = .{ -0.5, -0.5, -0.5 }, .uv = .{ 0.0, 1.0 } },
        .{ .position = .{ -0.5, -0.5, 0.5 }, .uv = .{ 1.0, 1.0 } },
        .{ .position = .{ -0.5, 0.5, 0.5 }, .uv = .{ 1.0, 0.0 } },
        .{ .position = .{ -0.5, 0.5, -0.5 }, .uv = .{ 0.0, 0.0 } },
        .{ .position = .{ 0.5, -0.5, 0.5 }, .uv = .{ 0.0, 1.0 } },
        .{ .position = .{ 0.5, -0.5, -0.5 }, .uv = .{ 1.0, 1.0 } },
        .{ .position = .{ 0.5, 0.5, -0.5 }, .uv = .{ 1.0, 0.0 } },
        .{ .position = .{ 0.5, 0.5, 0.5 }, .uv = .{ 0.0, 0.0 } },
        .{ .position = .{ -0.5, 0.5, 0.5 }, .uv = .{ 0.0, 1.0 } },
        .{ .position = .{ 0.5, 0.5, 0.5 }, .uv = .{ 1.0, 1.0 } },
        .{ .position = .{ 0.5, 0.5, -0.5 }, .uv = .{ 1.0, 0.0 } },
        .{ .position = .{ -0.5, 0.5, -0.5 }, .uv = .{ 0.0, 0.0 } },
        .{ .position = .{ -0.5, -0.5, -0.5 }, .uv = .{ 0.0, 1.0 } },
        .{ .position = .{ 0.5, -0.5, -0.5 }, .uv = .{ 1.0, 1.0 } },
        .{ .position = .{ 0.5, -0.5, 0.5 }, .uv = .{ 1.0, 0.0 } },
        .{ .position = .{ -0.5, -0.5, 0.5 }, .uv = .{ 0.0, 0.0 } },
    };
    const indices = [_]u16{
        0,  1,  2,  2,  3,  0,
        4,  5,  6,  6,  7,  4,
        8,  9,  10, 10, 11, 8,
        12, 13, 14, 14, 15, 12,
        16, 17, 18, 18, 19, 16,
        20, 21, 22, 22, 23, 20,
    };
    return build_ctx.addMeshPos3Uv(vertices[0..], indices[0..]);
}

fn buildSphere(build_ctx: *const build.BuildContext, detail: SphereDetail) !mesh.MeshHandle {
    const lat_segments = @max(detail.latitude_segments, 3);
    const lon_segments = @max(detail.longitude_segments, 3);
    const vertex_count = (@as(usize, lat_segments) + 1) * (@as(usize, lon_segments) + 1);
    const index_count = @as(usize, lat_segments) * @as(usize, lon_segments) * 6;
    if (vertex_count > std.math.maxInt(u16)) return error.TooManyVertices;

    var vertices = try build_ctx.allocator.alloc(backend.VertexPos3Uv, vertex_count);
    defer build_ctx.allocator.free(vertices);
    var indices = try build_ctx.allocator.alloc(u16, index_count);
    defer build_ctx.allocator.free(indices);

    var vtx: usize = 0;
    var lat: u16 = 0;
    while (lat <= lat_segments) : (lat += 1) {
        const v = @as(f32, @floatFromInt(lat)) / @as(f32, @floatFromInt(lat_segments));
        const phi = v * std.math.pi;
        const ring_y = std.math.cos(phi) * 0.5;
        const ring_r = std.math.sin(phi) * 0.5;

        var lon: u16 = 0;
        while (lon <= lon_segments) : (lon += 1) {
            const u = @as(f32, @floatFromInt(lon)) / @as(f32, @floatFromInt(lon_segments));
            const theta = u * (2.0 * std.math.pi);
            vertices[vtx] = .{
                .position = .{
                    std.math.cos(theta) * ring_r,
                    ring_y,
                    std.math.sin(theta) * ring_r,
                },
                .uv = .{ u, v },
            };
            vtx += 1;
        }
    }

    var idx: usize = 0;
    lat = 0;
    while (lat < lat_segments) : (lat += 1) {
        var lon: u16 = 0;
        while (lon < lon_segments) : (lon += 1) {
            const row = @as(u32, lat) * (@as(u32, lon_segments) + 1);
            const next_row = @as(u32, lat + 1) * (@as(u32, lon_segments) + 1);
            const a: u16 = @intCast(row + lon);
            const b: u16 = @intCast(next_row + lon);
            const c: u16 = @intCast(next_row + lon + 1);
            const d: u16 = @intCast(row + lon + 1);
            indices[idx + 0] = a;
            indices[idx + 1] = b;
            indices[idx + 2] = c;
            indices[idx + 3] = a;
            indices[idx + 4] = c;
            indices[idx + 5] = d;
            idx += 6;
        }
    }

    return build_ctx.addMeshPos3Uv(vertices, indices);
}
