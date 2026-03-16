pub fn renderSystem(
    commands: *Commands,
    queue: ResMut(render.RenderQueue),
    clear_opt: ResOpt(common.ClearColor),
    camera_opt: ResOpt(common.Camera3d),
    layer_cameras_opt: ResOpt(types.LayerCameras),
    layer_viewports_opt: ResOpt(types.LayerViewports),
    viewport_opt: ResOpt(types.ViewportSize),
    framebuffer_opt: ResOpt(types.FramebufferSize),
    render_bounds_opt: ResOpt(common.RenderBounds),
    ordered_post_process: Query(.{ render.PostProcessPass, render.PostProcessOrder }),
    unordered_post_process: Query(.{ render.PostProcessPass, Without(render.PostProcessOrder) }),
    present_query: Query(.{render.PostProcessPresentSlot}),
) !void {
    const state = commands.getResourceMut(types.RenderState) orelse return;
    const mesh_library = commands.getResourceMut(render.MeshLibrary) orelse return;
    const shader_library = commands.getResourceMut(render.ShaderLibrary) orelse return;
    const post_process_shader_library = commands.getResourceMut(render.PostProcessShaderLibrary) orelse return;
    const material_library = commands.getResourceMut(render.MaterialLibrary) orelse return;

    const surface_size = if (framebuffer_opt.ptr) |bounds|
        render.Size{
            .width = @intFromFloat(@max(1.0, bounds.width)),
            .height = @intFromFloat(@max(1.0, bounds.height)),
        }
    else if (render_bounds_opt.ptr) |bounds|
        render.Size{
            .width = @intFromFloat(@max(1.0, bounds.width)),
            .height = @intFromFloat(@max(1.0, bounds.height)),
        }
    else
        state.surface.size();

    switch (state.surface) {
        .native => |*native| native.size = surface_size,
        .web => |*web| web.size = surface_size,
    }
    if (surface_size.width != state.renderer.surface_size.width or surface_size.height != state.renderer.surface_size.height) {
        state.renderer.resize(surface_size.width, surface_size.height);
    }

    const clear = if (clear_opt.ptr) |c| c.color else common.Color.BSOD;
    var frame = try state.renderer.beginFrame();
    defer frame.endFrame() catch {};

    const viewport_size = if (viewport_opt.ptr) |vp|
        render.Size{ .width = @intFromFloat(vp.width), .height = @intFromFloat(vp.height) }
    else
        surface_size;
    var post_process_passes = try collectPostProcessPasses(commands.allocator, ordered_post_process, unordered_post_process);
    defer post_process_passes.deinit(commands.allocator);
    const processed_max_layer = resolveProcessedMaxLayer(post_process_passes.items);
    const scene_target = if (post_process_passes.items.len > 0) blk: {
        break :blk try frameTargetForSlot(&state.renderer, 0, surface_size);
    } else render.FrameTarget.surface;
    try frame.beginScenePass(scene_target, clear);

    const layers = try collectLayers(commands.allocator, queue.ptr.items.items);
    defer commands.allocator.free(layers);
    try drawSceneLayers(
        &frame,
        commands.allocator,
        queue.ptr.items.items,
        layers,
        layer_cameras_opt.ptr,
        layer_viewports_opt.ptr,
        camera_opt.ptr,
        viewport_size,
        surface_size,
        mesh_library,
        shader_library,
        material_library,
        state.default_material,
        .{ .max_layer = processed_max_layer },
    );

    if (post_process_passes.items.len == 0) return;

    const present_slot = resolvePresentSlot(post_process_passes.items, present_query);
    for (post_process_passes.items) |pass_item| {
        const pass = pass_item.pass;
        if (pass.input_slot == pass.output_slot) continue;
        const shader = post_process_shader_library.get(pass.material.shader) orelse continue;
        _ = try state.renderer.ensurePostProcessSlot(pass.input_slot, surface_size.width, surface_size.height);
        const target = if (pass.output_slot == present_slot)
            render.FrameTarget.surface
        else blk: {
            break :blk try frameTargetForSlot(&state.renderer, pass.output_slot, surface_size);
        };
        try frame.beginPostProcessPass(target, common.Color.rgba(0, 0, 0, 0));
        frame.setViewportScissor(
            0.0,
            0.0,
            @floatFromInt(surface_size.width),
            @floatFromInt(surface_size.height),
        );
        frame.drawPostProcess(
            shader.*,
            pass.input_slot,
            pass.material.params.values,
            surface_size,
            pass.material.blend,
        );
    }

    if (hasLayersAbove(layers, processed_max_layer)) {
        try frame.beginScenePassLoad(render.FrameTarget.surface);
        try drawSceneLayers(
            &frame,
            commands.allocator,
            queue.ptr.items.items,
            layers,
            layer_cameras_opt.ptr,
            layer_viewports_opt.ptr,
            camera_opt.ptr,
            viewport_size,
            surface_size,
            mesh_library,
            shader_library,
            material_library,
            state.default_material,
            .{ .min_layer = processed_max_layer + 1 },
        );
    }
}

