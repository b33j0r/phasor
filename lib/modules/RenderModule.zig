//! ECS render module that manages a renderer and draws MeshInstance components.
pub const RenderSurface = struct {
    target: render.SurfaceTarget,
};

pub const RenderState = struct {
    renderer: render.Renderer,
    surface: render.SurfaceTarget,
    default_sampler: render.Sampler,
    default_texture: render.Texture,
    default_material: render.Material,

    pub fn deinit(self: *RenderState) void {
        self.renderer.destroyMaterial(&self.default_material);
        self.renderer.destroyTexture(&self.default_texture);
        self.renderer.destroySampler(&self.default_sampler);
        self.renderer.deinit();
        self.* = undefined;
    }
};

pub const ViewportSize = struct {
    width: f32,
    height: f32,
};

pub const LayerCameras = struct {
    allocator: std.mem.Allocator,
    map: std.AutoHashMap(i32, LayerCamera),

    pub fn init(allocator: std.mem.Allocator) LayerCameras {
        return .{
            .allocator = allocator,
            .map = std.AutoHashMap(i32, LayerCamera).init(allocator),
        };
    }

    pub fn deinit(self: *LayerCameras) void {
        self.map.deinit();
        self.* = undefined;
    }

    pub fn clear(self: *LayerCameras) void {
        self.map.clearRetainingCapacity();
    }
};

const LayerCamera = struct {
    camera: common.Camera3d,
    view: common.Mat4,
};

pub fn install(app: *AppCommands, commands: *Commands) !void {
    if (!commands.hasResource(common.ClearColor)) {
        try commands.insertResource(common.ClearColor{});
    }
    if (!commands.hasResource(render.RenderQueue)) {
        try commands.insertResource(render.RenderQueue.init(commands.allocator));
    }
    if (!commands.hasResource(LayerCameras)) {
        try commands.insertResource(LayerCameras.init(commands.allocator));
    }
    try commands.registerEvent(common.WindowResized, 8);
    if (!commands.isEmpty()) {
        try commands.apply();
    }

    try app.addSystem("Startup", initSystem);
    try app.addSystem("Startup", ensureAssetsContextSystem);
    try app.addSystem("BeforeFrame", handleViewportResize);
    try app.addSystem("BeforeFrame", updateSpriteMeshes);
    try app.addSystem("BeforeFrame", updateTextMeshes);
    try app.addSystem("BeforeFrame", updateLayerCameras);
    try app.addSystem("BeforeFrame", extractSystem);
    try app.addSystem("AfterFrame", renderSystem);
    try app.addSystem("Shutdown", shutdownSystem);
}

pub fn uninstall(app: *AppCommands) void {
    app.removeSystem(initSystem);
    app.removeSystem(ensureAssetsContextSystem);
    app.removeSystem(handleViewportResize);
    app.removeSystem(updateSpriteMeshes);
    app.removeSystem(updateTextMeshes);
    app.removeSystem(updateLayerCameras);
    app.removeSystem(extractSystem);
    app.removeSystem(renderSystem);
    app.removeSystem(shutdownSystem);
}

fn initSystem(commands: *Commands) !void {
    if (commands.getResource(RenderState) != null) return;

    const surface_res = commands.getResource(RenderSurface) orelse return;
    var config = if (commands.getResource(render.RendererConfig)) |cfg|
        cfg.*
    else
        render.RendererConfig{};
    if (commands.getResource(render.VSync)) |vsync| {
        if (config.present_mode == null) {
            config.present_mode = render.configForVsync(vsync.enabled).present_mode;
        }
    }

    var renderer = try render.Renderer.init(commands.allocator, surface_res.target, config);
    errdefer renderer.deinit();

    var sampler = try renderer.createSampler();
    errdefer renderer.destroySampler(&sampler);

    const white = [_]u8{ 255, 255, 255, 255 };
    var texture = try renderer.createTextureRgba8(1, 1, white[0..]);
    errdefer renderer.destroyTexture(&texture);

    const material = try renderer.createMaterial(texture, sampler);

    var font = render.Font.orbitronDefault();
    try font.load(commands.allocator, &renderer, sampler);
    errdefer font.unload(commands.allocator, &renderer);

    try commands.insertResource(RenderState{
        .renderer = renderer,
        .surface = surface_res.target,
        .default_sampler = sampler,
        .default_texture = texture,
        .default_material = material,
    });

    try commands.insertResource(render.DefaultFont{ .font = font });

    if (!commands.hasResource(render.MeshLibrary)) {
        try commands.insertResource(render.MeshLibrary.init(commands.allocator));
    }
}

