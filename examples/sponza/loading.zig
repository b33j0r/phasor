pub fn ensureSceneLoader(commands: *ecs.Commands) !void {
    if (commands.hasResource(SceneLoaderState)) return;

    var loader = try SceneLoaderState.init(commands.allocator, commands.io);
    errdefer loader.deinit();
    try loader.agent.start(commands.io.*, runSceneLoader, SceneLoaderTaskContext{
        .allocator = commands.allocator,
        .path = sponza_scene_path,
    });
    loader.started = true;
    loader.progress = .{ .label = "1/7 locating cached assets", .fraction = 0.02 };
    try commands.insertResource(loader);
}

pub fn ensureLoadingScreenVisuals(
    commands: *ecs.Commands,
    build_ctx: ResOpt(render.BuildContext),
    core_shaders: ResMut(render.CoreShaders),
    scene_assets: ResMut(Assets),
    screen_state: ResOpt(LoadingScreenState),
    current_phase: ResOpt(phases.SponzaPhases.CurrentPhase),
) !void {
    if (screen_state.ptr == null) return;
    const phase = current_phase.ptr orelse return;
    if (phase.phase != .Loading) return;
    if (commands.hasResource(LoadingScreenVisualState)) return;

    const build_ctx_res = build_ctx.ptr orelse return;
    try build_ctx_res.ensureCoreColorPos3Color4Shader(&core_shaders.ptr.color_pos3_color4);
    _ = scene_assets;
    const shaders = core_shaders.ptr;
    if (!shaders.color_pos3_color4.isValid()) return error.CoreColorShaderMissing;

    const mesh_handle = try createUiRectMesh(commands.allocator, build_ctx_res, 1.0, 1.0);
    const shader_material = render.Material.withShader(shaders.color_pos3_color4);

    const track_entity = try commands.createEntity(.{
        Transform{},
        MeshInstance{
            .mesh_handle = mesh_handle,
            .material = shader_material,
            .color = Color.rgba(32, 32, 32, 230),
        },
        render.Layer(1001){},
        LoadingScreen{},
        LoadingScreenBarTrack{},
    });
    const fill_entity = try commands.createEntity(.{
        Transform{},
        MeshInstance{
            .mesh_handle = mesh_handle,
            .material = shader_material,
            .color = Color.rgb(235, 235, 235),
        },
        render.Layer(1001){},
        LoadingScreen{},
        LoadingScreenBarFill{},
    });

    try commands.insertResource(LoadingScreenVisualState{
        .track_entity = track_entity,
        .fill_entity = fill_entity,
    });
}

pub fn drainSceneLoader(commands: *ecs.Commands, loader: ResMut(SceneLoaderState)) !void {
    while (loader.ptr.agent.tryRecv()) |message| {
        switch (message) {
            .progress => |progress| loader.ptr.progress = progress,
            .ready => |payload| {
                if (loader.ptr.payload) |*existing| existing.deinit(commands.allocator);
                loader.ptr.payload = payload;
                loader.ptr.progress = .{ .label = "5/7 validating collision bake", .fraction = 0.54 };
            },
            .failed => |err_name| loader.ptr.failed = err_name,
        }
    }
}

