const std = @import("std");
const meta = @import("meta.zig");
const Column = @import("column.zig").Column;
const Entity = @import("Entity.zig");

pub const Table = struct {
    allocator: std.mem.Allocator,
    schema: meta.TypeIdSet,
    columns: []Column,
    entity_ids: std.ArrayListUnmanaged(Entity.Id) = .empty,

    const Self = @This();

    /// MovePlan is an ephemeral mapping of shared columns between two tables.
    pub const Error = error{
        ComponentTypeMismatch,
        ComponentCountMismatch,
    };

    pub const MovePlan = struct {
        allocator: std.mem.Allocator,
        mappings: []Mapping,

        pub const Mapping = struct {
            src_index: usize,
            dest_index: usize,
        };

        pub fn build(allocator: std.mem.Allocator, src: *const Self, dest: *const Self) !MovePlan {
            var list: std.ArrayListUnmanaged(Mapping) = .empty;
            errdefer list.deinit(allocator);

            var i: usize = 0;
            var j: usize = 0;
            while (i < src.schema.items.len and j < dest.schema.items.len) {
                const src_id = src.schema.items[i];
                const dst_id = dest.schema.items[j];
                if (src_id == dst_id) {
                    try list.append(allocator, .{ .src_index = i, .dest_index = j });
                    i += 1;
                    j += 1;
                } else if (src_id < dst_id) {
                    i += 1;
                } else {
                    j += 1;
                }
            }

            const mappings = try list.toOwnedSlice(allocator);
            return MovePlan{
                .allocator = allocator,
                .mappings = mappings,
            };
        }

        /// Release any allocations for this plan.
        pub fn deinit(self: *MovePlan) void {
            if (self.mappings.len > 0) self.allocator.free(self.mappings);
            self.* = undefined;
        }
    };

    /// Build a table from a component type list (sorted by TypeId).
    pub fn initFromTypes(allocator: std.mem.Allocator, comptime Types: anytype) !Self {
        const schema = meta.typeIdSet(Types);
        const HasValue = @TypeOf(Types) != type;
        const Tup = if (HasValue) @TypeOf(Types) else Types;
        const fields = std.meta.fields(Tup);

        const Entry = struct {
            id: meta.TypeId,
            T: type,
        };

        const entries = comptime blk: {
            var tmp: [fields.len]Entry = undefined;
            for (fields, 0..) |field, i| {
                const T = if (HasValue) blk2: {
                    const value = @field(Types, field.name);
                    break :blk2 if (@TypeOf(value) == type) value else @TypeOf(value);
                } else field.type;
                tmp[i] = .{ .id = meta.typeId(T), .T = T };
            }

            std.sort.pdq(Entry, &tmp, {}, struct {
                fn lessThan(_: void, a: Entry, b: Entry) bool {
                    return a.id < b.id;
                }
            }.lessThan);

            break :blk tmp;
        };

        var columns = try allocator.alloc(Column, entries.len);
        errdefer allocator.free(columns);

        var i: usize = 0;
        errdefer {
            var j: usize = 0;
            while (j < i) : (j += 1) {
                columns[j].deinit();
            }
        }

        inline for (entries, 0..) |entry, idx| {
            columns[idx] = try Column.init(entry.T, allocator);
            i += 1;
        }

        return Self{
            .allocator = allocator,
            .schema = schema,
            .columns = columns,
            .entity_ids = .empty,
        };
    }

    /// Release column storage and entity bookkeeping.
    pub fn deinit(self: *Self) void {
        for (self.columns) |*column| {
            column.deinit();
        }
        if (self.columns.len > 0) self.allocator.free(self.columns);
        self.entity_ids.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn len(self: *const Self) usize {
        return self.entity_ids.items.len;
    }

    /// Add an entity with components that exactly match the table schema.
    pub fn addEntity(self: *Self, entity_id: Entity.Id, components: anytype) !usize {
        const input_set = meta.typeIdSet(@TypeOf(components));
        if (!self.schema.eql(&input_set)) return error.ComponentTypeMismatch;
        if (self.columns.len != self.schema.items.len) return error.ComponentCountMismatch;

        try self.entity_ids.append(self.allocator, entity_id);
        const row_index = self.entity_ids.items.len - 1;
        errdefer {
            _ = self.entity_ids.pop();
        }

        const fields = std.meta.fields(@TypeOf(components));
        errdefer {
            for (self.columns) |*column| {
                if (column.len() > row_index) {
                    _ = column.swapRemoveDeinit(row_index);
                }
            }
        }

        inline for (fields) |field| {
            const value = @field(components, field.name);
            const T = field.type;
            const id = meta.typeId(T);
            const col_index = self.getColumnIndex(id) orelse return error.ComponentTypeMismatch;
            try self.columns[col_index].pushAs(T, value);
        }

        return row_index;
    }

    /// Get a typed component pointer for a row, or null if absent.
    pub fn getComponentPtr(self: *Self, row: usize, comptime T: type) ?*T {
        const id = meta.typeId(T);
        const col_index = self.getColumnIndex(id) orelse return null;
        return self.columns[col_index].getAs(T, row);
    }

    /// Swap-remove a row and return the moved entity id (if any).
    pub fn swapRemove(self: *Self, row: usize) ?Entity.Id {
        if (row >= self.entity_ids.items.len) return null;
        const last_index = self.entity_ids.items.len - 1;
        const moved_id: ?Entity.Id = if (row != last_index) self.entity_ids.items[last_index] else null;

        _ = self.entity_ids.swapRemove(row);
        for (self.columns) |*column| {
            _ = column.swapRemoveDeinit(row);
        }

        return moved_id;
    }

    /// Copy a row into another table using a per-call MovePlan.
    pub fn copyRowTo(self: *Self, row: usize, dest: *Self) !usize {
        var plan = try MovePlan.build(self.allocator, self, dest);
        defer plan.deinit();
        return self.copyRowToPlan(row, dest, &plan);
    }

    /// Copy a row into another table using a precomputed MovePlan.
    pub fn copyRowToPlan(self: *Self, row: usize, dest: *Self, plan: *const MovePlan) !usize {
        if (row >= self.entity_ids.items.len) return error.IndexOutOfBounds;

        const entity_id = self.entity_ids.items[row];
        try dest.entity_ids.append(dest.allocator, entity_id);
        const new_row = dest.entity_ids.items.len - 1;
        errdefer {
            _ = dest.entity_ids.pop();
        }

        errdefer {
            var k: usize = 0;
            while (k < dest.columns.len) : (k += 1) {
                if (dest.columns[k].len() > new_row) {
                    _ = dest.columns[k].swapRemoveDeinit(new_row);
                }
            }
        }

        for (plan.mappings) |mapping| {
            const src_col = &self.columns[mapping.src_index];
            const dst_col = &dest.columns[mapping.dest_index];
            const ptr = src_col.getPtr(row) orelse return error.ComponentTypeMismatch;
            try dst_col.pushFromPtr(ptr);
        }

        // Fill destination-only columns to keep row alignment.
        var map_index: usize = 0;
        var dest_index: usize = 0;
        while (dest_index < dest.columns.len) : (dest_index += 1) {
            if (map_index < plan.mappings.len and plan.mappings[map_index].dest_index == dest_index) {
                map_index += 1;
                continue;
            }
            try dest.columns[dest_index].pushDefault();
        }

        return new_row;
    }


    fn getColumnIndex(self: *const Self, id: meta.TypeId) ?usize {
        var left: usize = 0;
        var right: usize = self.schema.items.len;
        while (left < right) {
            const mid = left + (right - left) / 2;
            const value = self.schema.items[mid];
            if (value == id) return mid;
            if (value < id) {
                left = mid + 1;
            } else {
                right = mid;
            }
        }
        return null;
    }
};

test "Table initFromTypes/add/get basics" {
    const fixtures = @import("column/fixtures.zig");

    var table = try Table.initFromTypes(std.testing.allocator, .{ fixtures.Position, fixtures.Velocity });
    defer table.deinit();

    const e0: Entity.Id = 10;
    const row0 = try table.addEntity(e0, .{
        fixtures.Position{ .x = 1, .y = 2 },
        fixtures.Velocity{ .dx = 3, .dy = 4 },
    });

    try std.testing.expectEqual(@as(usize, 0), row0);
    try std.testing.expectEqual(@as(usize, 1), table.len());

    const p = table.getComponentPtr(row0, fixtures.Position).?;
    try std.testing.expectEqual(@as(f32, 1), p.x);
    try std.testing.expectEqual(@as(f32, 2), p.y);

}

test "Table swapRemove returns moved entity id" {
    const fixtures = @import("column/fixtures.zig");

    var table = try Table.initFromTypes(std.testing.allocator, .{ fixtures.Position });
    defer table.deinit();

    _ = try table.addEntity(1, .{fixtures.Position{ .x = 1, .y = 1 }});
    _ = try table.addEntity(2, .{fixtures.Position{ .x = 2, .y = 2 }});

    const moved = table.swapRemove(0).?;
    try std.testing.expectEqual(@as(Entity.Id, 2), moved);
    try std.testing.expectEqual(@as(usize, 1), table.len());
}

test "Table move copies shared components only" {
    const fixtures = @import("column/fixtures.zig");

    var src = try Table.initFromTypes(std.testing.allocator, .{ fixtures.Position, fixtures.Velocity });
    defer src.deinit();
    var dst = try Table.initFromTypes(std.testing.allocator, .{ fixtures.Position, fixtures.Health });
    defer dst.deinit();

    _ = try src.addEntity(1, .{
        fixtures.Position{ .x = 1, .y = 2 },
        fixtures.Velocity{ .dx = 3, .dy = 4 },
    });

    const new_row = try src.copyRowTo(0, &dst);
    try std.testing.expectEqual(@as(usize, 1), dst.len());

    const p = dst.getComponentPtr(new_row, fixtures.Position).?;
    try std.testing.expectEqual(@as(f32, 1), p.x);
    try std.testing.expectEqual(@as(f32, 2), p.y);
    const h = dst.getComponentPtr(new_row, fixtures.Health).?;
    try std.testing.expectEqual(@as(i32, 0), h.hp);
}

test "Table move returns moved id on source swapRemove" {
    const fixtures = @import("column/fixtures.zig");

    var src = try Table.initFromTypes(std.testing.allocator, .{ fixtures.Position });
    defer src.deinit();
    var dst = try Table.initFromTypes(std.testing.allocator, .{ fixtures.Position });
    defer dst.deinit();

    _ = try src.addEntity(10, .{fixtures.Position{ .x = 1, .y = 1 }});
    _ = try src.addEntity(20, .{fixtures.Position{ .x = 2, .y = 2 }});

    _ = try src.copyRowTo(0, &dst);
    const moved = src.swapRemove(0).?;
    try std.testing.expectEqual(@as(Entity.Id, 20), moved);
}

test "Table move works with ZST components" {
    const fixtures = @import("column/fixtures.zig");

    var src = try Table.initFromTypes(std.testing.allocator, .{ fixtures.Position });
    defer src.deinit();
    var dst = try Table.initFromTypes(std.testing.allocator, .{ fixtures.Position, fixtures.ShipIsOnFire });
    defer dst.deinit();

    _ = try src.addEntity(1, .{fixtures.Position{ .x = 1, .y = 2 }});
    const new_row = try src.copyRowTo(0, &dst);
    try std.testing.expectEqual(@as(usize, 1), dst.len());
    const p = dst.getComponentPtr(new_row, fixtures.Position).?;
    try std.testing.expectEqual(@as(f32, 1), p.x);
}

test "Table addEntity with ZST and non-ZST" {
    const fixtures = @import("column/fixtures.zig");

    var table = try Table.initFromTypes(std.testing.allocator, .{ fixtures.Position, fixtures.Tag });
    defer table.deinit();

    const row = try table.addEntity(1, .{ fixtures.Position{ .x = 1, .y = 2 }, fixtures.Tag{} });
    try std.testing.expectEqual(@as(usize, 1), table.len());
    try std.testing.expect(table.getComponentPtr(row, fixtures.Tag) != null);
}

test "MovePlan captures shared columns" {
    const fixtures = @import("column/fixtures.zig");

    var src = try Table.initFromTypes(std.testing.allocator, .{ fixtures.Position, fixtures.Velocity });
    defer src.deinit();
    var dst = try Table.initFromTypes(std.testing.allocator, .{ fixtures.Position, fixtures.Health });
    defer dst.deinit();

    var plan = try Table.MovePlan.build(std.testing.allocator, &src, &dst);
    defer plan.deinit();

    try std.testing.expectEqual(@as(usize, 1), plan.mappings.len);
}

test "Table copyRowToPlan copies shared components" {
    const fixtures = @import("column/fixtures.zig");

    var src = try Table.initFromTypes(std.testing.allocator, .{ fixtures.Position, fixtures.Velocity });
    defer src.deinit();
    var dst = try Table.initFromTypes(std.testing.allocator, .{ fixtures.Position, fixtures.Health });
    defer dst.deinit();

    _ = try src.addEntity(1, .{
        fixtures.Position{ .x = 1, .y = 2 },
        fixtures.Velocity{ .dx = 3, .dy = 4 },
    });

    var plan = try Table.MovePlan.build(std.testing.allocator, &src, &dst);
    defer plan.deinit();

    const new_row = try src.copyRowToPlan(0, &dst, &plan);
    try std.testing.expect(dst.getComponentPtr(new_row, fixtures.Position) != null);
}
