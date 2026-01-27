const std = @import("std");
const phasor = @import("../root.zig");
const World = @import("World.zig");
const Schedule = @import("schedule.zig").Schedule;
const resources = @import("resources.zig");

pub const Error = error{
    NotImplemented,
};

pub fn error_message(err: Error) []const u8 {
    return switch (err) {
        Error.NotImplemented => "Not implemented",
    };
}

const Self = @This();

allocator: std.mem.Allocator,
world: World,
schedule: Schedule,

pub fn init(allocator: std.mem.Allocator) Self {
    return .{
        .allocator = allocator,
        .world = World.init(allocator),
        .schedule = Schedule.init(),
    };
}

pub fn deinit(self: *Self) void {
    self.schedule.deinit(self.allocator);
    self.world.deinit();
    self.* = undefined;
}

pub fn addSystem(self: *Self, system: Schedule.SystemFn) !void {
    try self.schedule.addSystem(self.allocator, system);
}

pub const RunConfig = struct {
    warmup_frames: u64 = 0,
    sample_frames: u64 = 600,
};

pub fn run(self: *Self, config: RunConfig) !void {
    var last = try std.time.Instant.now();
    var frame: u64 = 0;
    const end_frame = config.warmup_frames + config.sample_frames;

    if (!self.world.hasResource(resources.FrameNum)) try self.world.insertResource(resources.FrameNum{});
    if (!self.world.hasResource(resources.DeltaTime)) try self.world.insertResource(resources.DeltaTime{});
    if (!self.world.hasResource(resources.ElapsedTime)) try self.world.insertResource(resources.ElapsedTime{});
    if (!self.world.hasResource(resources.Metrics)) try self.world.insertResource(resources.Metrics{});

    while (frame < end_frame) : (frame += 1) {
        const frame_start = try std.time.Instant.now();
        const dt_ns = frame_start.since(last);
        last = frame_start;

        if (self.world.getResourceMut(resources.FrameNum)) |f| f.value = frame;
        if (self.world.getResourceMut(resources.DeltaTime)) |dt| dt.seconds = @as(f32, @floatFromInt(dt_ns)) / 1_000_000_000.0;
        if (self.world.getResourceMut(resources.ElapsedTime)) |t| t.seconds += @as(f64, @floatFromInt(dt_ns)) / 1_000_000_000.0;
        if (self.world.getResourceMut(resources.Metrics)) |m| {
            m.frame = frame;
            m.resetFrame();
            m.frame_ns = @as(u64, @intCast(dt_ns));
        }

        const update_start = try std.time.Instant.now();
        try self.schedule.run(&self.world);
        const update_ns = (try std.time.Instant.now()).since(update_start);
        if (self.world.getResourceMut(resources.Metrics)) |m| {
            m.update_ns = update_ns;
        }
    }
}