pub fn advanceSceneFinalize(
    commands: *ecs.Commands,
    build_ctx: ResOpt(render.BuildContext),
    core_shaders: ResMut(render.CoreShaders),
    collision_store: ResMut(physics.CollisionMeshStore),
    scene_assets: ResMut(Assets),
    loader: ResMut(SceneLoaderState),
) !void {
    if (commands.hasResource(SceneReady)) return;
    if (loader.ptr.failed != null) return;

    const build_ctx_res = build_ctx.ptr orelse return;
    try build_ctx_res.ensureCoreSkyPanoramaHdrShader(&core_shaders.ptr.sky_panorama_hdr);
    try build_ctx_res.ensureCoreSkyProceduralShader(&core_shaders.ptr.sky_procedural);
    if (!scene_assets.ptr.scene_shader.handle.isValid()) return error.SceneShaderMissing;
    if (!scene_assets.ptr.sky_panorama.material_handle.isValid()) return error.SkyPanoramaMissing;
    if (!scene_assets.ptr.sky_moon_overlay.material_handle.isValid()) return error.SkyMoonOverlayMissing;
    const shaders = core_shaders.ptr;
    if (!shaders.sky_panorama_hdr.isValid()) return error.CoreSkyPanoramaShaderMissing;
    if (!shaders.sky_procedural.isValid()) return error.CoreSkyProceduralShaderMissing;

    if (!commands.hasResource(SceneFinalizeState)) {
        if (loader.ptr.payload) |payload| {
            const bounds = payload.bake.bounds;
            const center = bounds.center();
            const root_translation = Vec3{
                .x = -center.x,
                .y = -bounds.min.y,
                .z = -center.z,
            };
            try commands.insertResource(SceneFinalizeState{
                .allocator = commands.allocator,
                .payload = payload,
                .root_translation = root_translation,
                .scene_size = bounds.size(),
            });
            loader.ptr.payload = null;
        }
        return;
    }

    const finalize = commands.getResourceMut(SceneFinalizeState) orelse return;
    switch (finalize.stage) {
        .inspect_bake => {
            loader.ptr.progress = .{ .label = "5/7 validating collision bake", .fraction = 0.58 };
            try logCollisionBakeStats(commands.allocator, finalize.payload.bake);
            finalize.stage = .create_scene_root;
        },
        .create_scene_root => {
            loader.ptr.progress = .{ .label = "6/7 creating scene root", .fraction = 0.64 };
            const root = try commands.createEntity(.{
                Transform{
                    .translation = finalize.root_translation,
                },
                SceneRoot{},
                render.Layer(0){},
            });
            finalize.scene_root = root;

            _ = try commands.createEntity(.{
                Transform{
                    .translation = .{
                        .x = 0.0,
                        .y = finalize.scene_size.y * 0.35,
                        .z = 0.0,
                    },
                },
                modules.SkyModule.PanoramaSky{
                    .material = scene_assets.ptr.sky_moon_overlay.material,
                    .shader_handle = shaders.sky_procedural,
                    .size = @max(@max(finalize.scene_size.x, finalize.scene_size.y), finalize.scene_size.z) * 4.0,
                    .follow_camera = true,
                    .face_segments = 56,
                },
                render.Layer(-1){},
            });
            finalize.stage = .parse_collision;
        },
        .parse_collision => {
            loader.ptr.progress = .{ .label = "6/7 decoding collision mesh", .fraction = 0.70 };
            finalize.parsed_collision = try physics.CollisionBake.mesh_formats.parseAlloc(
                commands.allocator,
                finalize.payload.bake.collision_blob,
            );
            finalize.next_collision_mesh = 0;
            finalize.stage = .instantiate_collision;
        },
        .instantiate_collision => {
            const parsed = finalize.parsed_collision orelse return error.MissingParsedCollision;
            const total_meshes = parsed.meshes.len;
            const remaining = total_meshes -| finalize.next_collision_mesh;
            const chunk_len = @min(@as(usize, 16), remaining);
            const completed = finalize.next_collision_mesh;
            loader.ptr.progress = .{
                .label = "6/7 building collision bodies",
                .fraction = if (total_meshes == 0)
                    0.82
                else
                    0.72 + (0.10 * (@as(f32, @floatFromInt(completed)) / @as(f32, @floatFromInt(total_meshes)))),
            };

            var produced: usize = 0;
            while (produced < chunk_len) : (produced += 1) {
                const mesh = parsed.meshes[finalize.next_collision_mesh];
                finalize.next_collision_mesh += 1;
                if (mesh.index_count < 3 or mesh.vertex_count == 0) continue;
                const handle = try addCollisionSubmesh(commands.allocator, collision_store.ptr, parsed, mesh);
                _ = try commands.createEntity(.{
                    Transform{
                        .translation = finalize.root_translation,
                    },
                    physics.Body{ .kind = .Static },
                    physics.Collider{
                        .shape = .{ .TriangleMesh = handle },
                        .material = .{ .friction = 0.85, .restitution = 0.0 },
                        .collision = .{
                            .layer = mesh.layer,
                            .mask = mesh.mask,
                        },
                    },
                });
            }

            if (finalize.next_collision_mesh >= total_meshes) {
                finalize.stage = .instantiate_scene;
            }
        },
        .instantiate_scene => {
            if (finalize.scene_apply == null) {
                finalize.scene_apply = try finalize.payload.prepared_scene.beginApply(commands.allocator);
            }
            const apply = &finalize.scene_apply.?;
            const finished = try finalize.payload.prepared_scene.applyBatch(
                commands,
                build_ctx_res,
                .{
                    .parent = finalize.scene_root,
                    .shader_handle = scene_assets.ptr.scene_shader.handle,
                    .mesh_layout = .Pos3NormTangentUv,
                },
                apply,
                6,
            );
            loader.ptr.progress = .{
                .label = "7/7 uploading render scene",
                .fraction = 0.84 + (0.15 * apply.progress(finalize.payload.prepared_scene.primitives.len)),
            };
            if (!finished) return;

            const imported = try finalize.payload.prepared_scene.completeApply(apply);
            finalize.scene_apply = null;
            try commands.insertResource(imported);
            try commands.insertResource(SceneSpawnPlan{
                .scene_size = finalize.scene_size,
            });
            try commands.insertResource(SceneReady{});
            try commands.insertResource(MouseCapture{ .enabled = true });
            try commands.insertResource(ClearColor{ .color = Color.rgb(8, 10, 14) });
            loader.ptr.progress = .{ .label = "Ready", .fraction = 1.0 };
            try commands.insertResource(phases.SponzaPhases.NextPhase{ .phase = .{ .InGame = .{ .Playing = .{} } } });
            _ = commands.removeResource(SceneFinalizeState);
        },
    }
}

