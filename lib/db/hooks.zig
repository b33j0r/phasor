pub const TableHooks = struct {
    ctx: *anyopaque,
    vtable: VTable,

    pub const VTable = struct {
        on_row_added: ?*const fn (ctx: *anyopaque, table_index: usize, row: usize, entity_id: Entity.Id) void,
        on_row_removed: ?*const fn (ctx: *anyopaque, table_index: usize, row: usize, entity_id: Entity.Id) void,
        on_row_moved: ?*const fn (ctx: *anyopaque, table_index: usize, from_row: usize, to_row: usize, entity_id: Entity.Id) void,
    };

    pub fn none() TableHooks {
        return .{
            .ctx = undefined,
            .vtable = .{
                .on_row_added = null,
                .on_row_removed = null,
                .on_row_moved = null,
            },
        };
    }

    pub fn from(comptime T: type, ptr: *T) TableHooks {
        return .{
            .ctx = ptr,
            .vtable = .{
                .on_row_added = if (@hasDecl(T, "onRowAdded")) struct {
                    fn f(ctx: *anyopaque, table_index: usize, row: usize, entity_id: Entity.Id) void {
                        const typed: *T = @ptrCast(@alignCast(ctx));
                        typed.onRowAdded(table_index, row, entity_id);
                    }
                }.f else null,
                .on_row_removed = if (@hasDecl(T, "onRowRemoved")) struct {
                    fn f(ctx: *anyopaque, table_index: usize, row: usize, entity_id: Entity.Id) void {
                        const typed: *T = @ptrCast(@alignCast(ctx));
                        typed.onRowRemoved(table_index, row, entity_id);
                    }
                }.f else null,
                .on_row_moved = if (@hasDecl(T, "onRowMoved")) struct {
                    fn f(ctx: *anyopaque, table_index: usize, from_row: usize, to_row: usize, entity_id: Entity.Id) void {
                        const typed: *T = @ptrCast(@alignCast(ctx));
                        typed.onRowMoved(table_index, from_row, to_row, entity_id);
                    }
                }.f else null,
            },
        };
    }

    pub fn onRowAdded(self: *const TableHooks, table_index: usize, row: usize, entity_id: Entity.Id) void {
        if (self.vtable.on_row_added) |f| f(self.ctx, table_index, row, entity_id);
    }

    pub fn onRowRemoved(self: *const TableHooks, table_index: usize, row: usize, entity_id: Entity.Id) void {
        if (self.vtable.on_row_removed) |f| f(self.ctx, table_index, row, entity_id);
    }

    pub fn onRowMoved(self: *const TableHooks, table_index: usize, from_row: usize, to_row: usize, entity_id: Entity.Id) void {
        if (self.vtable.on_row_moved) |f| f(self.ctx, table_index, from_row, to_row, entity_id);
    }
};

