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
        shader_handle: render.ShaderHandle = render.ShaderHandle.invalid(),
        mesh_layout: MeshLayout = .Pos3Uv,
    };

    pub const MeshLayout = enum {
        Pos3Uv,
        Pos3NormUv,
        Pos3NormTangentUv,
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
        var prepared = try PreparedImportedScene.prepare(allocator, io, source_path, scene_data, .{
            .mesh_layout = options.mesh_layout,
        });
        defer prepared.deinit();
        return prepared.instantiate(allocator, commands, build_ctx, options);
    }
};

pub const PreparedImportedScene = struct {
    allocator: std.mem.Allocator,
    mesh_layout: ImportedScene.MeshLayout,
    nodes: []PreparedNode = &.{},
    root_node_indices: []u32 = &.{},
    materials: []PreparedMaterial = &.{},
    textures: []?PreparedTexture = &.{},
    meshes: []PreparedMesh = &.{},
    primitives: []PreparedPrimitive = &.{},
    bounds: ImportedScene.Bounds = .{},

    pub const PrepareOptions = struct {
        mesh_layout: ImportedScene.MeshLayout = .Pos3Uv,
        material_overrides: []const MaterialOverride = &.{},
    };

    pub const MaterialOverride = struct {
        material_index: ?u32 = null,
        material_name_equals: ?[]const u8 = null,
        material_name_contains: ?[]const u8 = null,
        alpha_mode: ?render.Material.AlphaMode = null,
        has_metallic_roughness_texture: ?bool = null,
        has_occlusion_texture: ?bool = null,
        has_normal_texture: ?bool = null,
        min_metallic_map_average: ?f32 = null,
        max_metallic_map_average: ?f32 = null,
        min_roughness_map_average: ?f32 = null,
        max_roughness_map_average: ?f32 = null,
        min_base_color_saturation_average: ?f32 = null,
        max_base_color_saturation_average: ?f32 = null,
        metallic_factor: ?f32 = null,
        roughness_factor: ?f32 = null,
        occlusion_strength: ?f32 = null,
        normal_scale: ?f32 = null,
        use_metallic_roughness_texture: ?bool = null,
        use_occlusion_texture: ?bool = null,
        use_normal_texture: ?bool = null,
        double_sided: ?bool = null,
    };

    pub const ApplyState = struct {
        allocator: std.mem.Allocator,
        renderer: ?*render.Renderer = null,
        mesh_library: ?*render.MeshLibrary = null,
        texture_library: ?*render.TextureLibrary = null,
        material_library: ?*render.MaterialLibrary = null,
        node_entities: []u64 = &.{},
        root_entities: []u64 = &.{},
        loaded_textures_srgb: []?render.TextureHandle = &.{},
        loaded_textures_linear: []?render.TextureHandle = &.{},
        scene_materials: []?render.MaterialHandle = &.{},
        default_white_texture: ?render.TextureHandle = null,
        default_flat_normal_texture: ?render.TextureHandle = null,
        mesh_handles: std.ArrayListUnmanaged(render.MeshHandle) = .empty,
        texture_handles: std.ArrayListUnmanaged(render.TextureHandle) = .empty,
        material_handles: std.ArrayListUnmanaged(render.MaterialHandle) = .empty,
        nodes_created: bool = false,
        next_primitive: usize = 0,

        pub fn init(allocator: std.mem.Allocator, prepared: *const PreparedImportedScene) !ApplyState {
            const node_entities = try allocator.alloc(u64, prepared.nodes.len);
            errdefer allocator.free(node_entities);

            const root_entities = try allocator.alloc(u64, prepared.root_node_indices.len);
            errdefer allocator.free(root_entities);

            const loaded_textures_srgb = try allocator.alloc(?render.TextureHandle, prepared.textures.len);
            errdefer allocator.free(loaded_textures_srgb);
            for (loaded_textures_srgb) |*slot| slot.* = null;

            const loaded_textures_linear = try allocator.alloc(?render.TextureHandle, prepared.textures.len);
            errdefer allocator.free(loaded_textures_linear);
            for (loaded_textures_linear) |*slot| slot.* = null;

            const scene_materials = try allocator.alloc(?render.MaterialHandle, prepared.materials.len);
            errdefer allocator.free(scene_materials);
            for (scene_materials) |*slot| slot.* = null;

            return .{
                .allocator = allocator,
                .node_entities = node_entities,
                .root_entities = root_entities,
                .loaded_textures_srgb = loaded_textures_srgb,
                .loaded_textures_linear = loaded_textures_linear,
                .scene_materials = scene_materials,
            };
        }

        fn ensureRuntime(self: *ApplyState, build_ctx: *const render.BuildContext) void {
            if (self.renderer != null) return;
            self.renderer = build_ctx.renderer;
            self.mesh_library = build_ctx.mesh_library;
            self.texture_library = build_ctx.texture_library;
            self.material_library = build_ctx.material_library;
        }

        pub fn progress(self: *const ApplyState, total_primitives: usize) f32 {
            if (total_primitives == 0) return if (self.nodes_created) 1.0 else 0.0;
            return @as(f32, @floatFromInt(self.next_primitive)) / @as(f32, @floatFromInt(total_primitives));
        }

        pub fn deinit(self: *ApplyState) void {
            if (self.renderer) |renderer| {
                const mesh_library = self.mesh_library orelse unreachable;
                const texture_library = self.texture_library orelse unreachable;
                const material_library = self.material_library orelse unreachable;
                for (self.material_handles.items) |handle| {
                    _ = material_library.destroyMaterial(renderer, handle);
                }
                for (self.texture_handles.items) |handle| {
                    _ = texture_library.destroyTexture(renderer, handle);
                }
                for (self.mesh_handles.items) |handle| {
                    _ = mesh_library.destroyMesh(renderer, handle);
                }
            }
            self.mesh_handles.deinit(self.allocator);
            self.texture_handles.deinit(self.allocator);
            self.material_handles.deinit(self.allocator);
            if (self.scene_materials.len > 0) self.allocator.free(self.scene_materials);
            if (self.loaded_textures_linear.len > 0) self.allocator.free(self.loaded_textures_linear);
            if (self.loaded_textures_srgb.len > 0) self.allocator.free(self.loaded_textures_srgb);
            if (self.root_entities.len > 0) self.allocator.free(self.root_entities);
            if (self.node_entities.len > 0) self.allocator.free(self.node_entities);
            self.* = undefined;
        }

        fn finish(self: *ApplyState) !ImportedScene {
            const renderer = self.renderer orelse return error.MissingRenderer;
            const mesh_library = self.mesh_library orelse return error.MissingMeshLibrary;
            const texture_library = self.texture_library orelse return error.MissingTextureLibrary;
            const material_library = self.material_library orelse return error.MissingMaterialLibrary;

            const mesh_handles = try self.mesh_handles.toOwnedSlice(self.allocator);
            errdefer self.allocator.free(mesh_handles);
            const texture_handles = try self.texture_handles.toOwnedSlice(self.allocator);
            errdefer self.allocator.free(texture_handles);
            const material_handles = try self.material_handles.toOwnedSlice(self.allocator);
            errdefer self.allocator.free(material_handles);

            self.mesh_handles = .empty;
            self.texture_handles = .empty;
            self.material_handles = .empty;

            const root_entities = self.root_entities;
            self.root_entities = &.{};

            if (self.scene_materials.len > 0) self.allocator.free(self.scene_materials);
            self.scene_materials = &.{};
            if (self.loaded_textures_linear.len > 0) self.allocator.free(self.loaded_textures_linear);
            self.loaded_textures_linear = &.{};
            if (self.loaded_textures_srgb.len > 0) self.allocator.free(self.loaded_textures_srgb);
            self.loaded_textures_srgb = &.{};
            if (self.node_entities.len > 0) self.allocator.free(self.node_entities);
            self.node_entities = &.{};

            const allocator = self.allocator;
            self.* = undefined;

            return .{
                .allocator = allocator,
                .renderer = renderer,
                .mesh_library = mesh_library,
                .texture_library = texture_library,
                .material_library = material_library,
                .mesh_handles = mesh_handles,
                .texture_handles = texture_handles,
                .material_handles = material_handles,
                .root_entities = root_entities,
            };
        }
    };

    pub fn prepare(
        allocator: std.mem.Allocator,
        io: *const std.Io,
        source_path: ?[]const u8,
        scene_data: *const scene_mod.SceneData,
        options: PrepareOptions,
    ) !PreparedImportedScene {
        var result = PreparedImportedScene{
            .allocator = allocator,
            .mesh_layout = options.mesh_layout,
        };
        errdefer result.deinit();

        result.nodes = try allocator.alloc(PreparedNode, scene_data.nodes.len);
        for (scene_data.nodes, 0..) |node, index| {
            result.nodes[index] = .{
                .parent_index = node.parent_index,
                .local_transform = node.local_transform,
            };
        }

        result.root_node_indices = try collectRootNodes(allocator, scene_data);

        result.textures = try allocator.alloc(?PreparedTexture, scene_data.textures.len);
        for (result.textures) |*slot| slot.* = null;
        for (scene_data.textures, 0..) |_, texture_index| {
            result.textures[texture_index] = try prepareTextureData(allocator, io, source_path, scene_data, @intCast(texture_index));
        }

        result.materials = try allocator.alloc(PreparedMaterial, scene_data.materials.len);
        for (scene_data.materials, 0..) |material, index| {
            var prepared_material = PreparedMaterial.fromScene(material);
            applyMaterialOverrides(
                &prepared_material,
                material,
                @intCast(index),
                result.textures,
                options.material_overrides,
            );
            result.materials[index] = prepared_material;
        }

        var meshes: std.ArrayListUnmanaged(PreparedMesh) = .empty;
        defer meshes.deinit(allocator);
        errdefer for (meshes.items) |*mesh| mesh.deinit(allocator);
        var primitives: std.ArrayListUnmanaged(PreparedPrimitive) = .empty;
        defer primitives.deinit(allocator);

        for (scene_data.nodes, 0..) |node, node_index| {
            const mesh_index = node.mesh_index orelse continue;
            if (mesh_index >= scene_data.meshes.len) continue;
            const mesh_data = scene_data.meshes[mesh_index];
            for (mesh_data.primitives) |primitive| {
                var prepared_mesh = try preparePrimitiveMesh(
                    allocator,
                    scene_data,
                    primitive,
                    &result.bounds,
                    options.mesh_layout,
                );
                errdefer prepared_mesh.deinit(allocator);
                try meshes.append(allocator, prepared_mesh);
                try primitives.append(allocator, .{
                    .node_index = @intCast(node_index),
                    .mesh_index = @intCast(meshes.items.len - 1),
                    .material_index = primitive.material_index,
                });
            }
        }

        result.meshes = try meshes.toOwnedSlice(allocator);
        result.primitives = try primitives.toOwnedSlice(allocator);
        return result;
    }

    pub fn deinit(self: *PreparedImportedScene) void {
        for (self.textures) |*texture| {
            if (texture.*) |*value| value.deinit(self.allocator);
        }
        if (self.textures.len > 0) self.allocator.free(self.textures);
        if (self.materials.len > 0) self.allocator.free(self.materials);
        if (self.root_node_indices.len > 0) self.allocator.free(self.root_node_indices);
        if (self.nodes.len > 0) self.allocator.free(self.nodes);
        for (self.meshes) |*mesh| mesh.deinit(self.allocator);
        if (self.meshes.len > 0) self.allocator.free(self.meshes);
        if (self.primitives.len > 0) self.allocator.free(self.primitives);
        self.* = undefined;
    }

    pub fn beginApply(self: *const PreparedImportedScene, allocator: std.mem.Allocator) !ApplyState {
        return ApplyState.init(allocator, self);
    }

    pub fn applyBatch(
        self: *const PreparedImportedScene,
        commands: anytype,
        build_ctx: *const render.BuildContext,
        options: ImportedScene.Options,
        state: *ApplyState,
        max_primitives: usize,
    ) !bool {
        state.ensureRuntime(build_ctx);

        if (!state.nodes_created) {
            try self.createNodeEntities(commands, options, state);
            if (self.primitives.len == 0) return true;
        }

        const remaining = self.primitives.len -| state.next_primitive;
        const batch_len = @min(max_primitives, remaining);
        var produced: usize = 0;
        while (produced < batch_len) : (produced += 1) {
            const prepared_primitive = self.primitives[state.next_primitive];
            state.next_primitive += 1;

            const prepared_mesh = self.meshes[prepared_primitive.mesh_index];
            const mesh_handle = try createPreparedMesh(build_ctx, prepared_mesh);
            errdefer _ = build_ctx.destroyMesh(mesh_handle);
            try state.mesh_handles.append(state.allocator, mesh_handle);

            var material = render.Material.default;
            var scene_material = render.SceneMaterial.default;
            var color = common.Color.WHITE;
            if (prepared_primitive.material_index) |material_index| {
                if (material_index < self.materials.len) {
                    const prepared_material = self.materials[material_index];
                    color = colorFromFactor(prepared_material.base_color_factor);
                    scene_material = try buildPreparedSceneMaterial(build_ctx, self, prepared_material, state);
                    material.alpha_mode = scene_material.alpha_mode;
                    if (try ensurePreparedSceneMaterial(
                        build_ctx,
                        self,
                        prepared_material,
                        @intCast(material_index),
                        scene_material,
                        state,
                    )) |material_handle| {
                        material = render.Material.withTextured(material_handle);
                        material.alpha_mode = scene_material.alpha_mode;
                    }
                }
            }

            _ = try commands.createEntity(.{
                common.Parent{ .id = state.node_entities[prepared_primitive.node_index] },
                common.LocalTransform.identity(),
                common.Transform{},
                render.MeshInstance{
                    .mesh_handle = mesh_handle,
                    .shader_handle = options.shader_handle,
                    .color = color,
                    .material = material,
                    .scene_material = scene_material,
                },
                render.Layer(0){},
            });
        }

        return state.next_primitive >= self.primitives.len;
    }

    pub fn completeApply(self: *const PreparedImportedScene, state: *ApplyState) !ImportedScene {
        var imported = try state.finish();
        imported.bounds = self.bounds;
        return imported;
    }

    pub fn instantiate(
        self: *const PreparedImportedScene,
        allocator: std.mem.Allocator,
        commands: anytype,
        build_ctx: *const render.BuildContext,
        options: ImportedScene.Options,
    ) !ImportedScene {
        var state = try self.beginApply(allocator);
        errdefer state.deinit();

        while (true) {
            const finished = try self.applyBatch(commands, build_ctx, options, &state, std.math.maxInt(usize));
            if (!finished) continue;
            return self.completeApply(&state);
        }
    }

    fn createNodeEntities(
        self: *const PreparedImportedScene,
        commands: anytype,
        options: ImportedScene.Options,
        state: *ApplyState,
    ) !void {
        for (self.nodes, 0..) |node, index| {
            const entity = try commands.createEntity(.{
                transformFromLocal(node.local_transform),
            });
            state.node_entities[index] = entity;
        }

        for (self.nodes, 0..) |node, index| {
            const parent_entity = if (node.parent_index) |parent_index|
                state.node_entities[parent_index]
            else
                options.parent;
            if (parent_entity) |parent| {
                try commands.addComponents(state.node_entities[index], .{
                    common.Parent{ .id = parent },
                    node.local_transform,
                });
            }
        }

        for (self.root_node_indices, 0..) |node_index, index| {
            state.root_entities[index] = state.node_entities[node_index];
        }
        state.nodes_created = true;
    }
};