pub fn updateLoadingScreen(
    elapsed: Res(ElapsedTime),
    loader: ResOpt(SceneLoaderState),
    screen_state: ResMut(LoadingScreenState),
    scene_assets: ResOpt(Assets),
    current_phase: ResOpt(phases.SponzaPhases.CurrentPhase),
    window_bounds_opt: ResOpt(common.WindowBounds),
    texts: Query(.{ render.Text, Transform, LoadingScreenText }),
    bar_tracks: Query(.{ Transform, MeshInstance, LoadingScreenBarTrack }),
    bar_fills: Query(.{ Transform, MeshInstance, LoadingScreenBarFill }),
) void {
    const loader_state = loader.ptr;
    const spinner = spinnerFrame(elapsed.ptr.seconds);
    var header_buffer: [64]u8 = undefined;
    const phase_name = if (current_phase.ptr) |phase| switch (phase.phase) {
        .Loading => "Loading",
        .InGame => |in_game| switch (in_game) {
            .Playing => "InGame.Playing",
            .Paused => "InGame.Paused",
        },
    } else "Boot";
    const header = std.fmt.bufPrint(&header_buffer, "Sponza {c} {s}", .{ spinner, phase_name }) catch "Sponza";

    var bar_buffer: [20]u8 = undefined;
    const progress = if (loader_state) |state| state.progress else SceneLoaderProgress{ .label = "Booting", .fraction = 0.0 };
    const clamped_progress = std.math.clamp(progress.fraction, 0.0, 1.0);
    const filled = @min(@as(usize, @intFromFloat(clamped_progress * 20.0)), bar_buffer.len);
    for (&bar_buffer, 0..) |*slot, index| {
        slot.* = if (index < filled) '#' else '-';
    }
    const percent = @as(u32, @intFromFloat(clamped_progress * 100.0));

    const message = if (loader_state) |state|
        if (state.failed) |err_name|
            std.fmt.bufPrint(
                screen_state.ptr.overlay.buffer[0..],
                "{s}\n\nLoad failed\n{s}",
                .{ header, err_name },
            ) catch "Sponza: load failed"
        else
            std.fmt.bufPrint(
                screen_state.ptr.overlay.buffer[0..],
                "{s}\n\n{d}%\n{s}",
                .{ header, percent, progress.label },
            ) catch "Sponza: loading..."
    else
        std.fmt.bufPrint(
            screen_state.ptr.overlay.buffer[0..],
            "{s}\n\nPreparing scene loader",
            .{header},
        ) catch "Sponza: booting...";

    const width = if (window_bounds_opt.ptr) |bounds|
        @as(f32, @floatFromInt(bounds.width))
    else
        1440.0;
    const height = if (window_bounds_opt.ptr) |bounds|
        @as(f32, @floatFromInt(bounds.height))
    else
        900.0;
    const bar_width: f32 = 420.0;
    const bar_height: f32 = 18.0;
    const bar_center_x = width * 0.5;
    const bar_center_y = height * 0.5 + 88.0;

    var it = texts.iterator();
    while (it.next()) |row| {
        const text = row.get(render.Text) orelse continue;
        const transform = row.get(Transform) orelse continue;
        transform.translation.x = width * 0.5;
        transform.translation.y = height * 0.5;
        text.content = message;
        text.font_size = 28.0;
        text.color = Color.rgb(230, 232, 236);
        text.horizontal_alignment = .Center;
        text.vertical_alignment = .Center;
        if (scene_assets.ptr) |assets_state| {
            if (assets_state.ui_serif_font.handle.isValid()) {
                text.font_handle = assets_state.ui_serif_font.handle;
            }
        }
    }

    var track_it = bar_tracks.iterator();
    while (track_it.next()) |row| {
        const transform = row.get(Transform) orelse continue;
        const mesh = row.get(MeshInstance) orelse continue;
        transform.translation = .{ .x = bar_center_x, .y = bar_center_y, .z = 0.0 };
        transform.scale = .{ .x = bar_width, .y = bar_height, .z = 1.0 };
        mesh.color = Color.rgba(32, 32, 32, 230);
    }

    var fill_it = bar_fills.iterator();
    while (fill_it.next()) |row| {
        const transform = row.get(Transform) orelse continue;
        const mesh = row.get(MeshInstance) orelse continue;
        const fill_width = @max(4.0, bar_width * clamped_progress);
        transform.translation = .{
            .x = bar_center_x - (bar_width - fill_width) * 0.5,
            .y = bar_center_y,
            .z = 0.0,
        };
        transform.scale = .{ .x = fill_width, .y = bar_height - 4.0, .z = 1.0 };
        mesh.color = if (loader_state != null and loader_state.?.failed == null)
            Color.rgb(242, 242, 242)
        else
            Color.rgb(196, 48, 48);
    }
}

