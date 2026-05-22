pub const std_options = @import("common").logging.moduleStdOptions();

pub const gltf = @import("gltf/root.zig");
pub const scene = @import("scene.zig");
pub const imported_scene = @import("imported_scene.zig");
pub const SceneData = scene.SceneData;
pub const ImportedScene = imported_scene.ImportedScene;
pub const PreparedImportedScene = imported_scene.PreparedImportedScene;
pub const AssetsModule = @import("module.zig").AssetsModule;
pub const AssetsModuleConfig = @import("module.zig").AssetsModuleConfig;
pub const AssetsLoadState = @import("module.zig").AssetsLoadState;
pub const AssetsLoadingPolicy = enum {
    autoload,
    manual,
};
pub const AssetsLoadStage = enum {
    idle,
    bundle_started,
    bundle_planning,
    bundle_plan_complete,
    bundle_executing,
    asset_discovered,
    asset_planned,
    asset_execute,
    scene_prepared,
    scene_instance_gpu_started,
    scene_instance_gpu_progress,
    asset_complete,
    bundle_complete,
};
pub const AssetsProgressEvent = struct {
    bundle_id: u64 = 0,
    asset_name: ?[]const u8 = null,
    stage: AssetsLoadStage = .idle,
    completed_units: u32 = 0,
    total_units: ?u32 = null,
    progress01: f32 = 0.0,
    loaded_assets: u32 = 0,
    total_assets: u32 = 0,
};

pub const AssetTaskNode = struct {
    label: []const u8,
    units: usize = 1,
    children: []AssetTaskNode = &.{},

    pub fn totalUnits(self: *const AssetTaskNode) usize {
        var total = self.units;
        for (self.children) |*child| {
            total += child.totalUnits();
        }
        return total;
    }
};

pub const AssetLoadPlan = struct {
    allocator: std.mem.Allocator,
    root: AssetTaskNode,

    pub fn init(allocator: std.mem.Allocator, label: []const u8) AssetLoadPlan {
        return .{
            .allocator = allocator,
            .root = .{ .label = label, .units = 0 },
        };
    }

    pub fn deinit(self: *AssetLoadPlan) void {
        freeNode(self.allocator, &self.root);
        self.* = undefined;
    }

    pub fn addTask(self: *AssetLoadPlan, label: []const u8, units: usize) !void {
        const old_len = self.root.children.len;
        const next = try self.allocator.realloc(self.root.children, old_len + 1);
        next[old_len] = .{ .label = label, .units = units };
        self.root.children = next;
    }

    pub fn totalUnits(self: *const AssetLoadPlan) usize {
        return self.root.totalUnits();
    }

    fn freeNode(allocator: std.mem.Allocator, node: *AssetTaskNode) void {
        for (node.children) |*child| {
            freeNode(allocator, child);
        }
        if (node.children.len > 0) allocator.free(node.children);
        node.children = &.{};
    }
};

pub const AssetTask = struct {
    completed_units: *usize,
    local_completed: usize = 0,
    total_units: usize = 1,

    pub fn progress(self: *AssetTask, amount: usize) void {
        if (amount == 0) return;
        const remaining = self.total_units -| self.local_completed;
        const applied = @min(amount, remaining);
        self.local_completed += applied;
        self.completed_units.* += applied;
    }

    pub fn complete(self: *AssetTask) void {
        self.progress(self.total_units -| self.local_completed);
    }
};

pub const AssetEmbeddedFile = struct {
    uri: []const u8,
    bytes: []const u8,
};
pub const EmbeddedFile = AssetEmbeddedFile;

pub const SceneLoadRequest = struct {
    allocator: std.mem.Allocator,
    io: *const std.Io,
    bytes: ?[]const u8 = null,
    resolved_path_z: ?[:0]const u8 = null,
    source_name: ?[]const u8 = null,
    embedded_files: []const EmbeddedFile = &.{},
};

pub const SceneLoader = struct {
    name: []const u8,
    extensions: []const []const u8,
    load: *const fn (request: SceneLoadRequest) anyerror!SceneData,

    pub fn supportsExtension(self: SceneLoader, extension: []const u8) bool {
        for (self.extensions) |candidate| {
            if (std.ascii.eqlIgnoreCase(trimLeadingDot(candidate), trimLeadingDot(extension))) return true;
        }
        return false;
    }
};

pub const GltfSceneLoader = struct {
    pub const name = "glTF";
    pub const extensions = [_][]const u8{ "gltf", "glb" };

    pub fn load(request: SceneLoadRequest) !SceneData {
        if (request.bytes) |bytes| {
            var scene_data = try gltf.parseFromBytes(request.allocator, bytes);
            errdefer scene_data.deinit();

            try applyEmbeddedFiles(request.allocator, &scene_data, request.embedded_files);
            if (builtin.target.cpu.arch.isWasm()) {
                if (request.resolved_path_z) |resolved_path| {
                    try applyExternalFiles(request.allocator, request.io, &scene_data, std.mem.sliceTo(resolved_path, 0));
                }
            }
            return scene_data;
        }

        const resolved_path = request.resolved_path_z orelse return error.MissingSceneSource;
        if (builtin.target.cpu.arch.isWasm()) {
            const bytes = try AssetFileIo.readFileAlloc(request.allocator, request.io, resolved_path, max_asset_file_bytes);
            defer request.allocator.free(bytes);

            var scene_data = try gltf.parseFromBytes(request.allocator, bytes);
            errdefer scene_data.deinit();
            try applyExternalFiles(request.allocator, request.io, &scene_data, std.mem.sliceTo(resolved_path, 0));
            return scene_data;
        }

        return gltf.parseFromFile(request.allocator, resolved_path);
    }
};

