pub const AssetsModuleConfig = struct {
    loading_policy: assets_mod.AssetsLoadingPolicy = .autoload,
    emit_autoload_progress: bool = false,
    scene_primitives_per_frame: usize = 8,
    progress_event_capacity: usize = 256,
};

pub fn AssetsLoadState(comptime T: type) type {
    return struct {
        allocator: std.mem.Allocator,
        config: AssetsModuleConfig,
        next_session_id: u64 = 1,
        session: ?Session = null,
        plan_slots: [asset_fields.len]?PlanSlot = @splat(null),
        pending_builds: std.ArrayListUnmanaged(PendingSceneBuild) = .empty,

        const Self = @This();
        const asset_fields = std.meta.fields(T);

        const LoadPhase = enum {
            planning,
            executing_assets,
            executing_instances,
            complete,
        };

        pub const Session = struct {
            id: u64,
            active: bool = true,
            complete: bool = false,
            bundle_started_emitted: bool = false,
            discoveries_emitted: bool = false,
            phase: LoadPhase = .planning,
            plan_index: usize = 0,
            execute_index: usize = 0,
            plan_units_completed: usize = 0,
            plan_units_total: usize = asset_fields.len,
            execute_units_completed: usize = 0,
            execute_units_total: usize = 0,
            assets_loaded: usize = 0,
            total_assets: usize = asset_fields.len,
            first_scene_ready_logged: bool = false,
            awaiting_first_present_log: bool = false,
            start_ms: i64 = 0,
            gpu_start_ms: ?i64 = null,
            gpu_ready_ms: ?i64 = null,
        };

        const PlanSlot = AssetPlanSlot;

        const PendingSceneBuild = struct {
            entity_id: ecs.Entity.Id,
            asset: *assets_mod.Scene,
            apply_state: assets_mod.PreparedImportedScene.ApplyState,
            options: assets_mod.Scene.InstantiateOptions,
            total_primitives: usize,
            last_reported_primitives: usize = 0,

            fn deinit(self: *PendingSceneBuild) void {
                self.apply_state.deinit();
                self.* = undefined;
            }
        };

        pub fn init(allocator: std.mem.Allocator, config: AssetsModuleConfig) Self {
            return .{
                .allocator = allocator,
                .config = config,
            };
        }

        pub fn deinit(self: *Self) void {
            self.clearPlans();
            self.clearPendingBuilds();
            self.pending_builds.deinit(self.allocator);
            self.* = undefined;
        }

        pub fn beginDefaultSession(self: *Self, io: *const std.Io) void {
            self.cancel();
            const session_id = self.next_session_id;
            self.next_session_id += 1;
            self.session = .{
                .id = session_id,
                .start_ms = nowMs(io),
            };
        }

        pub fn cancel(self: *Self) void {
            self.clearPlans();
            self.clearPendingBuilds();
            self.session = null;
        }

        pub fn hasActiveSession(self: *const Self) bool {
            return if (self.session) |session| session.active else false;
        }

        pub fn isComplete(self: *const Self) bool {
            return if (self.session) |session| session.complete else false;
        }

        pub fn sessionId(self: *const Self) u64 {
            return if (self.session) |session| session.id else 0;
        }

        pub fn overallProgress01(self: *const Self) f32 {
            const session = self.session orelse return 0.0;
            if (session.complete or session.phase == .complete) return 1.0;
            const plan_weight: f32 = 0.2;
            const plan_progress = if (session.plan_units_total == 0)
                1.0
            else
                @as(f32, @floatFromInt(session.plan_units_completed)) / @as(f32, @floatFromInt(session.plan_units_total));
            if (session.phase == .planning) return plan_progress * plan_weight;

            const execute_progress = if (session.execute_units_total == 0)
                1.0
            else
                @as(f32, @floatFromInt(session.execute_units_completed)) / @as(f32, @floatFromInt(session.execute_units_total));
            return plan_weight + execute_progress * (1.0 - plan_weight);
        }

        pub fn currentCounts(self: *const Self) struct { completed: usize, total: usize } {
            const session = self.session orelse return .{ .completed = 0, .total = 0 };
            if (session.phase == .planning) {
                return .{ .completed = session.plan_units_completed, .total = session.plan_units_total };
            }
            return .{ .completed = session.execute_units_completed, .total = session.execute_units_total };
        }

        pub fn currentStage(self: *const Self) assets_mod.AssetsLoadStage {
            const session = self.session orelse return .idle;
            if (session.complete) return .bundle_complete;
            return switch (session.phase) {
                .planning => .bundle_planning,
                .executing_assets => .asset_execute,
                .executing_instances => .scene_instance_gpu_progress,
                .complete => .bundle_complete,
            };
        }

        fn clearPlans(self: *Self) void {
            for (&self.plan_slots) |*slot| {
                if (slot.*) |*value| {
                    value.deinit(self.allocator);
                    slot.* = null;
                }
            }
        }

        fn clearPendingBuilds(self: *Self) void {
            for (self.pending_builds.items) |*pending| {
                pending.deinit();
            }
            self.pending_builds.clearRetainingCapacity();
        }

        fn findPendingBuildIndex(self: *const Self, entity_id: ecs.Entity.Id) ?usize {
            for (self.pending_builds.items, 0..) |pending, index| {
                if (pending.entity_id == entity_id) return index;
            }
            return null;
        }

        fn findPlanSlotByAsset(self: *const Self, asset_ptr: *const anyopaque) ?*const PlanSlot {
            const wanted = @intFromPtr(asset_ptr);
            for (&self.plan_slots) |*slot| {
                if (slot.*) |*value| {
                    if (@intFromPtr(value.asset_ptr) == wanted) return value;
                }
            }
            return null;
        }
    };
}