const PreparedNode = struct {
    parent_index: ?u32 = null,
    local_transform: common.LocalTransform = .{},
};

const PreparedPrimitive = struct {
    node_index: u32,
    mesh_index: u32,
    material_index: ?u32 = null,
};

const PreparedTexture = struct {
    width: u32,
    height: u32,
    data: []u8,

    fn deinit(self: *PreparedTexture, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
        self.* = undefined;
    }
};

const PreparedMaterial = struct {
    base_color_factor: common.Color.F32 = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 },
    emissive_factor: common.Color.F32 = .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0 },
    metallic_factor: f32 = 1.0,
    roughness_factor: f32 = 1.0,
    normal_scale: f32 = 1.0,
    occlusion_strength: f32 = 1.0,
    alpha_cutoff: f32 = 0.5,
    alpha_mode: render.Material.AlphaMode = .Opaque,
    double_sided: bool = false,
    base_color_texture: ?scene_mod.TextureRef = null,
    metallic_roughness_texture: ?scene_mod.TextureRef = null,
    normal_texture: ?scene_mod.TextureRef = null,
    occlusion_texture: ?scene_mod.TextureRef = null,
    emissive_texture: ?scene_mod.TextureRef = null,

    fn fromScene(material: scene_mod.MaterialData) PreparedMaterial {
        return .{
            .base_color_factor = material.base_color_factor,
            .emissive_factor = material.emissive_factor,
            .metallic_factor = material.metallic_factor,
            .roughness_factor = material.roughness_factor,
            .normal_scale = material.normal_scale,
            .occlusion_strength = material.occlusion_strength,
            .alpha_cutoff = material.alpha_cutoff,
            .alpha_mode = alphaModeFromScene(material.alpha_mode),
            .double_sided = material.double_sided,
            .base_color_texture = material.base_color_texture,
            .metallic_roughness_texture = material.metallic_roughness_texture,
            .normal_texture = material.normal_texture,
            .occlusion_texture = material.occlusion_texture,
            .emissive_texture = material.emissive_texture,
        };
    }
};