fn ensureAssetsContextSystem(commands: *Commands) !void {
    if (commands.hasResource(assets.AssetsContext)) return;
    const state = commands.getResourceMut(RenderState) orelse return;
    try commands.insertResource(assets.AssetsContext{
        .allocator = commands.allocator,
        .io = commands.io,
        .renderer = &state.renderer,
        .sampler = &state.default_sampler,
    });
}

fn extractSystem(
    queue: ResMut(render.RenderQueue),
    mesh_query: Query(.{ render.MeshInstance, common.Transform, render.MaterialInstance }),
    mesh_default_query: Query(.{ render.MeshInstance, common.Transform, Without(render.MaterialInstance) }),
    triangle_query: Query(.{render.Triangle}),
) !void {
    queue.ptr.reset();

    var tri_it = triangle_query.iterator();
    while (tri_it.next()) |row| {
        const tri = row.get(render.Triangle) orelse continue;
        const layer = layerKeyForRow(row);
        try queue.ptr.pushTriangle(tri.*, layer);
    }

    var it = mesh_query.iterator();
    while (it.next()) |row| {
        const instance = row.get(render.MeshInstance) orelse continue;
        const transform = row.get(common.Transform) orelse continue;
        const material = row.get(render.MaterialInstance) orelse continue;
        const layer = layerKeyForRow(row);
        try queue.ptr.pushMeshInstanceWithMaterial(instance.*, transform.toMat4(), material.material, layer);
    }

    var default_it = mesh_default_query.iterator();
    while (default_it.next()) |row| {
        const instance = row.get(render.MeshInstance) orelse continue;
        const transform = row.get(common.Transform) orelse continue;
        const layer = layerKeyForRow(row);
        try queue.ptr.pushMeshInstance(instance.*, transform.toMat4(), layer);
    }
}

fn updateSpriteMeshes(commands: *Commands, sprites: Query(.{ render.Sprite, common.Transform })) !void {
    const state = commands.getResourceMut(RenderState) orelse return;
    const mesh_library = commands.getResourceMut(render.MeshLibrary) orelse return;

    var it = sprites.iterator();
    while (it.next()) |row| {
        const sprite = row.get(render.Sprite) orelse continue;
        const size_hash = render.spriteSizeHash(sprite.*);
        if (sprite.mesh_handle.isValid() and sprite.size_hash == size_hash) {
            if (row.get(render.MeshInstance)) |instance| {
                instance.mesh_handle = sprite.mesh_handle;
                instance.color = sprite.color;
            } else {
                try commands.addComponent(row.entity_id, render.MeshInstance{
                    .mesh_handle = sprite.mesh_handle,
                    .color = sprite.color,
                });
            }
            continue;
        }

        var width: f32 = 1.0;
        var height: f32 = 1.0;
        switch (sprite.size_mode) {
            .Auto => {},
            .Manual => |m| {
                width = m.width;
                height = m.height;
            },
        }

        const half_w = width * 0.5;
        const half_h = height * 0.5;
        const vertices = [_]render.VertexUv{
            .{ .position = .{ -half_w, -half_h }, .uv = .{ 0.0, 0.0 } },
            .{ .position = .{ half_w, -half_h }, .uv = .{ 1.0, 0.0 } },
            .{ .position = .{ half_w, half_h }, .uv = .{ 1.0, 1.0 } },
            .{ .position = .{ -half_w, half_h }, .uv = .{ 0.0, 1.0 } },
        };
        const indices = [_]u16{ 0, 1, 2, 0, 2, 3 };

        if (sprite.mesh_handle.isValid()) {
            _ = mesh_library.destroyMesh(&state.renderer, sprite.mesh_handle);
        }
        const mesh_handle = try mesh_library.addMesh(&state.renderer, vertices[0..], indices[0..]);
        sprite.mesh_handle = mesh_handle;
        sprite.size_hash = size_hash;

        if (row.get(render.MeshInstance)) |instance| {
            instance.mesh_handle = mesh_handle;
            instance.color = sprite.color;
        } else {
            try commands.addComponent(row.entity_id, render.MeshInstance{
                .mesh_handle = mesh_handle,
                .color = sprite.color,
            });
        }
    }
}

