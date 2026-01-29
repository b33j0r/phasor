//! `PhasesModule` provides hierarchical phase transitions with enter/update/exit hooks.
pub const PhaseContext = struct {
    allocator: std.mem.Allocator,
    world: *World,
    enter_systems: std.ArrayListUnmanaged(System) = .empty,
    update_systems: std.ArrayListUnmanaged(System) = .empty,
    exit_systems: std.ArrayListUnmanaged(System) = .empty,

    pub fn init(allocator: std.mem.Allocator, world: *World) PhaseContext {
        return .{
            .allocator = allocator,
            .world = world,
        };
    }

    pub fn deinit(self: *PhaseContext) void {
        unregisterSystems(self.world, self.enter_systems.items);
        unregisterSystems(self.world, self.update_systems.items);
        unregisterSystems(self.world, self.exit_systems.items);
        self.enter_systems.deinit(self.allocator);
        self.update_systems.deinit(self.allocator);
        self.exit_systems.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn addEnterSystem(self: *PhaseContext, comptime system_fn: anytype) !void {
        try addSystemToList(self, &self.enter_systems, system_fn);
    }

    pub fn addUpdateSystem(self: *PhaseContext, comptime system_fn: anytype) !void {
        try addSystemToList(self, &self.update_systems, system_fn);
    }

    pub fn addExitSystem(self: *PhaseContext, comptime system_fn: anytype) !void {
        try addSystemToList(self, &self.exit_systems, system_fn);
    }

    pub fn runEnter(self: *PhaseContext) !void {
        try runSystems(self, self.enter_systems.items);
    }

    pub fn runExit(self: *PhaseContext) !void {
        try runSystems(self, self.exit_systems.items);
    }

    pub fn update(self: *PhaseContext) !void {
        try runSystems(self, self.update_systems.items);
    }

    fn addSystemToList(self: *PhaseContext, list: *std.ArrayListUnmanaged(System), comptime system_fn: anytype) !void {
        const system = try System.from(system_fn);
        try system.register(self.world);
        errdefer system.unregister(self.world) catch {};
        try list.append(self.allocator, system);
    }

    fn runSystems(self: *PhaseContext, systems: []System) !void {
        for (systems) |system| {
            var commands = Commands.init(self.allocator, self.world);
            defer commands.deinit();
            try system.run(&commands);
            if (!commands.isEmpty()) {
                try commands.apply();
            }
        }
    }

    fn unregisterSystems(world: *World, systems: []System) void {
        for (systems) |system| {
            system.unregister(world) catch {};
        }
    }
};

/// A stack of PhaseContexts, one per active phase level (root..leaf)
pub fn PhaseContextStack(comptime PhasesT: type) type {
    return struct {
        allocator: std.mem.Allocator,
        world: *World,
        stack: std.ArrayListUnmanaged(*PhaseContext) = .empty,

        pub const Phases = PhasesT;
        const Self = @This();

        pub fn init(alloc: std.mem.Allocator, world: *World) !Self {
            return .{ .allocator = alloc, .world = world };
        }

        pub fn deinit(self: *Self) void {
            var i: usize = self.stack.items.len;
            while (i > 0) {
                i -= 1;
                const ctx = self.stack.items[i];
                ctx.deinit();
                self.allocator.destroy(ctx);
            }
            self.stack.deinit(self.allocator);
            self.* = undefined;
        }

        pub fn push(self: *Self) !*PhaseContext {
            const ctx = try self.allocator.create(PhaseContext);
            errdefer self.allocator.destroy(ctx);
            ctx.* = PhaseContext.init(self.allocator, self.world);
            try self.stack.append(self.allocator, ctx);
            return ctx;
        }

        pub fn pop(self: *Self) ?*PhaseContext {
            if (self.stack.items.len == 0) return null;
            return self.stack.pop();
        }

        pub fn top(self: *Self) ?*PhaseContext {
            if (self.stack.items.len == 0) return null;
            return self.stack.items[self.stack.items.len - 1];
        }

        pub fn depth(self: *const Self) usize {
            return self.stack.items.len;
        }

        pub fn forEach(self: *Self, f: *const fn (*PhaseContext) anyerror!void) !void {
            for (self.stack.items) |ctx| try f(ctx);
        }

        pub fn forEachReverse(self: *Self, f: *const fn (*PhaseContext) anyerror!void) !void {
            var i = self.stack.items.len;
            while (i > 0) {
                i -= 1;
                try f(self.stack.items[i]);
            }
        }
    };
}

/// Hierarchical phases definition with LCA-diff transitions.
/// Usage:
///   const PhasesDefinition = PhasesModule.Definition(MyPhases, MyPhases{ .MainMenu = .{} });
pub fn Definition(PhasesT: type, initial_phase: PhasesT) type {
    return struct {
        /// Public types/resources
        pub const Phases = PhasesT;
        pub const Stack = PhaseContextStack(Phases);
        pub const NextPhase = struct { phase: Phases };
        pub const CurrentPhase = struct { phase: Phases };
        pub const PhaseContextStackResource = struct {
            stack: Stack,

            pub fn deinit(self: *PhaseContextStackResource) void {
                self.stack.deinit();
            }
        };

        pub fn install(app: *AppCommands, commands: *Commands) !void {
            const stack = try Stack.init(commands.allocator, commands.world);
            try commands.insertResource(PhaseContextStackResource{ .stack = stack });

            try app.addSystem(schedule.DefaultSchedule.Startup, handleInitialPhase);
            try app.addSystem(schedule.DefaultSchedule.BeforeFrame, handlePhaseTransitions);
            try app.addSystem(schedule.DefaultSchedule.Update, updateCurrentPhaseStack);
        }

        pub fn uninstall(app: *AppCommands, commands: *Commands) !void {
            app.removeSystem(handleInitialPhase);
            app.removeSystem(handlePhaseTransitions);
            app.removeSystem(updateCurrentPhaseStack);

            if (commands.getResourceMut(PhaseContextStackResource)) |res| {
                try res.stack.forEachReverse(runExitSystems);
                _ = commands.removeResource(PhaseContextStackResource);
            }
            _ = commands.removeResource(NextPhase);
            _ = commands.removeResource(CurrentPhase);
        }

        fn handleInitialPhase(commands: *Commands) !void {
            if (!commands.hasResource(NextPhase)) {
                try commands.insertResource(NextPhase{ .phase = initial_phase });
            }
        }

        fn handlePhaseTransitions(commands: *Commands) !void {
            const next_opt = getNextPhase(commands);
            if (next_opt == null) return;

            const next_phase = next_opt.?;
            const stack_res = commands.getResourceMut(PhaseContextStackResource) orelse return error.MissingPhaseContextStack;

            if (commands.getResourceMut(CurrentPhase)) |cur_res| {
                const cur = cur_res.phase;

                if (@TypeOf(cur) == @TypeOf(next_phase)) {
                    // Same union root → do LCA diff transition
                    try exitDiff(&stack_res.stack, cur, next_phase);
                    try enterDiff(&stack_res.stack, cur, next_phase);
                } else {
                    // Different roots → full teardown and rebuild
                    try stack_res.stack.forEachReverse(runExitSystems);
                    while (stack_res.stack.depth() > 0) {
                        if (stack_res.stack.pop()) |ctx| {
                            ctx.deinit();
                            stack_res.stack.allocator.destroy(ctx);
                        }
                    }
                    try enterWhole(&stack_res.stack, next_phase);
                }

                cur_res.phase = next_phase;
            } else {
                // First activation
                try enterWhole(&stack_res.stack, next_phase);
                try commands.insertResource(CurrentPhase{ .phase = next_phase });
            }

            try clearNextPhase(commands);
        }

        fn updateCurrentPhaseStack(commands: *Commands) !void {
            if (commands.getResource(CurrentPhase) == null) return;
            const stack_res = commands.getResourceMut(PhaseContextStackResource) orelse return error.MissingPhaseContextStack;
            // Update runs root→leaf (each level's active update pipeline)
            try stack_res.stack.forEach(runUpdateSystems);
        }

        fn getNextPhase(commands: *Commands) ?Phases {
            return if (commands.getResource(NextPhase)) |n| n.phase else null;
        }

        fn clearNextPhase(commands: *Commands) !void {
            _ = commands.removeResource(NextPhase);
        }

        fn runEnterSystems(ctx: *PhaseContext) !void {
            try ctx.runEnter();
        }
        fn runExitSystems(ctx: *PhaseContext) !void {
            try ctx.runExit();
        }
        fn runUpdateSystems(ctx: *PhaseContext) !void {
            try ctx.update();
        }

        /// Enter the entire subtree `v` (parent first, then child), pushing
        /// a PhaseContext for each level and *running* enter systems immediately.
        fn enterWhole(stack: *Stack, v: anytype) !void {
            const T = @TypeOf(v);
            switch (@typeInfo(T)) {
                .@"union" => {
                    const ctx = try stack.push();
                    if (@hasDecl(T, "enter")) {
                        var copy = v;
                        try T.enter(&copy, ctx);
                    }
                    try runEnterSystems(ctx);

                    switch (v) {
                        inline else => |inner| {
                            if (@TypeOf(inner) != void) try enterWhole(stack, inner);
                        },
                    }
                },
                .@"struct" => {
                    const ctx = try stack.push();
                    if (@hasDecl(T, "enter")) {
                        var copy = v;
                        try T.enter(&copy, ctx);
                    }
                    try runEnterSystems(ctx);
                },
                else => {},
            }
        }

        /// Exit the entire subtree `v` (child first, then parent), *running*
        /// exit systems just before popping each PhaseContext.
        fn exitWhole(stack: *Stack, v: anytype) !void {
            const T = @TypeOf(v);
            switch (@typeInfo(T)) {
                .@"union" => {
                    switch (v) {
                        inline else => |inner| {
                            if (@TypeOf(inner) != void) try exitWhole(stack, inner);
                        },
                    }
                    if (@hasDecl(T, "exit")) {
                        const ctx = stack.top().?;
                        var copy = v;
                        try T.exit(&copy, ctx);
                    }
                    if (stack.pop()) |ctx| {
                        try runExitSystems(ctx);
                        ctx.deinit();
                        stack.allocator.destroy(ctx);
                    }
                },
                .@"struct" => {
                    if (@hasDecl(T, "exit")) {
                        const ctx = stack.top().?;
                        var copy = v;
                        try T.exit(&copy, ctx);
                    }
                    if (stack.pop()) |ctx| {
                        try runExitSystems(ctx);
                        ctx.deinit();
                        stack.allocator.destroy(ctx);
                    }
                },
                else => {},
            }
        }

        /// Exit only the *active child* subtree of union `u`, keeping the parent's context.
        fn exitActiveChildOnly(stack: *Stack, u: anytype) !void {
            switch (u) {
                inline else => |inner| {
                    if (@TypeOf(inner) != void) try exitWhole(stack, inner);
                },
            }
        }

        /// Enter only the *child* subtree of union `u`, assuming the parent context is already mounted.
        fn enterChildOnly(stack: *Stack, u: anytype) !void {
            switch (u) {
                inline else => |inner| {
                    if (@TypeOf(inner) != void) try enterWhole(stack, inner);
                },
            }
        }

        /// Exit diff: exit from current leaf up to (but not including) the LCA
        fn exitDiff(stack: *Stack, cur: anytype, nxt: anytype) !void {
            const CurT = @TypeOf(cur);
            const NxtT = @TypeOf(nxt);

            switch (@typeInfo(CurT)) {
                .@"union" => {
                    if (CurT == NxtT) {
                        const cur_tag = std.meta.activeTag(cur);
                        const nxt_tag = std.meta.activeTag(nxt);
                        if (cur_tag == nxt_tag) {
                            switch (cur) {
                                inline else => |cur_inner, tag| {
                                    const nxt_inner = @field(nxt, @tagName(tag));
                                    try exitDiff(stack, cur_inner, nxt_inner);
                                },
                            }
                            return;
                        }
                        try exitActiveChildOnly(stack, cur);
                        return;
                    }
                    try exitWhole(stack, cur);
                },
                .@"struct" => {
                    if (CurT != NxtT) {
                        try exitWhole(stack, cur);
                    }
                },
                else => {},
            }
        }

        /// Enter diff: enter from just below the LCA down to the new leaf
        fn enterDiff(stack: *Stack, cur: anytype, nxt: anytype) !void {
            const CurT = @TypeOf(cur);
            const NxtT = @TypeOf(nxt);

            switch (@typeInfo(NxtT)) {
                .@"union" => {
                    if (CurT == NxtT) {
                        const cur_tag = std.meta.activeTag(cur);
                        const nxt_tag = std.meta.activeTag(nxt);
                        if (cur_tag == nxt_tag) {
                            switch (nxt) {
                                inline else => |nxt_inner, tag| {
                                    const cur_inner = @field(cur, @tagName(tag));
                                    try enterDiff(stack, cur_inner, nxt_inner);
                                },
                            }
                            return;
                        }
                        try enterChildOnly(stack, nxt);
                        return;
                    }
                    try enterWhole(stack, nxt);
                },
                .@"struct" => {
                    if (CurT != NxtT) {
                        try enterWhole(stack, nxt);
                    }
                },
                else => {},
            }
        }
    };
}

test "phase transitions run enter/exit hooks in order" {
    const allocator = std.testing.allocator;
    var io_threaded = std.Io.Threaded.init(allocator, .{ .environ = std.process.Environ.empty });
    defer io_threaded.deinit();
    const io = io_threaded.io();

    var world = World.init(allocator);
    defer world.deinit();

    try world.registerEvent(&io, Logged, 32);
    try world.insertResource(LogBuffer.init(allocator));

    var schedule_manager = try schedule.ScheduleManager.init(allocator);
    defer schedule_manager.deinit(&world);

    var app_cmds = AppCommands.init(allocator, &world, &schedule_manager);
    var commands = Commands.init(allocator, &world);
    defer commands.deinit();

    try Module.install(&app_cmds, &commands, TestPhases);
    try schedule_manager.addSystem(&world, schedule.DefaultSchedule.Update, collectLogs);
    if (!commands.isEmpty()) {
        try commands.apply();
    }

    const startup = schedule_manager.schedulePtr(schedule.DefaultSchedule.Startup).?;
    const before_frame = schedule_manager.schedulePtr(schedule.DefaultSchedule.BeforeFrame).?;
    const update = schedule_manager.schedulePtr(schedule.DefaultSchedule.Update).?;

    try runScheduleOnce(allocator, &io, &world, startup);
    try runScheduleOnce(allocator, &io, &world, before_frame); // MainMenu.enter
    try runScheduleOnce(allocator, &io, &world, update);
    try runScheduleOnce(allocator, &io, &world, before_frame); // MainMenu.exit → InGame.enter → Playing.enter
    try runScheduleOnce(allocator, &io, &world, update);
    try runScheduleOnce(allocator, &io, &world, before_frame); // Playing.exit → Paused.enter
    try runScheduleOnce(allocator, &io, &world, update);
    try runScheduleOnce(allocator, &io, &world, before_frame); // Paused.exit → InGame.exit → Quit.enter
    try runScheduleOnce(allocator, &io, &world, update);

    const log = world.getResource(LogBuffer).?;
    const expected = [_][]const u8{
        "MainMenu.enter",
        "MainMenu.exit",
        "InGame.enter",
        "Playing.enter",
        "Playing.exit",
        "Paused.enter",
        "Paused.exit",
        "InGame.exit",
        "Quit.enter",
    };

    try std.testing.expectEqual(expected.len, log.items.items.len);
    for (expected, 0..) |exp, idx| {
        try std.testing.expectEqualStrings(exp, log.items.items[idx]);
    }

    const cur = world.getResource(TestPhases.CurrentPhase).?;
    try std.testing.expect(cur.phase == MyPhases.Quit);
}

const Logged = struct {
    name: []const u8,
};

const LogBuffer = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayListUnmanaged([]const u8) = .empty,

    pub fn init(allocator: std.mem.Allocator) LogBuffer {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *LogBuffer) void {
        self.items.deinit(self.allocator);
    }
};