const TextureEncoding = enum {
    srgb,
    linear,
};

const PreparedMesh = union(ImportedScene.MeshLayout) {
    Pos3Uv: struct {
        vertices: []render.VertexPos3Uv,
        indices: []u16,
    },
    Pos3NormUv: struct {
        vertices: []render.VertexPos3NormUv,
        indices: []u16,
    },
    Pos3NormTangentUv: struct {
        vertices: []render.VertexPos3NormTangentUv,
        indices: []u16,
    },

    fn deinit(self: *PreparedMesh, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .Pos3Uv => |mesh| {
                allocator.free(mesh.vertices);
                allocator.free(mesh.indices);
            },
            .Pos3NormUv => |mesh| {
                allocator.free(mesh.vertices);
                allocator.free(mesh.indices);
            },
            .Pos3NormTangentUv => |mesh| {
                allocator.free(mesh.vertices);
                allocator.free(mesh.indices);
            },
        }
        self.* = undefined;
    }
};

fn applyMaterialOverrides(
    prepared: *PreparedMaterial,
    source: scene_mod.MaterialData,
    material_index: u32,
    prepared_textures: []const ?PreparedTexture,
    overrides: []const PreparedImportedScene.MaterialOverride,
) void {
    for (overrides) |override| {
        if (!materialOverrideMatches(override, source, prepared.*, material_index, prepared_textures)) continue;

        if (override.metallic_factor) |value| prepared.metallic_factor = std.math.clamp(value, 0.0, 1.0);
        if (override.roughness_factor) |value| prepared.roughness_factor = std.math.clamp(value, 0.0, 1.0);
        if (override.occlusion_strength) |value| prepared.occlusion_strength = std.math.clamp(value, 0.0, 1.0);
        if (override.normal_scale) |value| prepared.normal_scale = value;
        if (override.use_metallic_roughness_texture) |enabled| {
            if (!enabled) prepared.metallic_roughness_texture = null;
        }
        if (override.use_occlusion_texture) |enabled| {
            if (!enabled) prepared.occlusion_texture = null;
        }
        if (override.use_normal_texture) |enabled| {
            if (!enabled) prepared.normal_texture = null;
        }
        if (override.double_sided) |value| prepared.double_sided = value;
    }
}