pub const Scene = struct {
    pub const EmbeddedFile = AssetEmbeddedFile;
    pub const Loader = SceneLoader;
    pub const LoadRequest = SceneLoadRequest;
    pub const PrepareOptions = PreparedImportedScene.PrepareOptions;
    pub const InstantiateOptions = ImportedScene.Options;

    path: ?[:0]const u8 = null,
    data: ?[]const u8 = null,
    source_name: ?[:0]const u8 = null,
    format_hint: ?[]const u8 = null,
    embedded_files: []const AssetEmbeddedFile = &.{},
    loaders: []const SceneLoader = default_scene_loaders,
    mesh_layout: ImportedScene.MeshLayout = .Pos3NormUv,
    material_overrides: []const ImportedScene.MaterialOverride = &.{},
    resolved_path: ?[]u8 = null,
    scene_data: ?SceneData = null,
    prepared_scene: ?PreparedImportedScene = null,
    default_shader_handle: render.ShaderHandle = render.ShaderHandle.invalid(),

    pub const Instance = struct {
        asset: *Scene,
        scene: ?ImportedScene = null,

        pub const __traits__ = .{struct {
            pub const __trait__ = common.Deinit;
        }};

        pub fn deinit(self: *Instance) void {
            if (self.scene) |*scene_value| scene_value.deinit();
            self.scene = null;
        }
    };

    pub const Plan = struct {
        allocator: std.mem.Allocator,
        scene_data: ?SceneData = null,
        prepared_scene: ?PreparedImportedScene = null,
        resolved_path: ?[]u8 = null,
        default_shader_handle: render.ShaderHandle = render.ShaderHandle.invalid(),
        primitive_count: usize = 0,

        pub fn deinit(self: *Plan) void {
            if (self.prepared_scene) |*prepared| {
                prepared.deinit();
                self.prepared_scene = null;
            }
            if (self.scene_data) |*scene_data| {
                scene_data.deinit();
                self.scene_data = null;
            }
            if (self.resolved_path) |resolved_path| {
                self.allocator.free(resolved_path.ptr[0 .. resolved_path.len + 1]);
                self.resolved_path = null;
            }
            self.* = undefined;
        }
    };

    pub fn file(path: [:0]const u8) Scene {
        return .{ .path = path };
    }

    pub fn embedded(bytes: []const u8) Scene {
        return .{ .data = bytes };
    }

    pub fn embeddedNamed(name: [:0]const u8, bytes: []const u8) Scene {
        return .{
            .data = bytes,
            .source_name = name,
        };
    }

    pub fn embeddedWithFiles(bytes: []const u8, embedded_files: []const AssetEmbeddedFile) Scene {
        return .{
            .data = bytes,
            .embedded_files = embedded_files,
        };
    }

    pub fn embeddedNamedWithFiles(name: [:0]const u8, bytes: []const u8, embedded_files: []const AssetEmbeddedFile) Scene {
        return .{
            .data = bytes,
            .source_name = name,
            .embedded_files = embedded_files,
        };
    }

    pub fn withFormat(self: Scene, format_hint: []const u8) Scene {
        var out = self;
        out.format_hint = format_hint;
        return out;
    }

    pub fn withLoaders(self: Scene, comptime loader_types: anytype) Scene {
        var out = self;
        out.loaders = sceneLoaders(loader_types);
        return out;
    }

    pub fn withMeshLayout(self: Scene, mesh_layout: ImportedScene.MeshLayout) Scene {
        var out = self;
        out.mesh_layout = mesh_layout;
        return out;
    }

    pub fn withMaterialOverrides(self: Scene, material_overrides: []const ImportedScene.MaterialOverride) Scene {
        var out = self;
        out.material_overrides = material_overrides;
        return out;
    }

    pub fn load(self: *Scene, ctx: AssetsContext) !void {
        if (self.prepared_scene != null) return;

        var task_completed: usize = 0;
        var task = AssetTask{ .completed_units = &task_completed };
        var load_plan = try self.plan(ctx, &task);
        errdefer load_plan.deinit();
        var execute_task = AssetTask{ .completed_units = &task_completed };
        try self.execute(ctx, &load_plan, &execute_task);
    }

    pub fn plan(self: *Scene, ctx: AssetsContext, task: *AssetTask) !Plan {
        if (self.prepared_scene != null) {
            task.complete();
            return .{ .allocator = ctx.allocator };
        }

        var result = try self.buildPlan(ctx);
        errdefer result.deinit();
        task.complete();
        return result;
    }

    pub fn execute(self: *Scene, ctx: AssetsContext, plan_value: *Plan, task: *AssetTask) !void {
        if (self.prepared_scene != null) {
            task.complete();
            return;
        }

        self.scene_data = plan_value.scene_data orelse return error.MissingScenePlanData;
        plan_value.scene_data = null;
        self.prepared_scene = plan_value.prepared_scene orelse return error.MissingScenePlanData;
        plan_value.prepared_scene = null;
        self.resolved_path = plan_value.resolved_path;
        plan_value.resolved_path = null;
        self.default_shader_handle = plan_value.default_shader_handle;
        if (ctx.core_shaders) |core_shaders| {
            self.default_shader_handle = core_shaders.simple_shadow_lit;
        }

        const source_name = self.sourceName() orelse "<embedded>";
        log.debug(
            "loaded scene asset {s}: meshes={} materials={} primitives={}",
            .{ source_name, self.scene_data.?.meshes.len, self.scene_data.?.materials.len, self.prepared_scene.?.primitives.len },
        );
        task.complete();
    }

    pub fn unload(self: *Scene, ctx: AssetsContext) !void {
        if (self.prepared_scene) |*prepared| {
            prepared.deinit();
            self.prepared_scene = null;
        }
        if (self.scene_data) |*scene_data| {
            scene_data.deinit();
            self.scene_data = null;
            if (self.resolved_path) |resolved_path| {
                log.debug("unloaded scene {s}", .{resolved_path});
            } else {
                log.debug("unloaded embedded scene", .{});
            }
        }
        if (self.resolved_path) |resolved_path| {
            ctx.allocator.free(resolved_path.ptr[0 .. resolved_path.len + 1]);
            self.resolved_path = null;
        }
        self.default_shader_handle = render.ShaderHandle.invalid();
    }

    pub fn isLoaded(self: *const Scene) bool {
        return self.prepared_scene != null;
    }

    pub fn label(self: *const Scene) []const u8 {
        return self.sourceName() orelse "<embedded>";
    }

    pub fn preparedScene(self: *const Scene) ?*const PreparedImportedScene {
        return if (self.prepared_scene) |*prepared| prepared else null;
    }

    pub fn primitiveCount(self: *const Scene) usize {
        const prepared = self.prepared_scene orelse return 0;
        return prepared.primitiveCount();
    }

    pub fn beginApplyState(self: *Scene, allocator: std.mem.Allocator) !PreparedImportedScene.ApplyState {
        const prepared = self.prepared_scene orelse return error.SceneNotLoaded;
        return prepared.beginApply(allocator);
    }

    pub fn sceneData(self: *const Scene) ?*const SceneData {
        return if (self.scene_data) |*data| data else null;
    }

    pub fn meshes(self: *const Scene) []const scene.MeshData {
        const data = self.sceneData() orelse return &.{};
        return data.meshes;
    }

    pub fn materials(self: *const Scene) []const scene.MaterialData {
        const data = self.sceneData() orelse return &.{};
        return data.materials;
    }

    pub fn bounds(self: *const Scene) ImportedScene.Bounds {
        const prepared = self.prepared_scene orelse return .{};
        return prepared.bounds;
    }

    pub fn instance(self: *Scene) Instance {
        return .{ .asset = self };
    }

    pub fn instantiate(
        self: *Scene,
        allocator: std.mem.Allocator,
        commands: anytype,
        build_ctx: *const render.BuildContext,
        options: InstantiateOptions,
    ) !ImportedScene {
        const prepared = &(self.prepared_scene orelse return error.SceneNotLoaded);
        var resolved_options = options;
        if (!resolved_options.shader_handle.isValid()) {
            try build_ctx.ensureCoreSimpleShadowLitShader(&self.default_shader_handle);
            resolved_options.shader_handle = self.default_shader_handle;
        }
        if (!resolved_options.shader_handle.isValid()) return error.MissingSceneShader;
        return prepared.instantiate(allocator, commands, build_ctx, resolved_options);
    }

    pub fn defaultSceneDef(self: *const Scene) ?*const scene.SceneDef {
        const data = self.sceneData() orelse return null;
        return data.defaultScene();
    }

    pub fn findNodeNamed(self: *const Scene, name: []const u8) ?u32 {
        const data = self.sceneData() orelse return null;
        return data.findNodeNamed(name);
    }

    pub fn findNodePath(self: *const Scene, path: []const []const u8) ?u32 {
        const data = self.sceneData() orelse return null;
        return data.findNodePath(path);
    }

    fn loadSceneData(self: *Scene, ctx: AssetsContext) !void {
        if (self.scene_data != null) return;

        var resolved_owned: ?[:0]u8 = null;
        errdefer if (resolved_owned) |value| ctx.allocator.free(value);

        if (self.path) |path| {
            resolved_owned = try AssetFileIo.resolveFileSearch(ctx.allocator, ctx.io, path);
        }

        const source_name = if (resolved_owned) |resolved|
            std.mem.sliceTo(resolved, 0)
        else if (self.source_name) |name|
            std.mem.sliceTo(name, 0)
        else
            null;

        const extension = self.detectFormatExtension(source_name) orelse return error.UnknownSceneFormat;
        const loader = findSceneLoader(self.loaders, extension) orelse return error.SceneFormatNotRegistered;

        self.scene_data = try loader.load(.{
            .allocator = ctx.allocator,
            .io = ctx.io,
            .bytes = self.data,
            .resolved_path_z = resolved_owned,
            .source_name = source_name,
            .embedded_files = self.embedded_files,
        });

        if (resolved_owned) |resolved| {
            self.resolved_path = resolved[0..resolved.len];
        }
    }

    fn buildPlan(self: *Scene, ctx: AssetsContext) !Plan {
        var result = Plan{ .allocator = ctx.allocator };
        errdefer result.deinit();

        var resolved_owned: ?[:0]u8 = null;
        errdefer if (resolved_owned) |value| ctx.allocator.free(value);

        if (self.path) |path| {
            resolved_owned = try AssetFileIo.resolveFileSearch(ctx.allocator, ctx.io, path);
        }

        const source_name = if (resolved_owned) |resolved|
            std.mem.sliceTo(resolved, 0)
        else if (self.source_name) |name|
            std.mem.sliceTo(name, 0)
        else
            null;

        const extension = self.detectFormatExtension(source_name) orelse return error.UnknownSceneFormat;
        const loader = findSceneLoader(self.loaders, extension) orelse return error.SceneFormatNotRegistered;

        result.scene_data = try loader.load(.{
            .allocator = ctx.allocator,
            .io = ctx.io,
            .bytes = self.data,
            .resolved_path_z = resolved_owned,
            .source_name = source_name,
            .embedded_files = self.embedded_files,
        });

        result.prepared_scene = try PreparedImportedScene.prepare(
            ctx.allocator,
            ctx.io,
            if (resolved_owned) |resolved| resolved[0..resolved.len] else null,
            &result.scene_data.?,
            .{
                .mesh_layout = self.mesh_layout,
                .material_overrides = self.material_overrides,
            },
        );
        result.primitive_count = result.prepared_scene.?.primitiveCount();
        if (ctx.core_shaders) |core_shaders| {
            result.default_shader_handle = core_shaders.simple_shadow_lit;
        }
        if (resolved_owned) |resolved| {
            result.resolved_path = resolved[0..resolved.len];
            resolved_owned = null;
        }
        return result;
    }

    fn detectFormatExtension(self: *const Scene, source_name: ?[]const u8) ?[]const u8 {
        if (self.format_hint) |hint| return trimLeadingDot(hint);
        if (source_name) |name| {
            const ext = std.fs.path.extension(name);
            if (ext.len > 0) return trimLeadingDot(ext);
        }
        return null;
    }

    fn sourceName(self: *const Scene) ?[]const u8 {
        if (self.resolved_path) |resolved_path| return resolved_path;
        if (self.source_name) |source_name| return std.mem.sliceTo(source_name, 0);
        if (self.path) |path| return std.mem.sliceTo(path, 0);
        return null;
    }
};