fn updateTextMeshes(
    commands: *Commands,
    default_font: ResMut(render.DefaultFont),
    texts: Query(.{ render.Text, common.Transform }),
) !void {
    const state = commands.getResourceMut(RenderState) orelse return;
    const mesh_library = commands.getResourceMut(render.MeshLibrary) orelse return;
    const font = &default_font.ptr.font;
    const material = font.material orelse return;
    if (font.atlas == null) return;

    var it = texts.iterator();
    while (it.next()) |row| {
        const text = row.get(render.Text) orelse continue;
        _ = row.get(common.Transform) orelse continue;

        const layout_hash = render.textLayoutHash(text.*);
        if (text.content.len == 0) {
            if (text.mesh_handle.isValid()) {
                _ = mesh_library.destroyMesh(&state.renderer, text.mesh_handle);
                text.mesh_handle = render.MeshHandle.invalid();
            }
            text.layout_hash = layout_hash;
            if (row.get(render.MeshInstance)) |instance| {
                instance.mesh_handle = render.MeshHandle.invalid();
            }
            continue;
        }
        if (!text.mesh_handle.isValid() or text.layout_hash != layout_hash) {
            if (text.mesh_handle.isValid()) {
                _ = mesh_library.destroyMesh(&state.renderer, text.mesh_handle);
                text.mesh_handle = render.MeshHandle.invalid();
            }

            var mesh_data = render.buildTextMesh(commands.allocator, font, text.*) catch |err| {
                if (err == error.EmptyText) {
                    text.layout_hash = layout_hash;
                    if (row.get(render.MeshInstance)) |instance| {
                        instance.mesh_handle = render.MeshHandle.invalid();
                    }
                    continue;
                }
                return err;
            };
            defer mesh_data.deinit(commands.allocator);

            const mesh_handle = try mesh_library.addMesh(&state.renderer, mesh_data.vertices, mesh_data.indices);
            text.mesh_handle = mesh_handle;
            text.layout_hash = layout_hash;
        }

        if (row.get(render.MeshInstance)) |instance| {
            instance.mesh_handle = text.mesh_handle;
            instance.color = text.color;
        } else {
            try commands.addComponent(row.entity_id, render.MeshInstance{
                .mesh_handle = text.mesh_handle,
                .color = text.color,
            });
        }

        if (row.get(render.MaterialInstance)) |mat| {
            mat.material = material;
        } else {
            try commands.addComponent(row.entity_id, render.MaterialInstance{
                .material = material,
            });
        }
    }
}

fn updateLayerCameras(
    cameras: Query(.{ common.Camera3d, common.Transform }),
    layer_cameras: ResMut(LayerCameras),
) !void {
    layer_cameras.ptr.clear();

    var it = cameras.iterator();
    while (it.next()) |row| {
        const cam = row.get(common.Camera3d) orelse continue;
        const transform = row.get(common.Transform) orelse continue;
        const layer = cameraLayerKeyForRow(row);
        try layer_cameras.ptr.map.put(layer, .{
            .camera = cam.*,
            .view = viewMatrix(transform.*),
        });
    }
}

