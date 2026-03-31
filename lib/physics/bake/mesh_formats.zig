const std = @import("std");
const phasor = @import("phasor");
const common = phasor.common;

pub const magic: u32 = 0x314D4850; // PHM1
pub const version: u16 = 1;

pub const Header = extern struct {
    magic_value: u32 = magic,
    version_value: u16 = version,
    reserved: u16 = 0,
    mesh_count: u32 = 0,
    vertex_count: u32 = 0,
    index_count: u32 = 0,
    flags: u32 = 0,
    aabb_min: common.Vec3 = .{},
    aabb_max: common.Vec3 = .{},
};

pub const Mesh = extern struct {
    first_vertex: u32 = 0,
    vertex_count: u32 = 0,
    first_index: u32 = 0,
    index_count: u32 = 0,
    layer: u32 = 1,
    mask: u32 = 0xFFFF_FFFF,
    flags: u32 = 0,
    reserved: u32 = 0,
};

pub const Vertex = extern struct {
    position: common.Vec3,
};

pub const File = struct {
    header: Header,
    meshes: []Mesh,
    vertices: []Vertex,
    indices: []u32,

    pub fn deinit(self: *File, allocator: std.mem.Allocator) void {
        allocator.free(self.meshes);
        allocator.free(self.vertices);
        allocator.free(self.indices);
        self.* = undefined;
    }
};

pub const Error = std.mem.Allocator.Error || error{
    FileTooSmall,
    BadMagic,
    UnsupportedVersion,
    TruncatedMeshTable,
    TruncatedVertexTable,
    TruncatedIndexTable,
    InvalidMeshRange,
};

pub fn parseAlloc(allocator: std.mem.Allocator, bytes: []const u8) Error!File {
    if (bytes.len < @sizeOf(Header)) return Error.FileTooSmall;

    var cursor: usize = 0;
    const header = std.mem.bytesToValue(Header, bytes[cursor .. cursor + @sizeOf(Header)]);
    cursor += @sizeOf(Header);

    if (header.magic_value != magic) return Error.BadMagic;
    if (header.version_value != version) return Error.UnsupportedVersion;

    const mesh_bytes = @as(usize, header.mesh_count) * @sizeOf(Mesh);
    if (cursor + mesh_bytes > bytes.len) return Error.TruncatedMeshTable;
    const meshes = try allocator.alloc(Mesh, header.mesh_count);
    errdefer allocator.free(meshes);
    for (meshes, 0..) |*dst, i| {
        const start = cursor + i * @sizeOf(Mesh);
        dst.* = std.mem.bytesToValue(Mesh, bytes[start .. start + @sizeOf(Mesh)]);
    }
    cursor += mesh_bytes;

    const vertex_bytes = @as(usize, header.vertex_count) * @sizeOf(Vertex);
    if (cursor + vertex_bytes > bytes.len) return Error.TruncatedVertexTable;
    const vertices = try allocator.alloc(Vertex, header.vertex_count);
    errdefer allocator.free(vertices);
    for (vertices, 0..) |*dst, i| {
        const start = cursor + i * @sizeOf(Vertex);
        dst.* = std.mem.bytesToValue(Vertex, bytes[start .. start + @sizeOf(Vertex)]);
    }
    cursor += vertex_bytes;

    const index_bytes = @as(usize, header.index_count) * @sizeOf(u32);
    if (cursor + index_bytes > bytes.len) return Error.TruncatedIndexTable;
    const indices = try allocator.alloc(u32, header.index_count);
    errdefer allocator.free(indices);
    for (indices, 0..) |*dst, i| {
        const start = cursor + i * @sizeOf(u32);
        dst.* = std.mem.bytesToValue(u32, bytes[start .. start + @sizeOf(u32)]);
    }

    for (meshes) |mesh| {
        if (mesh.first_vertex + mesh.vertex_count > header.vertex_count) return Error.InvalidMeshRange;
        if (mesh.first_index + mesh.index_count > header.index_count) return Error.InvalidMeshRange;
    }

    return .{
        .header = header,
        .meshes = meshes,
        .vertices = vertices,
        .indices = indices,
    };
}