fn materialOverrideMatches(
    override: PreparedImportedScene.MaterialOverride,
    source: scene_mod.MaterialData,
    prepared: PreparedMaterial,
    material_index: u32,
    prepared_textures: []const ?PreparedTexture,
) bool {
    if (override.material_index) |match_index| {
        if (match_index != material_index) return false;
    }
    if (override.alpha_mode) |alpha_mode| {
        if (prepared.alpha_mode != alpha_mode) return false;
    }
    if (override.material_name_equals) |expected| {
        const name = source.name orelse return false;
        if (!std.mem.eql(u8, name, expected)) return false;
    }
    if (override.material_name_contains) |needle| {
        const name = source.name orelse return false;
        if (std.mem.indexOf(u8, name, needle) == null) return false;
    }
    if (override.has_metallic_roughness_texture) |expected| {
        if ((prepared.metallic_roughness_texture != null) != expected) return false;
    }
    if (override.has_occlusion_texture) |expected| {
        if ((prepared.occlusion_texture != null) != expected) return false;
    }
    if (override.has_normal_texture) |expected| {
        if ((prepared.normal_texture != null) != expected) return false;
    }
    if (override.min_metallic_map_average != null or override.max_metallic_map_average != null or override.min_roughness_map_average != null or override.max_roughness_map_average != null) {
        const metallic_roughness_ref = prepared.metallic_roughness_texture orelse return false;
        const mr_stats = textureStatsForIndex(prepared_textures, metallic_roughness_ref.texture_index) orelse return false;
        if (override.min_metallic_map_average) |min_value| {
            if (mr_stats.blue < min_value) return false;
        }
        if (override.max_metallic_map_average) |max_value| {
            if (mr_stats.blue > max_value) return false;
        }
        if (override.min_roughness_map_average) |min_value| {
            if (mr_stats.green < min_value) return false;
        }
        if (override.max_roughness_map_average) |max_value| {
            if (mr_stats.green > max_value) return false;
        }
    }
    if (override.min_base_color_saturation_average != null or override.max_base_color_saturation_average != null) {
        const base_ref = prepared.base_color_texture orelse return false;
        const base_stats = textureStatsForIndex(prepared_textures, base_ref.texture_index) orelse return false;
        if (override.min_base_color_saturation_average) |min_value| {
            if (base_stats.saturation < min_value) return false;
        }
        if (override.max_base_color_saturation_average) |max_value| {
            if (base_stats.saturation > max_value) return false;
        }
    }
    return true;
}

