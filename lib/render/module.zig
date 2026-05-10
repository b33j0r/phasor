//! ECS render module that manages renderer lifecycle and delegates frame stages.
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
    if (!commands.hasResource(SurfaceRefreshRequest)) {
        try commands.insertResource(SurfaceRefreshRequest{});
    }
    if (!commands.hasResource(ExtractedSceneLighting)) {
        try commands.insertResource(ExtractedSceneLighting{});
    }
    if (!commands.hasResource(ShadowSettings)) {
        try commands.insertResource(ShadowSettings{});
    }
    if (!commands.hasResource(render.ShadowMode)) {
        try commands.insertResource(render.ShadowMode.inherit);
    }
    if (!commands.hasResource(render.SceneStatsMode)) {
        try commands.insertResource(render.SceneStatsMode{});
    }
    if (!commands.hasResource(render.SceneStatsSnapshot)) {
        try commands.insertResource(render.SceneStatsSnapshot{});
    }
    if (!commands.hasResource(render.EnvironmentSpecularMode)) {
        try commands.insertResource(render.EnvironmentSpecularMode.on);
    }
    if (!commands.hasResource(render.SceneDebugView)) {
        try commands.insertResource(render.SceneDebugView.off);
    }
    if (!commands.hasResource(render.CoreShaders)) {
        try commands.insertResource(render.CoreShaders{});
    }
    try commands.registerEvent(common.WindowResized, 8);
    try commands.registerEvent(common.WindowMoved, 8);
    try commands.registerEvent(common.ContentScaleChanged, 8);
    if (!commands.isEmpty()) {
        try commands.apply();
    }

    try app.addSystem(schedule.DefaultSchedule.WindowCreate, initSystem);
    try app.addSystem(schedule.DefaultSchedule.AssetsLoad, ensureAssetsContextSystem);
    try app.addSystem(schedule.DefaultSchedule.AssetsLoad, ensureBuildContextSystem);
    try app.addSystem("BeforeFrame", initSystem);
    try app.addSystem("BeforeFrame", ensureAssetsContextSystem);
    try app.addSystem("BeforeFrame", ensureBuildContextSystem);
    try app.addSystem("BeforeFrame", render_prepare.handleViewportResize);
    try app.addSystem("BeforeFrame", render_prepare.handleSurfaceMove);
    try app.addSystem("BeforeFrame", render_prepare.handleSurfaceScaleChange);
    try app.addSystem("BeforeFrame", render_prepare.applyPendingSurfaceRefresh);
    try render_shape.ShapesModule.install(app, commands);
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
    app.removeSystem(ensureBuildContextSystem);
    app.removeSystem(render_prepare.handleViewportResize);
    app.removeSystem(render_prepare.handleSurfaceMove);
    app.removeSystem(render_prepare.handleSurfaceScaleChange);
    app.removeSystem(render_prepare.applyPendingSurfaceRefresh);
    app.removeSystem(render_prepare.updateTextMeshes);
    app.removeSystem(render_prepare.updateLayerCameras);
    app.removeSystem(render_extract.extractSystem);
    app.removeSystem(render_prepare.cleanupUnusedMeshes);
    app.removeSystem(render_submit.renderSystem);
    app.removeSystem(shutdownSystem);
    render_shape.ShapesModule.uninstall(app);
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
    var shadow_shader_uv2 = try renderer.createShadowShader(.{
        .wgsl = @embedFile("shaders/shadow_caster_uv2.wgsl"),
        .vertex_layout = .uv2,
        .binding_mode = .material,
    });
    errdefer renderer.destroyShadowShader(&shadow_shader_uv2);
    var shadow_shader_pos3_uv2 = try renderer.createShadowShader(.{
        .wgsl = @embedFile("shaders/shadow_caster_pos3_uv2.wgsl"),
        .vertex_layout = .pos3_uv2,
        .binding_mode = .material,
    });
    errdefer renderer.destroyShadowShader(&shadow_shader_pos3_uv2);
    var shadow_shader_pos3_norm_uv2 = try renderer.createShadowShader(.{
        .wgsl = @embedFile("shaders/shadow_caster_pos3_norm_uv2.wgsl"),
        .vertex_layout = .pos3_norm_uv2,
        .binding_mode = .material,
    });
    errdefer renderer.destroyShadowShader(&shadow_shader_pos3_norm_uv2);
    var shadow_shader_pos3_norm_tangent_uv2 = try renderer.createShadowShader(.{
        .wgsl = @embedFile("shaders/shadow_caster_pos3_norm_tangent_uv2.wgsl"),
        .vertex_layout = .pos3_norm_tangent_uv2,
        .binding_mode = .material,
    });
    errdefer renderer.destroyShadowShader(&shadow_shader_pos3_norm_tangent_uv2);
    var shadow_shader_pos3_color4 = try renderer.createShadowShader(.{
        .wgsl = @embedFile("shaders/shadow_caster_pos3_color4.wgsl"),
        .vertex_layout = .pos3_color4,
        .binding_mode = .none,
    });
    errdefer renderer.destroyShadowShader(&shadow_shader_pos3_color4);

    var font = render.Font.orbitronDefault();
    try font.load(commands.allocator, &renderer, sampler);
    errdefer font.unload(commands.allocator, &renderer);

    try commands.insertResource(RenderState{
        .renderer = renderer,
        .surface = surface_res.target,
        .default_sampler = sampler,
        .default_texture = texture,
        .default_material = material,
        .shadow_shader_uv2 = shadow_shader_uv2,
        .shadow_shader_pos3_uv2 = shadow_shader_pos3_uv2,
        .shadow_shader_pos3_norm_uv2 = shadow_shader_pos3_norm_uv2,
        .shadow_shader_pos3_norm_tangent_uv2 = shadow_shader_pos3_norm_tangent_uv2,
        .shadow_shader_pos3_color4 = shadow_shader_pos3_color4,
        .submit_scratch = render_types.SubmitScratch.init(commands.allocator),
    });

    try commands.insertResource(render.DefaultFont{ .font = font });

    if (!commands.hasResource(render.MeshLibrary)) {
        try commands.insertResource(render.MeshLibrary.init(commands.allocator));
    }
    if (!commands.hasResource(render.FontLibrary)) {
        try commands.insertResource(render.FontLibrary.init(commands.allocator));
    }
    if (!commands.hasResource(render.ShaderLibrary)) {
        try commands.insertResource(render.ShaderLibrary.init(commands.allocator));
    }
    if (!commands.hasResource(render.PostProcessShaderLibrary)) {
        try commands.insertResource(render.PostProcessShaderLibrary.init(commands.allocator));
    }
    if (!commands.hasResource(render.TextureLibrary)) {
        try commands.insertResource(render.TextureLibrary.init(commands.allocator));
    }
    if (!commands.hasResource(render.MaterialLibrary)) {
        try commands.insertResource(render.MaterialLibrary.init(commands.allocator));
    }
    try ensureCoreShaders(commands);
    if (!commands.isEmpty()) {
        try commands.apply();
    }
    log.debug("renderer core resources initialized", .{});
}