pub fn unloadImportedScene(commands: *ecs.Commands) void {
    _ = commands.removeResource(assets.ImportedScene);
    _ = commands.removeResource(SceneReady);
    _ = commands.removeResource(SceneSpawnPlan);
    _ = commands.removeResource(SceneFinalizeState);
    _ = commands.removeResource(SceneLoaderState);
    _ = commands.removeResource(LightingReady);
    _ = commands.removeResource(LoadingScreenState);
    _ = commands.removeResource(LoadingScreenVisualState);
    _ = commands.removeResource(HudCameraState);
}

fn createUiRectMesh(
    allocator: std.mem.Allocator,
    build_ctx: *const render.BuildContext,
    width: f32,
    height: f32,
) !render.MeshHandle {
    const half_width = width * 0.5;
    const half_height = height * 0.5;
    const vertices = [_]render.VertexPos3Color{
        .{ .position = .{ -half_width, -half_height, 0.0 }, .color = .{ 1.0, 1.0, 1.0, 1.0 } },
        .{ .position = .{ half_width, -half_height, 0.0 }, .color = .{ 1.0, 1.0, 1.0, 1.0 } },
        .{ .position = .{ half_width, half_height, 0.0 }, .color = .{ 1.0, 1.0, 1.0, 1.0 } },
        .{ .position = .{ -half_width, half_height, 0.0 }, .color = .{ 1.0, 1.0, 1.0, 1.0 } },
    };
    const indices = [_]u16{ 0, 1, 2, 2, 3, 0 };
    _ = allocator;
    return build_ctx.addMeshPos3Color(vertices[0..], indices[0..]);
}

