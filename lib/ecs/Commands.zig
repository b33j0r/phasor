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

pub fn flushToQueue(commands: *Self, queue: *std.Io.Queue(CommandBatch)) !void {
    if (commands.commands.items.len == 0) return;
    const owned = try commands.commands.toOwnedSlice(commands.allocator);
    const batch = CommandBatch{
        .allocator = commands.allocator,
        .commands = owned,
    };
    queue.putOneUncancelable(commands.io.*, batch) catch |err| {
        commands.commands = .{
            .items = owned,
            .capacity = owned.len,
        };
        return err;
    };
}

const Entity = db.Entity;

// Imports
const std = @import("std");
const db = @import("db");
const Command = @import("Command.zig");
const World = @import("World.zig");
