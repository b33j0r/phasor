const std = @import("std");
const common = @import("common");
const render = @import("render");
const scene_mod = @import("scene.zig");
const stb_image = @import("stb_image");

pub const ImportedScene = struct {
    allocator: std.mem.Allocator,
    renderer: *render.Renderer,
    mesh_library: *render.MeshLibrary,
    texture_library: *render.TextureLibrary,
    material_library: *render.MaterialLibrary,
    mesh_handles: []render.MeshHandle = &.{},
    texture_handles: []render.TextureHandle = &.{},
    material_handles: []render.MaterialHandle = &.{},
    root_entities: []u64 = &.{},
    bounds: Bounds = .{},

    pub const Options = struct {
        parent: ?u64 = null,
    };

    pub const Bounds = struct {
        min: common.Vec3 = .{},
        max: common.Vec3 = .{},
        valid: bool = false,

        fn include(self: *Bounds, point: common.Vec3) void {
            if (!self.valid) {
                self.min = point;
                self.max = point;
                self.valid = true;
                return;
            }
            self.min.x = @min(self.min.x, point.x);
            self.min.y = @min(self.min.y, point.y);
            self.min.z = @min(self.min.z, point.z);
            self.max.x = @max(self.max.x, point.x);
            self.max.y = @max(self.max.y, point.y);
            self.max.z = @max(self.max.z, point.z);
        }

        pub fn center(self: Bounds) common.Vec3 {
            if (!self.valid) return .{};
            return .{
                .x = (self.min.x + self.max.x) * 0.5,
                .y = (self.min.y + self.max.y) * 0.5,
                .z = (self.min.z + self.max.z) * 0.5,
            };
        }

        pub fn size(self: Bounds) common.Vec3 {
            if (!self.valid) return .{};
            return .{
                .x = self.max.x - self.min.x,
                .y = self.max.y - self.min.y,
                .z = self.max.z - self.min.z,
            };
        }

        pub fn maxDimension(self: Bounds) f32 {
            const extents = self.size();
            return @max(extents.x, @max(extents.y, extents.z));
        }
    };

    pub fn deinit(self: *ImportedScene) void {
        for (self.material_handles) |handle| {
            _ = self.material_library.destroyMaterial(self.renderer, handle);
        }
        self.allocator.free(self.material_handles);

        for (self.texture_handles) |handle| {
            _ = self.texture_library.destroyTexture(self.renderer, handle);
        }
        self.allocator.free(self.texture_handles);

        for (self.mesh_handles) |handle| {
            _ = self.mesh_library.destroyMesh(self.renderer, handle);
        }
        self.allocator.free(self.mesh_handles);
        self.allocator.free(self.root_entities);
        self.* = undefined;
    }

    pub fn instantiate(
        allocator: std.mem.Allocator,
        io: *const std.Io,
        commands: anytype,
        build_ctx: *const render.BuildContext,
        source_path: ?[]const u8,
        scene_data: *const scene_mod.SceneData,
        options: Options,
    ) !ImportedScene {
        const loaded_textures = try allocator.alloc(?render.TextureHandle, scene_data.textures.len);
        defer allocator.free(loaded_textures);
        for (loaded_textures) |*slot| slot.* = null;

        const base_color_materials = try allocator.alloc(?render.MaterialHandle, scene_data.textures.len);
        defer allocator.free(base_color_materials);
        for (base_color_materials) |*slot| slot.* = null;

        var meshes: std.ArrayListUnmanaged(render.MeshHandle) = .empty;
        defer meshes.deinit(allocator);
        var textures: std.ArrayListUnmanaged(render.TextureHandle) = .empty;
        defer textures.deinit(allocator);
        var materials: std.ArrayListUnmanaged(render.MaterialHandle) = .empty;
        defer materials.deinit(allocator);

        errdefer {
            for (materials.items) |handle| {
                _ = build_ctx.material_library.destroyMaterial(build_ctx.renderer, handle);
            }
            for (textures.items) |handle| {
                _ = build_ctx.texture_library.destroyTexture(build_ctx.renderer, handle);
            }
            for (meshes.items) |handle| {
                _ = build_ctx.mesh_library.destroyMesh(build_ctx.renderer, handle);
            }
        }

        var result = ImportedScene{
            .allocator = allocator,
            .renderer = build_ctx.renderer,
            .mesh_library = build_ctx.mesh_library,
            .texture_library = build_ctx.texture_library,
            .material_library = build_ctx.material_library,
        };

        const node_entities = try allocator.alloc(u64, scene_data.nodes.len);
        defer allocator.free(node_entities);

        for (scene_data.nodes, 0..) |node, i| {
            const entity = try commands.createEntity(.{
                transformFromLocal(node.local_transform),
            });
            node_entities[i] = entity;
        }

        for (scene_data.nodes, 0..) |node, i| {
            const parent_entity = if (node.parent_index) |parent_index|
                node_entities[parent_index]
            else
                options.parent;
            if (parent_entity) |parent| {
                try commands.addComponents(node_entities[i], .{
                    common.Parent{ .id = parent },
                    node.local_transform,
                });
            }
        }

        const root_indices = try collectRootNodes(allocator, scene_data);
        defer allocator.free(root_indices);

        const root_entities = try allocator.alloc(u64, root_indices.len);
        for (root_indices, 0..) |node_index, i| {
            root_entities[i] = node_entities[node_index];
        }

        for (scene_data.nodes, 0..) |node, node_index| {
            const mesh_index = node.mesh_index orelse continue;
            if (mesh_index >= scene_data.meshes.len) continue;
            const mesh_data = scene_data.meshes[mesh_index];
            for (mesh_data.primitives) |primitive| {
                const mesh_handle = try buildPrimitiveMesh(allocator, build_ctx, scene_data, primitive, &result.bounds);
                try meshes.append(allocator, mesh_handle);

                var material = render.Material.default;
                var scene_material = render.SceneMaterial.default;
                var color = common.Color.WHITE;
                if (primitive.material_index) |material_index| {
                    if (material_index < scene_data.materials.len) {
                        const imported_material = scene_data.materials[material_index];
                        color = colorFromFactor(imported_material.base_color_factor);
                        scene_material = try buildSceneMaterial(
                            allocator,
                            io,
                            build_ctx,
                            source_path,
                            scene_data,
                            imported_material,
                            loaded_textures,
                            &textures,
                        );
                        material.alpha_mode = scene_material.alpha_mode;
                        if (imported_material.base_color_texture) |base_color_texture| {
                            if (try ensureBaseColorMaterial(
                                allocator,
                                io,
                                build_ctx,
                                source_path,
                                scene_data,
                                base_color_texture.texture_index,
                                loaded_textures,
                                base_color_materials,
                                &textures,
                                &materials,
                            )) |material_handle| {
                                material = render.Material.withTextured(material_handle);
                                material.alpha_mode = scene_material.alpha_mode;
                            }
                        }
                    }
                }

                _ = try commands.createEntity(.{
                    common.Parent{ .id = node_entities[node_index] },
                    common.LocalTransform.identity(),
                    common.Transform{},
                    render.MeshInstance{
                        .mesh_handle = mesh_handle,
                        .color = color,
                        .material = material,
                        .scene_material = scene_material,
                    },
                    render.Layer(0){},
                });
            }
        }

        result.mesh_handles = try meshes.toOwnedSlice(allocator);
        result.texture_handles = try textures.toOwnedSlice(allocator);
        result.material_handles = try materials.toOwnedSlice(allocator);
        result.root_entities = root_entities;
        return result;
    }
};