const TextureStats = struct {
    red: f32,
    green: f32,
    blue: f32,
    saturation: f32,
};

fn textureStatsForIndex(prepared_textures: []const ?PreparedTexture, texture_index: u32) ?TextureStats {
    if (texture_index >= prepared_textures.len) return null;
    const texture = prepared_textures[texture_index] orelse return null;
    if (texture.data.len < 4) return null;
    var sum_r: f32 = 0.0;
    var sum_g: f32 = 0.0;
    var sum_b: f32 = 0.0;
    var sum_sat: f32 = 0.0;
    var count: usize = 0;
    var offset: usize = 0;
    while (offset + 3 < texture.data.len) : (offset += 4) {
        const r: f32 = @floatFromInt(texture.data[offset + 0]);
        const g: f32 = @floatFromInt(texture.data[offset + 1]);
        const b: f32 = @floatFromInt(texture.data[offset + 2]);
        sum_r += r;
        sum_g += g;
        sum_b += b;
        const max_rgb = @max(r, @max(g, b));
        const min_rgb = @min(r, @min(g, b));
        sum_sat += (max_rgb - min_rgb) / 255.0;
        count += 1;
    }
    if (count == 0) return null;
    const inv_count = 1.0 / @as(f32, @floatFromInt(count));
    return .{
        .red = (sum_r * inv_count) / 255.0,
        .green = (sum_g * inv_count) / 255.0,
        .blue = (sum_b * inv_count) / 255.0,
        .saturation = sum_sat * inv_count,
    };
}

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