fn renderSystem(
    commands: *Commands,
    queue: ResMut(render.RenderQueue),
    clear_opt: ResOpt(common.ClearColor),
    camera_opt: ResOpt(common.Camera3d),
    layer_cameras_opt: ResOpt(LayerCameras),
    viewport_opt: ResOpt(ViewportSize),
) !void {
    const state = commands.getResourceMut(RenderState) orelse return;
    const mesh_library = commands.getResourceMut(render.MeshLibrary) orelse return;

    render.surface_canvas.pollSize(&state.surface);
    const surface_size = state.surface.size();
    if (surface_size.width != state.renderer.surface_size.width or surface_size.height != state.renderer.surface_size.height) {
        state.renderer.resize(surface_size.width, surface_size.height);
    }

    const clear = if (clear_opt.ptr) |c| c.color else common.Color.BSOD;
    var frame = try state.renderer.beginFrame(clear);

    const viewport_size = if (viewport_opt.ptr) |vp|
        render.Size{ .width = @intFromFloat(vp.width), .height = @intFromFloat(vp.height) }
    else
        surface_size;
    const layers = try collectLayers(commands.allocator, queue.ptr.items.items);
    defer commands.allocator.free(layers);

    for (layers) |layer| {
        const camera = cameraForLayer(layer, layer_cameras_opt.ptr, camera_opt.ptr);
        const view = if (camera) |cam| cam.view else common.Mat4.identity();
        const viewport_matrix = if (camera) |cam|
            switch (cam.camera) {
                .Viewport => |vp| viewportMatrix(vp, viewport_size),
                else => null,
            }
        else
            null;
        const projection = if (camera) |cam|
            projectionMatrix(cam.camera, viewport_size)
        else
            null;
        const view_proj = if (viewport_matrix) |vp|
            common.Mat4.mul(vp, view)
        else if (projection) |proj|
            common.Mat4.mul(proj, view)
        else
            null;

        for (queue.ptr.items.items) |item| {
            switch (item) {
                .triangle => |tri| {
                    if (tri.layer != layer) continue;
                    const draw_tri = if (camera) |cam|
                        switch (cam.camera) {
                            .Viewport => |vp| applyViewport(tri.triangle, vp, viewport_size, view),
                            else => tri.triangle,
                        }
                    else
                        tri.triangle;
                    frame.draw(.{ .triangle = draw_tri });
                },
                .mesh => |instance| {
                    if (instance.layer != layer) continue;
                    if (instance.blend) continue;
                    const mesh = mesh_library.get(instance.mesh_handle) orelse continue;
                    const model = resolveModel(instance.transform, view_proj);

                    const color_f = common.Color.F32.fromColor(instance.color);
                    const gpu_instance = render.BackendMeshInstance{
                        .transform = model,
                        .color = .{ color_f.r, color_f.g, color_f.b, color_f.a },
                    };

                    const material = instance.material orelse state.default_material;
                    frame.draw(.{ .textured_quad = .{
                        .mesh = mesh.*,
                        .material = material,
                        .instance = gpu_instance,
                        .blend = instance.blend,
                    } });
                },
            }
        }

        var blended: std.ArrayListUnmanaged(BlendItem) = .empty;
        defer blended.deinit(commands.allocator);

        for (queue.ptr.items.items, 0..) |item, item_index| {
            switch (item) {
                .mesh => |instance| {
                    if (instance.layer != layer) continue;
                    if (!instance.blend) continue;
                    const mesh = mesh_library.get(instance.mesh_handle) orelse continue;
                    const model = resolveModel(instance.transform, view_proj);
                    const color_f = common.Color.F32.fromColor(instance.color);
                    const gpu_instance = render.BackendMeshInstance{
                        .transform = model,
                        .color = .{ color_f.r, color_f.g, color_f.b, color_f.a },
                    };
                    const material = instance.material orelse state.default_material;
                    try blended.append(commands.allocator, .{
                        .depth = clipDepth(model),
                        .order = item_index,
                        .mesh = mesh.*,
                        .material = material,
                        .instance = gpu_instance,
                    });
                },
                else => {},
            }
        }

        if (blended.items.len > 1) {
            std.sort.pdq(BlendItem, blended.items, {}, blendItemLessThan);
        }

        for (blended.items) |draw| {
            frame.draw(.{ .textured_quad = .{
                .mesh = draw.mesh,
                .material = draw.material,
                .instance = draw.instance,
                .blend = true,
            } });
        }
    }

    try frame.endFrame();
}

fn handleViewportResize(
    commands: *Commands,
    reader: EventReader(common.WindowResized),
    window_bounds_opt: ResOpt(common.WindowBounds),
    render_bounds_opt: ResOpt(common.RenderBounds),
) !void {
    var latest: ?common.WindowResized = null;
    while (reader.tryRecv()) |evt| {
        latest = evt;
    }

    if (latest) |evt| {
        try commands.insertResource(ViewportSize{
            .width = @floatFromInt(evt.width),
            .height = @floatFromInt(evt.height),
        });
        return;
    }

    if (!commands.hasResource(ViewportSize)) {
        if (window_bounds_opt.ptr) |bounds| {
            try commands.insertResource(ViewportSize{
                .width = @floatFromInt(bounds.width),
                .height = @floatFromInt(bounds.height),
            });
        } else if (render_bounds_opt.ptr) |bounds| {
            try commands.insertResource(ViewportSize{ .width = bounds.width, .height = bounds.height });
        }
    }
}

