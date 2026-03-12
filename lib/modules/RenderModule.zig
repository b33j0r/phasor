//! ECS render module that manages renderer lifecycle and delegates frame stages.
const render_types = @import("render/types.zig");
const render_prepare = @import("render/prepare.zig");
const render_extract = @import("render/extract.zig");
const render_submit = @import("render/submit.zig");

pub const RenderSurface = render_types.RenderSurface;
pub const RenderState = render_types.RenderState;
pub const ViewportSize = render_types.ViewportSize;
pub const FramebufferSize = render_types.FramebufferSize;
pub const RenderRecovery = render_types.RenderRecovery;
pub const SpriteMeshCache = render_types.SpriteMeshCache;
pub const LayerCameras = render_types.LayerCameras;
pub const LayerCamera = render_types.LayerCamera;
pub const LayerViewports = render_types.LayerViewports;

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
    if (!commands.hasResource(RenderRecovery)) {
        try commands.insertResource(RenderRecovery{});
    }
    if (!commands.hasResource(SpriteMeshCache)) {
        try commands.insertResource(SpriteMeshCache.init(commands.allocator));
    }
    try commands.registerEvent(common.WindowResized, 8);
    if (!commands.isEmpty()) {
        try commands.apply();
    }

    try app.addSystem(schedule.DefaultSchedule.WindowCreate, initSystem);
    try app.addSystem(schedule.DefaultSchedule.AssetsLoad, ensureAssetsContextSystem);
    try app.addSystem("BeforeFrame", initSystem);
    try app.addSystem("BeforeFrame", ensureAssetsContextSystem);
    try app.addSystem("BeforeFrame", render_prepare.handleViewportResize);
    try app.addSystem("BeforeFrame", render_prepare.updateSpriteMeshes);
    try app.addSystem("BeforeFrame", render_prepare.updateTextMeshes);
    try app.addSystem("BeforeFrame", render_prepare.updateLayerCameras);
    try app.addSystem("BeforeFrame", render_extract.extractSystem);
    try app.addSystem(schedule.DefaultSchedule.Render, render_submit.renderSystem);
    try app.addSystem("AfterFrame", render_prepare.cleanupUnusedMeshes);
    try app.addSystem(schedule.DefaultSchedule.WindowDestroy, shutdownSystem);
}

pub fn uninstall(app: *AppCommands) void {
    app.removeSystem(initSystem);
    app.removeSystem(ensureAssetsContextSystem);
    app.removeSystem(render_prepare.handleViewportResize);
    app.removeSystem(render_prepare.updateSpriteMeshes);
    app.removeSystem(render_prepare.updateTextMeshes);
    app.removeSystem(render_prepare.updateLayerCameras);
    app.removeSystem(render_extract.extractSystem);
    app.removeSystem(render_prepare.cleanupUnusedMeshes);
    app.removeSystem(render_submit.renderSystem);
    app.removeSystem(shutdownSystem);
}

fn initSystem(commands: *Commands) !void {
    if (commands.getResource(RenderState) != null) return;
    try initRenderer(commands);
}

fn initRenderer(commands: *Commands) !void {
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
    if (!commands.hasResource(render.ShaderLibrary)) {
        try commands.insertResource(render.ShaderLibrary.init(commands.allocator));
    }
    if (!commands.hasResource(render.TextureLibrary)) {
        try commands.insertResource(render.TextureLibrary.init(commands.allocator));
    }
    if (!commands.hasResource(render.MaterialLibrary)) {
        try commands.insertResource(render.MaterialLibrary.init(commands.allocator));
    }
}

fn ensureAssetsContextSystem(commands: *Commands) !void {
    if (commands.hasResource(assets.AssetsContext)) return;
    const state = commands.getResourceMut(RenderState) orelse return;
    const mesh_library = commands.getResourceMut(render.MeshLibrary) orelse return;
    const shader_library = commands.getResourceMut(render.ShaderLibrary) orelse return;
    const texture_library = commands.getResourceMut(render.TextureLibrary) orelse return;
    const material_library = commands.getResourceMut(render.MaterialLibrary) orelse return;
    try commands.insertResource(assets.AssetsContext{
        .allocator = commands.allocator,
        .io = commands.io,
        .renderer = &state.renderer,
        .sampler = &state.default_sampler,
        .mesh_library = mesh_library,
        .shader_library = shader_library,
        .texture_library = texture_library,
        .material_library = material_library,
    });
}