pub fn AssetsModule(comptime T: type, comptime config: AssetsModuleConfig) type {
    return struct {
        const Self = @This();
        const State = AssetsLoadState(T);

        pub fn install(app: *AppCommands, commands: *Commands) !void {
            if (!commands.hasResource(T)) {
                try commands.insertResource(T{});
            }
            if (!commands.hasResource(State)) {
                try commands.insertResource(State.init(commands.allocator, config));
            }
            if (!commands.hasResource(ecs.events.Events(assets_mod.AssetsProgressEvent))) {
                try commands.registerEvent(assets_mod.AssetsProgressEvent, config.progress_event_capacity);
            }
            if (!commands.isEmpty()) {
                try commands.apply();
            }

            try app.addSystem(schedule.DefaultSchedule.AssetsLoad, Self.loadAssets);
            try app.addSystem(schedule.DefaultSchedule.BeforeFrame, Self.loadAssets);
            try app.addSystem(schedule.DefaultSchedule.BeforeFrame, Self.instantiateSceneInstances);
            try app.addSystem(schedule.DefaultSchedule.BeforeFrame, Self.processLoadSession);
            try app.addSystem(schedule.DefaultSchedule.AfterFrame, Self.reportFirstPresentAfterLoad);
            try app.addSystem(schedule.DefaultSchedule.AssetsUnload, Self.resetLoadState);
            try app.addSystem(schedule.DefaultSchedule.AssetsUnload, Self.removeSceneInstances);
            try app.addSystem(schedule.DefaultSchedule.AssetsUnload, Self.unloadAssets);
        }

        pub fn uninstall(app: *AppCommands, commands: *Commands) void {
            app.removeSystem(Self.loadAssets);
            app.removeSystem(Self.instantiateSceneInstances);
            app.removeSystem(Self.processLoadSession);
            app.removeSystem(Self.reportFirstPresentAfterLoad);
            app.removeSystem(Self.resetLoadState);
            app.removeSystem(Self.removeSceneInstances);
            app.removeSystem(Self.unloadAssets);
            _ = commands.removeResource(State);
        }

        fn loadAssets(assets: ResMut(T), assets_ctx: ResOpt(assets_mod.AssetsContext)) !void {
            if (config.loading_policy != .autoload) return;
            const ctx_res = assets_ctx.ptr orelse return;
            const ctx = ctx_res.*;
            inline for (std.meta.fields(T)) |field| {
                const asset = &@field(assets.ptr, field.name);
                try asset.load(ctx);
            }
        }

        fn instantiateSceneInstances(
            commands: *Commands,
            assets_ctx: ResOpt(assets_mod.AssetsContext),
            instances: Query(.{assets_mod.Scene.Instance}),
        ) !void {
            if (config.loading_policy != .autoload) return;
            const build_ctx = (assets_ctx.ptr orelse return).buildContext() orelse return;

            var it = instances.iterator();
            while (it.next()) |row| {
                const instance = row.get(assets_mod.Scene.Instance) orelse continue;
                if (instance.scene != null) continue;
                instance.scene = try instance.asset.instantiate(commands.allocator, commands, &build_ctx, .{ .parent = row.entity_id });
            }
        }

        fn processLoadSession(
            commands: *Commands,
            assets: ResMut(T),
            assets_ctx: ResOpt(assets_mod.AssetsContext),
            state_res: ResMut(State),
            writer: EventWriter(assets_mod.AssetsProgressEvent),
            instances: Query(.{assets_mod.Scene.Instance}),
        ) !void {
            if (config.loading_policy != .manual) return;
            const state = state_res.ptr;
            var session = &(state.session orelse return);
            if (!session.active) return;

            const ctx_res = assets_ctx.ptr orelse return;
            const ctx = ctx_res.*;

            if (!session.bundle_started_emitted) {
                session.bundle_started_emitted = true;
                try emitBundleEvent(state, writer, .bundle_started);
            }
            if (!session.discoveries_emitted) {
                session.discoveries_emitted = true;
                inline for (std.meta.fields(T)) |field| {
                    try emitAssetEvent(state, writer, field.name, .asset_discovered, 0, null);
                }
            }

            switch (session.phase) {
                .planning => {
                    if (try Self.planNextAssetField(state, assets.ptr, ctx, writer)) return;
                    try Self.finishPlanning(state, instances, writer);
                    return;
                },
                .executing_assets => {
                    if (try Self.executeNextAssetField(state, assets.ptr, ctx, writer)) return;
                    session.phase = .executing_instances;
                    try emitBundleEvent(state, writer, .bundle_executing);
                },
                .executing_instances => {},
                .complete => return,
            }

            const build_ctx = ctx.buildContext() orelse return;
            try Self.discoverPendingSceneBuilds(state, instances, commands.allocator, commands.io, &build_ctx, writer);

            if (state.pending_builds.items.len == 0) {
                if (!session.complete) {
                    session.complete = true;
                    session.active = false;
                    session.phase = .complete;
                    session.awaiting_first_present_log = true;
                    if (session.gpu_ready_ms == null) session.gpu_ready_ms = nowMs(commands.io);
                    try emitBundleEvent(state, writer, .bundle_complete);
                }
                return;
            }

            var it = instances.iterator();
            while (it.next()) |row| {
                const pending_index = state.findPendingBuildIndex(row.entity_id) orelse continue;
                const instance = row.get(assets_mod.Scene.Instance) orelse continue;
                var pending = &state.pending_builds.items[pending_index];
                const prepared = pending.asset.preparedScene() orelse return error.SceneNotLoaded;

                const finished = try prepared.applyBatch(
                    commands,
                    &build_ctx,
                    pending.options,
                    &pending.apply_state,
                    @max(state.config.scene_primitives_per_frame, 1),
                );

                if (pending.apply_state.next_primitive > pending.last_reported_primitives) {
                    const delta = pending.apply_state.next_primitive - pending.last_reported_primitives;
                    session.execute_units_completed += delta;
                    pending.last_reported_primitives = pending.apply_state.next_primitive;
                    try emitAssetEvent(
                        state,
                        writer,
                        pending.asset.label(),
                        .scene_instance_gpu_progress,
                        pending.last_reported_primitives,
                        pending.total_primitives,
                    );
                }

                if (!finished) return;

                const completed_asset_name = pending.asset.label();
                const completed_total_primitives = pending.total_primitives;
                instance.scene = try prepared.completeApply(&pending.apply_state);
                _ = state.pending_builds.swapRemove(pending_index);
                if (!session.first_scene_ready_logged) {
                    session.first_scene_ready_logged = true;
                    session.gpu_ready_ms = nowMs(commands.io);
                    log.debug(
                        "first scene instance ready for bundle {d} after {d} ms",
                        .{ session.id, session.gpu_ready_ms.? - session.start_ms },
                    );
                }
                try emitAssetEvent(state, writer, completed_asset_name, .asset_complete, completed_total_primitives, completed_total_primitives);

                if (state.pending_builds.items.len == 0 and session.assets_loaded >= session.total_assets) {
                    session.complete = true;
                    session.active = false;
                    session.phase = .complete;
                    session.awaiting_first_present_log = true;
                    if (session.gpu_ready_ms == null) session.gpu_ready_ms = nowMs(commands.io);
                    try emitBundleEvent(state, writer, .bundle_complete);
                }
                return;
            }

            if (state.pending_builds.items.len > 0) {
                var stale = state.pending_builds.swapRemove(0);
                stale.deinit();
            }
        }

        fn reportFirstPresentAfterLoad(state_res: ResMut(State)) void {
            const state = state_res.ptr;
            var session = &(state.session orelse return);
            if (!session.awaiting_first_present_log) return;
            session.awaiting_first_present_log = false;
            const gpu_ready_ms = session.gpu_ready_ms orelse session.start_ms;
            log.debug(
                "bundle {d} first present complete: cpu/gpu load={} ms total",
                .{ session.id, gpu_ready_ms - session.start_ms },
            );
        }

        fn resetLoadState(state_res: ResMut(State)) void {
            state_res.ptr.cancel();
        }

        fn removeSceneInstances(
            commands: *Commands,
            instances: Query(.{assets_mod.Scene.Instance}),
        ) !void {
            var it = instances.iterator();
            while (it.next()) |row| {
                try commands.removeEntityTree(row.entity_id);
            }
        }

        fn unloadAssets(assets: ResMut(T), assets_ctx: ResOpt(assets_mod.AssetsContext)) !void {
            const ctx_res = assets_ctx.ptr orelse return;
            const ctx = ctx_res.*;
            inline for (std.meta.fields(T)) |field| {
                const asset = &@field(assets.ptr, field.name);
                try asset.unload(ctx);
            }
        }

        fn planNextAssetField(
            state: *State,
            assets: *T,
            ctx: assets_mod.AssetsContext,
            writer: EventWriter(assets_mod.AssetsProgressEvent),
        ) !bool {
            var session = &(state.session orelse return false);
            inline for (std.meta.fields(T), 0..) |field, index| {
                if (session.plan_index == index) {
                    const asset = &@field(assets, field.name);
                    state.plan_slots[index] = try planAssetSlot(@TypeOf(asset.*), asset, state.allocator, ctx, field.name, &session.plan_units_completed);
                    session.plan_index += 1;
                    try emitAssetEvent(state, writer, field.name, .asset_planned, session.plan_units_completed, session.plan_units_total);
                    return true;
                }
            }
            return false;
        }

        fn finishPlanning(
            state: *State,
            instances: Query(.{assets_mod.Scene.Instance}),
            writer: EventWriter(assets_mod.AssetsProgressEvent),
        ) !void {
            var session = &(state.session orelse return);
            if (session.phase != .planning) return;

            var execute_units: usize = 0;
            for (state.plan_slots) |slot| {
                if (slot) |value| {
                    execute_units += value.execute_units;
                }
            }

            var it = instances.iterator();
            while (it.next()) |row| {
                const instance = row.get(assets_mod.Scene.Instance) orelse continue;
                if (instance.scene != null) continue;
                const slot = state.findPlanSlotByAsset(instance.asset) orelse continue;
                execute_units += slot.scene_primitives;
            }

            session.execute_units_total = execute_units;
            session.phase = .executing_assets;
            try emitBundleEvent(state, writer, .bundle_plan_complete);
        }

        fn executeNextAssetField(
            state: *State,
            assets: *T,
            ctx: assets_mod.AssetsContext,
            writer: EventWriter(assets_mod.AssetsProgressEvent),
        ) !bool {
            var session = &(state.session orelse return false);
            inline for (std.meta.fields(T), 0..) |field, index| {
                _ = field;
                if (session.execute_index == index) {
                    var slot = state.plan_slots[index] orelse {
                        session.execute_index += 1;
                        return true;
                    };
                    if (slot.execute_units > 0) {
                        var task = assets_mod.AssetTask{
                            .completed_units = &session.execute_units_completed,
                            .total_units = slot.execute_units,
                        };
                        try slot.execute(ctx, &task);
                    }
                    const asset_name = slot.asset_name;
                    slot.deinit(state.allocator);
                    state.plan_slots[index] = null;
                    session.assets_loaded += 1;
                    session.execute_index += 1;
                    try emitAssetEvent(state, writer, asset_name, .asset_execute, session.execute_units_completed, session.execute_units_total);
                    return true;
                }
            }
            _ = assets;
            return false;
        }

        fn discoverPendingSceneBuilds(
            state: *State,
            instances: Query(.{assets_mod.Scene.Instance}),
            allocator: std.mem.Allocator,
            io: *const std.Io,
            build_ctx: *const render_mod.BuildContext,
            writer: EventWriter(assets_mod.AssetsProgressEvent),
        ) !void {
            var session = &(state.session orelse return);
            var it = instances.iterator();
            while (it.next()) |row| {
                const instance = row.get(assets_mod.Scene.Instance) orelse continue;
                if (instance.scene != null) continue;
                if (state.findPendingBuildIndex(row.entity_id) != null) continue;

                var apply_state = try instance.asset.beginApplyState(allocator);
                errdefer apply_state.deinit();
                const primitive_count = instance.asset.primitiveCount();
                var options = assets_mod.Scene.InstantiateOptions{ .parent = row.entity_id };
                if (!options.shader_handle.isValid()) {
                    try build_ctx.ensureCoreSimpleShadowLitShader(&instance.asset.default_shader_handle);
                    options.shader_handle = instance.asset.default_shader_handle;
                }
                if (!options.shader_handle.isValid()) return error.MissingSceneShader;
                try state.pending_builds.append(allocator, .{
                    .entity_id = row.entity_id,
                    .asset = instance.asset,
                    .apply_state = apply_state,
                    .options = options,
                    .total_primitives = primitive_count,
                });
                if (primitive_count > 0) {
                    try emitAssetEvent(state, writer, instance.asset.label(), .scene_instance_gpu_started, 0, primitive_count);
                }
                if (session.gpu_start_ms == null) {
                    session.gpu_start_ms = nowMs(io);
                }
            }
        }

        fn emitBundleEvent(
            state: *const State,
            writer: EventWriter(assets_mod.AssetsProgressEvent),
            stage: assets_mod.AssetsLoadStage,
        ) !void {
            const session = state.session orelse return;
            const counts = state.currentCounts();
            try writer.send(.{
                .bundle_id = session.id,
                .asset_name = null,
                .stage = stage,
                .completed_units = @intCast(counts.completed),
                .total_units = @intCast(counts.total),
                .progress01 = state.overallProgress01(),
                .loaded_assets = @intCast(session.assets_loaded),
                .total_assets = @intCast(session.total_assets),
            });
        }

        fn emitAssetEvent(
            state: *const State,
            writer: EventWriter(assets_mod.AssetsProgressEvent),
            asset_name: []const u8,
            stage: assets_mod.AssetsLoadStage,
            completed_units: usize,
            total_units: ?usize,
        ) !void {
            const session = state.session orelse return;
            try writer.send(.{
                .bundle_id = session.id,
                .asset_name = asset_name,
                .stage = stage,
                .completed_units = @intCast(completed_units),
                .total_units = if (total_units) |value| @intCast(value) else null,
                .progress01 = state.overallProgress01(),
                .loaded_assets = @intCast(session.assets_loaded),
                .total_assets = @intCast(session.total_assets),
            });
        }
    };
}

