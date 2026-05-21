allocator: std.mem.Allocator,
commands: std.ArrayListUnmanaged(Command) = .empty,
io: *const std.Io,
world: *World,

const Self = @This();

pub fn init(allocator: std.mem.Allocator, io: *const std.Io, world: *World) Self {
    return .{
        .allocator = allocator,
        .commands = .empty,
        .io = io,
        .world = world,
    };
}

pub fn deinit(self: *Self) void {
    for (self.commands.items) |*cmd| {
        cmd.cleanup();
    }
    self.commands.deinit(self.allocator);
    self.* = undefined;
}

pub fn apply(self: *Self) !void {
    var first_err: ?anyerror = null;
    for (self.commands.items) |*cmd| {
        var cmd_value = cmd.*;
        {
            defer cmd_value.cleanup();
            if (first_err == null) {
                cmd_value.execute(self.world) catch |err| {
                    first_err = err;
                };
            } else {
                _ = cmd_value.execute(self.world) catch {};
            }
        }
    }
    self.commands.clearRetainingCapacity();
    if (first_err) |err| return err;
}

fn queueContext(self: *Self, context: anytype) !void {
    const ContextType = @TypeOf(context);
    var cmd = Command.from(self.allocator, context) catch |err| {
        if (@hasDecl(ContextType, "cleanup")) {
            var tmp = context;
            tmp.cleanup(self.allocator);
        }
        return err;
    };
    errdefer cmd.cleanup();
    try self.commands.append(self.allocator, cmd);
}

pub fn reserveEntityId(self: *Self) Entity.Id {
    return self.world.database.reserveEntityId();
}

pub fn createEntity(self: *Self, components: anytype) !Entity.Id {
    const entity_id = self.reserveEntityId();

    const CreateEntityContext = struct {
        entity_id: Entity.Id,
        components: @TypeOf(components),

        pub fn execute(ctx: *@This(), world: *World) anyerror!void {
            _ = try world.database.createEntityWithId(ctx.entity_id, ctx.components);
        }
    };

    try self.queueContext(CreateEntityContext{
        .entity_id = entity_id,
        .components = components,
    });

    return entity_id;
}

/// Same as createEntity but discards the returned entity ID.
pub fn insertEntity(self: *Self, components: anytype) !void {
    _ = try self.createEntity(components);
}

pub fn removeEntity(self: *Self, entity_id: Entity.Id) !void {
    const RemoveEntityContext = struct {
        entity_id: Entity.Id,

        pub fn execute(ctx: *@This(), world: *World) anyerror!void {
            try world.database.removeEntity(ctx.entity_id);
        }
    };

    try self.queueContext(RemoveEntityContext{
        .entity_id = entity_id,
    });
}

pub fn removeEntityTree(self: *Self, entity_id: Entity.Id) !void {
    const RemoveEntityTreeContext = struct {
        entity_id: Entity.Id,

        pub fn execute(ctx: *@This(), world: *World) anyerror!void {
            try removeEntityTreeImmediate(world, ctx.entity_id);
        }
    };

    try self.queueContext(RemoveEntityTreeContext{
        .entity_id = entity_id,
    });
}

fn removeEntityTreeImmediate(world: *World, entity_id: Entity.Id) !void {
    var children: std.ArrayListUnmanaged(Entity.Id) = .empty;
    defer children.deinit(world.database.allocator);

    try collectChildEntities(&world.database, entity_id, &children);
    for (children.items) |child_id| {
        try removeEntityTreeImmediate(world, child_id);
    }

    world.database.removeEntity(entity_id) catch |err| switch (err) {
        error.EntityNotFound => {},
        else => return err,
    };
}

fn collectChildEntities(database: *db.Database, parent_id: Entity.Id, children: *std.ArrayListUnmanaged(Entity.Id)) !void {
    for (database.tables.items) |*table| {
        var row: usize = 0;
        while (row < table.len()) : (row += 1) {
            const parent = table.getComponentPtr(row, common.Parent) orelse continue;
            if (parent.id == parent_id) {
                const child_id = table.entityIdAt(row) orelse continue;
                try children.append(database.allocator, child_id);
            }
        }
    }
}

pub fn addComponent(self: *Self, entity_id: Entity.Id, component: anytype) !void {
    try self.addComponents(entity_id, .{component});
}

pub fn removeComponent(self: *Self, entity_id: Entity.Id, comptime T: type) !void {
    try self.removeComponents(entity_id, .{T});
}

pub fn addComponents(self: *Self, entity_id: Entity.Id, components: anytype) !void {
    const AddComponentsContext = struct {
        entity_id: Entity.Id,
        components: @TypeOf(components),

        pub fn execute(ctx: *@This(), world: *World) anyerror!void {
            try world.database.addComponents(ctx.entity_id, ctx.components);
        }
    };

    try self.queueContext(AddComponentsContext{
        .entity_id = entity_id,
        .components = components,
    });
}

