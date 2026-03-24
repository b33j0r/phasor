pub const std_options = phasor.common.logging.stdOptions(.debug);

const sponza_metric_lines = [_]modules.MetricLine{
    modules.lineFormat(-92, gameplay.formatEnvironmentSpecularLine),
    modules.lineFormat(-91, gameplay.formatDebugViewLine),
    modules.lineFormat(-90, gameplay.formatPlayerPositionLine),
    modules.withExtraText(
        modules.lineFormat(-80, gameplay.formatControlsMoveLine),
        "(WASD + Mouse)",
    ),
    modules.withExtraText(
        modules.lineFormat(-79, gameplay.formatControlsActionLine),
        "(Shift) Sprint  (Space) Jump",
    ),
    modules.withExtraText(
        modules.lineFormat(-78, gameplay.formatControlsModeLine),
        "(F) Fly  (H) Sky  (C) Grade  (V) View  (B) EnvSpec  (M) Bookmark",
    ),
    modules.withExtraText(
        modules.lineFormat(-77, gameplay.formatControlsCaptureLine),
        "(P) Shot  (O) AutoShot",
    ),
    modules.withExtraText(
        modules.lineFormat(-76, gameplay.formatControlsPauseLine),
        "(Esc) Pause  (Enter/Esc) Resume",
    ),
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
        var commands = ecs.Commands.init(app.allocator, app.io, &app.world);
        defer commands.deinit();
        try commands.insertResource(render.ShadowMode.off);
        try commands.insertResource(render.EnvironmentSpecularMode.on);
        try commands.insertResource(render.SceneDebugView.off);
        if (!commands.isEmpty()) try commands.apply();
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
            .font_size = 22.0,
            .text_color = Color.WHITE,
            .buffer_capacity = 768,
            .extra_builtin_lines = &.{
                modules.builtinLine(.mouse_look),
                modules.builtinLine(.scene_stats),
                modules.builtinLine(.light_stats),
                modules.builtinLineWithExtraText(.color_grade, "(C)"),
            },
            .extra_lines = &sponza_metric_lines,
        });
        try app.addSystemTo(ecs.schedule.DefaultSchedule.Shutdown, loading.unloadImportedScene);
    }
};

pub const main = platform.main(App);

// Imports
const phasor = @import("phasor");
const phases = @import("phases.zig");
const loading = @import("loading.zig");
const gameplay = @import("gameplay.zig");
const Assets = @import("shared.zig").Assets;
const FpsPhysics = @import("shared.zig").FpsPhysics;

const common = phasor.common;
const ecs = phasor.ecs;
const modules = phasor.modules;
const physics = phasor.physics;
const platform = phasor.platform;
const render = phasor.renderer;
const Color = common.Color;