fn transformFromLocal(local: common.LocalTransform) common.Transform {
    return .{
        .translation = local.translation,
        .rotation = local.rotation,
        .scale = local.scale,
    };
}

fn colorFromFactor(factor: common.Color.F32) common.Color {
    return common.Color.fromColor(factor);
}

fn collectRootNodes(allocator: std.mem.Allocator, scene_data: *const scene_mod.SceneData) ![]u32 {
    if (scene_data.default_scene) |default_scene| {
        if (default_scene < scene_data.scenes.len) {
            return allocator.dupe(u32, scene_data.scenes[default_scene].root_nodes);
        }
    }
    if (scene_data.scenes.len > 0) {
        return allocator.dupe(u32, scene_data.scenes[0].root_nodes);
    }
    var roots: std.ArrayListUnmanaged(u32) = .empty;
    defer roots.deinit(allocator);
    for (scene_data.nodes, 0..) |node, i| {
        if (node.isRoot()) {
            try roots.append(allocator, @intCast(i));
        }
    }
    return roots.toOwnedSlice(allocator);
}

fn buildPrimitiveMesh(
    allocator: std.mem.Allocator,
    build_ctx: *const render.BuildContext,
    scene_data: *const scene_mod.SceneData,
    primitive: scene_mod.PrimitiveData,
    bounds: *ImportedScene.Bounds,
) !render.MeshHandle {
    const position_accessor = primitive.position_accessor orelse return error.MissingPositions;
    if (position_accessor.element_type != .Vec3 or position_accessor.component_type != 5126) {
        return error.UnsupportedPositionAccessor;
    }

    const position_meta = scene_data.accessors[position_accessor.accessor_index];
    const position_bytes = scene_data.accessorByteSlice(position_accessor.accessor_index) orelse return error.MissingPositionBytes;
    const vertex_count = position_accessor.count;
    if (vertex_count > std.math.maxInt(u16)) return error.TooManyVertices;

    var vertices = try allocator.alloc(render.VertexPos3Uv, vertex_count);
    defer allocator.free(vertices);

    const uv_accessor = primitive.uv0_accessor;
    const uv_meta = if (uv_accessor) |ref| scene_data.accessors[ref.accessor_index] else null;
    const uv_bytes = if (uv_accessor) |ref| scene_data.accessorByteSlice(ref.accessor_index) else null;

    for (0..vertex_count) |i| {
        const pos = readVec3(position_bytes, position_meta.byte_stride, i);
        bounds.include(pos);
        const uv = if (uv_accessor != null and uv_meta != null and uv_bytes != null)
            readVec2(uv_bytes.?, uv_meta.?.byte_stride, i)
        else
            common.Vec2{};
        vertices[i] = .{
            .position = .{ pos.x, pos.y, pos.z },
            .uv = .{ uv.x, uv.y },
        };
    }

    const indices = try buildIndices(allocator, scene_data, primitive.indices_accessor, vertex_count);
    defer allocator.free(indices);
    return build_ctx.addMeshPos3Uv(vertices, indices);
}

