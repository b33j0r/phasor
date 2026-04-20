allocator: std.mem.Allocator,
io: *const std.Io,
world: World,
schedule_manager: schedule_mod.ScheduleManager,
command_channel: ?common.Channel(CommandBatch) = null,
command_queue_capacity: usize = 64,
startup_run: bool = false,
shutdown_run: bool = false,

const Self = @This();

pub const Error = error{
    NotImplemented,
};

pub fn error_message(err: Error) []const u8 {
    return switch (err) {
        Error.NotImplemented => "Not implemented",
    };
}

pub const InitConfig = struct {
    command_queue_capacity: usize = 64,
};

pub fn init(allocator: std.mem.Allocator, io: *const std.Io) !Self {
    return try initWithConfig(allocator, io, .{});
}

pub fn initWithConfig(allocator: std.mem.Allocator, io: *const std.Io, config: InitConfig) !Self {
    return .{
        .allocator = allocator,
        .io = io,
        .world = World.init(allocator),
        .schedule_manager = try schedule_mod.ScheduleManager.init(allocator),
        .command_channel = null,
        .command_queue_capacity = config.command_queue_capacity,
    };
}

pub fn default(allocator: std.mem.Allocator, io: *const std.Io) !Self {
    return init(allocator, io);
}

pub fn deinit(self: *Self) void {
    if (self.command_channel) |*channel| channel.deinit();
    self.world.deinit();
    self.schedule_manager.deinit(null);
    self.* = undefined;
}

pub fn addSystem(self: *Self, comptime system_fn: anytype) !void {
    try self.schedule_manager.addSystem(&self.world, schedule_mod.DefaultSchedule.Update, system_fn);
}

pub fn addSystemTo(self: *Self, schedule_label: []const u8, comptime system_fn: anytype) !void {
    try self.schedule_manager.addSystem(&self.world, schedule_label, system_fn);
}

pub fn removeSystem(self: *Self, comptime system_fn: anytype) void {
    self.schedule_manager.removeSystem(&self.world, system_fn);
}

pub fn appCommands(self: *Self) AppCommands {
    return AppCommands.init(self.allocator, self.io, &self.world, &self.schedule_manager);
}

pub fn addSchedule(self: *Self, label: []const u8) !void {
    try self.schedule_manager.addSchedule(label);
}

pub fn insertScheduleBetween(
    self: *Self,
    before_label: []const u8,
    label: []const u8,
    after_label: []const u8,
) !void {
    try self.schedule_manager.insertScheduleBetween(before_label, label, after_label);
}

pub fn installModule(self: *Self, comptime module: anytype) !void {
    var commands = Commands.init(self.allocator, self.io, &self.world);
    defer commands.deinit();
    var app_cmds = self.appCommands();

    try Module.install(&app_cmds, &commands, module);
    if (!commands.isEmpty()) {
        try commands.apply();
    }
}

pub fn uninstallModule(self: *Self, comptime module: anytype) !void {
    var commands = Commands.init(self.allocator, self.io, &self.world);
    defer commands.deinit();
    var app_cmds = self.appCommands();

    try Module.uninstall(&app_cmds, &commands, module);
    if (!commands.isEmpty()) {
        try commands.apply();
    }
}

pub fn run(self: *Self) !u8 {
    try self.start();
    while (true) {
        if (try self.step()) |exit_code| {
            return exit_code;
        }
    }
}

pub fn start(self: *Self) !void {
    if (self.startup_run) return;
    const command_channel = try self.ensureCommandChannel();
    log.debug("app startup begin", .{});
    try self.runScheduleByLabelInternal(schedule_mod.DefaultSchedule.WindowCreate, command_channel);
    try self.runScheduleByLabelInternal(schedule_mod.DefaultSchedule.AssetsLoad, command_channel);
    try self.runScheduleByLabelInternal(schedule_mod.DefaultSchedule.Startup, command_channel);
    self.startup_run = true;
    log.debug("app startup complete", .{});
}