const MyPhases = union(enum) {
    MainMenu: MainMenu,
    InGame: InGame,
    Quit: Quit,
};

const MainMenu = struct {
    pub fn enter(_: *MainMenu, ctx: *PhaseContext) !void {
        try ctx.addEnterSystem(log_enter);
        try ctx.addExitSystem(log_exit);
        try ctx.addUpdateSystem(transition_to_in_game);
    }

    fn log_enter(logger: EventWriter(Logged)) !void {
        try logger.send(.{ .name = "MainMenu.enter" });
    }

    fn log_exit(logger: EventWriter(Logged)) !void {
        try logger.send(.{ .name = "MainMenu.exit" });
    }

    fn transition_to_in_game(commands: *Commands) !void {
        try commands.insertResource(TestPhases.NextPhase{ .phase = MyPhases{ .InGame = .{ .Playing = .{} } } });
    }
};

const InGame = union(enum) {
    Playing: Playing,
    Paused: Paused,

    pub fn enter(_: *InGame, ctx: *PhaseContext) !void {
        try ctx.addEnterSystem(log_enter);
        try ctx.addExitSystem(log_exit);
    }

    fn log_enter(logger: EventWriter(Logged)) !void {
        try logger.send(.{ .name = "InGame.enter" });
    }

    fn log_exit(logger: EventWriter(Logged)) !void {
        try logger.send(.{ .name = "InGame.exit" });
    }
};