const AssetPlanSlot = struct {
    asset_name: []const u8,
    asset_ptr: *anyopaque,
    plan_ptr: *anyopaque,
    execute_units: usize,
    scene_primitives: usize,
    executeFn: *const fn (*anyopaque, *anyopaque, assets_mod.AssetsContext, *assets_mod.AssetTask) anyerror!void,
    deinitFn: *const fn (std.mem.Allocator, *anyopaque) void,

    fn execute(self: *AssetPlanSlot, ctx: assets_mod.AssetsContext, task: *assets_mod.AssetTask) !void {
        try self.executeFn(self.asset_ptr, self.plan_ptr, ctx, task);
    }

    fn deinit(self: *AssetPlanSlot, allocator: std.mem.Allocator) void {
        self.deinitFn(allocator, self.plan_ptr);
        self.* = undefined;
    }
};

const DefaultAssetPlan = struct {
    pub fn deinit(_: *DefaultAssetPlan) void {}
};

fn AssetPlanType(comptime AssetType: type) type {
    return if (@hasDecl(AssetType, "Plan")) AssetType.Plan else DefaultAssetPlan;
}

fn emptyPlan(comptime PlanT: type, allocator: std.mem.Allocator) PlanT {
    if (@hasField(PlanT, "allocator")) {
        return .{ .allocator = allocator };
    }
    return .{};
}

