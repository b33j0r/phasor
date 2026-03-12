const std = @import("std");
const meta = @import("meta.zig");
const Database = @import("Database.zig");
const QueryResult = @import("QueryResult.zig");
const traits = @import("Trait.zig");

allocator: std.mem.Allocator,
database: *Database,
groups: std.ArrayListUnmanaged(Group),

const GroupByResult = @This();

pub fn fromTraitType(
    allocator: std.mem.Allocator,
    database: *Database,
    TraitT: anytype,
) !GroupByResult {
    var group_by = GroupByResult{
        .allocator = allocator,
        .database = database,
        .groups = .empty,
    };

    const trait_id = meta.typeId(TraitT);
    var table_indices: std.ArrayListUnmanaged(usize) = .empty;
    defer table_indices.deinit(allocator);
    for (database.tables.items, 0..) |_, idx| {
        try table_indices.append(allocator, idx);
    }
    group_by.groups = try groupTablesByTrait(allocator, database, table_indices.items, trait_id);
    return group_by;
}

pub fn fromTraitTypeAndTableIndices(
    allocator: std.mem.Allocator,
    database: *Database,
    table_indices: []const usize,
    TraitT: anytype,
) !GroupByResult {
    var group_by = GroupByResult{
        .allocator = allocator,
        .database = database,
        .groups = .empty,
    };

    const trait_id = meta.typeId(TraitT);
    group_by.groups = try groupTablesByTrait(allocator, database, table_indices, trait_id);
    return group_by;
}

fn groupTablesByTrait(
    allocator: std.mem.Allocator,
    database: *Database,
    table_indices: []const usize,
    trait_id: meta.TypeId,
) !std.ArrayListUnmanaged(Group) {
    var groups = std.ArrayListUnmanaged(Group).empty;

    for (table_indices) |table_index| {
        if (table_index >= database.tables.items.len) continue;
        const table = &database.tables.items[table_index];

        for (table.columns) |column| {
            for (column.group_traits) |group_trait| {
                if (group_trait.trait_id != trait_id) continue;
                const group_key = group_trait.key;

                var found_group: ?*Group = null;
                for (groups.items) |*group| {
                    if (group.key == group_key) {
                        found_group = group;
                        break;
                    }
                }

                if (found_group == null) {
                    const new_group = Group.init(allocator, column.type_id, group_key, database);
                    try groups.append(allocator, new_group);
                    found_group = &groups.items[groups.items.len - 1];
                }

                var already_added = false;
                for (found_group.?.table_indices.items) |existing_id| {
                    if (existing_id == table_index) {
                        already_added = true;
                        break;
                    }
                }
                if (!already_added) {
                    try found_group.?.addTableIndex(table_index);
                }
            }
        }
    }

    std.mem.sort(Group, groups.items, {}, struct {
        fn lessThan(_: void, a: Group, b: Group) bool {
            return a.key < b.key;
        }
    }.lessThan);

    return groups;
}

pub fn deinit(self: *GroupByResult) void {
    for (self.groups.items) |*group| {
        group.deinit();
    }
    self.groups.deinit(self.allocator);
    self.* = undefined;
}

pub fn count(self: *const GroupByResult) usize {
    return self.groups.items.len;
}

pub fn iterator(self: *const GroupByResult) GroupIterator {
    return .{
        .groups = self.groups.items,
        .current_index = 0,
    };
}

pub const Group = struct {
    component_id: meta.TypeId,
    key: i32,
    allocator: std.mem.Allocator,
    database: *Database,
    table_indices: std.ArrayListUnmanaged(usize) = .empty,

    pub fn init(allocator: std.mem.Allocator, component_id: meta.TypeId, key: i32, database: *Database) Group {
        return .{
            .component_id = component_id,
            .key = key,
            .allocator = allocator,
            .database = database,
            .table_indices = .empty,
        };
    }

    pub fn deinit(self: *Group) void {
        self.table_indices.deinit(self.allocator);
    }

    pub fn addTableIndex(self: *Group, table_index: usize) !void {
        try self.table_indices.append(self.allocator, table_index);
    }

    pub fn groupBy(self: *const Group, TraitT: anytype) !GroupByResult {
        if (self.table_indices.items.len == 0) {
            return GroupByResult{
                .allocator = self.allocator,
                .database = self.database,
                .groups = .empty,
            };
        }

        return GroupByResult.fromTraitTypeAndTableIndices(
            self.allocator,
            self.database,
            self.table_indices.items,
            TraitT,
        );
    }

    pub fn query(self: *const Group, components: anytype) !QueryResult {
        if (self.table_indices.items.len == 0) {
            return QueryResult{
                .allocator = self.allocator,
                .database = self.database,
                .table_indices = &.{},
                .owned_table_indices = null,
            };
        }

        return QueryResult.fromComponentTypesAndTableIndices(
            self.allocator,
            self.database,
            self.table_indices.items,
            components,
        );
    }

    pub fn iterator(self: *const Group) EntityIterator {
        return .{
            .group = self,
            .table_index = 0,
            .row_index = 0,
        };
    }
};