const default_scene_loaders = sceneLoaders(.{GltfSceneLoader});

fn sceneLoaders(comptime loader_types: anytype) []const SceneLoader {
    const descriptors = comptime buildSceneLoaders(loader_types);
    return descriptors[0..];
}

fn buildSceneLoaders(comptime loader_types: anytype) [loader_types.len]SceneLoader {
    var descriptors: [loader_types.len]SceneLoader = undefined;
    inline for (loader_types, 0..) |LoaderType, index| {
        descriptors[index] = sceneLoaderForType(LoaderType);
    }
    return descriptors;
}

fn sceneLoaderForType(comptime LoaderType: type) SceneLoader {
    comptime {
        if (!@hasDecl(LoaderType, "extensions")) {
            @compileError(@typeName(LoaderType) ++ " must declare `pub const extensions`.");
        }
        if (!@hasDecl(LoaderType, "load")) {
            @compileError(@typeName(LoaderType) ++ " must declare `pub fn load(request: SceneLoadRequest) !SceneData`.");
        }
    }

    return .{
        .name = if (@hasDecl(LoaderType, "name")) LoaderType.name else @typeName(LoaderType),
        .extensions = LoaderType.extensions[0..],
        .load = struct {
            fn call(request: SceneLoadRequest) anyerror!SceneData {
                return LoaderType.load(request);
            }
        }.call,
    };
}

