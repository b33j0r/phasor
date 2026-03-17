pub const SponzaPhases = modules.PhasesModule.Definition(SponzaPhase, SponzaPhase{ .Loading = .{} });

pub const SponzaPhase = union(enum) {
    Loading: Loading,
    InGame: InGame,
};

pub const Loading = struct {
    pub fn enter(_: *Loading, ctx: *modules.PhasesModule.PhaseContext) !void {
        try ctx.world.insertResource(ClearColor{ .color = Color.BLACK });

        const db = ctx.world.dbMut();
        const camera_entity = db.reserveEntityId();
        _ = try db.createEntityWithId(camera_entity, .{
            Transform{},
            Camera3d{ .Viewport = .{ .mode = .TopLeft } },
            CameraLayer(1001){},
            LoadingScreen{},
        });

        const text_entity = db.reserveEntityId();
        _ = try db.createEntityWithId(text_entity, .{
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

        try ctx.world.insertResource(LoadingScreenState{
            .camera_entity = camera_entity,
            .text_entity = text_entity,
        });
    }

    pub fn exit(_: *Loading, ctx: *modules.PhasesModule.PhaseContext) !void {
        if (ctx.world.getResource(LoadingScreenState)) |state| {
            ctx.world.dbMut().removeEntity(state.text_entity) catch {};
            ctx.world.dbMut().removeEntity(state.camera_entity) catch {};
            _ = ctx.world.removeResource(LoadingScreenState);
        }
        if (ctx.world.getResource(LoadingScreenVisualState)) |state| {
            ctx.world.dbMut().removeEntity(state.fill_entity) catch {};
            ctx.world.dbMut().removeEntity(state.track_entity) catch {};
            _ = ctx.world.removeResource(LoadingScreenVisualState);
        }
    }
};

pub const InGame = union(enum) {
    Playing: struct {},
    Paused: struct {},

    pub fn enter(_: *InGame, ctx: *modules.PhasesModule.PhaseContext) !void {
        const db = ctx.world.dbMut();
        const camera_entity = db.reserveEntityId();
        _ = try db.createEntityWithId(camera_entity, .{
            Transform{},
            Camera3d{ .Viewport = .{ .mode = .TopLeft } },
            CameraLayer(1000){},
            HudCameraTag{},
        });
        try ctx.world.insertResource(HudCameraState{ .camera_entity = camera_entity });
    }

    pub fn exit(_: *InGame, ctx: *modules.PhasesModule.PhaseContext) !void {
        if (ctx.world.getResource(HudCameraState)) |state| {
            ctx.world.dbMut().removeEntity(state.camera_entity) catch {};
            _ = ctx.world.removeResource(HudCameraState);
        }
    }
};

pub fn isPlayingPhase(current_phase: ?*const SponzaPhases.CurrentPhase) bool {
    const phase = current_phase orelse return false;
    return switch (phase.phase) {
        .Loading => false,
        .InGame => |in_game| switch (in_game) {
            .Playing => true,
            .Paused => false,
        },
    };
}

pub fn isPausedPhase(current_phase: ?*const SponzaPhases.CurrentPhase) bool {
    const phase = current_phase orelse return false;
    return switch (phase.phase) {
        .Loading => false,
        .InGame => |in_game| switch (in_game) {
            .Playing => false,
            .Paused => true,
        },
    };
}

// Imports
const phasor = @import("phasor");
const shared = @import("shared.zig");

const common = phasor.common;
const modules = phasor.modules;
const render = phasor.renderer;

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
const Transform = common.Transform;