fn planAssetSlot(
    comptime AssetType: type,
    asset: *AssetType,
    allocator: std.mem.Allocator,
    ctx: assets_mod.AssetsContext,
    asset_name: []const u8,
    plan_completed_units: *usize,
) !AssetPlanSlot {
    const PlanT = AssetPlanType(AssetType);
    const Fns = PlanFns(AssetType, PlanT);
    const loaded = assetLoaded(asset);
    const plan_ptr = try allocator.create(PlanT);
    errdefer allocator.destroy(plan_ptr);

    var task = assets_mod.AssetTask{
        .completed_units = plan_completed_units,
        .total_units = 1,
    };
    if (loaded) {
        plan_ptr.* = emptyPlan(PlanT, allocator);
        task.complete();
    } else if (@hasDecl(AssetType, "plan")) {
        plan_ptr.* = try asset.plan(ctx, &task);
    } else {
        plan_ptr.* = emptyPlan(PlanT, allocator);
        task.complete();
    }

    return .{
        .asset_name = asset_name,
        .asset_ptr = @ptrCast(asset),
        .plan_ptr = @ptrCast(plan_ptr),
        .execute_units = if (loaded) 0 else 1,
        .scene_primitives = scenePrimitiveCount(PlanT, plan_ptr),
        .executeFn = Fns.execute,
        .deinitFn = Fns.deinit,
    };
}