pub fn removeComponents(self: *Self, entity_id: Entity.Id, comptime Types: anytype) !void {
    const RemoveComponentsContext = struct {
        entity_id: Entity.Id,

        pub fn execute(ctx: *@This(), world: *World) anyerror!void {
            try world.database.removeComponents(ctx.entity_id, Types);
        }
    };

    try self.queueContext(RemoveComponentsContext{
        .entity_id = entity_id,
    });
}

pub fn insertResource(self: *Self, resource: anytype) !void {
    const InsertResourceContext = struct {
        resource: @TypeOf(resource),

        pub fn execute(ctx: *@This(), world: *World) anyerror!void {
            try world.insertResource(ctx.resource);
        }
    };

    try self.queueContext(InsertResourceContext{
        .resource = resource,
    });
}

pub fn registerEvent(self: *Self, comptime T: type, capacity: usize) !void {
    const RegisterEventContext = struct {
        io: *const std.Io,
        capacity: usize,

        pub fn execute(ctx: *@This(), world: *World) anyerror!void {
            try world.registerEvent(ctx.io, T, ctx.capacity);
        }
    };

    try self.queueContext(RegisterEventContext{
        .io = self.io,
        .capacity = capacity,
    });
}

pub fn removeResource(self: *Self, comptime T: type) bool {
    return self.world.removeResource(T);
}

pub fn getResource(self: *Self, comptime T: type) ?*const T {
    return self.world.getResource(T);
}

pub fn getResourceMut(self: *Self, comptime T: type) ?*T {
    return self.world.getResourceMut(T);
}

pub fn hasResource(self: *Self, comptime T: type) bool {
    return self.world.hasResource(T);
}

pub fn query(self: *Self, comptime Parts: anytype) !db.QueryResult {
    const Spec = db.QuerySpec.Spec(Parts);
    return db.QueryResult.fromSpec(self.allocator, &self.world.database, Spec);
}

pub fn groupBy(self: *Self, comptime TraitT: type) !db.GroupByResult {
    return self.world.database.groupBy(TraitT);
}

pub fn isEmpty(self: *const Self) bool {
    return self.commands.items.len == 0;
}

pub const CommandBatch = struct {
    allocator: std.mem.Allocator,
    commands: []Command,

    pub fn apply(self: *CommandBatch, world: *World) !void {
        var first_err: ?anyerror = null;
        for (self.commands) |*cmd| {
            var cmd_value = cmd.*;
            {
                defer cmd_value.cleanup();
                if (first_err == null) {
                    cmd_value.execute(world) catch |err| {
                        first_err = err;
                    };
                } else {
                    _ = cmd_value.execute(world) catch {};
                }
            }
        }
        self.allocator.free(self.commands);
        self.commands = &.{};
        if (first_err) |err| return err;
    }

    pub fn deinit(self: *CommandBatch) void {
        for (self.commands) |*cmd| {
            cmd.cleanup();
        }
        if (self.commands.len > 0) {
            self.allocator.free(self.commands);
        }
        self.commands = &.{};
    }
};

pub fn flushToChannel(commands: *Self, channel: *common.Channel(CommandBatch)) !void {
    if (commands.commands.items.len == 0) return;
    const owned = try commands.commands.toOwnedSlice(commands.allocator);
    const batch = CommandBatch{
        .allocator = commands.allocator,
        .commands = owned,
    };
    channel.send(batch) catch |err| {
        commands.commands = .{
            .items = owned,
            .capacity = owned.len,
        };
        return err;
    };
}

test "commands flush batches through common channel" {
    const allocator = std.testing.allocator;
    var io_threaded = std.Io.Threaded.init(allocator, .{ .environ = std.process.Environ.empty });
    defer io_threaded.deinit();
    const io = io_threaded.io();

    var world = World.init(allocator);
    defer world.deinit();

    var commands = Self.init(allocator, &io, &world);
    defer commands.deinit();

    const Marker = struct { value: u32 };
    try commands.insertResource(Marker{ .value = 42 });

    var channel = try common.Channel(CommandBatch).init(allocator, &io, 2);
    defer channel.deinit();

    try commands.flushToChannel(&channel);
    var batch = try channel.recv();
    defer batch.deinit();

    try batch.apply(&world);
    try std.testing.expectEqual(@as(u32, 42), world.getResource(Marker).?.value);
}

test "removeEntityTree removes parented descendants" {
    const allocator = std.testing.allocator;
    var io_threaded = std.Io.Threaded.init(allocator, .{ .environ = std.process.Environ.empty });
    defer io_threaded.deinit();
    const io = io_threaded.io();

    var world = World.init(allocator);
    defer world.deinit();

    var commands = Self.init(allocator, &io, &world);
    defer commands.deinit();

    const Marker = struct {};

    const root = try commands.createEntity(.{Marker{}});
    const child = try commands.createEntity(.{ common.Parent{ .id = root }, Marker{} });
    _ = try commands.createEntity(.{ common.Parent{ .id = child }, Marker{} });
    try commands.apply();

    try commands.removeEntityTree(root);
    try commands.apply();

    try std.testing.expectEqual(@as(usize, 0), world.database.entityCount());
}

// Imports
const std = @import("std");
const common = @import("common");
const db = @import("db");
const Command = @import("Command.zig");
const World = @import("World.zig");

const Entity = db.Entity;