fn shutdownSystem(commands: *Commands) void {
    const state = commands.getResourceMut(RenderState) orelse {
        _ = commands.removeResource(SpriteMeshCache);
        _ = commands.removeResource(LayerCameras);
        _ = commands.removeResource(LayerViewports);
        _ = commands.removeResource(render.MeshLibrary);
        _ = commands.removeResource(render.ShaderLibrary);
        _ = commands.removeResource(render.TextureLibrary);
        _ = commands.removeResource(render.MaterialLibrary);
        _ = commands.removeResource(render.RenderQueue);
        _ = commands.removeResource(render.DefaultFont);
        return;
    };

    if (commands.getResourceMut(render.MeshLibrary)) |library| {
        library.destroyMeshes(&state.renderer);
        _ = commands.removeResource(render.MeshLibrary);
    }
    if (commands.getResourceMut(render.ShaderLibrary)) |library| {
        library.destroyShaders(&state.renderer);
        _ = commands.removeResource(render.ShaderLibrary);
    }
    if (commands.getResourceMut(render.MaterialLibrary)) |library| {
        library.destroyMaterials(&state.renderer);
        _ = commands.removeResource(render.MaterialLibrary);
    }
    if (commands.getResourceMut(render.TextureLibrary)) |library| {
        library.destroyTextures(&state.renderer);
        _ = commands.removeResource(render.TextureLibrary);
    }

    _ = commands.removeResource(SpriteMeshCache);

    if (commands.getResourceMut(render.DefaultFont)) |font| {
        font.font.unload(commands.allocator, &state.renderer);
        _ = commands.removeResource(render.DefaultFont);
    }

    _ = commands.removeResource(LayerCameras);
    _ = commands.removeResource(LayerViewports);
    _ = commands.removeResource(assets.AssetsContext);
    _ = commands.removeResource(render.RenderQueue);
    _ = commands.removeResource(RenderState);
}

pub fn signalDeviceLost(commands: *Commands) void {
    if (commands.getResourceMut(RenderRecovery)) |recovery| {
        recovery.lost = true;
        recovery.restored = false;
        return;
    }
    _ = commands.insertResource(RenderRecovery{ .lost = true, .restored = false }) catch {};
}

pub fn signalDeviceRestored(commands: *Commands) void {
    if (commands.getResourceMut(RenderRecovery)) |recovery| {
        recovery.lost = false;
        recovery.restored = true;
        return;
    }
    _ = commands.insertResource(RenderRecovery{ .lost = false, .restored = true }) catch {};
}

pub fn setSurfaceSize(
    commands: *Commands,
    logical_width: u32,
    logical_height: u32,
    framebuffer_width: u32,
    framebuffer_height: u32,
) void {
    const size = render.Size{ .width = framebuffer_width, .height = framebuffer_height };
    if (commands.getResourceMut(RenderSurface)) |surface| {
        switch (surface.target) {
            .web => |*web| {
                web.size = size;
            },
            else => {},
        }
    }
    if (commands.getResourceMut(RenderState)) |state| {
        switch (state.surface) {
            .web => |*web| {
                web.size = size;
            },
            else => {},
        }
    }
    _ = commands.insertResource(ViewportSize{
        .width = @floatFromInt(logical_width),
        .height = @floatFromInt(logical_height),
    }) catch {};
    _ = commands.insertResource(FramebufferSize{
        .width = @floatFromInt(framebuffer_width),
        .height = @floatFromInt(framebuffer_height),
    }) catch {};
}

// Imports
const common = @import("common");
const ecs = @import("ecs");
const render = @import("render");
const assets = @import("assets");
const AppCommands = ecs.AppCommands;
const Commands = ecs.Commands;
const schedule = ecs.schedule;