fn ensureCoreShaders(commands: *Commands) !void {
    const state = commands.getResourceMut(RenderState) orelse return;
    const shader_library = commands.getResourceMut(render.ShaderLibrary) orelse return;
    const existing = commands.getResource(render.CoreShaders) orelse return;
    if (existing.color_pos3_color4.isValid() and existing.simple_shadow_lit.isValid() and existing.sky_procedural_layered.isValid() and existing.sky_procedural_atmospheric.isValid() and existing.sky_panorama_hdr.isValid()) {
        return;
    }

    var core = render.CoreShaders{};

    core.color_pos3_color4 = try createCoreShader(&state.renderer, shader_library, .{
        .wgsl = render.CoreShaderSources.color_pos3_color4_wgsl,
        .vertex_layout = .pos3_color4,
        .binding_mode = .none,
    });
    errdefer _ = shader_library.destroyShader(&state.renderer, core.color_pos3_color4);

    core.simple_shadow_lit = try createCoreShader(&state.renderer, shader_library, .{
        .wgsl = render.CoreShaderSources.simple_shadow_lit_wgsl,
        .vertex_layout = .pos3_norm_uv2,
        .binding_mode = .material_scene,
    });
    errdefer _ = shader_library.destroyShader(&state.renderer, core.simple_shadow_lit);

    core.sky_procedural_layered = try createCoreShader(&state.renderer, shader_library, .{
        .wgsl = render.CoreShaderSources.sky_procedural_layered_wgsl,
        .vertex_layout = .pos3_uv2,
        .binding_mode = .material_scene,
    });
    errdefer _ = shader_library.destroyShader(&state.renderer, core.sky_procedural_layered);

    core.sky_procedural_atmospheric = try createCoreShader(&state.renderer, shader_library, .{
        .wgsl = render.CoreShaderSources.sky_procedural_atmospheric_wgsl,
        .vertex_layout = .pos3_uv2,
        .binding_mode = .material_scene,
    });
    errdefer _ = shader_library.destroyShader(&state.renderer, core.sky_procedural_atmospheric);

    core.sky_panorama_hdr = try createCoreShader(&state.renderer, shader_library, .{
        .wgsl = render.CoreShaderSources.sky_panorama_hdr_wgsl,
        .vertex_layout = .pos3_uv2,
        .binding_mode = .material_scene,
    });
    errdefer _ = shader_library.destroyShader(&state.renderer, core.sky_panorama_hdr);

    if (commands.getResourceMut(render.CoreShaders)) |core_res| {
        core_res.* = core;
    } else {
        try commands.insertResource(core);
    }
}

