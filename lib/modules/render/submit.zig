pub fn renderSystem(
    commands: *Commands,
    queue: ResMut(render.RenderQueue),
    clear_opt: ResOpt(common.ClearColor),
    camera_opt: ResOpt(common.Camera3d),
    layer_cameras_opt: ResOpt(types.LayerCameras),
    viewport_opt: ResOpt(types.ViewportSize),
) !void {
    const state = commands.getResourceMut(types.RenderState) orelse return;
    const mesh_library = commands.getResourceMut(render.MeshLibrary) orelse return;

    const surface_size = state.surface.size();
    if (surface_size.width != state.renderer.surface_size.width or surface_size.height != state.renderer.surface_size.height) {
        state.renderer.resize(surface_size.width, surface_size.height);
    }

    const clear = if (clear_opt.ptr) |c| c.color else common.Color.BSOD;
    var frame = try state.renderer.beginFrame(clear);
    defer frame.endFrame() catch {};

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

        var batch_items: std.ArrayListUnmanaged(BatchItem) = .empty;
        defer batch_items.deinit(commands.allocator);

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
                    const key = BatchKey{
                        .mesh = instance.mesh_handle,
                        .material = materialKey(material),
                    };
                    try batch_items.append(commands.allocator, .{
                        .key = key,
                        .mesh = mesh.*,
                        .material = material,
                        .instance = gpu_instance,
                    });
                },
            }
        }

        if (batch_items.items.len > 0) {
            std.sort.pdq(BatchItem, batch_items.items, {}, batchItemLessThan);
            var batch_instances: std.ArrayListUnmanaged(render.BackendMeshInstance) = .empty;
            defer batch_instances.deinit(commands.allocator);

            var idx: usize = 0;
            while (idx < batch_items.items.len) {
                const first = batch_items.items[idx];
                const key = first.key;
                batch_instances.clearRetainingCapacity();
                try batch_instances.append(commands.allocator, first.instance);
                idx += 1;
                while (idx < batch_items.items.len and batchKeyEqual(batch_items.items[idx].key, key)) : (idx += 1) {
                    try batch_instances.append(commands.allocator, batch_items.items[idx].instance);
                }
                const max_instances: usize = render.max_instances_per_draw;
                var start: usize = 0;
                while (start < batch_instances.items.len) {
                    const end = @min(start + max_instances, batch_instances.items.len);
                    frame.drawTexturedQuads(first.mesh, first.material, batch_instances.items[start..end], false);
                    start = end;
                }
            }
        }

        var blended: std.ArrayListUnmanaged(BlendItem) = .empty;
        defer blended.deinit(commands.allocator);

        for (queue.ptr.items.items) |item| {
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
                        .entity_id = instance.entity_id,
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
}

const BatchKey = struct {
    mesh: render.MeshHandle,
    material: usize,
};

const BatchItem = struct {
    key: BatchKey,
    mesh: render.Mesh,
    material: render.Material,
    instance: render.BackendMeshInstance,
};

fn batchKeyEqual(a: BatchKey, b: BatchKey) bool {
    return a.mesh.index == b.mesh.index and a.mesh.generation == b.mesh.generation and a.material == b.material;
}

fn batchItemLessThan(_: void, a: BatchItem, b: BatchItem) bool {
    if (a.key.mesh.index != b.key.mesh.index) return a.key.mesh.index < b.key.mesh.index;
    if (a.key.mesh.generation != b.key.mesh.generation) return a.key.mesh.generation < b.key.mesh.generation;
    return a.key.material < b.key.material;
}

fn materialKey(material: render.Material) usize {
    const T = @TypeOf(material);
    if (@hasField(T, "handle")) {
        return @as(usize, @intCast(material.handle));
    }
    return @intFromPtr(material.bind_group);
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
    layer_cameras: ?*const types.LayerCameras,
    fallback: ?*const common.Camera3d,
) ?types.LayerCamera {
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
    const zoom = if (vp.zoom <= 0.0) 1.0 else vp.zoom;
    const inv_zoom = 1.0 / zoom;
    const w = @as(f32, @floatFromInt(size.width)) * inv_zoom;
    const h = @as(f32, @floatFromInt(size.height)) * inv_zoom;
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
        .Perspective => |persp| {
            const zoom = if (persp.zoom <= 0.0) 1.0 else persp.zoom;
            return common.Mat4.perspective(persp.fov / zoom, aspect, persp.near, persp.far);
        },
        .Orthographic => |ortho| {
            const zoom = if (ortho.zoom <= 0.0) 1.0 else ortho.zoom;
            return common.Mat4.orthographic(
                ortho.left / zoom,
                ortho.right / zoom,
                ortho.bottom / zoom,
                ortho.top / zoom,
                ortho.near,
                ortho.far,
            );
        },
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
    entity_id: u64,
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

fn clipDepth(model: common.Mat4) f32 {
    const w = model.m[3][3];
    if (w != 0.0) {
        return model.m[3][2] / w;
    }
    return model.m[3][2];
}

fn blendItemLessThan(_: void, a: BlendItem, b: BlendItem) bool {
    if (a.depth == b.depth) {
        return a.entity_id < b.entity_id;
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

const std = @import("std");
const common = @import("common");
const ecs = @import("ecs");
const render = @import("render");
const types = @import("types.zig");

const Commands = ecs.Commands;
const system_params = ecs.system_params;
const ResMut = system_params.ResMut;
const ResOpt = system_params.ResOpt;
