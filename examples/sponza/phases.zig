pub const SponzaPhases = modules.PhasesModule.Definition(SponzaPhase, SponzaPhase{ .Loading = .{} });

pub const SponzaPhase = union(enum) {
    Loading: Loading,
    InGame: InGame,
};

pub const Loading = struct {
    pub fn enter(_: *Loading, ctx: *modules.PhasesModule.PhaseContext) !void {
        var commands = ecs.Commands.init(ctx.allocator, ctx.io, ctx.world);
        defer commands.deinit();
        if (!commands.hasResource(shared.SceneLoaderState)) {
            try loading.ensureSceneLoaderPresent(&commands);
        }
        if (!commands.hasResource(render.ColorGradingSettings)) {
            try lighting.ensureColorGrading(&commands);
        }
        try modules.TimeModule.setPaused(&commands, false);
        if (!commands.isEmpty()) {
            try commands.apply();
        }

        try ctx.addSystem(schedule.DefaultSchedule.BeforeFrame, loading.ensureSceneLoader);
        try ctx.addSystem(schedule.DefaultSchedule.BeforeFrame, loading.ensureLoadingScreenVisuals);
        try ctx.addSystem(schedule.DefaultSchedule.BeforeFrame, loading.drainSceneLoader);
        try ctx.addSystem(schedule.DefaultSchedule.BeforeFrame, loading.advanceSceneFinalize);
        try ctx.addSystem(schedule.DefaultSchedule.BeforeFrame, lighting.setupLighting);
        try ctx.addSystem(schedule.DefaultSchedule.BeforeFrame, lighting.setupSkyCycle);
        try ctx.addSystem(schedule.DefaultSchedule.BeforeFrame, particles.setupLionFire);
        try ctx.addSystem(schedule.DefaultSchedule.Update, loading.updateLoadingScreen);

        try commands.insertResource(ClearColor{ .color = Color.BLACK });

        const camera_entity = try commands.createEntity(.{
            Transform{},
            Camera3d{ .Viewport = .{ .mode = .TopLeft } },
            CameraLayer(1001){},
            LoadingScreen{},
        });

        const text_entity = try commands.createEntity(.{
            Transform{},
            render.Text{
                .content = "Sponza\nBooting...",
                .font_size = 28.0,
                .color = Color.rgb(230, 232, 236),
                .horizontal_alignment = .Center,
                .vertical_alignment = .Center,
            },
            render.Layer(1001){},
            LoadingScreen{},
            LoadingScreenText{},
        });

        try commands.insertResource(LoadingScreenState{
            .camera_entity = camera_entity,
            .text_entity = text_entity,
        });
        if (!commands.isEmpty()) {
            try commands.apply();
        }
    }

    pub fn exit(_: *Loading, ctx: *modules.PhasesModule.PhaseContext) !void {
        var commands = ecs.Commands.init(ctx.allocator, ctx.io, ctx.world);
        defer commands.deinit();
        if (ctx.world.getResource(LoadingScreenState)) |state| {
            try commands.removeEntity(state.text_entity);
            try commands.removeEntity(state.camera_entity);
            _ = commands.removeResource(LoadingScreenState);
        }
        if (ctx.world.getResource(LoadingScreenVisualState)) |state| {
            try commands.removeEntity(state.fill_entity);
            try commands.removeEntity(state.track_entity);
            _ = commands.removeResource(LoadingScreenVisualState);
        }
        if (!commands.isEmpty()) {
            try commands.apply();
        }
    }
};

