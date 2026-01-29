allocator: std.mem.Allocator,
io: *const std.Io,
world: World,
schedule_manager: schedule_mod.ScheduleManager,
command_queue: ?std.Io.Queue(CommandBatch) = null,
command_queue_buffer: ?[]CommandBatch = null,
command_queue_capacity: usize = 64,

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
        .command_queue = null,
        .command_queue_buffer = null,
        .command_queue_capacity = config.command_queue_capacity,
    };
}

pub fn default(allocator: std.mem.Allocator, io: *const std.Io) !Self {
    return init(allocator, io);
}

pub fn deinit(self: *Self) void {
    self.schedule_manager.deinit(&self.world);
    if (self.command_queue_buffer) |buffer| {
        self.allocator.free(buffer);
    }
    self.world.deinit();
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
    if (self.command_queue == null) {
        const buffer = try self.allocator.alloc(CommandBatch, self.command_queue_capacity);
        self.command_queue_buffer = buffer;
        self.command_queue = std.Io.Queue(CommandBatch).init(buffer);
    }
    const command_queue = &self.command_queue.?;

    try self.runScheduleByLabel(schedule_mod.DefaultSchedule.Startup, command_queue);

    while (true) {
        try self.runSchedules(command_queue, .{
            .skip_startup = true,
            .skip_shutdown = true,
        });
        if (self.world.getResource(resources.Exit)) |exit| {
            try self.runScheduleByLabel(schedule_mod.DefaultSchedule.Shutdown, command_queue);
            return exit.code;
        }
    }
}

fn runScheduleByLabel(
    self: *Self,
    label: []const u8,
    command_queue: *std.Io.Queue(CommandBatch),
) !void {
    if (self.schedule_manager.schedulePtr(label)) |schedule_ptr| {
        try self.runSchedule(schedule_ptr, command_queue);
    }
}

const RunSchedulesOptions = struct {
    skip_startup: bool = false,
    skip_shutdown: bool = false,
};

fn runSchedules(self: *Self, command_queue: *std.Io.Queue(CommandBatch), options: RunSchedulesOptions) !void {
    const schedule_order = try self.schedule_manager.executionOrder();
    for (schedule_order) |schedule_index| {
        var schedule_ptr = self.schedule_manager.scheduleAt(schedule_index);
        if (options.skip_startup and std.mem.eql(u8, schedule_ptr.label, schedule_mod.DefaultSchedule.Startup)) {
            continue;
        }
        if (options.skip_shutdown and std.mem.eql(u8, schedule_ptr.label, schedule_mod.DefaultSchedule.Shutdown)) {
            continue;
        }
        try self.runSchedule(schedule_ptr, command_queue);
    }
}

fn runSchedule(self: *Self, schedule_ptr: *schedule_mod.Schedule, command_queue: *std.Io.Queue(CommandBatch)) !void {
    const system_order = try schedule_ptr.systemOrder(self.allocator);
    for (system_order) |system_index| {
        const node = schedule_ptr.systemNodeAt(system_index);
        if (!node.enabled) continue;

        var commands = Commands.init(self.allocator, self.io, &self.world);
        defer commands.deinit();

        try node.system.run(&commands);
        if (!commands.isEmpty()) {
            try commands.flushToQueue(command_queue);
            var batch = try command_queue.getOneUncancelable(self.io.*);
            defer batch.deinit();
            try batch.apply(&self.world);
        }
    }
}

// Imports
const std = @import("std");
const World = @import("World.zig");
const schedule_mod = @import("schedule.zig");
const AppCommands = @import("AppCommands.zig").AppCommands;
const Module = @import("Module.zig");
const resources = @import("resources.zig");
const Commands = @import("Commands.zig");
const CommandBatch = @import("Commands.zig").CommandBatch;