fn buildIndices(
    allocator: std.mem.Allocator,
    scene_data: *const scene_mod.SceneData,
    indices_accessor: ?scene_mod.AccessorRef,
    vertex_count: usize,
) ![]u16 {
    if (indices_accessor) |accessor| {
        const meta = scene_data.accessors[accessor.accessor_index];
        const bytes = scene_data.accessorByteSlice(accessor.accessor_index) orelse return error.MissingIndexBytes;
        var out = try allocator.alloc(u16, accessor.count);
        for (0..accessor.count) |i| {
            out[i] = switch (meta.component_type) {
                5121 => readU8(bytes, meta.byte_stride, i),
                5123 => readU16(bytes, meta.byte_stride, i),
                5125 => blk: {
                    const value = readU32(bytes, meta.byte_stride, i);
                    if (value > std.math.maxInt(u16)) return error.IndexOutOfRange;
                    break :blk @intCast(value);
                },
                else => return error.UnsupportedIndexAccessor,
            };
        }
        return out;
    }

    const out = try allocator.alloc(u16, vertex_count);
    for (out, 0..) |*dst, i| dst.* = @intCast(i);
    return out;
}

fn buildSceneMaterial(
    allocator: std.mem.Allocator,
    io: *const std.Io,
    build_ctx: *const render.BuildContext,
    source_path: ?[]const u8,
    scene_data: *const scene_mod.SceneData,
    imported_material: scene_mod.MaterialData,
    loaded_textures: []?render.TextureHandle,
    textures: *std.ArrayListUnmanaged(render.TextureHandle),
) !render.SceneMaterial {
    return .{
        .base_color_factor = imported_material.base_color_factor,
        .emissive_factor = imported_material.emissive_factor,
        .metallic_factor = imported_material.metallic_factor,
        .roughness_factor = imported_material.roughness_factor,
        .normal_scale = imported_material.normal_scale,
        .occlusion_strength = imported_material.occlusion_strength,
        .alpha_cutoff = imported_material.alpha_cutoff,
        .alpha_mode = alphaModeFromScene(imported_material.alpha_mode),
        .double_sided = imported_material.double_sided,
        .base_color_texture = try loadSceneTexture(
            allocator,
            io,
            build_ctx,
            source_path,
            scene_data,
            imported_material.base_color_texture,
            loaded_textures,
            textures,
        ),
        .metallic_roughness_texture = try loadSceneTexture(
            allocator,
            io,
            build_ctx,
            source_path,
            scene_data,
            imported_material.metallic_roughness_texture,
            loaded_textures,
            textures,
        ),
        .normal_texture = try loadSceneTexture(
            allocator,
            io,
            build_ctx,
            source_path,
            scene_data,
            imported_material.normal_texture,
            loaded_textures,
            textures,
        ),
        .occlusion_texture = try loadSceneTexture(
            allocator,
            io,
            build_ctx,
            source_path,
            scene_data,
            imported_material.occlusion_texture,
            loaded_textures,
            textures,
        ),
        .emissive_texture = try loadSceneTexture(
            allocator,
            io,
            build_ctx,
            source_path,
            scene_data,
            imported_material.emissive_texture,
            loaded_textures,
            textures,
        ),
    };
}

