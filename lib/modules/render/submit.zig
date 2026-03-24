pub fn renderSystem(
    commands: *Commands,
    queue: ResMut(render.RenderQueue),
    clear_opt: ResOpt(common.ClearColor),
    camera_opt: ResOpt(common.Camera3d),
    color_grading_opt: ResOpt(render.ColorGradingSettings),
    layer_cameras_opt: ResOpt(types.LayerCameras),
    layer_viewports_opt: ResOpt(types.LayerViewports),
    viewport_opt: ResOpt(types.ViewportSize),
    framebuffer_opt: ResOpt(types.FramebufferSize),
    render_bounds_opt: ResOpt(common.RenderBounds),
    ordered_post_process: Query(.{ render.PostProcessPass, render.PostProcessOrder }),
    unordered_post_process: Query(.{ render.PostProcessPass, Without(render.PostProcessOrder) }),
    present_query: Query(.{render.PostProcessPresentSlot}),
    shadow_settings_opt: ResOpt(types.ShadowSettings),
    shadow_mode_opt: ResOpt(render.ShadowMode),
    environment_specular_mode_opt: ResOpt(render.EnvironmentSpecularMode),
    scene_environment_map_opt: ResOpt(render.SceneEnvironmentMap),
    debug_view_opt: ResOpt(render.SceneDebugView),
) !void {
    const state = commands.getResourceMut(types.RenderState) orelse return;
    state.submit_scratch.clearFrame();
    const mesh_library = commands.getResourceMut(render.MeshLibrary) orelse return;
    const shader_library = commands.getResourceMut(render.ShaderLibrary) orelse return;
    const post_process_shader_library = commands.getResourceMut(render.PostProcessShaderLibrary) orelse return;
    const texture_library = commands.getResourceMut(render.TextureLibrary) orelse return;
    const material_library = commands.getResourceMut(render.MaterialLibrary) orelse return;
    const extracted_lighting = commands.getResource(types.ExtractedSceneLighting) orelse return;

    const scene_environment_handle = if (scene_environment_map_opt.ptr) |map| map.texture_handle else render.TextureHandle.invalid();
    if (!scene_environment_handle.isValid()) {
        if (state.current_scene_environment.isValid()) {
            try state.renderer.resetSceneEnvironment();
            state.current_scene_environment = render.TextureHandle.invalid();
        }
    } else if (!textureHandleEqual(scene_environment_handle, state.current_scene_environment)) {
        const environment_texture = texture_library.get(scene_environment_handle) orelse return error.MissingTexture;
        try state.renderer.setSceneEnvironment(environment_texture.*);
        state.current_scene_environment = scene_environment_handle;
    }

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
    const post_process_passes = try collectPostProcessPasses(&state.submit_scratch, ordered_post_process, unordered_post_process);
    const processed_max_layer = resolveProcessedMaxLayer(post_process_passes);
    const shadow_mode = if (shadow_mode_opt.ptr) |mode| mode.* else render.ShadowMode.inherit;
    const environment_specular_mode = if (environment_specular_mode_opt.ptr) |mode| mode.* else render.EnvironmentSpecularMode.on;
    const debug_view = if (debug_view_opt.ptr) |mode| mode.* else render.SceneDebugView.off;
    const shadow_settings = resolveShadowSettings(
        if (shadow_settings_opt.ptr) |settings| settings.* else types.ShadowSettings{},
        shadow_mode,
    );
    const shadow_camera = cameraForLayer(0, layer_cameras_opt.ptr, camera_opt.ptr);
    var shadow_frame = if (shadow_camera) |camera|
        shadows.evaluateShadowFrame(
            shadow_settings,
            extracted_lighting,
            camera,
            viewport_size,
            surface_size,
        )
    else
        shadows.ShadowFrameData{};
    if (!shadow_frame.enabled) {
        shadow_frame.map_slot = shadow_settings.map_slot;
        shadow_frame.map_size = .{
            .width = @max(surface_size.width, 1),
            .height = @max(surface_size.height, 1),
        };
        shadow_frame.uniforms.params0 = .{
            1.0 / @as(f32, @floatFromInt(@max(shadow_frame.map_size.width, 1))),
            1.0 / @as(f32, @floatFromInt(@max(shadow_frame.map_size.height, 1))),
            shadow_settings.depth_bias,
            shadow_settings.normal_bias,
        };
        shadow_frame.uniforms.params1 = .{
            shadow_settings.strength,
            0.0,
            @floatFromInt(@intFromEnum(shadow_settings.technique)),
            0.0,
        };
    }
    if (shadow_frame.enabled) {
        const shadow_target = try frameTargetForShadowSlot(&state.renderer, shadow_frame.map_slot, shadow_frame.map_size);
        try frame.beginShadowPass(shadow_target, common.Color.WHITE);
        frame.setViewportScissor(
            0.0,
            0.0,
            @floatFromInt(shadow_frame.map_size.width),
            @floatFromInt(shadow_frame.map_size.height),
        );
        drawShadowCasters(
            &frame,
            queue.ptr.items.items,
            mesh_library,
            state.default_material,
            state.shadow_shader_uv2,
            state.shadow_shader_pos3_uv2,
            state.shadow_shader_pos3_norm_uv2,
            state.shadow_shader_pos3_norm_tangent_uv2,
            state.shadow_shader_pos3_color4,
            shadow_frame.light_view_proj,
        );
    }
    frame.setShadowUniforms(shadow_frame.uniforms, shadow_frame.map_slot, shadow_frame.map_size);
    const scene_target = if (post_process_passes.len > 0) blk: {
        break :blk try frameTargetForSlot(&state.renderer, 0, surface_size);
    } else render.FrameTarget.surface;
    try frame.beginScenePass(scene_target, clear);

    const layers = try collectLayers(&state.submit_scratch, queue.ptr.items.items);
    try drawSceneLayers(
        &frame,
        &state.submit_scratch,
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
        extracted_lighting,
        color_grading_opt.ptr,
        environment_specular_mode,
        debug_view,
        .{ .max_layer = processed_max_layer },
    );

    if (post_process_passes.len == 0) return;

    const present_slot = resolvePresentSlot(post_process_passes, present_query);
    for (post_process_passes) |pass_item| {
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
            &state.submit_scratch,
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
            extracted_lighting,
            color_grading_opt.ptr,
            environment_specular_mode,
            debug_view,
            .{ .min_layer = processed_max_layer + 1 },
        );
    }
}

