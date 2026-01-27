const std = @import("std");
const Table = @import("table.zig").Table;
const Entity = @import("entity.zig");
const meta = @import("meta.zig");

/// Database owns tables and entity locations, and provides move-first operations.
pub const Database = struct {
    allocator: std.mem.Allocator,
    tables: std.ArrayListUnmanaged(Table) = .empty,
    table_index_by_hash: std.AutoArrayHashMapUnmanaged(u64, usize) = .empty,
    entities: std.AutoArrayHashMapUnmanaged(Entity.Id, EntityLocation) = .empty,
    next_entity_id: Entity.Id = 0,

    const Self = @This();

    /// EntityLocation tracks which table and row an entity currently occupies.
    pub const EntityLocation = struct {
        table_index: usize,
        row: usize,
    };

    pub const Error = error{
        EntityNotFound,
    };

    /// Initialize an empty database.
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .tables = .empty,
            .table_index_by_hash = .empty,
            .entities = .empty,
            .next_entity_id = 0,
        };
    }

    /// Free all tables and entity tracking.
    pub fn deinit(self: *Self) void {
        for (self.tables.items) |*table| table.deinit();
        self.tables.deinit(self.allocator);
        self.table_index_by_hash.deinit(self.allocator);
        self.entities.deinit(self.allocator);
        self.* = undefined;
    }

    /// Get or create a table for the given component types.
    pub fn getOrCreateTable(self: *Self, comptime Types: anytype) !usize {
        const schema = meta.typeIdSet(Types);
        const hash = schema.hash();
        if (self.table_index_by_hash.get(hash)) |idx| return idx;

        var table = try Table.initFromTypes(self.allocator, Types);
        errdefer table.deinit();

        const idx = self.tables.items.len;
        try self.tables.append(self.allocator, table);
        try self.table_index_by_hash.put(self.allocator, hash, idx);
        return idx;
    }

    /// Create an entity in a specific table and record its location.
    pub fn createEntityInTable(self: *Self, table_index: usize, components: anytype) !Entity.Id {
        const entity_id = self.next_entity_id;
        self.next_entity_id += 1;
        const table = &self.tables.items[table_index];
        const row = try table.addEntity(entity_id, components);
        try self.entities.put(self.allocator, entity_id, .{
            .table_index = table_index,
            .row = row,
        });
        return entity_id;
    }

    /// Move an entity to another table, copying shared components and updating locations.
    pub fn moveEntity(self: *Self, entity_id: Entity.Id, dest_table_index: usize) !void {
        const loc = self.entities.getPtr(entity_id) orelse return Error.EntityNotFound;
        if (loc.table_index == dest_table_index) return;

        const src_table = &self.tables.items[loc.table_index];
        const dst_table = &self.tables.items[dest_table_index];
        var plan = try Table.MovePlan.build(self.allocator, src_table, dst_table);
        defer plan.deinit();
        const new_row = try src_table.copyRowToPlan(loc.row, dst_table, &plan);
        const moved = src_table.swapRemove(loc.row);
        if (moved) |moved_id| {
            if (self.entities.getPtr(moved_id)) |moved_loc| {
                moved_loc.row = loc.row;
            }
        }

        loc.table_index = dest_table_index;
        loc.row = new_row;
    }
};

test "Database moveEntity updates locations" {
    const fixtures = @import("column/fixtures.zig");

    var db = Database.init(std.testing.allocator);
    defer db.deinit();

    const src_idx = try db.getOrCreateTable(.{ fixtures.Position });
    const dst_idx = try db.getOrCreateTable(.{ fixtures.Position, fixtures.Velocity });

    const entity_id = try db.createEntityInTable(src_idx, .{fixtures.Position{ .x = 1, .y = 2 }});
    try db.moveEntity(entity_id, dst_idx);

    const loc = db.entities.get(entity_id).?;
    try std.testing.expectEqual(dst_idx, loc.table_index);
    try std.testing.expectEqual(@as(usize, 0), loc.row);
}

test "Database moveEntity updates moved row when swapRemove occurs" {
    const fixtures = @import("column/fixtures.zig");

    var db = Database.init(std.testing.allocator);
    defer db.deinit();

    const src_idx = try db.getOrCreateTable(.{ fixtures.Position });
    const dst_idx = try db.getOrCreateTable(.{ fixtures.Position, fixtures.Velocity });

    const e0 = try db.createEntityInTable(src_idx, .{fixtures.Position{ .x = 1, .y = 1 }});
    const e1 = try db.createEntityInTable(src_idx, .{fixtures.Position{ .x = 2, .y = 2 }});

    try db.moveEntity(e0, dst_idx);

    const loc0 = db.entities.get(e0).?;
    try std.testing.expectEqual(dst_idx, loc0.table_index);
    try std.testing.expectEqual(@as(usize, 0), loc0.row);

    const loc1 = db.entities.get(e1).?;
    try std.testing.expectEqual(src_idx, loc1.table_index);
    try std.testing.expectEqual(@as(usize, 0), loc1.row);
}
