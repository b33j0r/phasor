const std = @import("std");
const resources = @import("resources.zig");
const queries = @import("queries.zig");
const null_backend = @import("backends/null.zig");

pub const Error = error{
    BackendUnavailable,
};

pub const World = union(resources.Config.Backend) {
    Jolt: UnavailableBackend,
    Null: null_backend.State,
    Simple: null_backend.State,

    pub fn init(allocator: std.mem.Allocator, config: resources.Config) Error!World {
        return switch (config.backend) {
            .Null => .{ .Null = try null_backend.State.init(allocator, config) },
            .Simple => .{ .Simple = try null_backend.State.init(allocator, config) },
            .Jolt => Error.BackendUnavailable,
        };
    }

    pub fn deinit(self: *World, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .Null => |*state| state.deinit(allocator),
            .Simple => |*state| state.deinit(allocator),
            .Jolt => {},
        }
    }

    pub fn syncIn(self: *World, step_state: *resources.StepState) void {
        switch (self.*) {
            .Null => |*state| state.syncIn(step_state),
            .Simple => |*state| state.syncIn(step_state),
            .Jolt => {},
        }
    }

    pub fn step(self: *World, config: resources.Config, step_state: *resources.StepState, stats: *resources.Stats) void {
        switch (self.*) {
            .Null => |*state| state.step(config, step_state, stats),
            .Simple => |*state| state.step(config, step_state, stats),
            .Jolt => {},
        }
    }

    pub fn collectEvents(self: *World) void {
        switch (self.*) {
            .Null => |*state| state.collectEvents(),
            .Simple => |*state| state.collectEvents(),
            .Jolt => {},
        }
    }

    pub fn syncOut(self: *World) void {
        switch (self.*) {
            .Null => |*state| state.syncOut(),
            .Simple => |*state| state.syncOut(),
            .Jolt => {},
        }
    }

    pub fn castRay(self: *World, ray: queries.RayCast) ?queries.RayHit {
        return switch (self.*) {
            .Null => |*state| state.castRay(ray),
            .Simple => |*state| state.castRay(ray),
            .Jolt => null,
        };
    }

    pub fn castShape(self: *World, cast: queries.ShapeCast) ?queries.ShapeHit {
        return switch (self.*) {
            .Null => |*state| state.castShape(cast),
            .Simple => |*state| state.castShape(cast),
            .Jolt => null,
        };
    }
};

pub const UnavailableBackend = struct {};

test "null backend initializes" {
    var world = try World.init(std.testing.allocator, .{ .backend = .Null });
    defer world.deinit(std.testing.allocator);
}

test "unavailable backend is explicit" {
    try std.testing.expectError(Error.BackendUnavailable, World.init(std.testing.allocator, .{
        .backend = .Jolt,
    }));
}