fn textureHandleEqual(a: render.TextureHandle, b: render.TextureHandle) bool {
    return a.index == b.index and a.generation == b.generation;
}

fn resolveShadowSettings(
    base: types.ShadowSettings,
    mode: render.ShadowMode,
) types.ShadowSettings {
    var settings = base;
    switch (mode) {
        .inherit => {},
        .off => settings.technique = .none,
        .directional => settings.technique = .directional_shadow_map,
    }
    return settings;
}

fn drawShadowCasters(
    frame: *render.Frame,
    items: []const render.RenderItem,
    mesh_library: *render.MeshLibrary,
    default_material: render.BackendMaterial,
    shader_uv2: render.ShadowShader,
    shader_pos3_uv2: render.ShadowShader,
    shader_pos3_norm_uv2: render.ShadowShader,
    shader_pos3_norm_tangent_uv2: render.ShadowShader,
    shader_pos3_color4: render.ShadowShader,
    light_view_proj: common.Mat4,
) void {
    for (items) |item| {
        switch (item) {
            .mesh => |instance| {
                if (instance.blend) continue;
                const mesh = mesh_library.get(instance.mesh_handle) orelse continue;
                const clip_model = common.Mat4.mul(light_view_proj, instance.transform);
                const color_f = common.Color.F32.fromColor(instance.color);
                const gpu_instance = render.BackendMeshInstance{
                    .clip_transform = clip_model,
                    .model_transform = instance.transform,
                    .color = .{ color_f.r, color_f.g, color_f.b, color_f.a },
                    .pbr_params = instance.pbr_params,
                };
                switch (mesh.vertex_layout) {
                    .uv2 => frame.drawShadowTexturedMeshesWithShader(mesh.*, default_material, shader_uv2, &[_]render.BackendMeshInstance{gpu_instance}),
                    .pos3_uv2 => frame.drawShadowTexturedMeshesWithShader(mesh.*, default_material, shader_pos3_uv2, &[_]render.BackendMeshInstance{gpu_instance}),
                    .pos3_norm_uv2 => frame.drawShadowTexturedMeshesWithShader(mesh.*, default_material, shader_pos3_norm_uv2, &[_]render.BackendMeshInstance{gpu_instance}),
                    .pos3_norm_tangent_uv2 => frame.drawShadowTexturedMeshesWithShader(mesh.*, default_material, shader_pos3_norm_tangent_uv2, &[_]render.BackendMeshInstance{gpu_instance}),
                    .pos3_color4 => frame.drawShadowColoredMeshes(mesh.*, shader_pos3_color4, &[_]render.BackendMeshInstance{gpu_instance}),
                }
            },
            else => {},
        }
    }
}