const BatchKey = struct {
    mesh: render.MeshHandle,
    material: usize,
};

const BatchItem = struct {
    key: BatchKey,
    mesh: render.Mesh,
    material: render.BackendMaterial,
    instance: render.BackendMeshInstance,
};

const ShaderBatchKey = struct {
    mesh: render.MeshHandle,
    shader: render.ShaderHandle,
};

const TexturedShaderBatchKey = struct {
    mesh: render.MeshHandle,
    shader: render.ShaderHandle,
    material: usize,
};

const ShaderBatchItem = struct {
    key: ShaderBatchKey,
    mesh: render.Mesh,
    shader: render.Shader,
    instance: render.BackendMeshInstance,
};

const TexturedShaderBatchItem = struct {
    key: TexturedShaderBatchKey,
    mesh: render.Mesh,
    shader: render.Shader,
    material: render.BackendMaterial,
    instance: render.BackendMeshInstance,
};

const PostProcessPassItem = struct {
    order: i32,
    pass: render.PostProcessPass,
};

const LayerFilter = struct {
    min_layer: ?i32 = null,
    max_layer: ?i32 = null,
};

fn batchKeyEqual(a: BatchKey, b: BatchKey) bool {
    return a.mesh.index == b.mesh.index and a.mesh.generation == b.mesh.generation and a.material == b.material;
}

fn shaderBatchKeyEqual(a: ShaderBatchKey, b: ShaderBatchKey) bool {
    return a.mesh.index == b.mesh.index and
        a.mesh.generation == b.mesh.generation and
        a.shader.index == b.shader.index and
        a.shader.generation == b.shader.generation;
}

fn texturedShaderBatchKeyEqual(a: TexturedShaderBatchKey, b: TexturedShaderBatchKey) bool {
    return a.mesh.index == b.mesh.index and
        a.mesh.generation == b.mesh.generation and
        a.shader.index == b.shader.index and
        a.shader.generation == b.shader.generation and
        a.material == b.material;
}

fn batchItemLessThan(_: void, a: BatchItem, b: BatchItem) bool {
    if (a.key.mesh.index != b.key.mesh.index) return a.key.mesh.index < b.key.mesh.index;
    if (a.key.mesh.generation != b.key.mesh.generation) return a.key.mesh.generation < b.key.mesh.generation;
    return a.key.material < b.key.material;
}

fn shaderBatchItemLessThan(_: void, a: ShaderBatchItem, b: ShaderBatchItem) bool {
    if (a.key.mesh.index != b.key.mesh.index) return a.key.mesh.index < b.key.mesh.index;
    if (a.key.mesh.generation != b.key.mesh.generation) return a.key.mesh.generation < b.key.mesh.generation;
    if (a.key.shader.index != b.key.shader.index) return a.key.shader.index < b.key.shader.index;
    return a.key.shader.generation < b.key.shader.generation;
}

fn texturedShaderBatchItemLessThan(_: void, a: TexturedShaderBatchItem, b: TexturedShaderBatchItem) bool {
    if (a.key.mesh.index != b.key.mesh.index) return a.key.mesh.index < b.key.mesh.index;
    if (a.key.mesh.generation != b.key.mesh.generation) return a.key.mesh.generation < b.key.mesh.generation;
    if (a.key.shader.index != b.key.shader.index) return a.key.shader.index < b.key.shader.index;
    if (a.key.shader.generation != b.key.shader.generation) return a.key.shader.generation < b.key.shader.generation;
    return a.key.material < b.key.material;
}