fn preparePrimitiveMesh(
    allocator: std.mem.Allocator,
    scene_data: *const scene_mod.SceneData,
    primitive: scene_mod.PrimitiveData,
    bounds: *ImportedScene.Bounds,
    mesh_layout: ImportedScene.MeshLayout,
) !PreparedMesh {
    const position_accessor = primitive.position_accessor orelse return error.MissingPositions;
    if (position_accessor.element_type != .Vec3 or position_accessor.component_type != 5126) {
        return error.UnsupportedPositionAccessor;
    }

    const position_meta = scene_data.accessors[position_accessor.accessor_index];
    const position_bytes = scene_data.accessorByteSlice(position_accessor.accessor_index) orelse return error.MissingPositionBytes;
    const vertex_count = position_accessor.count;
    if (vertex_count > std.math.maxInt(u16)) return error.TooManyVertices;

    const uv_accessor = primitive.uv0_accessor;
    const uv_meta = if (uv_accessor) |ref| scene_data.accessors[ref.accessor_index] else null;
    const uv_bytes = if (uv_accessor) |ref| scene_data.accessorByteSlice(ref.accessor_index) else null;

    const indices = try buildIndices(allocator, scene_data, primitive.indices_accessor, vertex_count);
    errdefer allocator.free(indices);

    switch (mesh_layout) {
        .Pos3Uv => {
            const vertices = try allocator.alloc(render.VertexPos3Uv, vertex_count);
            errdefer allocator.free(vertices);

            for (0..vertex_count) |i| {
                const pos = readVec3(position_bytes, positionMetaStride(position_meta), i);
                bounds.include(pos);
                const uv = if (uv_accessor != null and uv_meta != null and uv_bytes != null)
                    readVec2(uv_bytes.?, uvMetaStride(uv_meta.?), i)
                else
                    common.Vec2{};
                vertices[i] = .{
                    .position = .{ pos.x, pos.y, pos.z },
                    .uv = .{ uv.x, uv.y },
                };
            }
            return .{ .Pos3Uv = .{ .vertices = vertices, .indices = indices } };
        },
        .Pos3NormUv => {
            const vertices = try allocator.alloc(render.VertexPos3NormUv, vertex_count);
            errdefer allocator.free(vertices);

            const normal_accessor = primitive.normal_accessor;
            const normal_meta = if (normal_accessor) |ref| scene_data.accessors[ref.accessor_index] else null;
            const normal_bytes = if (normal_accessor) |ref| scene_data.accessorByteSlice(ref.accessor_index) else null;

            for (0..vertex_count) |i| {
                const pos = readVec3(position_bytes, positionMetaStride(position_meta), i);
                bounds.include(pos);
                const normal = if (normal_accessor != null and normal_meta != null and normal_bytes != null)
                    readVec3(normal_bytes.?, positionMetaStride(normal_meta.?), i)
                else
                    common.Vec3{ .x = 0.0, .y = 1.0, .z = 0.0 };
                const uv = if (uv_accessor != null and uv_meta != null and uv_bytes != null)
                    readVec2(uv_bytes.?, uvMetaStride(uv_meta.?), i)
                else
                    common.Vec2{};
                vertices[i] = .{
                    .position = .{ pos.x, pos.y, pos.z },
                    .normal = .{ normal.x, normal.y, normal.z },
                    .uv = .{ uv.x, uv.y },
                };
            }
            return .{ .Pos3NormUv = .{ .vertices = vertices, .indices = indices } };
        },
        .Pos3NormTangentUv => {
            const vertices = try allocator.alloc(render.VertexPos3NormTangentUv, vertex_count);
            errdefer allocator.free(vertices);

            const normal_accessor = primitive.normal_accessor;
            const normal_meta = if (normal_accessor) |ref| scene_data.accessors[ref.accessor_index] else null;
            const normal_bytes = if (normal_accessor) |ref| scene_data.accessorByteSlice(ref.accessor_index) else null;
            const tangent_accessor = primitive.tangent_accessor;
            const tangent_meta = if (tangent_accessor) |ref| scene_data.accessors[ref.accessor_index] else null;
            const tangent_bytes = if (tangent_accessor) |ref| scene_data.accessorByteSlice(ref.accessor_index) else null;

            for (0..vertex_count) |i| {
                const pos = readVec3(position_bytes, positionMetaStride(position_meta), i);
                bounds.include(pos);
                const normal = if (normal_accessor != null and normal_meta != null and normal_bytes != null)
                    readVec3(normal_bytes.?, positionMetaStride(normal_meta.?), i)
                else
                    common.Vec3{ .x = 0.0, .y = 1.0, .z = 0.0 };
                const tangent = if (tangent_accessor != null and tangent_meta != null and tangent_bytes != null)
                    readVec4(tangent_bytes.?, positionMetaStride(tangent_meta.?), i)
                else
                    [4]f32{ 1.0, 0.0, 0.0, 1.0 };
                const uv = if (uv_accessor != null and uv_meta != null and uv_bytes != null)
                    readVec2(uv_bytes.?, uvMetaStride(uv_meta.?), i)
                else
                    common.Vec2{};
                vertices[i] = .{
                    .position = .{ pos.x, pos.y, pos.z },
                    .normal = .{ normal.x, normal.y, normal.z },
                    .tangent = tangent,
                    .uv = .{ uv.x, uv.y },
                };
            }
            return .{ .Pos3NormTangentUv = .{ .vertices = vertices, .indices = indices } };
        },
    }
}