pub fn step(self: *Self) !?u8 {
    if (!self.startup_run) {
        try self.start();
    }
    const command_channel = try self.ensureCommandChannel();
    try self.runSchedules(command_channel, .{
        .skip_startup = true,
        .skip_shutdown = true,
    });
    if (self.world.getResource(resources.Exit)) |exit| {
        if (!self.shutdown_run) {
            log.info("app shutdown requested with exit code {}", .{exit.code});
            try self.runScheduleByLabelInternal(schedule_mod.DefaultSchedule.Shutdown, command_channel);
            try self.runScheduleByLabelInternal(schedule_mod.DefaultSchedule.AssetsUnload, command_channel);
            try self.runScheduleByLabelInternal(schedule_mod.DefaultSchedule.WindowDestroy, command_channel);
            self.shutdown_run = true;
            log.debug("app shutdown complete", .{});
        }
        return exit.code;
    }
    return null;
}

pub fn runScheduleByLabel(self: *Self, label: []const u8) !void {
    const schedule_ptr = self.schedule_manager.schedulePtr(label) orelse
        return schedule_mod.ScheduleManager.Error.ScheduleNotFound;
    const command_channel = try self.ensureCommandChannel();
    try self.runScheduleInternal(schedule_ptr, command_channel);
}

fn ensureCommandChannel(self: *Self) !*common.Channel(CommandBatch) {
    if (self.command_channel == null) {
        self.command_channel = try common.Channel(CommandBatch).init(self.allocator, self.io, self.command_queue_capacity);
    }
    return &self.command_channel.?;
}

fn runScheduleByLabelInternal(
    self: *Self,
    label: []const u8,
    command_channel: *common.Channel(CommandBatch),
) !void {
    if (self.schedule_manager.schedulePtr(label)) |schedule_ptr| {
        try self.runScheduleInternal(schedule_ptr, command_channel);
    }
}

const RunSchedulesOptions = struct {
    skip_startup: bool = false,
    skip_shutdown: bool = false,
};

fn runSchedules(self: *Self, command_channel: *common.Channel(CommandBatch), options: RunSchedulesOptions) !void {
    const schedule_order = try self.schedule_manager.executionOrderFrom(schedule_mod.DefaultSchedule.BeforeFrame);
    for (schedule_order) |schedule_index| {
        const schedule_ptr = self.schedule_manager.scheduleAt(schedule_index);
        if (options.skip_startup and std.mem.eql(u8, schedule_ptr.label, schedule_mod.DefaultSchedule.Startup)) {
            continue;
        }
        if (options.skip_shutdown and std.mem.eql(u8, schedule_ptr.label, schedule_mod.DefaultSchedule.Shutdown)) {
            continue;
        }
        try self.runScheduleInternal(schedule_ptr, command_channel);
    }
}

fn runScheduleInternal(
    self: *Self,
    schedule_ptr: *schedule_mod.Schedule,
    command_channel: *common.Channel(CommandBatch),
) !void {
    const system_order = try schedule_ptr.systemOrder(self.allocator);
    for (system_order) |system_index| {
        const node = schedule_ptr.systemNodeAt(system_index);
        if (!node.enabled) continue;

        var commands = Commands.init(self.allocator, self.io, &self.world);
        defer commands.deinit();

        try node.system.run(&commands);
        if (!commands.isEmpty()) {
            try commands.flushToChannel(command_channel);
            var batch = try command_channel.recv();
            defer batch.deinit();
            try batch.apply(&self.world);
        }
    }
}

// Imports
const std = @import("std");
const common = @import("common");
const World = @import("World.zig");
const schedule_mod = @import("schedule.zig");
const AppCommands = @import("AppCommands.zig").AppCommands;
const Module = @import("Module.zig");
const resources = @import("resources.zig");
const Commands = @import("Commands.zig");
const CommandBatch = @import("Commands.zig").CommandBatch;
const log = std.log.scoped(.ecs_app);