fn spinnerFrame(seconds: f64) u8 {
    const frames = [_]u8{ '|', '/', '-', '\\' };
    const frame_index = @as(usize, @intFromFloat(@floor(seconds * 4.0)));
    return frames[frame_index % frames.len];
}

fn bakeSceneCollision(allocator: std.mem.Allocator, scene_data: *const assets.SceneData) !SceneBake {
    var builder = physics.CollisionBake.Builder.init(allocator);
    defer builder.deinit();

    var bounds: SceneBounds = .{};
    const roots = sceneRootNodes(scene_data);
    for (roots) |root_node_index| {
        try appendNodeCollision(allocator, scene_data, root_node_index, Transform.identity(), &builder, &bounds);
    }

    return .{
        .bounds = bounds,
        .collision_blob = try builder.finish(),
    };
}

fn logCollisionBakeStats(allocator: std.mem.Allocator, baked: SceneBake) !void {
    var parsed = try physics.CollisionBake.mesh_formats.parseAlloc(allocator, baked.collision_blob);
    defer parsed.deinit(allocator);

    var max_index: u32 = 0;
    for (parsed.indices) |index| {
        max_index = @max(max_index, index);
    }

    std.log.debug(
        "sponza collision bake: meshes={} vertices={} indices={} max_index={} bounds=({d:.2}, {d:.2}, {d:.2})",
        .{
            parsed.meshes.len,
            parsed.vertices.len,
            parsed.indices.len,
            max_index,
            baked.bounds.size().x,
            baked.bounds.size().y,
            baked.bounds.size().z,
        },
    );

    if (parsed.vertices.len == 0 or parsed.indices.len < 3) return error.InvalidCollisionBake;
    if (max_index >= parsed.vertices.len) return error.InvalidCollisionBake;
    try validateCollisionMeshes(parsed);
}

fn validateCollisionMeshes(parsed: physics.CollisionBake.File) !void {
    for (parsed.meshes, 0..) |mesh, mesh_index| {
        if (mesh.index_count == 0) continue;

        const vertex_start: u32 = mesh.first_vertex;
        const vertex_end: u32 = mesh.first_vertex + mesh.vertex_count;
        var local_min: u32 = std.math.maxInt(u32);
        var local_max: u32 = 0;

        for (parsed.indices[mesh.first_index .. mesh.first_index + mesh.index_count]) |index| {
            local_min = @min(local_min, index);
            local_max = @max(local_max, index);
            if (index < vertex_start or index >= vertex_end) {
                std.log.warn(
                    "sponza collision mesh {} invalid range: vertex_range=[{}, {}) bad_index={} local_min={} local_max={}",
                    .{ mesh_index, vertex_start, vertex_end, index, local_min, local_max },
                );
                return error.InvalidCollisionBake;
            }
        }
    }
}