fn createCoreShader(
    renderer: *render.Renderer,
    shader_library: *render.ShaderLibrary,
    source: render.ShaderSource,
) !render.ShaderHandle {
    const shader = try renderer.createShader(source);
    errdefer {
        var cleanup = shader;
        renderer.destroyShader(&cleanup);
    }
    return shader_library.addShader(shader);
}

fn ensureAssetsContextSystem(commands: *Commands) !void {
    if (commands.hasResource(render.AssetsContext)) return;
    const state = commands.getResourceMut(RenderState) orelse return;
    const mesh_library = commands.getResourceMut(render.MeshLibrary) orelse return;
    const font_library = commands.getResourceMut(render.FontLibrary) orelse return;
    const shader_library = commands.getResourceMut(render.ShaderLibrary) orelse return;
    const post_process_shader_library = commands.getResourceMut(render.PostProcessShaderLibrary) orelse return;
    const texture_library = commands.getResourceMut(render.TextureLibrary) orelse return;
    const material_library = commands.getResourceMut(render.MaterialLibrary) orelse return;
    try commands.insertResource(render.AssetsContext{
        .allocator = commands.allocator,
        .io = commands.io,
        .renderer = &state.renderer,
        .sampler = &state.default_sampler,
        .font_library = font_library,
        .mesh_library = mesh_library,
        .shader_library = shader_library,
        .post_process_shader_library = post_process_shader_library,
        .texture_library = texture_library,
        .material_library = material_library,
    });
    log.debug("AssetsContext ready", .{});
}

fn ensureBuildContextResource(commands: *Commands) !void {
    if (commands.hasResource(render.BuildContext)) return;
    const state = commands.getResourceMut(RenderState) orelse return;
    const mesh_library = commands.getResourceMut(render.MeshLibrary) orelse return;
    const font_library = commands.getResourceMut(render.FontLibrary) orelse return;
    const shader_library = commands.getResourceMut(render.ShaderLibrary) orelse return;
    const post_process_shader_library = commands.getResourceMut(render.PostProcessShaderLibrary) orelse return;
    const texture_library = commands.getResourceMut(render.TextureLibrary) orelse return;
    const material_library = commands.getResourceMut(render.MaterialLibrary) orelse return;

    try commands.insertResource(render.BuildContext{
        .allocator = commands.allocator,
        .renderer = &state.renderer,
        .default_sampler = &state.default_sampler,
        .mesh_library = mesh_library,
        .shader_library = shader_library,
        .post_process_shader_library = post_process_shader_library,
        .texture_library = texture_library,
        .material_library = material_library,
        .font_library = font_library,
    });
    log.debug("BuildContext ready", .{});
}

fn ensureBuildContextSystem(commands: *Commands) !void {
    try ensureBuildContextResource(commands);
}