fn findSceneLoader(loaders: []const SceneLoader, extension: []const u8) ?SceneLoader {
    for (loaders) |loader| {
        if (loader.supportsExtension(extension)) return loader;
    }
    return null;
}

fn trimLeadingDot(extension: []const u8) []const u8 {
    if (extension.len > 0 and extension[0] == '.') return extension[1..];
    return extension;
}

fn applyEmbeddedFiles(
    allocator: std.mem.Allocator,
    scene_data: *SceneData,
    embedded_files: []const EmbeddedFile,
) !void {
    if (embedded_files.len == 0) return;

    for (scene_data.buffers) |*buffer| {
        if (buffer.bytes != null) continue;
        const uri = buffer.uri orelse continue;
        const bytes = embeddedFileBytes(embedded_files, uri) orelse continue;
        buffer.bytes = try allocator.dupe(u8, bytes);
    }

    for (scene_data.images) |*image| {
        if (image.bytes != null) continue;
        const uri = image.uri orelse continue;
        const bytes = embeddedFileBytes(embedded_files, uri) orelse continue;
        image.bytes = try allocator.dupe(u8, bytes);
    }
}

fn applyExternalFiles(
    allocator: std.mem.Allocator,
    io: *const std.Io,
    scene_data: *SceneData,
    source_path: []const u8,
) !void {
    for (scene_data.buffers) |*buffer| {
        if (buffer.bytes != null) continue;
        const uri = buffer.uri orelse continue;
        if (std.mem.startsWith(u8, uri, "data:")) continue;
        buffer.bytes = try readSiblingAsset(allocator, io, source_path, uri);
    }

    for (scene_data.images) |*image| {
        if (image.bytes != null or image.buffer_view_index != null) continue;
        const uri = image.uri orelse continue;
        if (std.mem.startsWith(u8, uri, "data:")) continue;
        image.bytes = try readSiblingAsset(allocator, io, source_path, uri);
    }
}

fn embeddedFileBytes(embedded_files: []const EmbeddedFile, uri: []const u8) ?[]const u8 {
    for (embedded_files) |file| {
        if (std.mem.eql(u8, file.uri, uri)) return file.bytes;
    }
    return null;
}

pub const AssetsContext = render.AssetsContext;
const max_asset_file_bytes: usize = 128 * 1024 * 1024;

