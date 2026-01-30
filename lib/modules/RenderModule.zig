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

pub fn install(app: *AppCommands, commands: *Commands) !void {
    if (!commands.hasResource(common.ClearColor)) {
        try commands.insertResource(common.ClearColor{});
    }

    try app.addSystem(schedule.DefaultSchedule.BeforeFrame, initSystem);
    try app.addSystem(schedule.DefaultSchedule.AfterFrame, renderSystem);
    try app.addSystem(schedule.DefaultSchedule.Shutdown, shutdownSystem);
}

pub fn uninstall(app: *AppCommands) void {
    app.removeSystem(initSystem);
    app.removeSystem(renderSystem);
    app.removeSystem(shutdownSystem);
}

fn initSystem(commands: *Commands) !void {
    if (commands.getResource(RenderState) != null) return;

    const surface_res = commands.getResource(RenderSurface) orelse return;
    const config = if (commands.getResource(render.RendererConfig)) |cfg| cfg.* else render.RendererConfig{};

    var renderer = try render.Renderer.init(commands.allocator, surface_res.target, config);
    errdefer renderer.deinit();

    var sampler = try renderer.createSampler();
    errdefer renderer.destroySampler(&sampler);

    const white = [_]u8{ 255, 255, 255, 255 };
    var texture = try renderer.createTextureRgba8(1, 1, white[0..]);
    errdefer renderer.destroyTexture(&texture);

    const material = try renderer.createMaterial(texture, sampler);

    try commands.insertResource(RenderState{
        .renderer = renderer,
        .surface = surface_res.target,
        .default_sampler = sampler,
        .default_texture = texture,
        .default_material = material,
    });

    if (!commands.hasResource(render.MeshLibrary)) {
        try commands.insertResource(render.MeshLibrary.init(commands.allocator));
    }
}

fn renderSystem(
    commands: *Commands,
    clear_opt: ResOpt(common.ClearColor),
    mesh_query: Query(.{ render.MeshInstance }),
    triangle_query: Query(.{ render.Triangle }),
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

    var tri_it = triangle_query.iterator();
    while (tri_it.next()) |row| {
        const tri = row.get(render.Triangle) orelse continue;
        frame.draw(.{ .triangle = tri.* });
    }

    var it = mesh_query.iterator();
    while (it.next()) |row| {
        const instance = row.get(render.MeshInstance) orelse continue;
        const mesh = mesh_library.get(instance.mesh_handle) orelse continue;

        const color_f = common.Color.F32.fromColor(instance.color);
        const gpu_instance = render.BackendMeshInstance{
            .transform = instance.transform,
            .color = .{ color_f.r, color_f.g, color_f.b, color_f.a },
        };

        frame.draw(.{ .textured_quad = .{
            .mesh = mesh.*,
            .material = state.default_material,
            .instance = gpu_instance,
        } });
    }

    try frame.endFrame();
}

fn shutdownSystem(commands: *Commands) void {
    const state = commands.getResourceMut(RenderState) orelse {
        _ = commands.removeResource(render.MeshLibrary);
        return;
    };

    if (commands.getResourceMut(render.MeshLibrary)) |library| {
        library.destroyMeshes(&state.renderer);
        _ = commands.removeResource(render.MeshLibrary);
    }

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
const ResOpt = system_params.ResOpt;
