allocator: std.mem.Allocator,
database: *Database,
table_indices: std.ArrayListUnmanaged(usize) = .empty,

const QueryResult = @This();

pub fn fromSpec(allocator: std.mem.Allocator, database: *Database, comptime Spec: type) !QueryResult {
    comptime {
        if (!@hasDecl(Spec, "with") or !@hasDecl(Spec, "without")) {
            @compileError("QueryResult.fromSpec expects a QuerySpec generated type");
        }
    }

    var matches: std.ArrayListUnmanaged(usize) = .empty;
    errdefer matches.deinit(allocator);

    for (database.tables.items, 0..) |*table, idx| {
        if (table.schema.hasAll(&Spec.with) and !table.schema.hasAny(&Spec.without)) {
            try matches.append(allocator, idx);
        }
    }

    return .{
        .allocator = allocator,
        .database = database,
        .table_indices = matches,
    };
}

pub fn fromComponentTypesAndTableIndices(
    allocator: std.mem.Allocator,
    database: *Database,
    table_indices: []const usize,
    components: anytype,
) !QueryResult {
    const Spec = QuerySpec.Spec(components);
    var matches: std.ArrayListUnmanaged(usize) = .empty;
    errdefer matches.deinit(allocator);

    for (table_indices) |table_index| {
        if (table_index >= database.tables.items.len) continue;
        const table = &database.tables.items[table_index];
        if (table.schema.hasAll(&Spec.with) and !table.schema.hasAny(&Spec.without)) {
            try matches.append(allocator, table_index);
        }
    }

    return .{
        .allocator = allocator,
        .database = database,
        .table_indices = matches,
    };
}

pub fn deinit(self: *QueryResult) void {
    self.table_indices.deinit(self.allocator);
    self.* = undefined;
}

pub fn count(self: *const QueryResult) usize {
    var total: usize = 0;
    for (self.table_indices.items) |table_index| {
        const table = &self.database.tables.items[table_index];
        total += table.entity_ids.items.len;
    }
    return total;
}

pub fn iterator(self: *const QueryResult) Iterator {
    return .{
        .query = self,
        .table_index = 0,
        .row_index = 0,
    };
}

pub fn first(self: *const QueryResult) ?Row {
    var it = self.iterator();
    return it.next();
}

pub fn groupBy(self: *const QueryResult, TraitT: anytype) !GroupByResult {
    return GroupByResult.fromTraitTypeAndTableIndices(
        self.allocator,
        self.database,
        self.table_indices.items,
        TraitT,
    );
}

pub fn listAlloc(self: *const QueryResult, allocator: std.mem.Allocator) ![]Entity.Id {
    const total = self.count();
    if (total == 0) return allocator.alloc(Entity.Id, 0);

    var result = try allocator.alloc(Entity.Id, total);
    errdefer allocator.free(result);

    var it = self.iterator();
    var idx: usize = 0;
    while (it.next()) |row| {
        result[idx] = row.entity_id;
        idx += 1;
    }

    return result;
}

pub const Row = struct {
    database: *Database,
    table_index: usize,
    row: usize,
    entity_id: Entity.Id,

    pub fn get(self: *const Row, comptime T: type) ?*T {
        const table = &self.database.tables.items[self.table_index];
        return table.getComponentPtr(self.row, T);
    }
};

pub const Iterator = struct {
    query: *const QueryResult,
    table_index: usize,
    row_index: usize,

    pub fn next(self: *Iterator) ?Row {
        while (self.table_index < self.query.table_indices.items.len) {
            const table_index = self.query.table_indices.items[self.table_index];
            const table = &self.query.database.tables.items[table_index];
            if (self.row_index < table.entity_ids.items.len) {
                const entity_id = table.entity_ids.items[self.row_index];
                const row = self.row_index;
                self.row_index += 1;
                return .{
                    .database = self.query.database,
                    .table_index = table_index,
                    .row = row,
                    .entity_id = entity_id,
                };
            }

            self.table_index += 1;
            self.row_index = 0;
        }

        return null;
    }
};

test "QueryResult matches tables and iterates rows" {
    const allocator = std.testing.allocator;
    var database = Database.init(allocator);
    defer database.deinit();

    _ = try database.createEntityWithId(1, .{
        fixtures.Position{ .x = 1, .y = 2 },
        fixtures.Velocity{ .dx = 1, .dy = 0 },
    });
    _ = try database.createEntityWithId(2, .{
        fixtures.Position{ .x = 5, .y = 6 },
    });
    _ = try database.createEntityWithId(3, .{
        fixtures.Health{ .hp = 10 },
    });

    const Spec = QuerySpec.Spec(.{ fixtures.Position, QuerySpec.Without(fixtures.Velocity) });
    var result = try QueryResult.fromSpec(allocator, &database, Spec);
    defer result.deinit();

    try std.testing.expect(result.count() == 1);
    const first_row = result.first().?;
    try std.testing.expect(first_row.entity_id == 2);
    try std.testing.expect(first_row.get(fixtures.Position) != null);
    try std.testing.expect(first_row.get(fixtures.Velocity) == null);

    const ids = try result.listAlloc(allocator);
    defer allocator.free(ids);
    try std.testing.expect(ids.len == 1);
    try std.testing.expect(ids[0] == 2);
}

// Imports
const std = @import("std");
const Database = @import("Database.zig");
const Entity = @import("Entity.zig");
const QuerySpec = @import("QuerySpec.zig");
const GroupByResult = @import("GroupByResult.zig");
const fixtures = @import("common").fixtures;
