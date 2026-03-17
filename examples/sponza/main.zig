pub const std_options = phasor.common.logging.stdOptions(.debug);

const sponza_metric_lines = [_]modules.MetricLine{
    modules.lineFormat(-90, gameplay.formatPlayerPositionLine),
};

const App = struct {
    pub const options = platform.Options{
        .vsync = true,
        .window = .{
            .title = "Sponza",
            .width = 1440,
            .height = 900,
        },
    };

    pub fn configure(app: *ecs.App) !void {
        try platform.installDefaultModules(app);
        try app.installModule(phases.SponzaPhases);
        try app.installModule(modules.ParentModule);
        try app.installModule(modules.SkyModule);
        try app.installModule(modules.LightingModule);
        try app.installModule(physics.PhysicsModule{
            .config = .{
                .backend = .Jolt,
                .fixed_dt = 1.0 / 60.0,
                .max_substeps = 8,
                .gravity = .{ .x = 0.0, .y = -18.0, .z = 0.0 },
            },
        });
        try app.installModule(FpsPhysics{});
        try app.installModule(modules.FpsKeyBindingModule{});
        try app.installModule(modules.AssetsModule(Assets));
        try app.installModule(modules.MetricsModuleLayered(render.Layer(1000)){
            .font_size = 28.0,
            .text_color = Color.WHITE,
            .buffer_capacity = 768,
            .extra_builtin_lines = &.{
                .mouse_look,
                .scene_stats,
                .light_stats,
                .color_grade,
            },
            .extra_lines = &sponza_metric_lines,
        });

        try app.addSystemTo("Startup", loading.ensureSceneLoader);
        try app.addSystemTo("BeforeFrame", loading.ensureSceneLoader);
        try app.addSystemTo("BeforeFrame", loading.ensureLoadingScreenVisuals);
        try app.addSystemTo("BeforeFrame", loading.drainSceneLoader);
        try app.addSystemTo("BeforeFrame", loading.advanceSceneFinalize);
        try app.addSystemTo("Startup", lighting.setupColorGrading);
        try app.addSystemTo("BeforeFrame", lighting.setupColorGrading);
        try app.addSystemTo("Startup", lighting.setupLighting);
        try app.addSystemTo("BeforeFrame", lighting.setupLighting);
        try app.addSystemTo("Update", gameplay.spawnPlayerFromCollision);
        try app.addSystemTo("Update", gameplay.handlePhaseInput);
        try app.addSystemTo("Update", gameplay.cycleColorGradeInput);
        try app.addSystemTo("Update", gameplay.updatePlayerCamera);
        try app.addSystemTo("Update", gameplay.emitSponzaHudMetrics);
        try app.addSystemTo("Update", gameplay.logPlayerBookmark);
        try app.addSystemTo("Update", lighting.animateLights);
        try app.addSystemTo("Update", loading.updateLoadingScreen);
        try app.addSystemTo("Shutdown", loading.unloadImportedScene);
    }
};

pub const main = platform.main(App);

// Imports
const phasor = @import("phasor");
const phases = @import("phases.zig");
const loading = @import("loading.zig");
const gameplay = @import("gameplay.zig");
const lighting = @import("lighting.zig");
const Assets = @import("shared.zig").Assets;
const FpsPhysics = @import("shared.zig").FpsPhysics;

const common = phasor.common;
const ecs = phasor.ecs;
const modules = phasor.modules;
const physics = phasor.physics;
const platform = phasor.platform;
const render = phasor.renderer;
const Color = common.Color;
