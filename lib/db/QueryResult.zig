allocator: std.mem.Allocator,
database: *Database,
table_indices: []const usize = &.{},
owned_table_indices: ?[]usize = null,

const QueryResult = @This();

pub fn fromSpec(allocator: std.mem.Allocator, database: *Database, comptime Spec: type) !QueryResult {
    comptime {
        if (!@hasDecl(Spec, "with") or !@hasDecl(Spec, "without") or !@hasDecl(Spec, "without_group_traits")) {
            @compileError("QueryResult.fromSpec expects a QuerySpec generated type");
        }
    }

    const matches = try database.queryTableIndices(Spec);

    return .{
        .allocator = allocator,
        .database = database,
        .table_indices = matches,
        .owned_table_indices = null,
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
        if (table.schema.hasAll(&Spec.with) and
            !table.schema.hasAny(&Spec.without) and
            !tableHasAnyGroupTraits(table, Spec.without_group_traits.items))
        {
            try matches.append(allocator, table_index);
        }
    }

    const owned = try matches.toOwnedSlice(allocator);
    return .{
        .allocator = allocator,
        .database = database,
        .table_indices = owned,
        .owned_table_indices = owned,
    };
}

pub fn deinit(self: *QueryResult) void {
    if (self.owned_table_indices) |owned| {
        if (owned.len > 0) self.allocator.free(owned);
    }
    self.* = undefined;
}

pub fn count(self: *const QueryResult) usize {
    var total: usize = 0;
    for (self.table_indices) |table_index| {
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
        self.table_indices,
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
        while (self.table_index < self.query.table_indices.len) {
            const table_index = self.query.table_indices[self.table_index];
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

fn tableHasAnyGroupTraits(table: *const @import("table.zig").Table, trait_ids: []const meta.TypeId) bool {
    if (trait_ids.len == 0) return false;
    for (table.columns) |column| {
        for (column.group_traits) |group_trait| {
            if (containsTypeId(trait_ids, group_trait.trait_id)) return true;
        }
    }
    return false;
}

fn containsTypeId(ids: []const meta.TypeId, target: meta.TypeId) bool {
    var left: usize = 0;
    var right: usize = ids.len;
    while (left < right) {
        const mid = left + (right - left) / 2;
        const value = ids[mid];
        if (value == target) return true;
        if (value < target) {
            left = mid + 1;
        } else {
            right = mid;
        }
    }
    return false;
}

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

test "QueryResult excludes rows from tables carrying filtered group trait marker" {
    const LayerMarker = struct {
        pub const __query_group_trait__ = true;
    };
    const Layered = struct {
        pub const __traits__ = .{
            struct {
                pub const __trait__ = Group(LayerMarker);
                pub const key: i32 = 0;
            },
        };
    };

    const allocator = std.testing.allocator;
    var database = Database.init(allocator);
    defer database.deinit();

    _ = try database.createEntityWithId(1, .{
        fixtures.Position{ .x = 1, .y = 2 },
    });
    _ = try database.createEntityWithId(2, .{
        fixtures.Position{ .x = 3, .y = 4 },
        Layered{},
    });

    const Spec = QuerySpec.Spec(.{
        fixtures.Position,
        QuerySpec.Without(LayerMarker),
    });
    var result = try QueryResult.fromSpec(allocator, &database, Spec);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 1), result.count());
    try std.testing.expectEqual(@as(u64, 1), result.first().?.entity_id);
}

// Imports
const std = @import("std");
const Database = @import("Database.zig");
const Entity = @import("Entity.zig");
const QuerySpec = @import("QuerySpec.zig");
const GroupByResult = @import("GroupByResult.zig");
const Group = @import("Trait.zig").Group;
const meta = @import("meta.zig");
const fixtures = @import("common").fixtures;
