/// Database owns tables and entity locations, and provides move-first operations.
allocator: std.mem.Allocator,
tables: std.ArrayListUnmanaged(Table) = .empty,
table_index_by_hash: std.AutoArrayHashMapUnmanaged(u64, usize) = .empty,
entities: std.AutoArrayHashMapUnmanaged(Entity.Id, EntityLocation) = .empty,
next_entity_id: Entity.Id = 0,
hooks: ?*const hooks_mod.DatabaseHooks = null,
table_hooks: hooks_mod.TableHooks = hooks_mod.TableHooks.none(),

const Self = @This();

/// EntityLocation tracks which table and row an entity currently occupies.
pub const EntityLocation = struct {
    table_index: usize,
    row: usize,
};

pub const Error = error{
    EntityNotFound,
    ComponentMissing,
    EntityAlreadyExists,
};

/// Initialize an empty database.
pub fn init(allocator: std.mem.Allocator) Self {
    return Self{
        .allocator = allocator,
        .tables = .empty,
        .table_index_by_hash = .empty,
        .entities = .empty,
        .next_entity_id = 0,
        .hooks = null,
        .table_hooks = hooks_mod.TableHooks.none(),
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
    table.table_index = idx;
    table.hooks = self.table_hooks;
    try self.tables.append(self.allocator, table);
    try self.table_index_by_hash.put(self.allocator, hash, idx);
    return idx;
}

pub fn reserveEntityId(self: *Self) Entity.Id {
    const entity_id = self.next_entity_id;
    self.next_entity_id += 1;
    return entity_id;
}

/// Create an entity in a specific table and record its location.
pub fn createEntityInTable(self: *Self, table_index: usize, components: anytype) !Entity.Id {
    const entity_id = self.next_entity_id;
    self.next_entity_id += 1;
    return try self.createEntityWithIdInTable(entity_id, table_index, components);
}

pub fn createEntityWithId(self: *Self, entity_id: Entity.Id, components: anytype) !Entity.Id {
    if (self.entities.contains(entity_id)) return Error.EntityAlreadyExists;
    const table_index = try self.getOrCreateTable(@TypeOf(components));
    return try self.createEntityWithIdInTable(entity_id, table_index, components);
}

pub fn createEntityWithIdInTable(self: *Self, entity_id: Entity.Id, table_index: usize, components: anytype) !Entity.Id {
    if (self.entities.contains(entity_id)) return Error.EntityAlreadyExists;
    const table = &self.tables.items[table_index];
    const row = try table.addEntity(entity_id, components);
    try self.entities.put(self.allocator, entity_id, .{
        .table_index = table_index,
        .row = row,
    });
    if (self.hooks) |hooks_ptr| {
        hooks_ptr.onEntityCreated(entity_id, table_index);
    }
    if (entity_id >= self.next_entity_id) {
        self.next_entity_id = entity_id + 1;
    }
    return entity_id;
}

pub fn findTableIndexByTypeIds(self: *const Self, ids: []const meta.TypeId) ?usize {
    var hasher = std.hash.Wyhash.init(0);
    for (ids) |id| {
        hasher.update(std.mem.asBytes(&id));
    }
    const hash = hasher.final();
    const idx = self.table_index_by_hash.get(hash) orelse return null;
    const schema = self.tables.items[idx].schema.items;
    if (!std.mem.eql(meta.TypeId, schema, ids)) return null;
    return idx;
}

pub fn addComponents(self: *Self, entity_id: Entity.Id, components: anytype) !void {
    const loc = self.entities.getPtr(entity_id) orelse return Error.EntityNotFound;
    const src_table = &self.tables.items[loc.table_index];
    const add_ids = meta.typeIdSet(@TypeOf(components)).items;

    if (schemaContainsAll(src_table.schema.items, add_ids)) {
        try setComponentsInTable(src_table, loc.row, components);
        return;
    }

    const union_ids = try mergeTypeIds(self.allocator, src_table.schema.items, add_ids);
    defer self.allocator.free(union_ids);

    var dest_index = self.findTableIndexByTypeIds(union_ids);
    if (dest_index == null) {
        dest_index = try self.createTableFromUnion(src_table, union_ids, components);
    }

    const new_row = try moveEntityToTable(self, entity_id, dest_index.?);
    const dest_table = &self.tables.items[dest_index.?];
    try setComponentsInTable(dest_table, new_row, components);
}

pub fn removeComponents(self: *Self, entity_id: Entity.Id, comptime Types: anytype) !void {
    const loc = self.entities.getPtr(entity_id) orelse return Error.EntityNotFound;
    const src_table = &self.tables.items[loc.table_index];
    const remove_ids = meta.typeIdSet(Types).items;
    if (!schemaContainsAll(src_table.schema.items, remove_ids)) return Error.ComponentMissing;

    var remaining_ids = try diffTypeIds(self.allocator, src_table.schema.items, remove_ids);
    defer self.allocator.free(remaining_ids);

    if (remaining_ids.len == src_table.schema.items.len) return;

    var dest_index = self.findTableIndexByTypeIds(remaining_ids);
    if (dest_index == null) {
        dest_index = try self.createTableFromSubset(src_table, remaining_ids);
    }

    _ = try moveEntityToTable(self, entity_id, dest_index.?);
}

fn createTableFromUnion(
    self: *Self,
    src_table: *const Table,
    union_ids: []const meta.TypeId,
    components: anytype,
) !usize {
    var columns = try self.allocator.alloc(Column, union_ids.len);
    errdefer {
        for (columns) |*col| col.deinit();
        self.allocator.free(columns);
    }

    for (union_ids, 0..) |id, i| {
        if (findTypeIdIndex(src_table.schema.items, id)) |src_idx| {
            columns[i] = try src_table.columns[src_idx].cloneEmpty(self.allocator);
        } else {
            columns[i] = try columnFromComponents(id, components, self.allocator);
        }
    }

    const schema_copy = try self.allocator.dupe(meta.TypeId, union_ids);
    const table = Table.initFromTypeIds(self.allocator, schema_copy, columns);
    return try self.insertTable(schema_copy, table);
}

fn createTableFromSubset(
    self: *Self,
    src_table: *const Table,
    remaining_ids: []const meta.TypeId,
) !usize {
    var columns = try self.allocator.alloc(Column, remaining_ids.len);
    errdefer {
        for (columns) |*col| col.deinit();
        self.allocator.free(columns);
    }

    for (remaining_ids, 0..) |id, i| {
        const src_idx = findTypeIdIndex(src_table.schema.items, id) orelse return Error.ComponentMissing;
        columns[i] = try src_table.columns[src_idx].cloneEmpty(self.allocator);
    }

    const schema_copy = try self.allocator.dupe(meta.TypeId, remaining_ids);
    const table = Table.initFromTypeIds(self.allocator, schema_copy, columns);
    return try self.insertTable(schema_copy, table);
}

fn insertTable(self: *Self, schema_ids: []const meta.TypeId, table: Table) !usize {
    const hash = hashTypeIds(schema_ids);
    const idx = self.tables.items.len;
    var table_with_hooks = table;
    table_with_hooks.table_index = idx;
    table_with_hooks.hooks = self.table_hooks;
    try self.tables.append(self.allocator, table_with_hooks);
    try self.table_index_by_hash.put(self.allocator, hash, idx);
    return idx;
}

fn moveEntityToTable(self: *Self, entity_id: Entity.Id, dest_table_index: usize) !usize {
    const loc = self.entities.getPtr(entity_id) orelse return Error.EntityNotFound;
    if (loc.table_index == dest_table_index) return loc.row;

    const src_table = &self.tables.items[loc.table_index];
    const dest_table = &self.tables.items[dest_table_index];
    var plan = try Table.MovePlan.build(self.allocator, src_table, dest_table);
    defer plan.deinit();
    const new_row = try src_table.copyRowToPlan(loc.row, dest_table, &plan);
    const moved = src_table.swapRemove(loc.row);
    if (moved) |moved_id| {
        if (self.entities.getPtr(moved_id)) |moved_loc| {
            moved_loc.row = loc.row;
        }
    }

    if (self.hooks) |hooks_ptr| {
        hooks_ptr.onEntityMoved(entity_id, loc.table_index, dest_table_index);
    }
    loc.table_index = dest_table_index;
    loc.row = new_row;
    return new_row;
}

fn setComponentsInTable(table: *Table, row: usize, components: anytype) !void {
    const fields = std.meta.fields(@TypeOf(components));
    inline for (fields) |field| {
        const value = @field(components, field.name);
        const T = @TypeOf(value);
        const ptr = table.getComponentPtr(row, T) orelse return Error.ComponentMissing;
        ptr.* = value;
    }
}

fn columnFromComponents(id: meta.TypeId, components: anytype, allocator: std.mem.Allocator) !Column {
    const fields = std.meta.fields(@TypeOf(components));
    inline for (fields) |field| {
        const value = @field(components, field.name);
        const T = @TypeOf(value);
        if (meta.typeId(T) == id) {
            return Column.init(T, allocator);
        }
    }
    return Error.ComponentMissing;
}

fn hashTypeIds(ids: []const meta.TypeId) u64 {
    var hasher = std.hash.Wyhash.init(0);
    for (ids) |id| {
        hasher.update(std.mem.asBytes(&id));
    }
    return hasher.final();
}

fn findTypeIdIndex(items: []const meta.TypeId, target: meta.TypeId) ?usize {
    var left: usize = 0;
    var right: usize = items.len;
    while (left < right) {
        const mid = left + (right - left) / 2;
        const value = items[mid];
        if (value == target) return mid;
        if (value < target) {
            left = mid + 1;
        } else {
            right = mid;
        }
    }
    return null;
}

fn schemaContainsAll(schema: []const meta.TypeId, needed: []const meta.TypeId) bool {
    var i: usize = 0;
    var j: usize = 0;
    while (i < schema.len and j < needed.len) {
        if (schema[i] == needed[j]) {
            i += 1;
            j += 1;
        } else if (schema[i] < needed[j]) {
            i += 1;
        } else {
            return false;
        }
    }
    return j == needed.len;
}

fn mergeTypeIds(
    allocator: std.mem.Allocator,
    a: []const meta.TypeId,
    b: []const meta.TypeId,
) ![]meta.TypeId {
    var list: std.ArrayListUnmanaged(meta.TypeId) = .empty;
    errdefer list.deinit(allocator);

    var i: usize = 0;
    var j: usize = 0;
    while (i < a.len or j < b.len) {
        if (i == a.len) {
            try list.append(allocator, b[j]);
            j += 1;
            continue;
        }
        if (j == b.len) {
            try list.append(allocator, a[i]);
            i += 1;
            continue;
        }
        if (a[i] == b[j]) {
            try list.append(allocator, a[i]);
            i += 1;
            j += 1;
        } else if (a[i] < b[j]) {
            try list.append(allocator, a[i]);
            i += 1;
        } else {
            try list.append(allocator, b[j]);
            j += 1;
        }
    }

    return try list.toOwnedSlice(allocator);
}

fn diffTypeIds(
    allocator: std.mem.Allocator,
    source: []const meta.TypeId,
    remove: []const meta.TypeId,
) ![]meta.TypeId {
    var list: std.ArrayListUnmanaged(meta.TypeId) = .empty;
    errdefer list.deinit(allocator);

    var i: usize = 0;
    var j: usize = 0;
    while (i < source.len) {
        if (j < remove.len and source[i] == remove[j]) {
            i += 1;
            j += 1;
            continue;
        }
        if (j < remove.len and source[i] > remove[j]) {
            j += 1;
            continue;
        }
        try list.append(allocator, source[i]);
        i += 1;
    }

    return try list.toOwnedSlice(allocator);
}

pub fn tableMut(self: *Self, table_index: usize) *Table {
    return &self.tables.items[table_index];
}

pub fn tableConst(self: *const Self, table_index: usize) *const Table {
    return &self.tables.items[table_index];
}

pub fn removeEntity(self: *Self, entity_id: Entity.Id) !void {
    const loc = self.entities.getPtr(entity_id) orelse return Error.EntityNotFound;
    const table = &self.tables.items[loc.table_index];
    const moved = table.swapRemove(loc.row);
    if (moved) |moved_id| {
        if (self.entities.getPtr(moved_id)) |moved_loc| {
            moved_loc.row = loc.row;
        }
    }
    _ = self.entities.swapRemove(entity_id);
    if (self.hooks) |hooks_ptr| {
        hooks_ptr.onEntityRemoved(entity_id, loc.table_index);
    }
}

/// Move an entity to another table, copying shared components and updating locations.
pub fn moveEntity(self: *Self, entity_id: Entity.Id, dest_table_index: usize) !void {
    const loc = self.entities.getPtr(entity_id) orelse return Error.EntityNotFound;
    const from_table = loc.table_index;
    if (from_table == dest_table_index) return;

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
    if (self.hooks) |hooks_ptr| {
        hooks_ptr.onEntityMoved(entity_id, from_table, dest_table_index);
    }
}

pub fn setHooks(self: *Self, hooks_ptr: *const hooks_mod.DatabaseHooks) void {
    self.hooks = hooks_ptr;
    self.table_hooks = self.tableHooksForwarder(hooks_ptr);
    self.applyTableHooks();
}

pub fn clearHooks(self: *Self) void {
    self.hooks = null;
    self.table_hooks = hooks_mod.TableHooks.none();
    self.applyTableHooks();
}

pub fn notifyResourceInserted(self: *Self, type_id: meta.TypeId) void {
    if (self.hooks) |hooks_ptr| {
        hooks_ptr.onResourceInserted(type_id);
    }
}

pub fn notifyResourceRemoved(self: *Self, type_id: meta.TypeId) void {
    if (self.hooks) |hooks_ptr| {
        hooks_ptr.onResourceRemoved(type_id);
    }
}

fn tableHooksForwarder(_: *Self, hooks_ptr: *const hooks_mod.DatabaseHooks) hooks_mod.TableHooks {
    const Forwarder = struct {
        fn onRowAdded(ctx: *anyopaque, table_index: usize, row: usize, entity_id: Entity.Id) void {
            const db_hooks: *const hooks_mod.DatabaseHooks = @ptrCast(@alignCast(ctx));
            db_hooks.onTableRowAdded(table_index, row, entity_id);
        }

        fn onRowRemoved(ctx: *anyopaque, table_index: usize, row: usize, entity_id: Entity.Id) void {
            const db_hooks: *const hooks_mod.DatabaseHooks = @ptrCast(@alignCast(ctx));
            db_hooks.onTableRowRemoved(table_index, row, entity_id);
        }

        fn onRowMoved(ctx: *anyopaque, table_index: usize, from_row: usize, to_row: usize, entity_id: Entity.Id) void {
            const db_hooks: *const hooks_mod.DatabaseHooks = @ptrCast(@alignCast(ctx));
            db_hooks.onTableRowMoved(table_index, from_row, to_row, entity_id);
        }
    };

    return hooks_mod.TableHooks{
        .ctx = @constCast(hooks_ptr),
        .vtable = .{
            .on_row_added = Forwarder.onRowAdded,
            .on_row_removed = Forwarder.onRowRemoved,
            .on_row_moved = Forwarder.onRowMoved,
        },
    };
}

fn applyTableHooks(self: *Self) void {
    for (self.tables.items) |*table| {
        table.hooks = self.table_hooks;
    }
}

test "Database moveEntity updates locations" {

    var db = init(std.testing.allocator);
    defer db.deinit();

    const src_idx = try db.getOrCreateTable(.{fixtures.Position});
    const dst_idx = try db.getOrCreateTable(.{ fixtures.Position, fixtures.Velocity });

    const entity_id = try db.createEntityInTable(src_idx, .{fixtures.Position{ .x = 1, .y = 2 }});
    try db.moveEntity(entity_id, dst_idx);

    const loc = db.entities.get(entity_id).?;
    try std.testing.expectEqual(dst_idx, loc.table_index);
    try std.testing.expectEqual(@as(usize, 0), loc.row);
}

test "Database moveEntity updates moved row when swapRemove occurs" {

    var db = init(std.testing.allocator);
    defer db.deinit();

    const src_idx = try db.getOrCreateTable(.{fixtures.Position});
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

test "Database addComponents moves entity and preserves existing data" {

    var db = init(std.testing.allocator);
    defer db.deinit();

    const entity_id = try db.createEntityWithId(1, .{fixtures.Position{ .x = 1, .y = 2 }});
    try db.addComponents(entity_id, .{fixtures.Velocity{ .dx = 3, .dy = 4 }});

    const loc = db.entities.get(entity_id).?;
    const table = &db.tables.items[loc.table_index];
    const pos = table.getComponentPtr(loc.row, fixtures.Position).?;
    try std.testing.expectEqual(@as(f32, 1), pos.x);
    try std.testing.expectEqual(@as(f32, 2), pos.y);
    const vel = table.getComponentPtr(loc.row, fixtures.Velocity).?;
    try std.testing.expectEqual(@as(f32, 3), vel.dx);
    try std.testing.expectEqual(@as(f32, 4), vel.dy);
}

test "Database removeComponents moves entity and removes components" {

    var db = init(std.testing.allocator);
    defer db.deinit();

    const entity_id = try db.createEntityWithId(1, .{
        fixtures.Position{ .x = 5, .y = 6 },
        fixtures.Velocity{ .dx = 7, .dy = 8 },
        fixtures.Health{ .hp = 9 },
    });

    try db.removeComponents(entity_id, .{fixtures.Velocity});

    const loc = db.entities.get(entity_id).?;
    const table = &db.tables.items[loc.table_index];
    const pos = table.getComponentPtr(loc.row, fixtures.Position).?;
    try std.testing.expectEqual(@as(f32, 5), pos.x);
    try std.testing.expectEqual(@as(f32, 6), pos.y);
    try std.testing.expect(table.getComponentPtr(loc.row, fixtures.Velocity) == null);
    const hp = table.getComponentPtr(loc.row, fixtures.Health).?;
    try std.testing.expectEqual(@as(i32, 9), hp.hp);
}

// Imports
const std = @import("std");
const Table = @import("table.zig").Table;
const Column = @import("column/Column.zig");
const Entity = @import("Entity.zig");
const meta = @import("meta.zig");
const fixtures = @import("common").fixtures;
const hooks_mod = @import("hooks.zig");