fn addCollisionSubmesh(
    allocator: std.mem.Allocator,
    collision_store: *physics.CollisionMeshStore,
    parsed: physics.CollisionBake.File,
    mesh: physics.CollisionBake.Mesh,
) !physics.CollisionMeshHandle {
    var builder = physics.CollisionBake.Builder.init(allocator);
    defer builder.deinit();

    const vertex_start: usize = mesh.first_vertex;
    const vertex_end: usize = mesh.first_vertex + mesh.vertex_count;
    const index_start: usize = mesh.first_index;
    const index_end: usize = mesh.first_index + mesh.index_count;

    var positions = try allocator.alloc(Vec3, mesh.vertex_count);
    defer allocator.free(positions);
    for (parsed.vertices[vertex_start..vertex_end], 0..) |vertex, i| {
        positions[i] = vertex.position;
    }

    var packed_vertices = try allocator.alloc(f32, mesh.vertex_count * 3);
    defer allocator.free(packed_vertices);
    for (positions, 0..) |position, i| {
        packed_vertices[i * 3 + 0] = position.x;
        packed_vertices[i * 3 + 1] = position.y;
        packed_vertices[i * 3 + 2] = position.z;
    }

    var indices = try allocator.alloc(u32, mesh.index_count);
    defer allocator.free(indices);
    for (parsed.indices[index_start..index_end], 0..) |index, i| {
        indices[i] = index - mesh.first_vertex;
    }

    try builder.addTriangleSoup(positions, indices, .{
        .layer = mesh.layer,
        .mask = mesh.mask,
    });
    const bytes = try builder.finish();
    defer allocator.free(bytes);
    return collision_store.addPreparedTriangleMesh(
        .{
            .bytes = bytes,
            .format = .PhysicsMeshV1,
        },
        packed_vertices,
        indices,
    );
}

fn sceneRootNodes(scene_data: *const assets.SceneData) []const u32 {
    if (scene_data.default_scene) |default_scene| {
        if (default_scene < scene_data.scenes.len) {
            return scene_data.scenes[default_scene].root_nodes;
        }
    }
    if (scene_data.scenes.len > 0) {
        return scene_data.scenes[0].root_nodes;
    }
    return &.{};
}

fn appendNodeCollision(
    allocator: std.mem.Allocator,
    scene_data: *const assets.SceneData,
    node_index: u32,
    parent_transform: Transform,
    builder: *physics.CollisionBake.Builder,
    bounds: *SceneBounds,
) !void {
    if (node_index >= scene_data.nodes.len) return;
    const node = scene_data.nodes[node_index];
    const node_transform = combineTransform(parent_transform, localToWorld(node.local_transform));

    if (node.mesh_index) |mesh_index| {
        if (mesh_index < scene_data.meshes.len) {
            const mesh = scene_data.meshes[mesh_index];
            for (mesh.primitives) |primitive| {
                try appendPrimitiveCollision(allocator, scene_data, primitive, node_transform, builder, bounds);
            }
        }
    }

    for (node.children) |child_index| {
        try appendNodeCollision(allocator, scene_data, child_index, node_transform, builder, bounds);
    }
}

fn appendPrimitiveCollision(
    allocator: std.mem.Allocator,
    scene_data: *const assets.SceneData,
    primitive: assets.scene.PrimitiveData,
    transform: Transform,
    builder: *physics.CollisionBake.Builder,
    bounds: *SceneBounds,
) !void {
    const position_accessor = primitive.position_accessor orelse return;
    if (position_accessor.element_type != .Vec3 or position_accessor.component_type != 5126) {
        return error.UnsupportedPositionAccessor;
    }

    const position_meta = scene_data.accessors[position_accessor.accessor_index];
    const position_bytes = scene_data.accessorByteSlice(position_accessor.accessor_index) orelse return error.MissingPositionBytes;
    const vertex_count = position_accessor.count;
    if (vertex_count == 0) return;

    const indices = try buildTriangleIndicesU32(allocator, scene_data, primitive.indices_accessor, vertex_count);
    defer allocator.free(indices);

    var positions = try allocator.alloc(Vec3, vertex_count);
    defer allocator.free(positions);
    for (0..vertex_count) |i| {
        const local_pos = readVec3(position_bytes, positionMetaStride(position_meta), i);
        const world_pos = transformPoint(transform, local_pos);
        positions[i] = world_pos;
        bounds.include(world_pos);
    }

    try builder.addTriangleSoup(positions, indices, .{
        .layer = 0,
        .mask = 1 << 1,
    });
}