fn scenePrimitiveCount(comptime PlanT: type, plan: *const PlanT) usize {
    if (@hasField(PlanT, "primitive_count")) {
        return plan.primitive_count;
    }
    return 0;
}

fn PlanFns(comptime AssetType: type, comptime PlanT: type) type {
    return struct {
        fn execute(asset_ptr: *anyopaque, plan_ptr: *anyopaque, ctx: assets_mod.AssetsContext, task: *assets_mod.AssetTask) !void {
            const asset: *AssetType = @ptrCast(@alignCast(asset_ptr));
            const plan: *PlanT = @ptrCast(@alignCast(plan_ptr));
            if (@hasDecl(AssetType, "execute")) {
                try asset.execute(ctx, plan, task);
            } else {
                try asset.load(ctx);
                task.complete();
            }
        }

        fn deinit(allocator: std.mem.Allocator, plan_ptr: *anyopaque) void {
            const plan: *PlanT = @ptrCast(@alignCast(plan_ptr));
            if (@hasDecl(PlanT, "deinit")) {
                plan.deinit();
            }
            allocator.destroy(plan);
        }
    };
}

fn assetLoaded(asset: anytype) bool {
    const AssetType = @TypeOf(asset.*);
    if (@hasDecl(AssetType, "isLoaded")) {
        return asset.isLoaded();
    }
    if (@hasField(AssetType, "material_handle")) {
        return asset.material_handle.isValid();
    }
    if (@hasField(AssetType, "handle")) {
        return asset.handle.isValid();
    }
    if (@hasField(AssetType, "decoded") or @hasField(AssetType, "bytes") or @hasField(AssetType, "wasm_id")) {
        if (@hasField(AssetType, "decoded") and asset.decoded != null) return true;
        if (@hasField(AssetType, "bytes") and asset.bytes != null) return true;
        if (@hasField(AssetType, "wasm_id") and asset.wasm_id != null) return true;
        return false;
    }
    if (@hasField(AssetType, "loaded")) {
        return asset.loaded;
    }
    return false;
}