const Playing = struct {
    pub fn enter(_: *Playing, ctx: *PhaseContext) !void {
        try ctx.addEnterSystem(log_enter);
        try ctx.addExitSystem(log_exit);
        try ctx.addUpdateSystem(to_paused);
    }

    fn log_enter(logger: EventWriter(Logged)) !void {
        try logger.send(.{ .name = "Playing.enter" });
    }

    fn log_exit(logger: EventWriter(Logged)) !void {
        try logger.send(.{ .name = "Playing.exit" });
    }

    fn to_paused(commands: *Commands) !void {
        try commands.insertResource(TestPhases.NextPhase{ .phase = MyPhases{ .InGame = .{ .Paused = .{} } } });
    }
};

const Paused = struct {
    pub fn enter(_: *Paused, ctx: *PhaseContext) !void {
        try ctx.addEnterSystem(log_enter);
        try ctx.addExitSystem(log_exit);
        try ctx.addUpdateSystem(to_quit);
    }

    fn log_enter(logger: EventWriter(Logged)) !void {
        try logger.send(.{ .name = "Paused.enter" });
    }

    fn log_exit(logger: EventWriter(Logged)) !void {
        try logger.send(.{ .name = "Paused.exit" });
    }

    fn to_quit(commands: *Commands) !void {
        try commands.insertResource(TestPhases.NextPhase{ .phase = MyPhases.Quit });
    }
};

