pub fn ResMut(comptime T: type) type {
    return struct {
        ptr: *T,

        pub fn init_system_param(self: *@This(), comptime _: anytype, commands: *Commands) !void {
            self.ptr = commands.getResourceMut(T).?;
        }

        pub fn deref(self: @This()) *T {
            return self.ptr;
        }
    };
}

pub fn Res(comptime T: type) type {
    return struct {
        ptr: *const T,

        pub fn init_system_param(self: *@This(), comptime _: anytype, commands: *Commands) !void {
            self.ptr = commands.getResource(T).?;
        }

        pub fn deref(self: @This()) *const T {
            return self.ptr;
        }
    };
}

pub fn ResOpt(comptime T: type) type {
    return struct {
        ptr: ?*const T,

        pub fn init_system_param(self: *@This(), comptime _: anytype, commands: *Commands) !void {
            self.ptr = commands.getResource(T);
        }

        pub fn deref(self: @This()) ?*const T {
            return self.ptr;
        }
    };
}

pub const Without = db.QuerySpec.Without;

pub fn Query(comptime Parts: anytype) type {
    return struct {
        result: db.QueryResult = undefined,

        pub fn init_system_param(self: *@This(), comptime _: anytype, commands: *Commands) !void {
            self.result = try commands.query(Parts);
        }

        pub fn deinit(self: *@This()) void {
            self.result.deinit();
        }

        pub fn isEmpty(self: *const @This()) bool {
            return self.result.count() == 0;
        }

        pub fn count(self: *const @This()) usize {
            return self.result.count();
        }

        pub fn iterator(self: *const @This()) db.QueryResult.Iterator {
            return self.result.iterator();
        }

        pub fn first(self: *const @This()) ?db.QueryResult.Row {
            return self.result.first();
        }

        pub fn listAlloc(self: *const @This(), allocator: std.mem.Allocator) ![]db.Entity.Id {
            return self.result.listAlloc(allocator);
        }
    };
}

test "Query system param executes compiled queries" {
    const allocator = std.testing.allocator;
    var world = World.init(allocator);
    defer world.deinit();

    _ = try world.database.createEntityWithId(1, .{
        fixtures.Position{ .x = 1, .y = 2 },
    });
    _ = try world.database.createEntityWithId(2, .{
        fixtures.Position{ .x = 3, .y = 4 },
        fixtures.Velocity{ .dx = 1, .dy = 0 },
    });

    var commands = Commands.init(allocator, &world);
    defer commands.deinit();

    const sys_fn = struct {
        fn run(_: Query(.{ fixtures.Position, Without(fixtures.Velocity) })) void {}
    }.run;

    var query_param: Query(.{ fixtures.Position, Without(fixtures.Velocity) }) = undefined;
    try query_param.init_system_param(sys_fn, &commands);
    defer query_param.deinit();

    try std.testing.expect(query_param.count() == 1);
    const row = query_param.first().?;
    try std.testing.expect(row.entity_id == 1);
    try std.testing.expect(row.get(fixtures.Position) != null);
}

// Imports
const std = @import("std");
const Commands = @import("Commands.zig");
const World = @import("World.zig");
const db = @import("db");
const fixtures = db.column.fixtures;
