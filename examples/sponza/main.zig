const phasor = @import("phasor");
const s = @import("shared.zig");
const phases = @import("phases.zig");
const loading = @import("loading.zig");
const gameplay = @import("gameplay.zig");
const lighting = @import("lighting.zig");

pub const std_options = phasor.common.logging.stdOptions(.debug);

const sponza_metric_lines = [_]s.modules.MetricLine{
    s.modules.lineFormat(-90, gameplay.formatPlayerPositionLine),
};

const App = struct {
    pub const options = s.platform.Options{
        .vsync = true,
        .window = .{
            .title = "Sponza",
            .width = 1440,
            .height = 900,
        },
    };

    pub fn configure(app: *s.ecs.App) !void {
        try s.platform.installDefaultModules(app);
        try app.installModule(phases.SponzaPhases);
        try app.installModule(s.modules.ParentModule);
        try app.installModule(s.modules.SkyModule);
        try app.installModule(s.modules.LightingModule);
        try app.installModule(s.physics.PhysicsModule{
            .config = .{
                .backend = .Jolt,
                .fixed_dt = 1.0 / 60.0,
                .max_substeps = 8,
                .gravity = .{ .x = 0.0, .y = -18.0, .z = 0.0 },
            },
        });
        try app.installModule(s.FpsPhysics{});
        try app.installModule(s.modules.AssetsModule(s.Assets));
        try app.installModule(s.modules.MetricsModuleLayered(s.render.Layer(1000)){
            .font_size = 28.0,
            .text_color = s.Color.WHITE,
            .buffer_capacity = 768,
            .extra_builtin_lines = &.{
                .mouse_look,
                .scene_stats,
                .light_stats,
            },
            .extra_lines = &sponza_metric_lines,
        });

        try app.addSystemTo("Startup", loading.ensureSceneLoader);
        try app.addSystemTo("BeforeFrame", loading.ensureSceneLoader);
        try app.addSystemTo("BeforeFrame", loading.ensureLoadingScreenVisuals);
        try app.addSystemTo("BeforeFrame", loading.drainSceneLoader);
        try app.addSystemTo("BeforeFrame", loading.advanceSceneFinalize);
        try app.addSystemTo("Startup", lighting.setupLighting);
        try app.addSystemTo("BeforeFrame", lighting.setupLighting);
        try app.addSystemTo("Update", gameplay.spawnPlayerFromCollision);
        try app.addSystemTo("Update", gameplay.handlePhaseInput);
        try app.addSystemTo("Update", gameplay.updatePlayerCamera);
        try app.addSystemTo("Update", gameplay.emitSponzaHudMetrics);
        try app.addSystemTo("Update", gameplay.logPlayerBookmark);
        try app.addSystemTo("Update", lighting.animateLights);
        try app.addSystemTo("Update", loading.updateLoadingScreen);
        try app.addSystemTo("Shutdown", loading.unloadImportedScene);
    }
};

pub const main = s.platform.main(App);
