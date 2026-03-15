const std = @import("std");
const ecs = @import("ecs");
const resources = @import("resources.zig");
const queries = @import("queries.zig");
const null_backend = @import("backends/null.zig");
const jolt_backend = @import("backends/jolt.zig");

pub const Error = error{
    BackendUnavailable,
};

pub const World = union(resources.Config.Backend) {
    Jolt: jolt_backend.State,
    Null: null_backend.State,
    Simple: null_backend.State,

    pub fn init(allocator: std.mem.Allocator, config: resources.Config) Error!World {
        return switch (config.backend) {
            .Null => .{ .Null = try null_backend.State.init(allocator, config) },
            .Simple => .{ .Simple = try null_backend.State.init(allocator, config) },
            .Jolt => .{ .Jolt = try jolt_backend.State.init(allocator, config) },
        };
    }

    pub fn deinit(self: *World) void {
        switch (self.*) {
            .Null => |*state| state.deinit(),
            .Simple => |*state| state.deinit(),
            .Jolt => |*state| state.deinit(),
        }
    }

    pub fn syncIn(self: *World, commands: *ecs.Commands, config: resources.Config, step_state: *resources.StepState) void {
        switch (self.*) {
            .Null => |*state| state.syncIn(config, step_state),
            .Simple => |*state| state.syncIn(config, step_state),
            .Jolt => |*state| state.syncIn(commands, config, step_state),
        }
    }

    pub fn step(self: *World, config: resources.Config, step_state: *resources.StepState, stats: *resources.Stats) void {
        switch (self.*) {
            .Null => |*state| state.step(config, step_state, stats),
            .Simple => |*state| state.step(config, step_state, stats),
            .Jolt => |*state| state.step(config, step_state, stats),
        }
    }

    pub fn collectEvents(self: *World) void {
        switch (self.*) {
            .Null => |*state| state.collectEvents(),
            .Simple => |*state| state.collectEvents(),
            .Jolt => |*state| state.collectEvents(),
        }
    }

    pub fn syncOut(self: *World, commands: *ecs.Commands) void {
        switch (self.*) {
            .Null => |*state| state.syncOut(),
            .Simple => |*state| state.syncOut(),
            .Jolt => |*state| state.syncOut(commands),
        }
    }

    pub fn castRay(self: *World, ray: queries.RayCast) ?queries.RayHit {
        return switch (self.*) {
            .Null => |*state| state.castRay(ray),
            .Simple => |*state| state.castRay(ray),
            .Jolt => |*state| state.castRay(ray),
        };
    }

    pub fn castShape(self: *World, cast: queries.ShapeCast) ?queries.ShapeHit {
        return switch (self.*) {
            .Null => |*state| state.castShape(cast),
            .Simple => |*state| state.castShape(cast),
            .Jolt => |*state| state.castShape(cast),
        };
    }
};

pub const UnavailableBackend = struct {};

test "null backend initializes" {
    var world = try World.init(std.testing.allocator, .{ .backend = .Null });
    defer world.deinit();
}