fn alphaModeFromScene(mode: scene_mod.AlphaMode) render.Material.AlphaMode {
    return switch (mode) {
        .Opaque => .Opaque,
        .Mask => .Mask,
        .Blend => .Blend,
    };
}

fn loadSceneTexture(
    allocator: std.mem.Allocator,
    io: *const std.Io,
    build_ctx: *const render.BuildContext,
    source_path: ?[]const u8,
    scene_data: *const scene_mod.SceneData,
    texture_ref: ?scene_mod.TextureRef,
    loaded_textures: []?render.TextureHandle,
    textures: *std.ArrayListUnmanaged(render.TextureHandle),
) !render.SceneTexture {
    const texture_data = texture_ref orelse return .{};
    const texture_handle = try ensureTextureHandle(
        allocator,
        io,
        build_ctx,
        source_path,
        scene_data,
        texture_data.texture_index,
        loaded_textures,
        textures,
    ) orelse return .{};
    return .{
        .texture_handle = texture_handle,
        .texcoord_set = texture_data.texcoord_set,
    };
}

fn ensureBaseColorMaterial(
    allocator: std.mem.Allocator,
    io: *const std.Io,
    build_ctx: *const render.BuildContext,
    source_path: ?[]const u8,
    scene_data: *const scene_mod.SceneData,
    texture_index: u32,
    loaded_textures: []?render.TextureHandle,
    base_color_materials: []?render.MaterialHandle,
    textures: *std.ArrayListUnmanaged(render.TextureHandle),
    materials: *std.ArrayListUnmanaged(render.MaterialHandle),
) !?render.MaterialHandle {
    if (texture_index >= base_color_materials.len) return null;
    if (base_color_materials[texture_index]) |handle| return handle;

    const texture_handle = try ensureTextureHandle(
        allocator,
        io,
        build_ctx,
        source_path,
        scene_data,
        texture_index,
        loaded_textures,
        textures,
    ) orelse return null;
    const material_handle = try build_ctx.createMaterial(texture_handle, null);
    errdefer _ = build_ctx.destroyMaterial(material_handle);
    try materials.append(allocator, material_handle);
    base_color_materials[texture_index] = material_handle;
    return material_handle;
}

fn ensureTextureHandle(
    allocator: std.mem.Allocator,
    io: *const std.Io,
    build_ctx: *const render.BuildContext,
    source_path: ?[]const u8,
    scene_data: *const scene_mod.SceneData,
    texture_index: u32,
    loaded_textures: []?render.TextureHandle,
    textures: *std.ArrayListUnmanaged(render.TextureHandle),
) !?render.TextureHandle {
    if (texture_index >= loaded_textures.len) return null;
    if (loaded_textures[texture_index]) |handle| return handle;

    const handle = try loadTextureHandle(
        allocator,
        io,
        build_ctx,
        source_path,
        scene_data,
        texture_index,
    ) orelse return null;
    try textures.append(allocator, handle);
    loaded_textures[texture_index] = handle;
    return handle;
}