const BatchKey = types.BatchKey;
const BatchItem = types.BatchItem;
const ShaderBatchKey = types.ShaderBatchKey;
const TexturedShaderBatchKey = types.TexturedShaderBatchKey;
const ShaderBatchItem = types.ShaderBatchItem;
const TexturedShaderBatchItem = types.TexturedShaderBatchItem;
const PostProcessPassItem = types.PostProcessPassItem;
const BlendItem = types.BlendItem;

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

fn collectLayers(scratch: *types.SubmitScratch, items: []const render.RenderItem) ![]const i32 {
    scratch.layers.clearRetainingCapacity();
    for (items) |item| {
        const layer = switch (item) {
            .triangle => |tri| tri.layer,
            .mesh => |mesh| mesh.layer,
        };
        try scratch.layers.append(scratch.allocator, layer);
    }

    if (scratch.layers.items.len == 0) {
        return scratch.layers.items;
    }

    std.sort.pdq(i32, scratch.layers.items, {}, std.sort.asc(i32));

    var unique_count: usize = 1;
    for (scratch.layers.items[1..]) |value| {
        if (value != scratch.layers.items[unique_count - 1]) {
            scratch.layers.items[unique_count] = value;
            unique_count += 1;
        }
    }
    scratch.layers.items.len = unique_count;
    return scratch.layers.items;
}

