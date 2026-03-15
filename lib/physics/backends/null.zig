const std = @import("std");
const resources = @import("../resources.zig");
const queries = @import("../queries.zig");

pub const State = struct {
    allocator: std.mem.Allocator,
    simulated_time: f32 = 0.0,

    pub fn init(allocator: std.mem.Allocator, _: resources.Config) !State {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *State) void {
        self.* = undefined;
    }

    pub fn syncIn(_: *State, _: resources.Config, step_state: *resources.StepState) void {
        step_state.steps_last_frame = 0;
    }

    pub fn step(self: *State, config: resources.Config, step_state: *resources.StepState, stats: *resources.Stats) void {
        self.simulated_time += config.fixed_dt;
        step_state.alpha = 0.0;
        step_state.steps_last_frame = 0;
        stats.body_count = 0;
        stats.active_body_count = 0;
        stats.character_count = 0;
        stats.contact_count = 0;
        stats.broadphase_pairs = 0;
        stats.step_ms = 0.0;
        stats.last_substeps = 0;
    }

    pub fn collectEvents(_: *State) void {}

    pub fn syncOut(_: *State) void {}

    pub fn castRay(_: *State, _: queries.RayCast) ?queries.RayHit {
        return null;
    }

    pub fn castShape(_: *State, _: queries.ShapeCast) ?queries.ShapeHit {
        return null;
    }
};