fn loadTextureHandle(
    allocator: std.mem.Allocator,
    io: *const std.Io,
    build_ctx: *const render.BuildContext,
    source_path: ?[]const u8,
    scene_data: *const scene_mod.SceneData,
    texture_index: u32,
) !?render.TextureHandle {
    if (texture_index >= scene_data.textures.len) return null;
    const texture_data = scene_data.textures[texture_index];
    const image_index = texture_data.image_index orelse return null;
    if (image_index >= scene_data.images.len) return null;
    const image = scene_data.images[image_index];

    const bytes = if (image.bytes) |embedded_bytes|
        try allocator.dupe(u8, embedded_bytes)
    else if (image.buffer_view_index) |buffer_view_index|
        try imageBytesFromBufferView(allocator, scene_data, buffer_view_index)
    else if (image.uri) |uri|
        try readExternalImage(allocator, io, source_path orelse return null, uri)
    else
        return null;
    defer allocator.free(bytes);

    const decoded = try decodeImage(allocator, bytes);
    defer allocator.free(decoded.data);

    const texture_handle = try build_ctx.createTextureRgba8(decoded.width, decoded.height, decoded.data);
    return texture_handle;
}

const DecodedImage = struct {
    width: u32,
    height: u32,
    data: []u8,
};

fn decodeImage(allocator: std.mem.Allocator, bytes: []const u8) !DecodedImage {
    var width: c_int = 0;
    var height: c_int = 0;
    var channels: c_int = 0;
    const data_ptr = stb_image.c.stbi_load_from_memory(bytes.ptr, @intCast(bytes.len), &width, &height, &channels, 4);
    if (data_ptr == null) return error.ImageLoadFailed;
    defer stb_image.c.stbi_image_free(data_ptr);

    const pixel_count: usize = @intCast(width * height);
    const rgba_data = try allocator.alloc(u8, pixel_count * 4);
    const src_data: [*]const u8 = @ptrCast(data_ptr);
    @memcpy(rgba_data, src_data[0 .. pixel_count * 4]);
    return .{
        .width = @intCast(width),
        .height = @intCast(height),
        .data = rgba_data,
    };
}

fn imageBytesFromBufferView(allocator: std.mem.Allocator, scene_data: *const scene_mod.SceneData, buffer_view_index: u32) ![]u8 {
    if (buffer_view_index >= scene_data.buffer_views.len) return error.InvalidBufferView;
    const view = scene_data.buffer_views[buffer_view_index];
    if (view.buffer_index >= scene_data.buffers.len) return error.InvalidBuffer;
    const buffer = scene_data.buffers[view.buffer_index];
    const bytes = buffer.bytes orelse return error.MissingBufferBytes;
    const start = view.byte_offset;
    const end = start + view.byte_length;
    if (end > bytes.len) return error.InvalidBufferView;
    return allocator.dupe(u8, bytes[start..end]);
}

fn readExternalImage(allocator: std.mem.Allocator, io: *const std.Io, source_path: []const u8, uri: []const u8) ![]u8 {
    if (std.mem.startsWith(u8, uri, "data:")) return error.UnsupportedDataUri;
    const scene_dir = std.fs.path.dirname(source_path) orelse return error.InvalidScenePath;
    const absolute_path = try std.fs.path.join(allocator, &.{ scene_dir, uri });
    defer allocator.free(absolute_path);
    return std.Io.Dir.cwd().readFileAlloc(io.*, absolute_path, allocator, std.Io.Limit.limited(32 * 1024 * 1024));
}

fn readVec3(bytes: []const u8, stride: usize, index: usize) common.Vec3 {
    const base = index * stride;
    return .{
        .x = readF32(bytes, base + 0),
        .y = readF32(bytes, base + 4),
        .z = readF32(bytes, base + 8),
    };
}

fn readVec2(bytes: []const u8, stride: usize, index: usize) common.Vec2 {
    const base = index * stride;
    return .{
        .x = readF32(bytes, base + 0),
        .y = readF32(bytes, base + 4),
    };
}

fn readF32(bytes: []const u8, offset: usize) f32 {
    const bits = std.mem.readInt(u32, bytes[offset..][0..4], .little);
    return @bitCast(bits);
}

fn readU8(bytes: []const u8, stride: usize, index: usize) u16 {
    return bytes[index * stride];
}

fn readU16(bytes: []const u8, stride: usize, index: usize) u16 {
    return std.mem.readInt(u16, bytes[index * stride ..][0..2], .little);
}

fn readU32(bytes: []const u8, stride: usize, index: usize) u32 {
    return std.mem.readInt(u32, bytes[index * stride ..][0..4], .little);
}