pub const InGame = union(enum) {
    Playing: Playing,
    Paused: Paused,

    pub fn enter(_: *InGame, ctx: *modules.PhasesModule.PhaseContext) !void {
        var commands = ecs.Commands.init(ctx.allocator, ctx.io, ctx.world);
        defer commands.deinit();
        const camera_entity = try commands.createEntity(.{
            Transform{},
            Camera3d{ .Viewport = .{ .mode = .TopLeft } },
            CameraLayer(1000){},
            HudCameraTag{},
        });
        try commands.insertResource(HudCameraState{ .camera_entity = camera_entity });
        if (!commands.isEmpty()) {
            try commands.apply();
        }

        try ctx.addSystem(schedule.DefaultSchedule.Update, gameplay.handlePhaseInput);
        try ctx.addSystem(schedule.DefaultSchedule.Update, gameplay.cycleColorGradeInput);
        try ctx.addSystem(schedule.DefaultSchedule.Update, gameplay.cycleDebugViewInput);
        try ctx.addSystem(schedule.DefaultSchedule.Update, gameplay.toggleEnvironmentSpecularInput);
        try ctx.addSystem(schedule.DefaultSchedule.Update, gameplay.cycleNormalMapScaleInput);
        try ctx.addSystem(schedule.DefaultSchedule.Update, lighting.toggleSkyModeInput);
        try ctx.addSystem(schedule.DefaultSchedule.Update, lighting.updateDayNightWeather);
        try ctx.addSystem(schedule.DefaultSchedule.Update, lighting.updateProceduralSkyMeshParams);
        try ctx.addSystem(schedule.DefaultSchedule.Update, lighting.animateLights);
        try ctx.addSystem(schedule.DefaultSchedule.Update, gameplay.emitSponzaHudMetrics);
        try ctx.addSystem(schedule.DefaultSchedule.Update, gameplay.captureScreenshotInput);
    }

    pub fn exit(_: *InGame, ctx: *modules.PhasesModule.PhaseContext) !void {
        var commands = ecs.Commands.init(ctx.allocator, ctx.io, ctx.world);
        defer commands.deinit();
        if (ctx.world.getResource(HudCameraState)) |state| {
            try commands.removeEntity(state.camera_entity);
            _ = commands.removeResource(HudCameraState);
        }
        if (!commands.isEmpty()) {
            try commands.apply();
        }
    }
};

pub const Playing = struct {
    pub fn enter(_: *Playing, ctx: *modules.PhasesModule.PhaseContext) !void {
        var commands = ecs.Commands.init(ctx.allocator, ctx.io, ctx.world);
        defer commands.deinit();
        try commands.insertResource(MouseCapture{ .enabled = true });
        try modules.TimeModule.setPaused(&commands, false);
        if (!commands.isEmpty()) {
            try commands.apply();
        }

        try ctx.addSystem(schedule.DefaultSchedule.Update, gameplay.spawnPlayerFromCollision);
        try ctx.addSystem(schedule.DefaultSchedule.Update, gameplay.updatePlayerCamera);
        try ctx.addSystem(schedule.DefaultSchedule.Update, particles.updateLionFire);
        try ctx.addSystem(schedule.DefaultSchedule.Update, gameplay.logPlayerBookmark);
    }
};

pub const Paused = struct {
    pub fn enter(_: *Paused, ctx: *modules.PhasesModule.PhaseContext) !void {
        var commands = ecs.Commands.init(ctx.allocator, ctx.io, ctx.world);
        defer commands.deinit();
        try commands.insertResource(MouseCapture{ .enabled = false });
        try modules.TimeModule.setPaused(&commands, true);
        if (!commands.isEmpty()) {
            try commands.apply();
        }
    }
};

pub fn isPlayingPhase(current_phase: *const SponzaPhases.CurrentPhase) bool {
    return switch (current_phase.phase) {
        .Loading => false,
        .InGame => |in_game| switch (in_game) {
            .Playing => true,
            .Paused => false,
        },
    };
}

pub fn isPausedPhase(current_phase: *const SponzaPhases.CurrentPhase) bool {
    return switch (current_phase.phase) {
        .Loading => false,
        .InGame => |in_game| switch (in_game) {
            .Playing => false,
            .Paused => true,
        },
    };
}

// Imports
const phasor = @import("phasor");
const gameplay = @import("gameplay.zig");
const lighting = @import("lighting.zig");
const loading = @import("loading.zig");
const particles = @import("particles.zig");
const shared = @import("shared.zig");

const common = phasor.common;
const ecs = phasor.ecs;
const modules = phasor.modules;
const render = phasor.renderer;
const schedule = ecs.schedule;

const Camera3d = common.Camera3d;
const CameraLayer = render.CameraLayer;
const ClearColor = common.ClearColor;
const Color = common.Color;
const HudCameraState = shared.HudCameraState;
const HudCameraTag = shared.HudCameraTag;
const LoadingScreen = shared.LoadingScreen;
const LoadingScreenState = shared.LoadingScreenState;
const LoadingScreenText = shared.LoadingScreenText;
const LoadingScreenVisualState = shared.LoadingScreenVisualState;
const MouseCapture = modules.InputModule.MouseCapture;
const Transform = common.Transform;