pub const Texture = struct {
    pub const DynamicRange = enum {
        ldr,
        hdr,
    };

    path: ?[:0]const u8 = null,
    data: ?[]const u8 = null,
    alpha_mode: ?render.Material.AlphaMode = null,
    sampler_descriptor: ?render.SamplerDescriptor = null,
    dynamic_range: DynamicRange = .ldr,
    width: u32 = 0,
    height: u32 = 0,
    texture_handle: render.TextureHandle = render.TextureHandle.invalid(),
    material_handle: render.MaterialHandle = render.MaterialHandle.invalid(),
    material: render.Material = render.Material.default,
    owned_sampler: ?render.Sampler = null,

    pub fn embedded(bytes: []const u8) Texture {
        return .{ .data = bytes };
    }

    pub fn file(path: [:0]const u8) Texture {
        return .{ .path = path };
    }

    pub fn withAlphaMode(self: Texture, mode: render.Material.AlphaMode) Texture {
        var out = self;
        out.alpha_mode = mode;
        return out;
    }

    pub fn asOpaque(self: Texture) Texture {
        return self.withAlphaMode(.Opaque);
    }

    pub fn asBlended(self: Texture) Texture {
        return self.withAlphaMode(.Blend);
    }

    pub fn withSampler(self: Texture, descriptor: render.SamplerDescriptor) Texture {
        var out = self;
        out.sampler_descriptor = descriptor;
        return out;
    }

    pub fn asHdr(self: Texture) Texture {
        var out = self;
        out.dynamic_range = .hdr;
        return out;
    }

    pub fn tiledLinear(self: Texture) Texture {
        return self.withSampler(render.SamplerDescriptor.tiledLinear());
    }

    pub fn equirectangularLinear(self: Texture) Texture {
        return self.withSampler(.{
            .mag_filter = .linear,
            .min_filter = .linear,
            .mipmap_filter = .linear,
            .address_mode_u = .repeat,
            .address_mode_v = .clamp_to_edge,
            .address_mode_w = .clamp_to_edge,
        });
    }

    pub fn pixelArtTiled(self: Texture) Texture {
        return self.withSampler(render.SamplerDescriptor.pixelArtTiled());
    }

    pub fn load(self: *Texture, ctx: AssetsContext) !void {
        if (self.material_handle.isValid()) return;

        const renderer = ctx.renderer orelse return error.MissingRenderer;
        const sampler = ctx.sampler orelse return error.MissingSampler;
        const texture_library = ctx.texture_library orelse return error.MissingTextureLibrary;
        const material_library = ctx.material_library orelse return error.MissingMaterialLibrary;

        if (builtin.target.cpu.arch.isWasm() and self.dynamic_range == .hdr and self.path != null) {
            return error.WasmHdrTextureRequiresEmbeddedSource;
        }

        const texture_handle = switch (self.dynamic_range) {
            .ldr => blk: {
                const image = if (builtin.target.cpu.arch.isWasm()) blk2: {
                    const bytes = self.data orelse return error.MissingImageSource;
                    break :blk2 try loadImageFromBytes(ctx.allocator, bytes);
                } else if (self.data) |bytes|
                    try loadImageFromBytes(ctx.allocator, bytes)
                else if (self.path) |path|
                    try loadImage(ctx.allocator, ctx.io, path)
                else
                    return error.MissingImageSource;
                defer ctx.allocator.free(image.data);

                self.width = image.width;
                self.height = image.height;

                const texture = try renderer.createTextureRgba8(self.width, self.height, image.data);
                errdefer {
                    var t = texture;
                    renderer.destroyTexture(&t);
                }
                break :blk try texture_library.addTexture(texture);
            },
            .hdr => blk: {
                const image = if (builtin.target.cpu.arch.isWasm()) blk2: {
                    const bytes = self.data orelse return error.MissingImageSource;
                    break :blk2 try loadHdrImageFromBytes(ctx.allocator, bytes);
                } else if (self.data) |bytes|
                    try loadHdrImageFromBytes(ctx.allocator, bytes)
                else if (self.path) |path|
                    try loadHdrImage(ctx.allocator, ctx.io, path)
                else
                    return error.MissingImageSource;
                defer ctx.allocator.free(image.data);

                self.width = image.width;
                self.height = image.height;

                const texture = try renderer.createTextureRgba16FloatMipmapped(self.width, self.height, image.data);
                errdefer {
                    var t = texture;
                    renderer.destroyTexture(&t);
                }
                break :blk try texture_library.addTexture(texture);
            },
        };
        errdefer _ = texture_library.destroyTexture(renderer, texture_handle);

        var active_sampler = sampler.*;
        var owned_sampler: ?render.Sampler = null;
        if (self.sampler_descriptor) |descriptor| {
            var custom_sampler = try renderer.createSamplerWithDescriptor(descriptor);
            errdefer renderer.destroySampler(&custom_sampler);
            owned_sampler = custom_sampler;
            active_sampler = custom_sampler;
        }

        const texture_ptr = texture_library.get(texture_handle) orelse return error.MissingTexture;
        const material = try renderer.createMaterial(texture_ptr.*, active_sampler);
        errdefer {
            var m = material;
            renderer.destroyMaterial(&m);
        }
        const material_handle = try material_library.addMaterial(material);
        errdefer _ = material_library.destroyMaterial(renderer, material_handle);

        self.texture_handle = texture_handle;
        self.material_handle = material_handle;
        self.owned_sampler = owned_sampler;
        var material_instance = render.Material.withTextured(material_handle);
        if (self.alpha_mode) |mode| {
            material_instance.alpha_mode = mode;
        }
        self.material = material_instance;
        if (self.path) |path| {
            log.debug("loaded texture {s} ({}x{})", .{ std.mem.sliceTo(path, 0), self.width, self.height });
        } else {
            log.debug("loaded embedded texture ({}x{})", .{ self.width, self.height });
        }
    }

    pub fn unload(self: *Texture, ctx: AssetsContext) !void {
        const renderer = ctx.renderer orelse return;
        const texture_library = ctx.texture_library orelse return;
        const material_library = ctx.material_library orelse return;

        if (self.material_handle.isValid()) {
            _ = material_library.destroyMaterial(renderer, self.material_handle);
            self.material_handle = render.MaterialHandle.invalid();
        }
        if (self.texture_handle.isValid()) {
            _ = texture_library.destroyTexture(renderer, self.texture_handle);
            self.texture_handle = render.TextureHandle.invalid();
        }
        if (self.owned_sampler) |owned| {
            var sampler = owned;
            renderer.destroySampler(&sampler);
            self.owned_sampler = null;
        }
        self.material = render.Material.default;
        if (self.path) |path| {
            log.debug("unloaded texture {s}", .{std.mem.sliceTo(path, 0)});
        } else {
            log.debug("unloaded embedded texture", .{});
        }
    }
};