fn layerKeyForRow(row: db.QueryResult.Row) i32 {
    const table = &row.database.tables.items[row.table_index];
    return layerKeyForTable(table);
}

fn layerKeyForTable(table: *const db.table.Table) i32 {
    const trait_id = db.meta.typeId(render.LayerN);
    for (table.columns) |column| {
        for (column.group_traits) |group_trait| {
            if (group_trait.trait_id != trait_id) continue;
            return group_trait.key;
        }
    }
    return 0;
}

fn collectLayers(allocator: std.mem.Allocator, items: []const render.RenderItem) ![]i32 {
    var list: std.ArrayListUnmanaged(i32) = .empty;
    defer list.deinit(allocator);

    for (items) |item| {
        const layer = switch (item) {
            .triangle => |tri| tri.layer,
            .mesh => |mesh| mesh.layer,
        };
        try list.append(allocator, layer);
    }

    if (list.items.len == 0) {
        return allocator.alloc(i32, 0);
    }

    std.sort.pdq(i32, list.items, {}, std.sort.asc(i32));

    var unique_count: usize = 1;
    for (list.items[1..]) |value| {
        if (value != list.items[unique_count - 1]) {
            list.items[unique_count] = value;
            unique_count += 1;
        }
    }

    return allocator.dupe(i32, list.items[0..unique_count]);
}

fn cameraForLayer(
    layer: i32,
    layer_cameras: ?*const LayerCameras,
    fallback: ?*const common.Camera3d,
) ?LayerCamera {
    const has_layer_cameras = if (layer_cameras) |cameras| cameras.map.count() > 0 else false;
    if (layer_cameras) |cameras| {
        if (cameras.map.get(layer)) |cam| return cam;
    }
    if (!has_layer_cameras) {
        if (fallback) |cam| {
            return .{ .camera = cam.*, .view = common.Mat4.identity() };
        }
    }
    if (layer == 0) {
        if (fallback) |cam| {
            return .{ .camera = cam.*, .view = common.Mat4.identity() };
        }
    }
    return null;
}

fn viewportMatrix(vp: anytype, size: render.Size) common.Mat4 {
    const w = @as(f32, @floatFromInt(size.width));
    const h = @as(f32, @floatFromInt(size.height));
    if (w == 0.0 or h == 0.0) return common.Mat4.identity();
    return switch (vp.mode) {
        .TopLeft => common.Mat4.orthographic(0.0, w, h, 0.0, vp.near, vp.far),
        .Center => common.Mat4.orthographic(-w * 0.5, w * 0.5, -h * 0.5, h * 0.5, vp.near, vp.far),
    };
}

fn projectionMatrix(camera: common.Camera3d, size: render.Size) ?common.Mat4 {
    const w = @as(f32, @floatFromInt(size.width));
    const h = @as(f32, @floatFromInt(size.height));
    const aspect = if (h == 0.0) 1.0 else w / h;
    return switch (camera) {
        .Perspective => |persp| common.Mat4.perspective(persp.fov, aspect, persp.near, persp.far),
        .Orthographic => |ortho| common.Mat4.orthographic(
            ortho.left,
            ortho.right,
            ortho.bottom,
            ortho.top,
            ortho.near,
            ortho.far,
        ),
        .Viewport => null,
    };
}

fn applyViewport(tri: render.Triangle, vp: anytype, size: render.Size, view: common.Mat4) render.Triangle {
    var out = tri;
    for (&out.vertices) |*v| {
        const transformed = view.transformVec2(.{ .x = v.position[0], .y = v.position[1] });
        const pos = .{ transformed.x, transformed.y };
        const ndc = switch (vp.mode) {
            .TopLeft => positionToNdcTopLeft(pos, size),
            .Center => positionToNdcCenter(pos, size),
        };
        v.position = ndc;
    }
    return out;
}