fn nowMs(io: *const std.Io) i64 {
    if (builtin.target.cpu.arch.isWasm()) {
        return @intFromFloat(WasmImports.timeMs());
    }

    const ts = std.Io.Clock.real.now(io.*);
    return ts.toMilliseconds();
}

const log = std.log.scoped(.assets_loader);

// Imports
const std = @import("std");
const builtin = @import("builtin");
const ecs = @import("ecs");
const render_mod = @import("render");
const assets_mod = @import("./root.zig");
const AppCommands = ecs.AppCommands;
const Commands = ecs.Commands;
const schedule = ecs.schedule;
const Query = ecs.system_params.Query;
const ResMut = ecs.system_params.ResMut;
const ResOpt = ecs.system_params.ResOpt;
const EventWriter = ecs.events.EventWriter;

const WasmImports = if (builtin.target.cpu.arch.isWasm()) struct {
    extern "env" fn wasm_time_ms() f64;

    pub fn timeMs() f64 {
        return wasm_time_ms();
    }
} else struct {
    pub fn timeMs() f64 {
        return 0.0;
    }
};

test "autoload policy preserves default eager asset loading" {
    const allocator = std.testing.allocator;
    var io_threaded = std.Io.Threaded.init(allocator, .{ .environ = std.process.Environ.empty });
    defer io_threaded.deinit();
    const io = io_threaded.io();

    var app = try ecs.App.init(allocator, &io, .{});
    defer app.deinit();

    const FakeAsset = struct {
        loaded: bool = false,

        pub fn load(self: *@This(), _: assets_mod.AssetsContext) !void {
            self.loaded = true;
        }

        pub fn unload(self: *@This(), _: assets_mod.AssetsContext) !void {
            self.loaded = false;
        }
    };

    const TestAssets = struct {
        first: FakeAsset = .{},
        second: FakeAsset = .{},
    };

    try app.insertResource(assets_mod.AssetsContext{
        .allocator = allocator,
        .io = &io,
    });
    try app.installModule(AssetsModule(TestAssets, .{}));
    try app.runScheduleByLabel(schedule.DefaultSchedule.AssetsLoad);

    const assets = app.getResource(TestAssets).?;
    try std.testing.expect(assets.first.loaded);
    try std.testing.expect(assets.second.loaded);
}