fn buildTriangleIndicesU32(
    allocator: std.mem.Allocator,
    scene_data: *const assets.SceneData,
    indices_accessor: ?assets.scene.AccessorRef,
    vertex_count: usize,
) ![]u32 {
    if (indices_accessor) |accessor| {
        const meta = scene_data.accessors[accessor.accessor_index];
        const bytes = scene_data.accessorByteSlice(accessor.accessor_index) orelse return error.MissingIndexBytes;
        var out = try allocator.alloc(u32, accessor.count);
        for (0..accessor.count) |i| {
            out[i] = switch (meta.component_type) {
                5121 => readU8(bytes, meta.byte_stride, i),
                5123 => readU16(bytes, meta.byte_stride, i),
                5125 => readU32(bytes, meta.byte_stride, i),
                else => return error.UnsupportedIndexAccessor,
            };
        }
        return out;
    }

    const out = try allocator.alloc(u32, vertex_count);
    for (out, 0..) |*dst, i| dst.* = @intCast(i);
    return out;
}

fn localToWorld(local: common.LocalTransform) Transform {
    return .{
        .translation = local.translation,
        .rotation = local.rotation,
        .scale = local.scale,
    };
}

fn combineTransform(parent: Transform, local: Transform) Transform {
    return .{
        .translation = parent.translation.add(parent.rotation.rotateVec3(mulVec3Components(parent.scale, local.translation))),
        .rotation = parent.rotation.mul(local.rotation),
        .scale = mulVec3Components(parent.scale, local.scale),
    };
}

fn transformPoint(transform: Transform, point: Vec3) Vec3 {
    return transform.translation.add(transform.rotation.rotateVec3(mulVec3Components(transform.scale, point)));
}

fn mulVec3Components(a: Vec3, b: Vec3) Vec3 {
    return .{
        .x = a.x * b.x,
        .y = a.y * b.y,
        .z = a.z * b.z,
    };
}

fn positionMetaStride(meta: assets.scene.AccessorData) usize {
    if (meta.byte_stride != 0) return meta.byte_stride;
    return switch (meta.component_type) {
        5126 => 12,
        else => 12,
    };
}

fn readVec3(bytes: []const u8, stride: usize, index: usize) Vec3 {
    const base = index * stride;
    return .{
        .x = readF32(bytes, base),
        .y = readF32(bytes, base + 4),
        .z = readF32(bytes, base + 8),
    };
}

fn readF32(bytes: []const u8, offset: usize) f32 {
    return @bitCast(std.mem.bytesToValue(u32, bytes[offset .. offset + 4]));
}

fn readU8(bytes: []const u8, stride: usize, index: usize) u32 {
    return bytes[index * stride];
}

fn readU16(bytes: []const u8, stride: usize, index: usize) u32 {
    const base = index * stride;
    const lo = @as(u16, bytes[base]);
    const hi = @as(u16, bytes[base + 1]) << 8;
    return lo | hi;
}

fn readU32(bytes: []const u8, stride: usize, index: usize) u32 {
    const base = index * stride;
    return @as(u32, bytes[base]) |
        (@as(u32, bytes[base + 1]) << 8) |
        (@as(u32, bytes[base + 2]) << 16) |
        (@as(u32, bytes[base + 3]) << 24);
}

