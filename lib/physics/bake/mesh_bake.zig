const std = @import("std");
const common = @import("common");
const components = @import("../components.zig");
const mesh_formats = @import("mesh_formats.zig");

pub const Builder = struct {
    allocator: std.mem.Allocator,
    meshes: std.ArrayListUnmanaged(mesh_formats.Mesh) = .empty,
    vertices: std.ArrayListUnmanaged(mesh_formats.Vertex) = .empty,
    indices: std.ArrayListUnmanaged(u32) = .empty,
    aabb_min: common.Vec3 = .{},
    aabb_max: common.Vec3 = .{},
    has_bounds: bool = false,

    pub fn init(allocator: std.mem.Allocator) Builder {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Builder) void {
        self.meshes.deinit(self.allocator);
        self.vertices.deinit(self.allocator);
        self.indices.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn addTriangleSoup(
        self: *Builder,
        positions: []const common.Vec3,
        triangle_indices: []const u32,
        filter: components.CollisionFilter,
    ) !void {
        const first_vertex: u32 = @intCast(self.vertices.items.len);
        const first_index: u32 = @intCast(self.indices.items.len);

        try self.vertices.ensureUnusedCapacity(self.allocator, positions.len);
        for (positions) |position| {
            self.include(position);
            self.vertices.appendAssumeCapacity(.{ .position = position });
        }

        try self.indices.appendSlice(self.allocator, triangle_indices);
        try self.meshes.append(self.allocator, .{
            .first_vertex = first_vertex,
            .vertex_count = @intCast(positions.len),
            .first_index = first_index,
            .index_count = @intCast(triangle_indices.len),
            .layer = filter.layer,
            .mask = filter.mask,
        });
    }

    pub fn finish(self: *Builder) ![]u8 {
        const total_bytes =
            @sizeOf(mesh_formats.Header) +
            self.meshes.items.len * @sizeOf(mesh_formats.Mesh) +
            self.vertices.items.len * @sizeOf(mesh_formats.Vertex) +
            self.indices.items.len * @sizeOf(u32);

        const bytes = try self.allocator.alloc(u8, total_bytes);
        errdefer self.allocator.free(bytes);

        const header = mesh_formats.Header{
            .mesh_count = @intCast(self.meshes.items.len),
            .vertex_count = @intCast(self.vertices.items.len),
            .index_count = @intCast(self.indices.items.len),
            .aabb_min = self.aabb_min,
            .aabb_max = self.aabb_max,
        };

        var cursor: usize = 0;
        writeValue(bytes, &cursor, header);
        for (self.meshes.items) |mesh| writeValue(bytes, &cursor, mesh);
        for (self.vertices.items) |vertex| writeValue(bytes, &cursor, vertex);
        for (self.indices.items) |index| writeValue(bytes, &cursor, index);
        return bytes;
    }

    fn include(self: *Builder, point: common.Vec3) void {
        if (!self.has_bounds) {
            self.aabb_min = point;
            self.aabb_max = point;
            self.has_bounds = true;
            return;
        }
        self.aabb_min.x = @min(self.aabb_min.x, point.x);
        self.aabb_min.y = @min(self.aabb_min.y, point.y);
        self.aabb_min.z = @min(self.aabb_min.z, point.z);
        self.aabb_max.x = @max(self.aabb_max.x, point.x);
        self.aabb_max.y = @max(self.aabb_max.y, point.y);
        self.aabb_max.z = @max(self.aabb_max.z, point.z);
    }
};

fn writeValue(buffer: []u8, cursor: *usize, value: anytype) void {
    const bytes = std.mem.asBytes(&value);
    @memcpy(buffer[cursor.* .. cursor.* + bytes.len], bytes);
    cursor.* += bytes.len;
}

test "builder round-trips a simple mesh file" {
    var builder = Builder.init(std.testing.allocator);
    defer builder.deinit();

    try builder.addTriangleSoup(
        &.{
            .{ .x = 0.0, .y = 0.0, .z = 0.0 },
            .{ .x = 1.0, .y = 0.0, .z = 0.0 },
            .{ .x = 0.0, .y = 1.0, .z = 0.0 },
        },
        &.{ 0, 1, 2 },
        .{ .layer = 7, .mask = 0x0F },
    );

    const bytes = try builder.finish();
    defer std.testing.allocator.free(bytes);

    var file = try mesh_formats.parseAlloc(std.testing.allocator, bytes);
    defer file.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(u32, 1), file.header.mesh_count);
    try std.testing.expectEqual(@as(u32, 3), file.header.vertex_count);
    try std.testing.expectEqual(@as(u32, 3), file.header.index_count);
    try std.testing.expectEqual(@as(u32, 7), file.meshes[0].layer);
    try std.testing.expectEqual(@as(u32, 0x0F), file.meshes[0].mask);
    try std.testing.expectEqual(@as(f32, 1.0), file.header.aabb_max.x);
    try std.testing.expectEqual(@as(f32, 1.0), file.header.aabb_max.y);
}
