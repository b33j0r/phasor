pub fn install(app_cmds: *AppCommands, commands: *Commands, comptime module: anytype) !void {
    const ModuleType = moduleType(module);
    if (!@hasDecl(ModuleType, "install")) return;
    try invokeFn(ModuleType.install, app_cmds, commands);
}

pub fn uninstall(app_cmds: *AppCommands, commands: *Commands, comptime module: anytype) !void {
    const ModuleType = moduleType(module);
    if (!@hasDecl(ModuleType, "uninstall")) return;
    try invokeFn(ModuleType.uninstall, app_cmds, commands);
}

fn moduleType(comptime module: anytype) type {
    const module_type = @TypeOf(module);
    return switch (@typeInfo(module_type)) {
        .type => module,
        else => module_type,
    };
}

fn invokeFn(comptime func: anytype, app_cmds: *AppCommands, commands: *Commands) !void {
    const fn_info = @typeInfo(@TypeOf(func)).@"fn";
    const return_type = fn_info.return_type orelse void;
    const return_info = @typeInfo(return_type);

    if (return_type != void and return_info != .error_union) {
        @compileError("Module install/uninstall must return void or an error union");
    }
    if (return_info == .error_union and return_info.error_union.payload != void) {
        @compileError("Module install/uninstall error union must use void payload");
    }

    const ArgsTupleType = std.meta.ArgsTuple(@TypeOf(func));
    var args_tuple: ArgsTupleType = undefined;

    inline for (std.meta.fields(ArgsTupleType), 0..) |field, i| {
        const ParamType = field.type;
        if (ParamType == *AppCommands) {
            args_tuple[i] = app_cmds;
        } else if (ParamType == *Commands) {
            args_tuple[i] = commands;
        } else if (ParamType == AppCommands or ParamType == Commands) {
            @compileError("Module parameters must be pointers; use *AppCommands or *Commands");
        } else {
            @compileError("Unsupported module parameter type: " ++ @typeName(ParamType));
        }
    }

    if (return_type == void) {
        _ = @call(.auto, func, args_tuple);
    } else {
        try @call(.auto, func, args_tuple);
    }
}

// Imports
const std = @import("std");
const AppCommands = @import("AppCommands.zig").AppCommands;
const Commands = @import("Commands.zig");

test "module install supports pointer params" {
    const allocator = std.testing.allocator;
    var io_threaded = std.Io.Threaded.init(allocator, .{ .environ = std.process.Environ.empty });
    defer io_threaded.deinit();
    const io = io_threaded.io();

    var world = World.init(allocator);
    defer world.deinit();

    var manager = try schedule.ScheduleManager.init(allocator);
    defer manager.deinit(&world);

    var commands = Commands.init(allocator, &io, &world);
    defer commands.deinit();
    var app_cmds = AppCommands.init(allocator, &io, &world, &manager);

    const Marker = struct {};

    const ModuleDef = struct {
        pub fn install(app: *AppCommands, cmds: *Commands) !void {
            try app.addSystem(schedule.DefaultSchedule.Update, struct {
                fn run(_: *Commands) void {}
            }.run);
            try cmds.insertResource(Marker{});
        }
    };

    try install(&app_cmds, &commands, ModuleDef);
    if (!commands.isEmpty()) {
        try commands.apply();
    }

    const update_index = manager.scheduleIndex(schedule.DefaultSchedule.Update).?;
    const update_schedule = manager.scheduleAt(update_index);
    try std.testing.expectEqual(@as(usize, 1), update_schedule.systemCount());
    try std.testing.expect(world.hasResource(Marker));
}

test "module supports no-arg install and uninstall" {
    const allocator = std.testing.allocator;
    var io_threaded = std.Io.Threaded.init(allocator, .{ .environ = std.process.Environ.empty });
    defer io_threaded.deinit();
    const io = io_threaded.io();

    var world = World.init(allocator);
    defer world.deinit();

    var manager = try schedule.ScheduleManager.init(allocator);
    defer manager.deinit(&world);

    var commands = Commands.init(allocator, &io, &world);
    defer commands.deinit();
    var app_cmds = AppCommands.init(allocator, &io, &world, &manager);

    const ModuleDef = struct {
        pub fn install() void {}
        pub fn uninstall() void {}
    };

    try install(&app_cmds, &commands, ModuleDef);
    try uninstall(&app_cmds, &commands, ModuleDef);
}

test "module supports app-only install and uninstall" {
    const allocator = std.testing.allocator;
    var io_threaded = std.Io.Threaded.init(allocator, .{ .environ = std.process.Environ.empty });
    defer io_threaded.deinit();
    const io = io_threaded.io();

    var world = World.init(allocator);
    defer world.deinit();

    var manager = try schedule.ScheduleManager.init(allocator);
    defer manager.deinit(&world);

    var commands = Commands.init(allocator, &io, &world);
    defer commands.deinit();
    var app_cmds = AppCommands.init(allocator, &io, &world, &manager);

    const system_fn = struct {
        fn run(_: *Commands) void {}
    }.run;

    const ModuleDef = struct {
        pub fn install(app: *AppCommands) !void {
            try app.addSystem(schedule.DefaultSchedule.Update, system_fn);
        }

        pub fn uninstall(app: *AppCommands) void {
            app.removeSystem(system_fn);
        }
    };

    try install(&app_cmds, &commands, ModuleDef);

    const update_index = manager.scheduleIndex(schedule.DefaultSchedule.Update).?;
    var update_schedule = manager.scheduleAt(update_index);
    const order = try update_schedule.systemOrder(allocator);
    try std.testing.expectEqual(@as(usize, 1), order.len);
    try std.testing.expect(update_schedule.systemNodeAt(order[0]).enabled);

    try uninstall(&app_cmds, &commands, ModuleDef);
    try std.testing.expect(!update_schedule.systemNodeAt(order[0]).enabled);
}

test "module supports commands-only install and uninstall" {
    const allocator = std.testing.allocator;
    var io_threaded = std.Io.Threaded.init(allocator, .{ .environ = std.process.Environ.empty });
    defer io_threaded.deinit();
    const io = io_threaded.io();

    var world = World.init(allocator);
    defer world.deinit();

    var manager = try schedule.ScheduleManager.init(allocator);
    defer manager.deinit(&world);

    var commands = Commands.init(allocator, &io, &world);
    defer commands.deinit();
    var app_cmds = AppCommands.init(allocator, &io, &world, &manager);

    const Marker = struct {};

    const ModuleDef = struct {
        pub fn install(cmds: *Commands) !void {
            try cmds.insertResource(Marker{});
        }

        pub fn uninstall(cmds: *Commands) void {
            _ = cmds.removeResource(Marker);
        }
    };

    try install(&app_cmds, &commands, ModuleDef);
    if (!commands.isEmpty()) {
        try commands.apply();
    }
    try std.testing.expect(world.hasResource(Marker));

    try uninstall(&app_cmds, &commands, ModuleDef);
    try std.testing.expect(!world.hasResource(Marker));
}

const World = @import("World.zig");
const schedule = @import("schedule.zig");