pub const DecodedSound = struct {
    format: u32,
    channels: u32,
    sample_rate: u32,
    frame_count: u64,
    pcm: []f32,
};

pub const Mesh = struct {
    uv_vertices: ?[]const render.VertexUv = null,
    pos3_uv_vertices: ?[]const render.VertexPos3Uv = null,
    pos3_color_vertices: ?[]const render.VertexPos3Color = null,
    indices: []const u16 = &.{},
    handle: render.MeshHandle = render.MeshHandle.invalid(),

    pub fn load(self: *Mesh, ctx: AssetsContext) !void {
        if (self.handle.isValid()) return;
        const renderer = ctx.renderer orelse return error.MissingRenderer;
        const library = ctx.mesh_library orelse return error.MissingMeshLibrary;
        if (self.indices.len == 0) return error.EmptyMeshIndices;

        if (self.uv_vertices) |vertices| {
            self.handle = try library.addMesh(renderer, vertices, self.indices);
            log.debug("loaded uv mesh: vertices={} indices={}", .{ vertices.len, self.indices.len });
            return;
        }
        if (self.pos3_uv_vertices) |vertices| {
            self.handle = try library.addMeshPos3Uv(renderer, vertices, self.indices);
            log.debug("loaded pos3/uv mesh: vertices={} indices={}", .{ vertices.len, self.indices.len });
            return;
        }
        if (self.pos3_color_vertices) |vertices| {
            self.handle = try library.addMeshPos3Color(renderer, vertices, self.indices);
            log.debug("loaded pos3/color mesh: vertices={} indices={}", .{ vertices.len, self.indices.len });
            return;
        }

        return error.MissingMeshVertices;
    }

    pub fn unload(self: *Mesh, ctx: AssetsContext) !void {
        if (!self.handle.isValid()) return;
        const renderer = ctx.renderer orelse return;
        const library = ctx.mesh_library orelse return;
        _ = library.destroyMesh(renderer, self.handle);
        self.handle = render.MeshHandle.invalid();
        log.debug("unloaded mesh", .{});
    }
};

pub const Shader = struct {
    wgsl_source: ?[]const u8 = null,
    glsl_vertex_source: ?[]const u8 = null,
    glsl_fragment_source: ?[]const u8 = null,
    vertex_layout: render.ShaderVertexLayout = .pos3_color4,
    binding_mode: render.ShaderBindingMode = .none,
    handle: render.ShaderHandle = render.ShaderHandle.invalid(),

    pub fn load(self: *Shader, ctx: AssetsContext) !void {
        if (self.handle.isValid()) return;
        const renderer = ctx.renderer orelse return error.MissingRenderer;
        const library = ctx.shader_library orelse return error.MissingShaderLibrary;

        const shader = try renderer.createShader(.{
            .wgsl = self.wgsl_source,
            .glsl_vertex = self.glsl_vertex_source,
            .glsl_fragment = self.glsl_fragment_source,
            .vertex_layout = self.vertex_layout,
            .binding_mode = self.binding_mode,
        });
        self.handle = try library.addShader(shader);
        log.debug("loaded shader", .{});
    }

    pub fn unload(self: *Shader, ctx: AssetsContext) !void {
        if (!self.handle.isValid()) return;
        const renderer = ctx.renderer orelse return;
        const library = ctx.shader_library orelse return;
        _ = library.destroyShader(renderer, self.handle);
        self.handle = render.ShaderHandle.invalid();
        log.debug("unloaded shader", .{});
    }
};

pub const PostProcessShader = struct {
    wgsl_fragment: ?[]const u8 = null,
    handle: render.PostProcessShaderHandle = render.PostProcessShaderHandle.invalid(),
    generated_wgsl: ?[]u8 = null,

    pub fn load(self: *PostProcessShader, ctx: AssetsContext) !void {
        if (self.handle.isValid()) return;
        const renderer = ctx.renderer orelse return error.MissingRenderer;
        const library = ctx.post_process_shader_library orelse return error.MissingPostProcessShaderLibrary;
        const fragment = self.wgsl_fragment orelse return error.MissingShaderSource;

        const wgsl = try render.buildPostProcessWgsl(ctx.allocator, fragment);
        errdefer ctx.allocator.free(wgsl);
        const shader = try renderer.createPostProcessShader(.{ .wgsl = wgsl });
        errdefer {
            var cleanup = shader;
            renderer.destroyPostProcessShader(&cleanup);
        }
        self.generated_wgsl = wgsl;
        self.handle = try library.addShader(shader);
        log.debug("loaded post-process shader", .{});
    }

    pub fn unload(self: *PostProcessShader, ctx: AssetsContext) !void {
        const renderer = ctx.renderer orelse return;
        const library = ctx.post_process_shader_library orelse return;
        if (self.handle.isValid()) {
            _ = library.destroyShader(renderer, self.handle);
            self.handle = render.PostProcessShaderHandle.invalid();
        }
        if (self.generated_wgsl) |wgsl| {
            ctx.allocator.free(wgsl);
            self.generated_wgsl = null;
        }
        log.debug("unloaded post-process shader", .{});
    }
};

