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

pub fn install(app: *AppCommands, commands: *Commands) !void {
    if (!commands.hasResource(common.ClearColor)) {
        try commands.insertResource(common.ClearColor{});
    }
    if (!commands.hasResource(render.RenderQueue)) {
        try commands.insertResource(render.RenderQueue.init(commands.allocator));
    }
    try commands.registerEvent(common.WindowResized, 8);
    if (!commands.isEmpty()) {
        try commands.apply();
    }

    try app.addSystem(schedule.DefaultSchedule.BeforeFrame, initSystem);
    try app.addSystem(schedule.DefaultSchedule.BeforeFrame, handleViewportResize);
    try app.addSystem(schedule.DefaultSchedule.BeforeFrame, updateSpriteMeshes);
    try app.addSystem(schedule.DefaultSchedule.BeforeFrame, updateTextMeshes);
    try app.addSystem(schedule.DefaultSchedule.BeforeFrame, extractSystem);
    try app.addSystem(schedule.DefaultSchedule.AfterFrame, renderSystem);
    try app.addSystem(schedule.DefaultSchedule.Shutdown, shutdownSystem);
}

pub fn uninstall(app: *AppCommands) void {
    app.removeSystem(initSystem);
    app.removeSystem(handleViewportResize);
    app.removeSystem(updateSpriteMeshes);
    app.removeSystem(updateTextMeshes);
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
        try queue.ptr.pushTriangle(tri.*);
    }

    var it = mesh_query.iterator();
    while (it.next()) |row| {
        const instance = row.get(render.MeshInstance) orelse continue;
        const transform = row.get(common.Transform) orelse continue;
        const material = row.get(render.MaterialInstance) orelse continue;
        try queue.ptr.pushMeshInstanceWithMaterial(instance.*, transform.toMat4(), material.material);
    }

    var default_it = mesh_default_query.iterator();
    while (default_it.next()) |row| {
        const instance = row.get(render.MeshInstance) orelse continue;
        const transform = row.get(common.Transform) orelse continue;
        try queue.ptr.pushMeshInstance(instance.*, transform.toMat4());
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
            .{ .position = .{ -half_w, -half_h }, .uv = .{ 0.0, 1.0 } },
            .{ .position = .{ half_w, -half_h }, .uv = .{ 1.0, 1.0 } },
            .{ .position = .{ half_w, half_h }, .uv = .{ 1.0, 0.0 } },
            .{ .position = .{ -half_w, half_h }, .uv = .{ 0.0, 0.0 } },
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

fn renderSystem(
    commands: *Commands,
    queue: ResMut(render.RenderQueue),
    clear_opt: ResOpt(common.ClearColor),
    camera_opt: ResOpt(common.Camera3d),
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

    const viewport = if (camera_opt.ptr) |cam| switch (cam.*) {
        .Viewport => |vp| vp,
        else => null,
    } else null;
    const viewport_size = if (viewport_opt.ptr) |vp|
        render.Size{ .width = @intFromFloat(vp.width), .height = @intFromFloat(vp.height) }
    else
        surface_size;
    const viewport_matrix = if (viewport) |vp|
        viewportMatrix(vp, viewport_size)
    else
        null;

    for (queue.ptr.items.items) |item| {
        switch (item) {
            .triangle => |tri| {
                const draw_tri = if (viewport) |vp|
                    applyViewport(tri, vp, viewport_size)
                else
                    tri;
                frame.draw(.{ .triangle = draw_tri });
            },
            .mesh => |instance| {
                if (instance.blend) continue;
                const mesh = mesh_library.get(instance.mesh_handle) orelse continue;
                const model = if (viewport_matrix) |vp|
                    common.Mat4.mul(vp, instance.transform)
                else
                    instance.transform;

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

    for (queue.ptr.items.items) |item| {
        switch (item) {
            .mesh => |instance| {
                if (!instance.blend) continue;
                const mesh = mesh_library.get(instance.mesh_handle) orelse continue;
                const model = if (viewport_matrix) |vp|
                    common.Mat4.mul(vp, instance.transform)
                else
                    instance.transform;

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
            else => {},
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

fn viewportMatrix(vp: anytype, size: render.Size) common.Mat4 {
    const w = @as(f32, @floatFromInt(size.width));
    const h = @as(f32, @floatFromInt(size.height));
    if (w == 0.0 or h == 0.0) return common.Mat4.identity();
    return switch (vp.mode) {
        .TopLeft => common.Mat4.orthographic(0.0, w, h, 0.0, vp.near, vp.far),
        .Center => common.Mat4.orthographic(-w * 0.5, w * 0.5, -h * 0.5, h * 0.5, vp.near, vp.far),
    };
}

fn applyViewport(tri: render.Triangle, vp: anytype, size: render.Size) render.Triangle {
    var out = tri;
    for (&out.vertices) |*v| {
        const ndc = switch (vp.mode) {
            .TopLeft => positionToNdcTopLeft(v.position, size),
            .Center => positionToNdcCenter(v.position, size),
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

    _ = commands.removeResource(render.RenderQueue);
    _ = commands.removeResource(RenderState);
}

// Imports
const common = @import("common");
const ecs = @import("ecs");
const render = @import("render");
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