fn createPreparedMesh(build_ctx: *const render.BuildContext, prepared_mesh: PreparedMesh) !render.MeshHandle {
    return switch (prepared_mesh) {
        .Pos3Uv => |mesh| build_ctx.addMeshPos3Uv(mesh.vertices, mesh.indices),
        .Pos3NormUv => |mesh| build_ctx.addMeshPos3NormUv(mesh.vertices, mesh.indices),
        .Pos3NormTangentUv => |mesh| build_ctx.addMeshPos3NormTangentUv(mesh.vertices, mesh.indices),
    };
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
        const stride = scalarStride(meta);
        const out = try allocator.alloc(u16, accessor.count);
        for (0..accessor.count) |i| {
            out[i] = switch (meta.component_type) {
                5121 => readU8(bytes, stride, i),
                5123 => readU16(bytes, stride, i),
                5125 => blk: {
                    const value = readU32(bytes, stride, i);
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

fn buildPreparedSceneMaterial(
    build_ctx: *const render.BuildContext,
    prepared_scene: *const PreparedImportedScene,
    prepared_material: PreparedMaterial,
    state: *PreparedImportedScene.ApplyState,
) !render.SceneMaterial {
    return .{
        .base_color_factor = prepared_material.base_color_factor,
        .emissive_factor = prepared_material.emissive_factor,
        .metallic_factor = prepared_material.metallic_factor,
        .roughness_factor = prepared_material.roughness_factor,
        .normal_scale = prepared_material.normal_scale,
        .occlusion_strength = prepared_material.occlusion_strength,
        .alpha_cutoff = prepared_material.alpha_cutoff,
        .alpha_mode = prepared_material.alpha_mode,
        .double_sided = prepared_material.double_sided,
        .base_color_texture = try preparedSceneTexture(build_ctx, prepared_scene, prepared_material.base_color_texture, state, .srgb),
        .metallic_roughness_texture = try preparedSceneTexture(build_ctx, prepared_scene, prepared_material.metallic_roughness_texture, state, .linear),
        .normal_texture = try preparedSceneTexture(build_ctx, prepared_scene, prepared_material.normal_texture, state, .linear),
        .occlusion_texture = try preparedSceneTexture(build_ctx, prepared_scene, prepared_material.occlusion_texture, state, .linear),
        .emissive_texture = try preparedSceneTexture(build_ctx, prepared_scene, prepared_material.emissive_texture, state, .srgb),
    };
}

fn preparedSceneTexture(
    build_ctx: *const render.BuildContext,
    prepared_scene: *const PreparedImportedScene,
    texture_ref: ?scene_mod.TextureRef,
    state: *PreparedImportedScene.ApplyState,
    encoding: TextureEncoding,
) !render.SceneTexture {
    const texture_data = texture_ref orelse return .{};
    const texture_handle = try ensurePreparedTextureHandle(build_ctx, prepared_scene, texture_data.texture_index, encoding, state) orelse return .{};
    return .{
        .texture_handle = texture_handle,
        .texcoord_set = texture_data.texcoord_set,
    };
}

fn ensurePreparedSceneMaterial(
    build_ctx: *const render.BuildContext,
    prepared_scene: *const PreparedImportedScene,
    prepared_material: PreparedMaterial,
    material_index: u32,
    scene_material: render.SceneMaterial,
    state: *PreparedImportedScene.ApplyState,
) !?render.MaterialHandle {
    if (material_index >= state.scene_materials.len) return null;
    if (state.scene_materials[material_index]) |handle| return handle;

    const default_white = try ensurePreparedDefaultWhiteTexture(build_ctx, state);
    const default_flat_normal = try ensurePreparedDefaultFlatNormalTexture(build_ctx, state);
    _ = scene_material;
    const base_color_handle = if (prepared_material.base_color_texture) |texture_ref|
        (try ensurePreparedTextureHandle(build_ctx, prepared_scene, texture_ref.texture_index, .srgb, state) orelse default_white)
    else
        default_white;
    const metallic_roughness_handle = if (prepared_material.metallic_roughness_texture) |texture_ref|
        (try ensurePreparedTextureHandle(build_ctx, prepared_scene, texture_ref.texture_index, .linear, state) orelse default_white)
    else
        default_white;
    const occlusion_handle = if (prepared_material.occlusion_texture) |texture_ref|
        (try ensurePreparedTextureHandle(build_ctx, prepared_scene, texture_ref.texture_index, .linear, state) orelse default_white)
    else
        default_white;
    const normal_handle = if (prepared_material.normal_texture) |texture_ref|
        (try ensurePreparedTextureHandle(build_ctx, prepared_scene, texture_ref.texture_index, .linear, state) orelse default_flat_normal)
    else
        default_flat_normal;

    const material_handle = try build_ctx.createSceneMaterial(
        base_color_handle,
        metallic_roughness_handle,
        occlusion_handle,
        normal_handle,
        null,
    );
    errdefer _ = build_ctx.destroyMaterial(material_handle);
    try state.material_handles.append(state.allocator, material_handle);
    state.scene_materials[material_index] = material_handle;
    return material_handle;
}

fn ensurePreparedDefaultWhiteTexture(
    build_ctx: *const render.BuildContext,
    state: *PreparedImportedScene.ApplyState,
) !render.TextureHandle {
    if (state.default_white_texture) |handle| return handle;
    const white = [_]u8{ 255, 255, 255, 255 };
    const handle = try build_ctx.createTextureRgba8(1, 1, &white);
    errdefer _ = build_ctx.destroyTexture(handle);
    try state.texture_handles.append(state.allocator, handle);
    state.default_white_texture = handle;
    return handle;
}

fn ensurePreparedDefaultFlatNormalTexture(
    build_ctx: *const render.BuildContext,
    state: *PreparedImportedScene.ApplyState,
) !render.TextureHandle {
    if (state.default_flat_normal_texture) |handle| return handle;
    const flat_normal = [_]u8{ 128, 128, 255, 255 };
    const handle = try build_ctx.createTextureRgba8Linear(1, 1, &flat_normal);
    errdefer _ = build_ctx.destroyTexture(handle);
    try state.texture_handles.append(state.allocator, handle);
    state.default_flat_normal_texture = handle;
    return handle;
}

fn ensurePreparedTextureHandle(
    build_ctx: *const render.BuildContext,
    prepared_scene: *const PreparedImportedScene,
    texture_index: u32,
    encoding: TextureEncoding,
    state: *PreparedImportedScene.ApplyState,
) !?render.TextureHandle {
    const loaded_textures = switch (encoding) {
        .srgb => state.loaded_textures_srgb,
        .linear => state.loaded_textures_linear,
    };
    if (texture_index >= loaded_textures.len) return null;
    if (loaded_textures[texture_index]) |handle| return handle;

    const prepared = prepared_scene.textures[texture_index] orelse return null;
    const texture_handle = switch (encoding) {
        .srgb => try build_ctx.createTextureRgba8(prepared.width, prepared.height, prepared.data),
        .linear => try build_ctx.createTextureRgba8Linear(prepared.width, prepared.height, prepared.data),
    };
    errdefer _ = build_ctx.destroyTexture(texture_handle);
    try state.texture_handles.append(state.allocator, texture_handle);
    switch (encoding) {
        .srgb => state.loaded_textures_srgb[texture_index] = texture_handle,
        .linear => state.loaded_textures_linear[texture_index] = texture_handle,
    }
    return texture_handle;
}

fn prepareTextureData(
    allocator: std.mem.Allocator,
    io: *const std.Io,
    source_path: ?[]const u8,
    scene_data: *const scene_mod.SceneData,
    texture_index: u32,
) !?PreparedTexture {
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
    return .{
        .width = decoded.width,
        .height = decoded.height,
        .data = decoded.data,
    };
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

fn alphaModeFromScene(mode: scene_mod.AlphaMode) render.Material.AlphaMode {
    return switch (mode) {
        .Opaque => .Opaque,
        .Mask => .Mask,
        .Blend => .Blend,
    };
}

fn positionMetaStride(meta: scene_mod.AccessorData) usize {
    if (meta.byte_stride != 0) return meta.byte_stride;
    return switch (meta.component_type) {
        5126 => switch (meta.element_type) {
            .Vec2 => 8,
            .Vec3 => 12,
            .Vec4 => 16,
            else => 4,
        },
        else => scalarStride(meta),
    };
}

fn uvMetaStride(meta: scene_mod.AccessorData) usize {
    if (meta.byte_stride != 0) return meta.byte_stride;
    return switch (meta.component_type) {
        5126 => 8,
        else => scalarStride(meta) * 2,
    };
}

fn scalarStride(meta: scene_mod.AccessorData) usize {
    if (meta.byte_stride != 0) return meta.byte_stride;
    return switch (meta.component_type) {
        5120, 5121 => 1,
        5122, 5123 => 2,
        5125, 5126 => 4,
        else => 4,
    };
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

fn readVec4(bytes: []const u8, stride: usize, index: usize) [4]f32 {
    const base = index * stride;
    return .{
        readF32(bytes, base + 0),
        readF32(bytes, base + 4),
        readF32(bytes, base + 8),
        readF32(bytes, base + 12),
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