pub const DatabaseHooks = struct {
    ctx: *anyopaque,
    vtable: VTable,

    pub const VTable = struct {
        on_entity_created: ?*const fn (ctx: *anyopaque, entity_id: Entity.Id, table_index: usize) void,
        on_entity_removed: ?*const fn (ctx: *anyopaque, entity_id: Entity.Id, table_index: usize) void,
        on_entity_moved: ?*const fn (ctx: *anyopaque, entity_id: Entity.Id, from_table: usize, to_table: usize) void,
        on_table_row_added: ?*const fn (ctx: *anyopaque, table_index: usize, row: usize, entity_id: Entity.Id) void,
        on_table_row_removed: ?*const fn (ctx: *anyopaque, table_index: usize, row: usize, entity_id: Entity.Id) void,
        on_table_row_moved: ?*const fn (ctx: *anyopaque, table_index: usize, from_row: usize, to_row: usize, entity_id: Entity.Id) void,
        on_resource_inserted: ?*const fn (ctx: *anyopaque, type_id: meta.TypeId) void,
        on_resource_removed: ?*const fn (ctx: *anyopaque, type_id: meta.TypeId) void,
    };

    pub fn none() DatabaseHooks {
        return .{
            .ctx = undefined,
            .vtable = .{
                .on_entity_created = null,
                .on_entity_removed = null,
                .on_entity_moved = null,
                .on_table_row_added = null,
                .on_table_row_removed = null,
                .on_table_row_moved = null,
                .on_resource_inserted = null,
                .on_resource_removed = null,
            },
        };
    }

    pub fn from(comptime T: type, ptr: *T) DatabaseHooks {
        return .{
            .ctx = ptr,
            .vtable = .{
                .on_entity_created = if (@hasDecl(T, "onEntityCreated")) struct {
                    fn f(ctx: *anyopaque, entity_id: Entity.Id, table_index: usize) void {
                        const typed: *T = @ptrCast(@alignCast(ctx));
                        typed.onEntityCreated(entity_id, table_index);
                    }
                }.f else null,
                .on_entity_removed = if (@hasDecl(T, "onEntityRemoved")) struct {
                    fn f(ctx: *anyopaque, entity_id: Entity.Id, table_index: usize) void {
                        const typed: *T = @ptrCast(@alignCast(ctx));
                        typed.onEntityRemoved(entity_id, table_index);
                    }
                }.f else null,
                .on_entity_moved = if (@hasDecl(T, "onEntityMoved")) struct {
                    fn f(ctx: *anyopaque, entity_id: Entity.Id, from_table: usize, to_table: usize) void {
                        const typed: *T = @ptrCast(@alignCast(ctx));
                        typed.onEntityMoved(entity_id, from_table, to_table);
                    }
                }.f else null,
                .on_table_row_added = if (@hasDecl(T, "onTableRowAdded")) struct {
                    fn f(ctx: *anyopaque, table_index: usize, row: usize, entity_id: Entity.Id) void {
                        const typed: *T = @ptrCast(@alignCast(ctx));
                        typed.onTableRowAdded(table_index, row, entity_id);
                    }
                }.f else null,
                .on_table_row_removed = if (@hasDecl(T, "onTableRowRemoved")) struct {
                    fn f(ctx: *anyopaque, table_index: usize, row: usize, entity_id: Entity.Id) void {
                        const typed: *T = @ptrCast(@alignCast(ctx));
                        typed.onTableRowRemoved(table_index, row, entity_id);
                    }
                }.f else null,
                .on_table_row_moved = if (@hasDecl(T, "onTableRowMoved")) struct {
                    fn f(ctx: *anyopaque, table_index: usize, from_row: usize, to_row: usize, entity_id: Entity.Id) void {
                        const typed: *T = @ptrCast(@alignCast(ctx));
                        typed.onTableRowMoved(table_index, from_row, to_row, entity_id);
                    }
                }.f else null,
                .on_resource_inserted = if (@hasDecl(T, "onResourceInserted")) struct {
                    fn f(ctx: *anyopaque, type_id: meta.TypeId) void {
                        const typed: *T = @ptrCast(@alignCast(ctx));
                        typed.onResourceInserted(type_id);
                    }
                }.f else null,
                .on_resource_removed = if (@hasDecl(T, "onResourceRemoved")) struct {
                    fn f(ctx: *anyopaque, type_id: meta.TypeId) void {
                        const typed: *T = @ptrCast(@alignCast(ctx));
                        typed.onResourceRemoved(type_id);
                    }
                }.f else null,
            },
        };
    }

    pub fn onEntityCreated(self: *const DatabaseHooks, entity_id: Entity.Id, table_index: usize) void {
        if (self.vtable.on_entity_created) |f| f(self.ctx, entity_id, table_index);
    }

    pub fn onEntityRemoved(self: *const DatabaseHooks, entity_id: Entity.Id, table_index: usize) void {
        if (self.vtable.on_entity_removed) |f| f(self.ctx, entity_id, table_index);
    }

    pub fn onEntityMoved(self: *const DatabaseHooks, entity_id: Entity.Id, from_table: usize, to_table: usize) void {
        if (self.vtable.on_entity_moved) |f| f(self.ctx, entity_id, from_table, to_table);
    }

    pub fn onTableRowAdded(self: *const DatabaseHooks, table_index: usize, row: usize, entity_id: Entity.Id) void {
        if (self.vtable.on_table_row_added) |f| f(self.ctx, table_index, row, entity_id);
    }

    pub fn onTableRowRemoved(self: *const DatabaseHooks, table_index: usize, row: usize, entity_id: Entity.Id) void {
        if (self.vtable.on_table_row_removed) |f| f(self.ctx, table_index, row, entity_id);
    }

    pub fn onTableRowMoved(self: *const DatabaseHooks, table_index: usize, from_row: usize, to_row: usize, entity_id: Entity.Id) void {
        if (self.vtable.on_table_row_moved) |f| f(self.ctx, table_index, from_row, to_row, entity_id);
    }

    pub fn onResourceInserted(self: *const DatabaseHooks, type_id: meta.TypeId) void {
        if (self.vtable.on_resource_inserted) |f| f(self.ctx, type_id);
    }

    pub fn onResourceRemoved(self: *const DatabaseHooks, type_id: meta.TypeId) void {
        if (self.vtable.on_resource_removed) |f| f(self.ctx, type_id);
    }
};

// Imports
const Entity = @import("Entity.zig");
const meta = @import("meta.zig");
