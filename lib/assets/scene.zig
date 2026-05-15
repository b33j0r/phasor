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

pub const SamplerFilter = enum {
    nearest,
    linear,
};

pub const SamplerAddressMode = enum {
    clamp_to_edge,
    repeat,
    mirror_repeat,
};

pub const TextureSamplerData = struct {
    mag_filter: SamplerFilter = .linear,
    min_filter: SamplerFilter = .linear,
    mipmap_filter: SamplerFilter = .linear,
    address_mode_u: SamplerAddressMode = .repeat,
    address_mode_v: SamplerAddressMode = .repeat,
    address_mode_w: SamplerAddressMode = .repeat,
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

    pub fn defaultScene(self: *const SceneData) ?*const SceneDef {
        if (self.default_scene) |index| return self.sceneAt(index);
        if (self.scenes.len == 0) return null;
        return &self.scenes[0];
    }

    pub fn sceneAt(self: *const SceneData, index: u32) ?*const SceneDef {
        if (index >= self.scenes.len) return null;
        return &self.scenes[index];
    }

    pub fn nodeAt(self: *const SceneData, index: u32) ?*const NodeData {
        if (index >= self.nodes.len) return null;
        return &self.nodes[index];
    }

    pub fn findNodeNamed(self: *const SceneData, name: []const u8) ?u32 {
        for (self.nodes, 0..) |node, index| {
            const node_name = node.name orelse continue;
            if (std.mem.eql(u8, node_name, name)) return @intCast(index);
        }
        return null;
    }

    pub fn findChildNamed(self: *const SceneData, parent_index: u32, name: []const u8) ?u32 {
        const parent = self.nodeAt(parent_index) orelse return null;
        for (parent.children) |child_index| {
            const child = self.nodeAt(child_index) orelse continue;
            const child_name = child.name orelse continue;
            if (std.mem.eql(u8, child_name, name)) return child_index;
        }
        return null;
    }

    pub fn findNodePath(self: *const SceneData, path: []const []const u8) ?u32 {
        if (path.len == 0) return null;

        const start_scene = self.defaultScene() orelse return null;
        for (start_scene.root_nodes) |root_index| {
            const root = self.nodeAt(root_index) orelse continue;
            const root_name = root.name orelse continue;
            if (!std.mem.eql(u8, root_name, path[0])) continue;

            var current = root_index;
            var matched = true;
            for (path[1..]) |segment| {
                current = self.findChildNamed(current, segment) orelse {
                    matched = false;
                    break;
                };
            }
            if (matched) return current;
        }

        return null;
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
    tangent_accessor: ?AccessorRef = null,
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
    base_color_factor: common.Color.F32 = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 },
    base_color_texture: ?TextureRef = null,
    metallic_factor: f32 = 1.0,
    roughness_factor: f32 = 1.0,
    metallic_roughness_texture: ?TextureRef = null,
    normal_texture: ?TextureRef = null,
    normal_scale: f32 = 1.0,
    occlusion_texture: ?TextureRef = null,
    occlusion_strength: f32 = 1.0,
    emissive_factor: common.Color.F32 = .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0 },
    emissive_texture: ?TextureRef = null,
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
    sampler: TextureSamplerData = .{},

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