fn shutdownSystem(commands: *Commands) void {
    const state = commands.getResourceMut(RenderState) orelse {
        _ = commands.removeResource(render_shape.GeneratedMeshCache);
        _ = commands.removeResource(LayerCameras);
        _ = commands.removeResource(LayerViewports);
        _ = commands.removeResource(render.MeshLibrary);
        _ = commands.removeResource(render.FontLibrary);
        _ = commands.removeResource(render.ShaderLibrary);
        _ = commands.removeResource(render.PostProcessShaderLibrary);
        _ = commands.removeResource(render.TextureLibrary);
        _ = commands.removeResource(render.MaterialLibrary);
        _ = commands.removeResource(render.RenderQueue);
        _ = commands.removeResource(render.BuildContext);
        _ = commands.removeResource(render.DefaultFont);
        _ = commands.removeResource(render.CoreShaders);
        _ = commands.removeResource(render.SceneStatsMode);
        _ = commands.removeResource(render.SceneStatsSnapshot);
        _ = commands.removeResource(ShadowSettings);
        _ = commands.removeResource(render.ShadowMode);
        _ = commands.removeResource(render.SceneDebugView);
        return;
    };

    if (commands.getResourceMut(render.MeshLibrary)) |library| {
        library.destroyMeshes(&state.renderer);
        _ = commands.removeResource(render.MeshLibrary);
    }
    if (commands.getResourceMut(render.FontLibrary)) |library| {
        library.destroyFonts(commands.allocator, &state.renderer);
        _ = commands.removeResource(render.FontLibrary);
    }
    if (commands.getResourceMut(render.ShaderLibrary)) |library| {
        library.destroyShaders(&state.renderer);
        _ = commands.removeResource(render.ShaderLibrary);
    }
    if (commands.getResourceMut(render.PostProcessShaderLibrary)) |library| {
        library.destroyShaders(&state.renderer);
        _ = commands.removeResource(render.PostProcessShaderLibrary);
    }
    if (commands.getResourceMut(render.MaterialLibrary)) |library| {
        library.destroyMaterials(&state.renderer);
        _ = commands.removeResource(render.MaterialLibrary);
    }
    if (commands.getResourceMut(render.TextureLibrary)) |library| {
        library.destroyTextures(&state.renderer);
        _ = commands.removeResource(render.TextureLibrary);
    }

    _ = commands.removeResource(render_shape.GeneratedMeshCache);

    if (commands.getResourceMut(render.DefaultFont)) |font| {
        font.font.unload(commands.allocator, &state.renderer);
        _ = commands.removeResource(render.DefaultFont);
    }

    _ = commands.removeResource(LayerCameras);
    _ = commands.removeResource(LayerViewports);
    _ = commands.removeResource(ExtractedSceneLighting);
    _ = commands.removeResource(render.CoreShaders);
    _ = commands.removeResource(render.SceneStatsMode);
    _ = commands.removeResource(render.SceneStatsSnapshot);
    _ = commands.removeResource(ShadowSettings);
    _ = commands.removeResource(render.ShadowMode);
    _ = commands.removeResource(render.SceneDebugView);
    _ = commands.removeResource(render.AssetsContext);
    _ = commands.removeResource(render.BuildContext);
    _ = commands.removeResource(render.RenderQueue);
    _ = commands.removeResource(RenderState);
    log.debug("renderer resources released", .{});
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
const render = @import("root.zig");
const render_types = @import("types.zig");
const render_prepare = @import("prepare.zig");
const render_extract = @import("extract.zig");
const render_submit = @import("submit.zig");
const render_shadows = @import("shadows.zig");
const render_shape = @import("shape.zig");
const std = @import("std");

const AppCommands = ecs.AppCommands;
const Commands = ecs.Commands;
const ResMut = ecs.system_params.ResMut;
const ResOpt = ecs.system_params.ResOpt;
const schedule = ecs.schedule;
const log = std.log.scoped(.render_module);

pub const RenderSurface = render_types.RenderSurface;
pub const RenderState = render_types.RenderState;
pub const ViewportSize = render_types.ViewportSize;
pub const FramebufferSize = render_types.FramebufferSize;
pub const RenderRecovery = render_types.RenderRecovery;
pub const SurfaceRefreshRequest = render_types.SurfaceRefreshRequest;
pub const ShapesModule = render_shape.ShapesModule;
pub const GeneratedMeshCache = render_shape.GeneratedMeshCache;
pub const GeneratedMeshKey = render_shape.GeneratedMeshKey;
pub const GeneratedMeshInstance = render_shape.GeneratedMeshInstance;
pub const LayerCameras = render_types.LayerCameras;
pub const LayerCamera = render_types.LayerCamera;
pub const LayerViewports = render_types.LayerViewports;
pub const ExtractedSceneLighting = render_types.ExtractedSceneLighting;
pub const ShadowSettings = render_types.ShadowSettings;
pub const ShadowTechnique = render_shadows.ShadowTechnique;
