const s = @import("shared.zig");

pub const SponzaPhases = s.modules.PhasesModule.Definition(SponzaPhase, SponzaPhase{ .Loading = .{} });

pub const SponzaPhase = union(enum) {
    Loading: Loading,
    InGame: InGame,
};

pub const Loading = struct {
    pub fn enter(_: *Loading, ctx: *s.modules.PhasesModule.PhaseContext) !void {
        try ctx.world.insertResource(s.ClearColor{ .color = s.Color.BLACK });

        const db = ctx.world.dbMut();
        const camera_entity = db.reserveEntityId();
        _ = try db.createEntityWithId(camera_entity, .{
            s.Transform{},
            s.Camera3d{ .Viewport = .{ .mode = .TopLeft } },
            s.CameraLayer(1001){},
            s.LoadingScreen{},
        });

        const text_entity = db.reserveEntityId();
        _ = try db.createEntityWithId(text_entity, .{
            s.Transform{},
            s.render.Text{
                .content = "Sponza\nBooting...",
                .font_size = 28.0,
                .color = s.Color.rgb(230, 232, 236),
                .horizontal_alignment = .Center,
                .vertical_alignment = .Center,
            },
            s.render.Layer(1001){},
            s.LoadingScreen{},
            s.LoadingScreenText{},
        });

        try ctx.world.insertResource(s.LoadingScreenState{
            .camera_entity = camera_entity,
            .text_entity = text_entity,
        });
    }

    pub fn exit(_: *Loading, ctx: *s.modules.PhasesModule.PhaseContext) !void {
        if (ctx.world.getResource(s.LoadingScreenState)) |state| {
            ctx.world.dbMut().removeEntity(state.text_entity) catch {};
            ctx.world.dbMut().removeEntity(state.camera_entity) catch {};
            _ = ctx.world.removeResource(s.LoadingScreenState);
        }
        if (ctx.world.getResource(s.LoadingScreenVisualState)) |state| {
            ctx.world.dbMut().removeEntity(state.fill_entity) catch {};
            ctx.world.dbMut().removeEntity(state.track_entity) catch {};
            _ = ctx.world.removeResource(s.LoadingScreenVisualState);
        }
    }
};

pub const InGame = union(enum) {
    Playing: struct {},
    Paused: struct {},

    pub fn enter(_: *InGame, ctx: *s.modules.PhasesModule.PhaseContext) !void {
        const db = ctx.world.dbMut();
        const camera_entity = db.reserveEntityId();
        _ = try db.createEntityWithId(camera_entity, .{
            s.Transform{},
            s.Camera3d{ .Viewport = .{ .mode = .TopLeft } },
            s.CameraLayer(1000){},
            s.HudCameraTag{},
        });
        try ctx.world.insertResource(s.HudCameraState{ .camera_entity = camera_entity });
    }

    pub fn exit(_: *InGame, ctx: *s.modules.PhasesModule.PhaseContext) !void {
        if (ctx.world.getResource(s.HudCameraState)) |state| {
            ctx.world.dbMut().removeEntity(state.camera_entity) catch {};
            _ = ctx.world.removeResource(s.HudCameraState);
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