const Quit = struct {
    pub fn enter(_: *Quit, ctx: *PhaseContext) !void {
        try ctx.addEnterSystem(log_enter);
    }

    fn log_enter(logger: EventWriter(Logged)) !void {
        try logger.send(.{ .name = "Quit.enter" });
    }
};

const TestPhases = Definition(MyPhases, MyPhases{ .MainMenu = .{} });

fn collectLogs(reader: EventReader(Logged), buffer: ResMut(LogBuffer)) !void {
    const log = buffer.deref();
    while (reader.tryRecv()) |evt| {
        try log.items.append(log.allocator, evt.name);
    }
}

/// Internal for tests. Run a schedule once, applying commands immediately.
fn runScheduleOnce(
    allocator: std.mem.Allocator,
    io: *const std.Io,
    world: *World,
    schedule_ptr: *schedule.Schedule,
) !void {
    const command_queue_buffer = try allocator.alloc(CommandBatch, 64);
    defer allocator.free(command_queue_buffer);
    var command_queue = std.Io.Queue(CommandBatch).init(command_queue_buffer);

    const system_order = try schedule_ptr.systemOrder(allocator);
    for (system_order) |system_index| {
        const node = schedule_ptr.systemNodeAt(system_index);
        if (!node.enabled) continue;

        var commands = Commands.init(allocator, world);
        defer commands.deinit();

        try node.system.run(&commands);
        if (!commands.isEmpty()) {
            try commands.flushToQueue(io, &command_queue);
            var batch = try command_queue.getOneUncancelable(io.*);
            defer batch.deinit();
            try batch.apply(world);
        }
    }
}

// Imports
const std = @import("std");
const phasor = @import("../root.zig");
const AppCommands = phasor.ecs.AppCommands;
const Commands = phasor.ecs.Commands;
const CommandBatch = phasor.ecs.CommandBatch;
const Module = phasor.ecs.Module;
const ResMut = phasor.ecs.system_params.ResMut;
const EventReader = phasor.ecs.events.EventReader;
const EventWriter = phasor.ecs.events.EventWriter;
const World = phasor.ecs.World;
const System = phasor.ecs.system.System;
const schedule = phasor.ecs.schedule;