fn positionToNdcTopLeft(pos: [2]f32, size: render.Size) [2]f32 {
    const w = @as(f32, @floatFromInt(size.width));
    const h = @as(f32, @floatFromInt(size.height));
    if (w == 0.0 or h == 0.0) return pos;
    const x = (pos[0] / w) * 2.0 - 1.0;
    const y = 1.0 - (pos[1] / h) * 2.0;
    return .{ x, y };
}

const BlendItem = struct {
    depth: f32,
    order: usize,
    mesh: render.Mesh,
    material: render.Material,
    instance: render.BackendMeshInstance,
};

fn resolveModel(transform: common.Mat4, view_proj: ?common.Mat4) common.Mat4 {
    if (view_proj) |vp| {
        return common.Mat4.mul(vp, transform);
    }
    return transform;
}

fn viewMatrix(transform: common.Transform) common.Mat4 {
    const inv_scale = common.Vec3{
        .x = if (transform.scale.x != 0.0) 1.0 / transform.scale.x else 0.0,
        .y = if (transform.scale.y != 0.0) 1.0 / transform.scale.y else 0.0,
        .z = if (transform.scale.z != 0.0) 1.0 / transform.scale.z else 0.0,
    };
    const scale_mat = common.Mat4.scaleVec3(inv_scale);
    const rot_mat = common.Mat4.fromQuaternion(transform.rotation.inverse());
    const trans_mat = common.Mat4.translateVec3(transform.translation.scale(-1.0));
    return common.Mat4.mul(common.Mat4.mul(scale_mat, rot_mat), trans_mat);
}

fn cameraLayerKeyForRow(row: db.QueryResult.Row) i32 {
    const table = &row.database.tables.items[row.table_index];
    return cameraLayerKeyForTable(table);
}

fn cameraLayerKeyForTable(table: *const db.table.Table) i32 {
    const trait_id = db.meta.typeId(render.CameraLayerN);
    for (table.columns) |column| {
        for (column.group_traits) |group_trait| {
            if (group_trait.trait_id != trait_id) continue;
            return group_trait.key;
        }
    }
    return 0;
}

fn clipDepth(model: common.Mat4) f32 {
    const w = model.m[3][3];
    if (w != 0.0) {
        return model.m[3][2] / w;
    }
    return model.m[3][2];
}

fn blendItemLessThan(_: void, a: BlendItem, b: BlendItem) bool {
    if (a.depth == b.depth) {
        return a.order < b.order;
    }
    return a.depth > b.depth;
}

fn positionToNdcCenter(pos: [2]f32, size: render.Size) [2]f32 {
    const w = @as(f32, @floatFromInt(size.width));
    const h = @as(f32, @floatFromInt(size.height));
    if (w == 0.0 or h == 0.0) return pos;
    const x = pos[0] / (w * 0.5);
    const y = pos[1] / (h * 0.5);
    return .{ x, y };
}

fn shutdownSystem(commands: *Commands) void {
    const state = commands.getResourceMut(RenderState) orelse {
        _ = commands.removeResource(render.MeshLibrary);
        _ = commands.removeResource(render.RenderQueue);
        _ = commands.removeResource(render.DefaultFont);
        _ = commands.removeResource(LayerCameras);
        return;
    };

    if (commands.getResourceMut(render.MeshLibrary)) |library| {
        library.destroyMeshes(&state.renderer);
        _ = commands.removeResource(render.MeshLibrary);
    }

    if (commands.getResourceMut(render.DefaultFont)) |font| {
        font.font.unload(commands.allocator, &state.renderer);
        _ = commands.removeResource(render.DefaultFont);
    }

    _ = commands.removeResource(LayerCameras);

    _ = commands.removeResource(assets.AssetsContext);
    _ = commands.removeResource(render.RenderQueue);
    _ = commands.removeResource(RenderState);
}

// Imports
const std = @import("std");
const common = @import("common");
const ecs = @import("ecs");
const render = @import("render");
const assets = @import("assets");
const db = @import("db");
const AppCommands = ecs.AppCommands;
const Commands = ecs.Commands;
const schedule = ecs.schedule;
const system_params = ecs.system_params;
const Query = system_params.Query;
const ResMut = system_params.ResMut;
const ResOpt = system_params.ResOpt;
const Without = system_params.Without;
const events = ecs.events;
const EventReader = events.EventReader;