pub const Sound = struct {
    path: ?[:0]const u8 = null,
    data: ?[]const u8 = null,
    bytes: ?[]u8 = null,
    decoded: ?DecodedSound = null,
    wasm_id: ?u32 = null,

    pub fn load(self: *Sound, ctx: AssetsContext) !void {
        if (self.data != null or self.bytes != null) return;
        if (self.path) |path| {
            self.bytes = try readFileSearch(ctx.allocator, ctx.io, path);
            log.debug("loaded sound bytes {s} ({d} bytes)", .{ std.mem.sliceTo(path, 0), self.bytes.?.len });
        }
    }

    pub fn unload(self: *Sound, ctx: AssetsContext) !void {
        if (self.decoded) |decoded| {
            ctx.allocator.free(decoded.pcm);
            self.decoded = null;
        }
        if (self.bytes) |bytes| {
            ctx.allocator.free(bytes);
            self.bytes = null;
        }
        if (builtin.target.cpu.arch.isWasm()) {
            if (self.wasm_id) |id| {
                wasmAudioUnload(id);
                self.wasm_id = null;
            }
        }
        if (self.path) |path| {
            log.debug("unloaded sound {s}", .{std.mem.sliceTo(path, 0)});
        } else if (self.data != null) {
            log.debug("unloaded embedded sound", .{});
        }
    }

    pub fn bytesSlice(self: *const Sound) ?[]const u8 {
        if (self.data) |data| return data;
        if (self.bytes) |bytes| return bytes;
        return null;
    }
};

pub const Font = struct {
    name: []const u8 = "Font",
    path: ?[:0]const u8 = null,
    data: ?[]const u8 = null,
    bytes: ?[]u8 = null,
    pixel_height: f32 = 64.0,
    atlas_width: u32 = 512,
    atlas_height: u32 = 512,
    handle: render.FontHandle = render.FontHandle.invalid(),

    pub fn embedded(name: []const u8, bytes: []const u8) Font {
        return .{
            .name = name,
            .data = bytes,
        };
    }

    pub fn file(name: []const u8, path: [:0]const u8) Font {
        return .{
            .name = name,
            .path = path,
        };
    }

    pub fn withPixelHeight(self: Font, pixel_height: f32) Font {
        var out = self;
        out.pixel_height = pixel_height;
        return out;
    }

    pub fn withAtlasSize(self: Font, width: u32, height: u32) Font {
        var out = self;
        out.atlas_width = width;
        out.atlas_height = height;
        return out;
    }

    pub fn load(self: *Font, ctx: AssetsContext) !void {
        if (self.handle.isValid()) return;

        const renderer = ctx.renderer orelse return error.MissingRenderer;
        const sampler = ctx.sampler orelse return error.MissingSampler;
        const font_library = ctx.font_library orelse return error.MissingFontLibrary;

        if (self.data == null and self.bytes == null) {
            if (self.path) |path| {
                self.bytes = try readFileSearch(ctx.allocator, ctx.io, path);
            } else {
                return error.MissingFontSource;
            }
        }

        var font = render.Font{
            .name = self.name,
            .data = if (self.data) |data| data else self.bytes.?,
            .pixel_height = self.pixel_height,
            .atlas_width = self.atlas_width,
            .atlas_height = self.atlas_height,
        };
        try font.load(ctx.allocator, renderer, sampler.*);
        errdefer font.unload(ctx.allocator, renderer);

        self.handle = try font_library.addFont(font);
        log.debug("loaded font {s}", .{self.name});
    }

    pub fn unload(self: *Font, ctx: AssetsContext) !void {
        const renderer = ctx.renderer orelse return;
        const font_library = ctx.font_library orelse return;

        if (self.handle.isValid()) {
            _ = font_library.destroyFont(ctx.allocator, renderer, self.handle);
            self.handle = render.FontHandle.invalid();
        }
        if (self.bytes) |bytes| {
            ctx.allocator.free(bytes);
            self.bytes = null;
        }
        log.debug("unloaded font {s}", .{self.name});
    }
};

const ImageData = struct {
    width: u32,
    height: u32,
    data: []u8,
};

const HdrImageData = struct {
    width: u32,
    height: u32,
    data: []f32,
};