test "manual policy waits for explicit load session and emits progress" {
    const allocator = std.testing.allocator;
    var io_threaded = std.Io.Threaded.init(allocator, .{ .environ = std.process.Environ.empty });
    defer io_threaded.deinit();
    const io = io_threaded.io();

    var app = try ecs.App.init(allocator, &io, .{});
    defer app.deinit();

    const FakeAsset = struct {
        loaded: bool = false,

        pub fn load(self: *@This(), _: assets_mod.AssetsContext) !void {
            self.loaded = true;
        }

        pub fn unload(self: *@This(), _: assets_mod.AssetsContext) !void {
            self.loaded = false;
        }
    };

    const TestAssets = struct {
        first: FakeAsset = .{},
        second: FakeAsset = .{},
    };

    const ProgressLog = struct {
        stages: std.ArrayListUnmanaged(assets_mod.AssetsLoadStage) = .empty,
        pub fn deinit(self: *@This()) void {
            self.stages.deinit(allocator);
        }
    };

    const reader_system = struct {
        fn run(commands: *Commands, reader: ecs.events.EventReader(assets_mod.AssetsProgressEvent), progress: ResMut(ProgressLog)) !void {
            while (reader.next()) |event| {
                try progress.ptr.stages.append(commands.allocator, event.stage);
            }
        }
    }.run;

    try app.insertResource(assets_mod.AssetsContext{
        .allocator = allocator,
        .io = &io,
    });
    try app.insertResource(ProgressLog{});
    try app.installModule(AssetsModule(TestAssets, .{
        .loading_policy = .manual,
        .scene_primitives_per_frame = 1,
    }));
    try app.addSystem(schedule.DefaultSchedule.Update, reader_system);

    try app.runScheduleByLabel(schedule.DefaultSchedule.BeforeFrame);
    var assets = app.getResource(TestAssets).?;
    try std.testing.expect(!assets.first.loaded);
    try std.testing.expect(!assets.second.loaded);

    const state = app.getResourceMut(AssetsLoadState(TestAssets)).?;
    state.beginDefaultSession(&io);

    try app.runScheduleByLabel(schedule.DefaultSchedule.BeforeFrame);
    try app.runScheduleByLabel(schedule.DefaultSchedule.Update);
    assets = app.getResource(TestAssets).?;
    try std.testing.expect(assets.first.loaded != assets.second.loaded);

    try app.runScheduleByLabel(schedule.DefaultSchedule.BeforeFrame);
    try app.runScheduleByLabel(schedule.DefaultSchedule.Update);
    try app.runScheduleByLabel(schedule.DefaultSchedule.BeforeFrame);
    try app.runScheduleByLabel(schedule.DefaultSchedule.Update);

    assets = app.getResource(TestAssets).?;
    try std.testing.expect(assets.first.loaded);
    try std.testing.expect(assets.second.loaded);
    try std.testing.expect(app.getResource(AssetsLoadState(TestAssets)).?.isComplete());

    const progress = app.getResource(ProgressLog).?;
    try std.testing.expect(progress.stages.items.len >= 4);
    try std.testing.expect(progress.stages.items[0] == .bundle_started);
    try std.testing.expect(progress.stages.items[progress.stages.items.len - 1] == .bundle_complete);
}