fn collectPostProcessPasses(
    scratch: *types.SubmitScratch,
    ordered_query: Query(.{ render.PostProcessPass, render.PostProcessOrder }),
    unordered_query: Query(.{ render.PostProcessPass, Without(render.PostProcessOrder) }),
) ![]const PostProcessPassItem {
    scratch.post_process_passes.clearRetainingCapacity();
    var ordered_it = ordered_query.iterator();
    while (ordered_it.next()) |row| {
        const pass = row.get(render.PostProcessPass) orelse continue;
        const order = row.get(render.PostProcessOrder) orelse continue;
        if (!pass.enabled or !pass.material.shader.isValid()) continue;
        try scratch.post_process_passes.append(scratch.allocator, .{ .order = order.value, .pass = pass.* });
    }

    var unordered_it = unordered_query.iterator();
    while (unordered_it.next()) |row| {
        const pass = row.get(render.PostProcessPass) orelse continue;
        if (!pass.enabled or !pass.material.shader.isValid()) continue;
        try scratch.post_process_passes.append(scratch.allocator, .{ .order = 0, .pass = pass.* });
    }

    if (scratch.post_process_passes.items.len > 1) {
        std.sort.pdq(PostProcessPassItem, scratch.post_process_passes.items, {}, postProcessPassLessThan);
    }
    return scratch.post_process_passes.items;
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
    scratch: *types.SubmitScratch,
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
    extracted_lighting: *const types.ExtractedSceneLighting,
    color_grading: ?*const render.ColorGradingSettings,
    environment_specular_mode: render.EnvironmentSpecularMode,
    debug_view: render.SceneDebugView,
    filter: LayerFilter,
) !void {
    for (layers) |layer| {
        if (!layerIncluded(layer, filter)) continue;
        const camera = cameraForLayer(layer, layer_cameras, fallback_camera);
        const layer_rect = if (camera) |cam|
            switch (cam.camera) {
                .Viewport => layerViewportRect(layer, layer_viewports, viewport_size),
                else => types.ViewportRect{
                    .x = 0.0,
                    .y = 0.0,
                    .width = @as(f32, @floatFromInt(viewport_size.width)),
                    .height = @as(f32, @floatFromInt(viewport_size.height)),
                },
            }
        else
            layerViewportRect(layer, layer_viewports, viewport_size);
        if (layer_rect.width <= 0.0 or layer_rect.height <= 0.0) continue;
        const scissor_rect = scaleViewportRect(layer_rect, viewport_size, surface_size);
        frame.setViewportScissor(scissor_rect.x, scissor_rect.y, scissor_rect.width, scissor_rect.height);

        const layer_size = render.Size{
            .width = @intFromFloat(layer_rect.width),
            .height = @intFromFloat(layer_rect.height),
        };
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
        frame.setSceneUniforms(buildSceneUniforms(
            camera,
            view_proj,
            extracted_lighting,
            color_grading,
            environment_specular_mode,
            debug_view,
        ));

        scratch.batch_items.clearRetainingCapacity();
        scratch.shader_batch_items.clearRetainingCapacity();
        scratch.textured_shader_batch_items.clearRetainingCapacity();

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
                    const clip_model = resolveModel(instance.transform, view_proj);

                    const color_f = common.Color.F32.fromColor(instance.color);
                    const gpu_instance = render.BackendMeshInstance{
                        .clip_transform = clip_model,
                        .model_transform = instance.transform,
                        .color = .{ color_f.r, color_f.g, color_f.b, color_f.a },
                        .pbr_params = instance.pbr_params,
                    };

                    if (instance.shader_handle) |shader_handle| {
                        const shader = shader_library.get(shader_handle) orelse continue;
                        switch (shader.binding_mode) {
                            .none => {
                                const key = ShaderBatchKey{
                                    .mesh = instance.mesh_handle,
                                    .shader = shader_handle,
                                };
                                try scratch.shader_batch_items.append(scratch.allocator, .{
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
                                try scratch.textured_shader_batch_items.append(scratch.allocator, .{
                                    .key = key,
                                    .mesh = mesh.*,
                                    .shader = shader.*,
                                    .material = material,
                                    .instance = gpu_instance,
                                });
                            },
                            .material_scene, .material_scene_env => {
                                const material = if (instance.material_handle) |handle|
                                    (material_library.get(handle) orelse continue).*
                                else
                                    instance.material orelse default_material;
                                const key = TexturedShaderBatchKey{
                                    .mesh = instance.mesh_handle,
                                    .shader = shader_handle,
                                    .material = materialKey(material),
                                };
                                try scratch.textured_shader_batch_items.append(scratch.allocator, .{
                                    .key = key,
                                    .mesh = mesh.*,
                                    .shader = shader.*,
                                    .material = material,
                                    .instance = gpu_instance,
                                });
                            },
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
                    try scratch.batch_items.append(scratch.allocator, .{
                        .key = key,
                        .mesh = mesh.*,
                        .material = material,
                        .instance = gpu_instance,
                    });
                },
            }
        }

        if (scratch.batch_items.items.len > 0) {
            std.sort.pdq(BatchItem, scratch.batch_items.items, {}, batchItemLessThan);
            scratch.batch_instances.clearRetainingCapacity();
            var idx: usize = 0;
            while (idx < scratch.batch_items.items.len) {
                const first = scratch.batch_items.items[idx];
                const key = first.key;
                scratch.batch_instances.clearRetainingCapacity();
                try scratch.batch_instances.append(scratch.allocator, first.instance);
                idx += 1;
                while (idx < scratch.batch_items.items.len and batchKeyEqual(scratch.batch_items.items[idx].key, key)) : (idx += 1) {
                    try scratch.batch_instances.append(scratch.allocator, scratch.batch_items.items[idx].instance);
                }
                const max_instances: usize = render.max_instances_per_draw;
                var start: usize = 0;
                while (start < scratch.batch_instances.items.len) {
                    const end = @min(start + max_instances, scratch.batch_instances.items.len);
                    frame.drawTexturedQuads(first.mesh, first.material, scratch.batch_instances.items[start..end], false);
                    start = end;
                }
            }
        }

        if (scratch.shader_batch_items.items.len > 0) {
            std.sort.pdq(ShaderBatchItem, scratch.shader_batch_items.items, {}, shaderBatchItemLessThan);
            scratch.shader_instances.clearRetainingCapacity();
            var idx_shader: usize = 0;
            while (idx_shader < scratch.shader_batch_items.items.len) {
                const first = scratch.shader_batch_items.items[idx_shader];
                const key = first.key;
                scratch.shader_instances.clearRetainingCapacity();
                try scratch.shader_instances.append(scratch.allocator, first.instance);
                idx_shader += 1;
                while (idx_shader < scratch.shader_batch_items.items.len and shaderBatchKeyEqual(scratch.shader_batch_items.items[idx_shader].key, key)) : (idx_shader += 1) {
                    try scratch.shader_instances.append(scratch.allocator, scratch.shader_batch_items.items[idx_shader].instance);
                }
                const max_instances: usize = render.max_instances_per_draw;
                var start: usize = 0;
                while (start < scratch.shader_instances.items.len) {
                    const end = @min(start + max_instances, scratch.shader_instances.items.len);
                    frame.drawColoredMeshes(first.mesh, first.shader, scratch.shader_instances.items[start..end], false);
                    start = end;
                }
            }
        }

        if (scratch.textured_shader_batch_items.items.len > 0) {
            std.sort.pdq(TexturedShaderBatchItem, scratch.textured_shader_batch_items.items, {}, texturedShaderBatchItemLessThan);
            scratch.textured_shader_instances.clearRetainingCapacity();
            var idx_shader: usize = 0;
            while (idx_shader < scratch.textured_shader_batch_items.items.len) {
                const first = scratch.textured_shader_batch_items.items[idx_shader];
                const key = first.key;
                scratch.textured_shader_instances.clearRetainingCapacity();
                try scratch.textured_shader_instances.append(scratch.allocator, first.instance);
                idx_shader += 1;
                while (idx_shader < scratch.textured_shader_batch_items.items.len and texturedShaderBatchKeyEqual(scratch.textured_shader_batch_items.items[idx_shader].key, key)) : (idx_shader += 1) {
                    try scratch.textured_shader_instances.append(scratch.allocator, scratch.textured_shader_batch_items.items[idx_shader].instance);
                }
                const max_instances: usize = render.max_instances_per_draw;
                var start: usize = 0;
                while (start < scratch.textured_shader_instances.items.len) {
                    const end = @min(start + max_instances, scratch.textured_shader_instances.items.len);
                    frame.drawTexturedMeshesWithShader(first.mesh, first.material, first.shader, scratch.textured_shader_instances.items[start..end], false);
                    start = end;
                }
            }
        }

        scratch.blended.clearRetainingCapacity();

        for (items) |item| {
            switch (item) {
                .mesh => |instance| {
                    if (instance.layer != layer) continue;
                    if (!instance.blend) continue;
                    const mesh = mesh_library.get(instance.mesh_handle) orelse continue;
                    const clip_model = resolveModel(instance.transform, view_proj);
                    const color_f = common.Color.F32.fromColor(instance.color);
                    const gpu_instance = render.BackendMeshInstance{
                        .clip_transform = clip_model,
                        .model_transform = instance.transform,
                        .color = .{ color_f.r, color_f.g, color_f.b, color_f.a },
                        .pbr_params = instance.pbr_params,
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
                            .material_scene, .material_scene_env => {
                                const material = if (instance.material_handle) |handle|
                                    (material_library.get(handle) orelse continue).*
                                else
                                    instance.material orelse default_material;
                                frame.drawTexturedMeshesWithShader(mesh.*, material, shader.*, &[_]render.BackendMeshInstance{gpu_instance}, true);
                            },
                        }
                        continue;
                    }
                    const material = if (instance.material_handle) |handle|
                        (material_library.get(handle) orelse continue).*
                    else
                        instance.material orelse default_material;
                    try scratch.blended.append(scratch.allocator, .{
                        .sort_key = instance.sort_key,
                        .depth = clipDepth(clip_model),
                        .entity_id = instance.entity_id,
                        .mesh = mesh.*,
                        .material = material,
                        .instance = gpu_instance,
                    });
                },
                else => {},
            }
        }

        if (scratch.blended.items.len > 1) {
            std.sort.pdq(BlendItem, scratch.blended.items, {}, blendItemLessThan);
        }

        for (scratch.blended.items) |draw| {
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

fn buildSceneUniforms(
    camera: ?types.LayerCamera,
    view_proj: ?common.Mat4,
    extracted_lighting: *const types.ExtractedSceneLighting,
    color_grading: ?*const render.ColorGradingSettings,
    environment_specular_mode: render.EnvironmentSpecularMode,
    debug_view: render.SceneDebugView,
) render.SceneUniforms {
    var uniforms = render.SceneUniforms{};
    uniforms.view_proj = view_proj orelse common.Mat4.identity();
    if (camera) |cam| {
        uniforms.camera_position = .{
            cam.transform.translation.x,
            cam.transform.translation.y,
            cam.transform.translation.z,
            1.0,
        };
    }
    uniforms.ambient_color = .{
        extracted_lighting.ambient_color.r,
        extracted_lighting.ambient_color.g,
        extracted_lighting.ambient_color.b,
        1.0,
    };
    uniforms.exposure_settings = .{
        extracted_lighting.exposure,
        if (extracted_lighting.exposure_enabled) 1.0 else 0.0,
        extracted_lighting.environment_intensity * extracted_lighting.environment_diffuse_strength,
        extracted_lighting.environment_intensity * extracted_lighting.environment_specular_strength,
    };
    uniforms.color_grading = if (color_grading) |settings| blk: {
        break :blk settings.uniformVec4();
    } else blk: {
        const defaults = render.ColorGradingSettings{};
        break :blk defaults.uniformVec4();
    };
    uniforms.environment_dominant_direction = .{
        extracted_lighting.environment_dominant_direction.x,
        extracted_lighting.environment_dominant_direction.y,
        extracted_lighting.environment_dominant_direction.z,
        0.0,
    };
    uniforms.environment_dominant_color = .{
        extracted_lighting.environment_dominant_color.r,
        extracted_lighting.environment_dominant_color.g,
        extracted_lighting.environment_dominant_color.b,
        1.0,
    };
    uniforms.light_counts[0] = extracted_lighting.light_count;
    uniforms.debug_view[0] = @intFromEnum(debug_view);
    uniforms.environment_flags[0] = switch (environment_specular_mode) {
        .on => 1,
        .off => 0,
    };
    uniforms.environment_irradiance_sh = extracted_lighting.environment_irradiance_sh;
    var i: usize = 0;
    while (i < extracted_lighting.light_count and i < render.max_scene_lights) : (i += 1) {
        uniforms.lights[i] = extracted_lighting.lights[i];
    }
    return uniforms;
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

fn frameTargetForShadowSlot(renderer: *render.Renderer, slot: u32, size: render.Size) !render.FrameTarget {
    const slot_value = try renderer.ensureShadowMapSlot(slot, size.width, size.height);
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
            return .{
                .camera = cam.*,
                .view = common.Mat4.identity(),
                .transform = common.Transform.identity(),
            };
        }
    }
    if (layer == 0) {
        if (fallback) |cam| {
            return .{
                .camera = cam.*,
                .view = common.Mat4.identity(),
                .transform = common.Transform.identity(),
            };
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
const shadows = @import("shadows.zig");
const types = @import("types.zig");

const Commands = ecs.Commands;
const system_params = ecs.system_params;
const Query = system_params.Query;
const ResMut = system_params.ResMut;
const ResOpt = system_params.ResOpt;
const Without = system_params.Without;