fn loadImageFromBytes(allocator: std.mem.Allocator, bytes: []const u8) !ImageData {
    var width: c_int = 0;
    var height: c_int = 0;
    var channels: c_int = 0;

    const data_ptr = stb_image.c.stbi_load_from_memory(
        bytes.ptr,
        @intCast(bytes.len),
        &width,
        &height,
        &channels,
        4,
    );
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

fn loadImage(allocator: std.mem.Allocator, io: *const std.Io, path: [:0]const u8) !ImageData {
    const bytes = try readFileSearch(allocator, io, path);
    defer allocator.free(bytes);

    var width: c_int = 0;
    var height: c_int = 0;
    var channels: c_int = 0;

    const data_ptr = stb_image.c.stbi_load_from_memory(
        bytes.ptr,
        @intCast(bytes.len),
        &width,
        &height,
        &channels,
        4,
    );
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

fn loadHdrImageFromBytes(allocator: std.mem.Allocator, bytes: []const u8) !HdrImageData {
    var width: c_int = 0;
    var height: c_int = 0;
    var channels: c_int = 0;

    const data_ptr = stb_image.c.stbi_loadf_from_memory(
        bytes.ptr,
        @intCast(bytes.len),
        &width,
        &height,
        &channels,
        4,
    );
    if (data_ptr == null) return error.ImageLoadFailed;
    defer stb_image.c.stbi_image_free(data_ptr);

    const pixel_count: usize = @intCast(width * height);
    const rgba_data = try allocator.alloc(f32, pixel_count * 4);
    const src_data: [*]const f32 = @ptrCast(@alignCast(data_ptr));
    @memcpy(rgba_data, src_data[0 .. pixel_count * 4]);

    return .{
        .width = @intCast(width),
        .height = @intCast(height),
        .data = rgba_data,
    };
}

fn loadHdrImage(allocator: std.mem.Allocator, io: *const std.Io, path: [:0]const u8) !HdrImageData {
    const bytes = try readFileSearch(allocator, io, path);
    defer allocator.free(bytes);
    return loadHdrImageFromBytes(allocator, bytes);
}

fn readFileSearch(allocator: std.mem.Allocator, io: *const std.Io, path: [:0]const u8) ![]u8 {
    const max_bytes: usize = max_asset_file_bytes;
    const resolved = try AssetFileIo.resolveFileSearch(allocator, io, path);
    defer allocator.free(resolved);
    return AssetFileIo.readFileAlloc(allocator, io, resolved, max_bytes);
}

const AssetFileIo = if (builtin.target.cpu.arch.isWasm()) AssetFileIoWasm else AssetFileIoNative;

const AssetFileIoNative = struct {
    fn resolveFileSearch(allocator: std.mem.Allocator, io: *const std.Io, path: [:0]const u8) ![:0]u8 {
        const rel_path = std.mem.sliceTo(path, 0);

        if (std.fs.path.isAbsolute(rel_path)) {
            if (fileExists(io, rel_path)) {
                return try allocator.dupeSentinel(u8, rel_path, 0);
            }
        }

        if (fileExists(io, rel_path)) {
            return try allocator.dupeSentinel(u8, rel_path, 0);
        }

        const cwd_path = std.Io.Dir.cwd().realPathFileAlloc(io.*, ".", allocator) catch null;
        defer if (cwd_path) |p| allocator.free(p);

        var base: ?[]const u8 = if (cwd_path) |p| p else null;
        var depth: usize = 0;
        while (base) |dir| : (depth += 1) {
            if (depth > 4) break;
            const candidate = try std.fs.path.join(allocator, &.{ dir, rel_path });
            defer allocator.free(candidate);

            if (fileExists(io, candidate)) {
                return try allocator.dupeSentinel(u8, candidate, 0);
            }

            base = std.fs.path.dirname(dir);
        }

        return error.FileNotFound;
    }

    fn readFileAlloc(allocator: std.mem.Allocator, io: *const std.Io, absolute_path: []const u8, max_bytes: usize) ![]u8 {
        return std.Io.Dir.cwd().readFileAlloc(io.*, absolute_path, allocator, std.Io.Limit.limited(max_bytes));
    }

    fn fileExists(io: *const std.Io, absolute_path: []const u8) bool {
        std.Io.Dir.cwd().access(io.*, absolute_path, .{}) catch return false;
        return true;
    }
};

const AssetFileIoWasm = struct {
    fn resolveFileSearch(allocator: std.mem.Allocator, io: *const std.Io, path: [:0]const u8) ![:0]u8 {
        _ = io;
        const rel_path = std.mem.sliceTo(path, 0);
        if (fileExists(null, rel_path)) return try allocator.dupeSentinel(u8, rel_path, 0);
        return error.FileNotFound;
    }

    fn readFileAlloc(allocator: std.mem.Allocator, io: *const std.Io, path: []const u8, max_bytes: usize) ![]u8 {
        _ = io;
        const len_i32 = wasmAssetFileSize(path.ptr, path.len);
        if (len_i32 < 0) return error.FileNotFound;
        const len: usize = @intCast(len_i32);
        if (len > max_bytes) return error.FileTooBig;

        const bytes = try allocator.alloc(u8, len);
        errdefer allocator.free(bytes);
        if (len == 0) return bytes;

        const read_len_i32 = wasmAssetReadFile(path.ptr, path.len, bytes.ptr, bytes.len);
        if (read_len_i32 < 0) return error.FileNotFound;
        const read_len: usize = @intCast(read_len_i32);
        if (read_len != len) return error.ShortRead;
        return bytes;
    }

    fn fileExists(_: ?*const std.Io, path: []const u8) bool {
        return wasmAssetFileSize(path.ptr, path.len) >= 0;
    }

    extern "env" fn wasmAssetFileSize(path_ptr: [*]const u8, path_len: usize) i32;
    extern "env" fn wasmAssetReadFile(path_ptr: [*]const u8, path_len: usize, dst_ptr: [*]u8, dst_len: usize) i32;
};

fn readSiblingAsset(
    allocator: std.mem.Allocator,
    io: *const std.Io,
    source_path: []const u8,
    uri: []const u8,
) ![]u8 {
    const scene_dir = std.fs.path.dirname(source_path) orelse return error.InvalidScenePath;
    const path = try std.fs.path.join(allocator, &.{ scene_dir, uri });
    defer allocator.free(path);
    return AssetFileIo.readFileAlloc(allocator, io, path, max_asset_file_bytes);
}

fn readFileAllocAbsolute(
    allocator: std.mem.Allocator,
    io: *const std.Io,
    absolute_path: []const u8,
    max_bytes: usize,
) ![]u8 {
    return AssetFileIo.readFileAlloc(allocator, io, absolute_path, max_bytes);
}

fn fileExistsAbsolute(io: *const std.Io, absolute_path: []const u8) bool {
    return AssetFileIo.fileExists(io, absolute_path);
}

extern "env" fn wasmAudioUnload(id: u32) void;

// Imports
const std = @import("std");
const common = @import("common");
const render = @import("render");
const builtin = @import("builtin");
const stb_image = @import("stb_image");
const log = std.log.scoped(.assets);

test "import tests" {
    _ = gltf;
    _ = common;
    _ = Scene;
}

test "asset load plan composes task units" {
    var plan = AssetLoadPlan.init(std.testing.allocator, "bundle");
    defer plan.deinit();

    try plan.addTask("plan", 2);
    try plan.addTask("execute", 5);
    try std.testing.expectEqual(@as(usize, 7), plan.totalUnits());

    var completed: usize = 0;
    var task = AssetTask{ .completed_units = &completed, .total_units = 3 };
    task.progress(1);
    task.complete();
    try std.testing.expectEqual(@as(usize, 3), completed);
}