fn runSceneLoader(
    task_io: std.Io,
    _: common.Channel(SceneLoaderCommand).Receiver,
    outbox: common.Channel(SceneLoaderMessage).Sender,
    ctx: SceneLoaderTaskContext,
) anyerror!void {
    // Reusable importer overrides: alpha-masked materials (cloth/foliage/cutouts) default to dielectric behavior.
    // This avoids metallic-channel dominance on masked surfaces when source assets encode aggressive MR textures.
    const material_overrides = [_]assets.PreparedImportedScene.MaterialOverride{
        .{
            .alpha_mode = .Mask,
            .metallic_factor = 0.0,
            .roughness_factor = 0.9,
        },
        // Generic sanity rule for suspicious MR-encoded dielectrics:
        // if a material reports very high average metallic map while also staying rough and color-saturated,
        // treat it as dielectric to avoid grayscale/specular washout under white lighting.
        .{
            .has_metallic_roughness_texture = true,
            .min_metallic_map_average = 0.65,
            .min_roughness_map_average = 0.2,
            .min_base_color_saturation_average = 0.08,
            .metallic_factor = 0.0,
            .roughness_factor = 0.85,
        },
        .{ .material_index = 14, .normal_scale = 0.25 },
        .{ .material_index = 15, .normal_scale = 0.25 },
        .{ .material_index = 16, .normal_scale = 0.25 },
        .{ .material_index = 17, .normal_scale = 0.25 },
        .{ .material_index = 18, .normal_scale = 0.25 },
        .{ .material_index = 19, .normal_scale = 0.25 },
    };

    try outbox.send(.{ .progress = .{ .label = "1/7 locating cached assets", .fraction = 0.08 } });

    const resolved_z = try ctx.allocator.dupeZ(u8, ctx.path);
    defer ctx.allocator.free(resolved_z);

    try outbox.send(.{ .progress = .{ .label = "2/7 parsing glTF scene", .fraction = 0.20 } });
    var scene_data = try assets.gltf.parseFromFile(ctx.allocator, resolved_z);
    errdefer scene_data.deinit();

    try outbox.send(.{ .progress = .{ .label = "3/7 baking collision meshes", .fraction = 0.34 } });
    const bake = try bakeSceneCollision(ctx.allocator, &scene_data);
    errdefer ctx.allocator.free(bake.collision_blob);

    try outbox.send(.{ .progress = .{ .label = "4/7 preparing render assets", .fraction = 0.50 } });
    var prepared_scene = try assets.PreparedImportedScene.prepare(
        ctx.allocator,
        &task_io,
        resolved_z,
        &scene_data,
        .{
            .mesh_layout = .Pos3NormTangentUv,
            .material_overrides = &material_overrides,
        },
    );
    errdefer prepared_scene.deinit();
    scene_data.deinit();

    try outbox.send(.{ .ready = .{
        .prepared_scene = prepared_scene,
        .bake = bake,
    } });
}

// Imports
const std = @import("std");
const phasor = @import("phasor");
const phases = @import("phases.zig");
const shared = @import("shared.zig");

const assets = phasor.assets;
const common = phasor.common;
const ecs = phasor.ecs;
const modules = phasor.modules;
const physics = phasor.physics;
const render = phasor.renderer;

const Query = ecs.system_params.Query;
const Res = ecs.system_params.Res;
const ResMut = ecs.system_params.ResMut;
const ResOpt = ecs.system_params.ResOpt;

const Assets = shared.Assets;
const ClearColor = common.ClearColor;
const Color = common.Color;
const ElapsedTime = modules.TimeModule.ElapsedTime;
const HudCameraState = shared.HudCameraState;
const LightingReady = shared.LightingReady;
const LoadingScreen = shared.LoadingScreen;
const LoadingScreenBarFill = shared.LoadingScreenBarFill;
const LoadingScreenBarTrack = shared.LoadingScreenBarTrack;
const LoadingScreenState = shared.LoadingScreenState;
const LoadingScreenText = shared.LoadingScreenText;
const LoadingScreenVisualState = shared.LoadingScreenVisualState;
const MeshInstance = render.MeshInstance;
const MouseCapture = modules.InputModule.MouseCapture;
const SceneBake = shared.SceneBake;
const SceneBounds = shared.SceneBounds;
const SceneFinalizeState = shared.SceneFinalizeState;
const SceneLoaderCommand = shared.SceneLoaderCommand;
const SceneLoaderMessage = shared.SceneLoaderMessage;
const SceneLoaderProgress = shared.SceneLoaderProgress;
const SceneLoaderState = shared.SceneLoaderState;
const SceneLoaderTaskContext = shared.SceneLoaderTaskContext;
const SceneReady = shared.SceneReady;
const SceneRoot = shared.SceneRoot;
const SceneSpawnPlan = shared.SceneSpawnPlan;
const Transform = common.Transform;
const Vec3 = common.Vec3;
const sponza_scene_path = shared.sponza_scene_path;