fn materialKey(material: render.BackendMaterial) usize {
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

fn collectPostProcessPasses(
    allocator: std.mem.Allocator,
    ordered_query: Query(.{ render.PostProcessPass, render.PostProcessOrder }),
    unordered_query: Query(.{ render.PostProcessPass, Without(render.PostProcessOrder) }),
) !std.ArrayListUnmanaged(PostProcessPassItem) {
    var list: std.ArrayListUnmanaged(PostProcessPassItem) = .empty;

    var ordered_it = ordered_query.iterator();
    while (ordered_it.next()) |row| {
        const pass = row.get(render.PostProcessPass) orelse continue;
        const order = row.get(render.PostProcessOrder) orelse continue;
        if (!pass.enabled or !pass.material.shader.isValid()) continue;
        try list.append(allocator, .{ .order = order.value, .pass = pass.* });
    }

    var unordered_it = unordered_query.iterator();
    while (unordered_it.next()) |row| {
        const pass = row.get(render.PostProcessPass) orelse continue;
        if (!pass.enabled or !pass.material.shader.isValid()) continue;
        try list.append(allocator, .{ .order = 0, .pass = pass.* });
    }

    if (list.items.len > 1) {
        std.sort.pdq(PostProcessPassItem, list.items, {}, postProcessPassLessThan);
    }
    return list;
}

fn resolveProcessedMaxLayer(passes: []const PostProcessPassItem) i32 {
    var max_layer: i32 = std.math.maxInt(i32);
    for (passes) |item| {
        max_layer = @min(max_layer, item.pass.scene.max_layer);
    }
    return max_layer;
}

fn hasLayersAbove(layers: []const i32, max_layer: i32) bool {
    for (layers) |layer| {
        if (layer > max_layer) return true;
    }
    return false;
}

fn layerIncluded(layer: i32, filter: LayerFilter) bool {
    if (filter.min_layer) |min_layer| {
        if (layer < min_layer) return false;
    }
    if (filter.max_layer) |max_layer| {
        if (layer > max_layer) return false;
    }
    return true;
}

fn drawSceneLayers(
    frame: *render.Frame,
    allocator: std.mem.Allocator,
    items: []const render.RenderItem,
    layers: []const i32,
    layer_cameras: ?*const types.LayerCameras,
    layer_viewports: ?*const types.LayerViewports,
    fallback_camera: ?*const common.Camera3d,
    viewport_size: render.Size,
    surface_size: render.Size,
    mesh_library: *render.MeshLibrary,
    shader_library: *render.ShaderLibrary,
    material_library: *render.MaterialLibrary,
    default_material: render.BackendMaterial,
    filter: LayerFilter,
) !void {
    for (layers) |layer| {
        if (!layerIncluded(layer, filter)) continue;
        const layer_rect = layerViewportRect(layer, layer_viewports, viewport_size);
        if (layer_rect.width <= 0.0 or layer_rect.height <= 0.0) continue;
        const scissor_rect = scaleViewportRect(layer_rect, viewport_size, surface_size);
        frame.setViewportScissor(scissor_rect.x, scissor_rect.y, scissor_rect.width, scissor_rect.height);

        const layer_size = render.Size{
            .width = @intFromFloat(layer_rect.width),
            .height = @intFromFloat(layer_rect.height),
        };
        const camera = cameraForLayer(layer, layer_cameras, fallback_camera);
        const view = if (camera) |cam| cam.view else common.Mat4.identity();
        const viewport_matrix = if (camera) |cam|
            switch (cam.camera) {
                .Viewport => |vp| viewportMatrix(vp, layer_size),
                else => null,
            }
        else
            null;
        const projection = if (camera) |cam|
            projectionMatrix(cam.camera, layer_size)
        else
            null;
        const view_proj = if (viewport_matrix) |vp|
            common.Mat4.mul(vp, view)
        else if (projection) |proj|
            common.Mat4.mul(proj, view)
        else
            null;

        var batch_items: std.ArrayListUnmanaged(BatchItem) = .empty;
        defer batch_items.deinit(allocator);
        var shader_batch_items: std.ArrayListUnmanaged(ShaderBatchItem) = .empty;
        defer shader_batch_items.deinit(allocator);
        var textured_shader_batch_items: std.ArrayListUnmanaged(TexturedShaderBatchItem) = .empty;
        defer textured_shader_batch_items.deinit(allocator);

        for (items) |item| {
            switch (item) {
                .triangle => |tri| {
                    if (tri.layer != layer) continue;
                    const draw_tri = if (camera) |cam|
                        switch (cam.camera) {
                            .Viewport => |vp| applyViewport(tri.triangle, vp, layer_size, view),
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

                    if (instance.shader_handle) |shader_handle| {
                        const shader = shader_library.get(shader_handle) orelse continue;
                        switch (shader.binding_mode) {
                            .none => {
                                const key = ShaderBatchKey{
                                    .mesh = instance.mesh_handle,
                                    .shader = shader_handle,
                                };
                                try shader_batch_items.append(allocator, .{
                                    .key = key,
                                    .mesh = mesh.*,
                                    .shader = shader.*,
                                    .instance = gpu_instance,
                                });
                            },
                            .material => {
                                const material = if (instance.material_handle) |handle|
                                    (material_library.get(handle) orelse continue).*
                                else
                                    instance.material orelse default_material;
                                const key = TexturedShaderBatchKey{
                                    .mesh = instance.mesh_handle,
                                    .shader = shader_handle,
                                    .material = materialKey(material),
                                };
                                try textured_shader_batch_items.append(allocator, .{
                                    .key = key,
                                    .mesh = mesh.*,
                                    .shader = shader.*,
                                    .material = material,
                                    .instance = gpu_instance,
                                });
                            },
                            .material_scene => continue,
                        }
                        continue;
                    }

                    const material = if (instance.material_handle) |handle|
                        (material_library.get(handle) orelse continue).*
                    else
                        instance.material orelse default_material;
                    const key = BatchKey{
                        .mesh = instance.mesh_handle,
                        .material = materialKey(material),
                    };
                    try batch_items.append(allocator, .{
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
            defer batch_instances.deinit(allocator);

            var idx: usize = 0;
            while (idx < batch_items.items.len) {
                const first = batch_items.items[idx];
                const key = first.key;
                batch_instances.clearRetainingCapacity();
                try batch_instances.append(allocator, first.instance);
                idx += 1;
                while (idx < batch_items.items.len and batchKeyEqual(batch_items.items[idx].key, key)) : (idx += 1) {
                    try batch_instances.append(allocator, batch_items.items[idx].instance);
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

        if (shader_batch_items.items.len > 0) {
            std.sort.pdq(ShaderBatchItem, shader_batch_items.items, {}, shaderBatchItemLessThan);
            var shader_instances: std.ArrayListUnmanaged(render.BackendMeshInstance) = .empty;
            defer shader_instances.deinit(allocator);

            var idx_shader: usize = 0;
            while (idx_shader < shader_batch_items.items.len) {
                const first = shader_batch_items.items[idx_shader];
                const key = first.key;
                shader_instances.clearRetainingCapacity();
                try shader_instances.append(allocator, first.instance);
                idx_shader += 1;
                while (idx_shader < shader_batch_items.items.len and shaderBatchKeyEqual(shader_batch_items.items[idx_shader].key, key)) : (idx_shader += 1) {
                    try shader_instances.append(allocator, shader_batch_items.items[idx_shader].instance);
                }
                const max_instances: usize = render.max_instances_per_draw;
                var start: usize = 0;
                while (start < shader_instances.items.len) {
                    const end = @min(start + max_instances, shader_instances.items.len);
                    frame.drawColoredMeshes(first.mesh, first.shader, shader_instances.items[start..end], false);
                    start = end;
                }
            }
        }

        if (textured_shader_batch_items.items.len > 0) {
            std.sort.pdq(TexturedShaderBatchItem, textured_shader_batch_items.items, {}, texturedShaderBatchItemLessThan);
            var shader_instances: std.ArrayListUnmanaged(render.BackendMeshInstance) = .empty;
            defer shader_instances.deinit(allocator);

            var idx_shader: usize = 0;
            while (idx_shader < textured_shader_batch_items.items.len) {
                const first = textured_shader_batch_items.items[idx_shader];
                const key = first.key;
                shader_instances.clearRetainingCapacity();
                try shader_instances.append(allocator, first.instance);
                idx_shader += 1;
                while (idx_shader < textured_shader_batch_items.items.len and texturedShaderBatchKeyEqual(textured_shader_batch_items.items[idx_shader].key, key)) : (idx_shader += 1) {
                    try shader_instances.append(allocator, textured_shader_batch_items.items[idx_shader].instance);
                }
                const max_instances: usize = render.max_instances_per_draw;
                var start: usize = 0;
                while (start < shader_instances.items.len) {
                    const end = @min(start + max_instances, shader_instances.items.len);
                    frame.drawTexturedMeshesWithShader(first.mesh, first.material, first.shader, shader_instances.items[start..end], false);
                    start = end;
                }
            }
        }

        var blended: std.ArrayListUnmanaged(BlendItem) = .empty;
        defer blended.deinit(allocator);

        for (items) |item| {
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
                    if (instance.shader_handle) |shader_handle| {
                        const shader = shader_library.get(shader_handle) orelse continue;
                        switch (shader.binding_mode) {
                            .none => frame.drawColoredMeshes(mesh.*, shader.*, &[_]render.BackendMeshInstance{gpu_instance}, true),
                            .material => {
                                const material = if (instance.material_handle) |handle|
                                    (material_library.get(handle) orelse continue).*
                                else
                                    instance.material orelse default_material;
                                frame.drawTexturedMeshesWithShader(mesh.*, material, shader.*, &[_]render.BackendMeshInstance{gpu_instance}, true);
                            },
                            .material_scene => {},
                        }
                        continue;
                    }
                    const material = if (instance.material_handle) |handle|
                        (material_library.get(handle) orelse continue).*
                    else
                        instance.material orelse default_material;
                    try blended.append(allocator, .{
                        .sort_key = instance.sort_key,
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

fn resolvePresentSlot(
    passes: []const PostProcessPassItem,
    present_query: Query(.{render.PostProcessPresentSlot}),
) u32 {
    var it = present_query.iterator();
    if (it.next()) |row| {
        if (row.get(render.PostProcessPresentSlot)) |slot| {
            return slot.slot;
        }
    }
    if (passes.len == 0) return 0;
    return passes[passes.len - 1].pass.output_slot;
}

fn postProcessPassLessThan(_: void, a: PostProcessPassItem, b: PostProcessPassItem) bool {
    return a.order < b.order;
}

fn frameTargetForSlot(renderer: *render.Renderer, slot: u32, size: render.Size) !render.FrameTarget {
    const slot_value = try renderer.ensurePostProcessSlot(slot, size.width, size.height);
    if (@TypeOf(slot_value) == u32) {
        return .{ .slot = slot_value };
    }
    return .{ .texture = slot_value };
}

fn layerViewportRect(
    layer: i32,
    viewports: ?*const types.LayerViewports,
    fallback_size: render.Size,
) types.ViewportRect {
    if (viewports) |vps| {
        if (vps.map.get(layer)) |rect| return rect;
    }
    return .{
        .x = 0.0,
        .y = 0.0,
        .width = @floatFromInt(fallback_size.width),
        .height = @floatFromInt(fallback_size.height),
    };
}

fn scaleViewportRect(rect: types.ViewportRect, logical_size: render.Size, physical_size: render.Size) types.ViewportRect {
    // Viewport cameras and layout operate in logical units; GPU scissors need physical pixels.
    const logical_w = @as(f32, @floatFromInt(logical_size.width));
    const logical_h = @as(f32, @floatFromInt(logical_size.height));
    const physical_w = @as(f32, @floatFromInt(physical_size.width));
    const physical_h = @as(f32, @floatFromInt(physical_size.height));
    const scale_x = if (logical_w > 0.0) physical_w / logical_w else 1.0;
    const scale_y = if (logical_h > 0.0) physical_h / logical_h else 1.0;
    return .{
        .x = rect.x * scale_x,
        .y = rect.y * scale_y,
        .width = rect.width * scale_x,
        .height = rect.height * scale_y,
    };
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
        const ndc = switch (vp.mode) {
            .TopLeft => positionToNdcTopLeft(transformed, size),
            .Center => positionToNdcCenter(transformed, size),
        };
        v.position = .{ ndc.x, ndc.y };
    }
    return out;
}

fn positionToNdcTopLeft(pos: common.Vec2, size: render.Size) common.Vec2 {
    const w = @as(f32, @floatFromInt(size.width));
    const h = @as(f32, @floatFromInt(size.height));
    if (w == 0.0 or h == 0.0) return pos;
    const x = (pos.x / w) * 2.0 - 1.0;
    const y = 1.0 - (pos.y / h) * 2.0;
    return .{ .x = x, .y = y };
}

const BlendItem = struct {
    sort_key: i32,
    depth: f32,
    entity_id: u64,
    mesh: render.Mesh,
    material: render.BackendMaterial,
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
    if (a.sort_key != b.sort_key) {
        return a.sort_key < b.sort_key;
    }
    if (a.depth == b.depth) {
        return a.entity_id < b.entity_id;
    }
    return a.depth > b.depth;
}

fn positionToNdcCenter(pos: common.Vec2, size: render.Size) common.Vec2 {
    const w = @as(f32, @floatFromInt(size.width));
    const h = @as(f32, @floatFromInt(size.height));
    if (w == 0.0 or h == 0.0) return pos;
    const x = pos.x / (w * 0.5);
    const y = pos.y / (h * 0.5);
    return .{ .x = x, .y = y };
}

const std = @import("std");
const common = @import("common");
const ecs = @import("ecs");
const render = @import("render");
const types = @import("types.zig");

const Commands = ecs.Commands;
const system_params = ecs.system_params;
const Query = system_params.Query;
const ResMut = system_params.ResMut;
const ResOpt = system_params.ResOpt;
const Without = system_params.Without;
