const std = @import("std");
const common = @import("common");

pub const AlphaMode = enum {
    Opaque,
    Mask,
    Blend,
};

pub const Topology = enum {
    Triangles,
    TriangleStrip,
    TriangleFan,
    Lines,
    LineStrip,
    Points,
};

pub const BufferSource = enum {
    None,
    ExternalUri,
    DataUri,
    GlbBinary,
};

pub const SceneData = struct {
    allocator: std.mem.Allocator,
    scenes: []SceneDef = &.{},
    default_scene: ?u32 = null,
    nodes: []NodeData = &.{},
    meshes: []MeshData = &.{},
    materials: []MaterialData = &.{},
    textures: []TextureData = &.{},
    images: []ImageData = &.{},
    buffer_views: []BufferViewData = &.{},
    accessors: []AccessorData = &.{},
    buffers: []BufferData = &.{},

    pub fn deinit(self: *SceneData) void {
        for (self.scenes) |*scene| {
            scene.deinit(self.allocator);
        }
        self.allocator.free(self.scenes);

        for (self.nodes) |*node| {
            node.deinit(self.allocator);
        }
        self.allocator.free(self.nodes);

        for (self.meshes) |*mesh| {
            mesh.deinit(self.allocator);
        }
        self.allocator.free(self.meshes);

        for (self.materials) |*material| {
            material.deinit(self.allocator);
        }
        self.allocator.free(self.materials);

        for (self.textures) |*texture| {
            texture.deinit(self.allocator);
        }
        self.allocator.free(self.textures);

        for (self.images) |*image| {
            image.deinit(self.allocator);
        }
        self.allocator.free(self.images);

        self.allocator.free(self.buffer_views);
        self.allocator.free(self.accessors);

        for (self.buffers) |*buffer| {
            buffer.deinit(self.allocator);
        }
        self.allocator.free(self.buffers);

        self.* = undefined;
    }

    pub fn accessorByteSlice(self: *const SceneData, accessor_index: u32) ?[]const u8 {
        if (accessor_index >= self.accessors.len) return null;
        const accessor = self.accessors[accessor_index];
        const view_index = accessor.buffer_view_index orelse return null;
        if (view_index >= self.buffer_views.len) return null;
        const view = self.buffer_views[view_index];
        if (view.buffer_index >= self.buffers.len) return null;
        const buffer = self.buffers[view.buffer_index];
        const bytes = buffer.bytes orelse return null;
        const start = view.byte_offset + accessor.byte_offset;
        const end = start + accessor.byte_length;
        if (end > bytes.len) return null;
        return bytes[start..end];
    }
};

pub const SceneDef = struct {
    name: ?[]u8 = null,
    root_nodes: []u32 = &.{},

    fn deinit(self: *SceneDef, allocator: std.mem.Allocator) void {
        if (self.name) |name| allocator.free(name);
        allocator.free(self.root_nodes);
    }
};

pub const NodeData = struct {
    name: ?[]u8 = null,
    parent_index: ?u32 = null,
    mesh_index: ?u32 = null,
    local_transform: common.LocalTransform = .{},
    children: []u32 = &.{},

    pub fn isRoot(self: NodeData) bool {
        return self.parent_index == null;
    }

    fn deinit(self: *NodeData, allocator: std.mem.Allocator) void {
        if (self.name) |name| allocator.free(name);
        allocator.free(self.children);
    }
};

pub const MeshData = struct {
    name: ?[]u8 = null,
    primitives: []PrimitiveData = &.{},

    fn deinit(self: *MeshData, allocator: std.mem.Allocator) void {
        if (self.name) |name| allocator.free(name);
        allocator.free(self.primitives);
    }
};

pub const PrimitiveData = struct {
    topology: Topology = .Triangles,
    material_index: ?u32 = null,
    indices_accessor: ?AccessorRef = null,
    position_accessor: ?AccessorRef = null,
    normal_accessor: ?AccessorRef = null,
    uv0_accessor: ?AccessorRef = null,
};

pub const AccessorRef = struct {
    accessor_index: u32,
    count: usize,
    component_type: u32,
    element_type: ElementType,
    byte_offset: usize = 0,

    pub const ElementType = enum {
        Scalar,
        Vec2,
        Vec3,
        Vec4,
        Mat2,
        Mat3,
        Mat4,
    };
};

pub const AccessorData = struct {
    buffer_view_index: ?u32 = null,
    count: usize = 0,
    component_type: u32 = 0,
    element_type: AccessorRef.ElementType = .Scalar,
    byte_offset: usize = 0,
    byte_stride: usize = 0,
    byte_length: usize = 0,
    normalized: bool = false,
};

pub const MaterialData = struct {
    name: ?[]u8 = null,
    base_color_factor: [4]f32 = .{ 1.0, 1.0, 1.0, 1.0 },
    base_color_texture: ?TextureRef = null,
    alpha_mode: AlphaMode = .Opaque,
    alpha_cutoff: f32 = 0.5,
    double_sided: bool = false,

    fn deinit(self: *MaterialData, allocator: std.mem.Allocator) void {
        if (self.name) |name| allocator.free(name);
    }
};

pub const TextureData = struct {
    name: ?[]u8 = null,
    image_index: ?u32 = null,

    fn deinit(self: *TextureData, allocator: std.mem.Allocator) void {
        if (self.name) |name| allocator.free(name);
    }
};

pub const TextureRef = struct {
    texture_index: u32,
    texcoord_set: u32 = 0,
};

pub const ImageData = struct {
    name: ?[]u8 = null,
    uri: ?[]u8 = null,
    mime_type: ?[]u8 = null,
    buffer_view_index: ?u32 = null,
    bytes: ?[]u8 = null,

    fn deinit(self: *ImageData, allocator: std.mem.Allocator) void {
        if (self.name) |name| allocator.free(name);
        if (self.uri) |uri| allocator.free(uri);
        if (self.mime_type) |mime_type| allocator.free(mime_type);
        if (self.bytes) |bytes| allocator.free(bytes);
    }
};

pub const BufferViewData = struct {
    buffer_index: u32,
    byte_offset: usize = 0,
    byte_length: usize = 0,
    byte_stride: usize = 0,
};

pub const BufferData = struct {
    uri: ?[]u8 = null,
    byte_length: usize = 0,
    source: BufferSource = .None,
    bytes: ?[]u8 = null,

    fn deinit(self: *BufferData, allocator: std.mem.Allocator) void {
        if (self.uri) |uri| allocator.free(uri);
        if (self.bytes) |bytes| allocator.free(bytes);
    }
};