pub const GroupIterator = struct {
    groups: []const Group,
    current_index: usize,

    pub fn next(self: *GroupIterator) ?*const Group {
        if (self.current_index >= self.groups.len) return null;
        const group = &self.groups[self.current_index];
        self.current_index += 1;
        return group;
    }
};

pub const EntityIterator = struct {
    group: *const Group,
    table_index: usize,
    row_index: usize,

    pub fn next(self: *EntityIterator) ?QueryResult.Row {
        while (self.table_index < self.group.table_indices.items.len) {
            const table_index = self.group.table_indices.items[self.table_index];
            const table = &self.group.database.tables.items[table_index];
            if (self.row_index < table.entity_ids.items.len) {
                const entity_id = table.entity_ids.items[self.row_index];
                const row_index = self.row_index;
                self.row_index += 1;
                return .{
                    .database = self.group.database,
                    .table_index = table_index,
                    .row = row_index,
                    .entity_id = entity_id,
                };
            }
            self.table_index += 1;
            self.row_index = 0;
        }
        return null;
    }
};

test "Database groupBy" {
    const ComponentTypeFactory = struct {
        pub fn Component(N: i32) type {
            return struct {
                pub const __traits__ = .{
                    struct {
                        pub const __trait__ = traits.Group(ComponentN);
                        pub const key: i32 = N;
                    },
                };
            };
        }

        pub const ComponentN = struct {};
    };

    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    const A = ComponentTypeFactory.Component(1);
    const B = ComponentTypeFactory.Component(2);

    const a_id = try db.createEntityWithId(1, .{A{}});
    const b_id = try db.createEntityWithId(2, .{B{}});

    var groups = try db.groupBy(ComponentTypeFactory.ComponentN);
    defer groups.deinit();

    try std.testing.expectEqual(@as(usize, 2), groups.count());

    var it = groups.iterator();
    const group1 = it.next().?;
    const group2 = it.next().?;
    try std.testing.expectEqual(@as(?*const GroupByResult.Group, null), it.next());

    try std.testing.expectEqual(@as(i32, 1), group1.key);
    try std.testing.expectEqual(@as(i32, 2), group2.key);

    var g1_it = group1.iterator();
    var g2_it = group2.iterator();
    try std.testing.expectEqual(a_id, g1_it.next().?.entity_id);
    try std.testing.expectEqual(@as(?QueryResult.Row, null), g1_it.next());
    try std.testing.expectEqual(b_id, g2_it.next().?.entity_id);
    try std.testing.expectEqual(@as(?QueryResult.Row, null), g2_it.next());
}

test "GroupByResult iteration order" {
    const ComponentTypeFactory = struct {
        pub fn Component(N: i32) type {
            return struct {
                pub const __traits__ = .{
                    struct {
                        pub const __trait__ = traits.Group(ComponentN);
                        pub const key: i32 = N;
                    },
                };
            };
        }

        pub const ComponentN = struct {};
    };

    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    const keys = [_]i32{ 5, 3, 8, 1, 9, 2, 7 };
    inline for (keys, 0..) |key, idx| {
        const Component = ComponentTypeFactory.Component(key);
        _ = try db.createEntityWithId(@intCast(idx + 1), .{Component{}});
    }

    var groups = try db.groupBy(ComponentTypeFactory.ComponentN);
    defer groups.deinit();

    try std.testing.expectEqual(keys.len, groups.count());

    var it = groups.iterator();
    var last_key: ?i32 = null;
    while (it.next()) |group| {
        if (last_key) |prev| {
            try std.testing.expect(prev < group.key);
        }
        last_key = group.key;
    }
}
