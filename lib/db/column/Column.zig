//! Owning, type-erased column. It owns an underlying `TypedColumn(T)` for some `T`.
allocator: std.mem.Allocator,
column: *anyopaque,
type_id: meta.TypeId,
size: usize,
alignment: usize,
group_traits: []const traits.GroupTrait,
vtable: *const VTable,

const Self = @This();

pub const VTable = struct {
    destroy: *const fn (alloc: std.mem.Allocator, ptr: *anyopaque) void,
    create_empty: *const fn (alloc: std.mem.Allocator) anyerror!*anyopaque,
    len: *const fn (ptr: *const anyopaque) usize,
    ensure_total_capacity: *const fn (ptr: *anyopaque, needed: usize) anyerror!void,
    get_ptr: *const fn (ptr: *anyopaque, index: usize) ?*anyopaque,
    push_from_ptr: *const fn (ptr: *anyopaque, value_ptr: *const anyopaque) anyerror!void,
    push_default: *const fn (ptr: *anyopaque) anyerror!void,
    swap_remove_deinit: *const fn (ptr: *anyopaque, index: usize) bool,
    swap_remove_take: *const fn (ptr: *anyopaque, index: usize, out_ptr: *anyopaque) anyerror!bool,
};

pub fn init(comptime T: type, allocator: std.mem.Allocator) !Self {
    const C = typed_column.TypedColumn(T);
    const col_ptr = try allocator.create(C);
    col_ptr.* = C.init(allocator);

    const vt = struct {
        fn destroy(alloc: std.mem.Allocator, ptr: *anyopaque) void {
            const c: *C = @ptrCast(@alignCast(ptr));
            c.deinit();
            alloc.destroy(c);
        }

        fn createEmpty(alloc: std.mem.Allocator) !*anyopaque {
            const c_ptr = try alloc.create(C);
            c_ptr.* = C.init(alloc);
            return @ptrCast(c_ptr);
        }

        fn len(ptr: *const anyopaque) usize {
            const c: *const C = @ptrCast(@alignCast(ptr));
            return c.len();
        }

        fn ensureTotalCapacity(ptr: *anyopaque, needed: usize) !void {
            const c: *C = @ptrCast(@alignCast(ptr));
            try c.ensureTotalCapacity(needed);
        }

        fn getPtr(ptr: *anyopaque, index: usize) ?*anyopaque {
            const c: *C = @ptrCast(@alignCast(ptr));
            const p = c.get(index) orelse return null;
            return @ptrCast(p);
        }

        fn pushFromPtr(ptr: *anyopaque, value_ptr: *const anyopaque) !void {
            const c: *C = @ptrCast(@alignCast(ptr));
            if (@intFromPtr(value_ptr) % @alignOf(T) != 0) return error.MisalignedPointer;
            const vp: *const T = @ptrCast(@alignCast(value_ptr));
            try c.push(vp.*);
        }

        fn pushDefault(ptr: *anyopaque) !void {
            const c: *C = @ptrCast(@alignCast(ptr));
            const default_value = defaultValue(T) orelse return error.MissingDefault;
            try c.push(default_value);
        }

        fn swapRemoveDeinit(ptr: *anyopaque, index: usize) bool {
            const c: *C = @ptrCast(@alignCast(ptr));
            return c.swapRemoveDeinit(index);
        }

        fn swapRemoveTake(ptr: *anyopaque, index: usize, out_ptr: *anyopaque) !bool {
            const c: *C = @ptrCast(@alignCast(ptr));
            if (@intFromPtr(out_ptr) % @alignOf(T) != 0) return error.MisalignedPointer;

            const value = c.swapRemoveTake(index) orelse return false;
            const out_t: *T = @ptrCast(@alignCast(out_ptr));
            out_t.* = value;
            return true;
        }
    };

    return .{
        .allocator = allocator,
        .column = @ptrCast(col_ptr),
        .type_id = meta.typeId(T),
        .size = @sizeOf(T),
        .alignment = @alignOf(T),
        .group_traits = traits.groupTraits(T),
        .vtable = &.{
            .destroy = vt.destroy,
            .create_empty = vt.createEmpty,
            .len = vt.len,
            .ensure_total_capacity = vt.ensureTotalCapacity,
            .get_ptr = vt.getPtr,
            .push_from_ptr = vt.pushFromPtr,
            .push_default = vt.pushDefault,
            .swap_remove_deinit = vt.swapRemoveDeinit,
            .swap_remove_take = vt.swapRemoveTake,
        },
    };
}

pub fn deinit(self: *Self) void {
    self.vtable.destroy(self.allocator, self.column);
    // Benign-ish state (still UB if you call methods after deinit, but avoids propagating undefined).
    self.* = .{
        .allocator = self.allocator,
        .column = undefined,
        .type_id = 0,
        .size = 0,
        .alignment = 0,
        .group_traits = &.{},
        .vtable = undefined,
    };
}

pub fn cloneEmpty(self: *const Self, allocator: std.mem.Allocator) !Self {
    const col_ptr = try self.vtable.create_empty(allocator);
    return .{
        .allocator = allocator,
        .column = col_ptr,
        .type_id = self.type_id,
        .size = self.size,
        .alignment = self.alignment,
        .group_traits = self.group_traits,
        .vtable = self.vtable,
    };
}

pub fn len(self: *const Self) usize {
    return self.vtable.len(self.column);
}

pub fn ensureTotalCapacity(self: *Self, needed: usize) !void {
    try self.vtable.ensure_total_capacity(self.column, needed);
}

pub fn getPtr(self: *Self, index: usize) ?*anyopaque {
    return self.vtable.get_ptr(self.column, index);
}

pub fn pushFromPtr(self: *Self, value_ptr: *const anyopaque) !void {
    try self.vtable.push_from_ptr(self.column, value_ptr);
}

/// Appends a default-initialized value for the underlying type.
pub fn pushDefault(self: *Self) !void {
    try self.vtable.push_default(self.column);
}

fn defaultValue(comptime T: type) ?T {
    const info = @typeInfo(T);
    const can_have_decls = switch (info) {
        .@"struct", .@"enum", .@"union", .@"opaque" => true,
        else => false,
    };

    if (can_have_decls and @hasDecl(T, "default")) {
        return T.default;
    }
    if (can_have_decls and @hasDecl(T, "initDefault")) {
        if (@typeInfo(@TypeOf(T.initDefault)) == .@"fn") {
            return T.initDefault();
        }
    }
    if (@sizeOf(T) == 0) {
        return @as(T, .{});
    }
    if (info == .optional) {
        return null;
    }
    return null;
}

/// Safer, typed convenience for pushing.
pub fn pushAs(self: *Self, comptime T: type, value: T) !void {
    if (self.type_id != meta.typeId(T)) return error.TypeMismatch;
    try self.pushFromPtr(@ptrCast(&value));
}

pub fn getAs(self: *Self, comptime T: type, index: usize) ?*T {
    if (self.type_id != meta.typeId(T)) return null;
    const p = self.getPtr(index) orelse return null;
    return @ptrCast(@alignCast(p));
}

pub fn swapRemoveDeinit(self: *Self, index: usize) bool {
    return self.vtable.swap_remove_deinit(self.column, index);
}

/// Removes an element and writes it into `out_ptr` (must be aligned for the underlying type).
/// Does NOT call `deinit` on the removed value.
pub fn swapRemoveTake(self: *Self, index: usize, out_ptr: *anyopaque) !bool {
    return try self.vtable.swap_remove_take(self.column, index, out_ptr);
}

test "Column pushAs/getAs basics" {
    const Position = fixtures.Position;
    const Velocity = fixtures.Velocity;
    var col = try Self.init(Position, std.testing.allocator);
    defer col.deinit();

    try std.testing.expectEqual(meta.typeId(Position), col.type_id);
    try std.testing.expectEqual(@as(usize, @sizeOf(Position)), col.size);
    try std.testing.expectEqual(@as(usize, @alignOf(Position)), col.alignment);

    try col.pushAs(Position, .{ .x = 1, .y = 2 });
    try col.pushAs(Position, .{ .x = 3, .y = 4 });

    try std.testing.expectEqual(@as(usize, 2), col.len());
    try std.testing.expectEqual(@as(f32, 1), col.getAs(Position, 0).?.*.x);
    try std.testing.expectEqual(@as(f32, 4), col.getAs(Position, 1).?.*.y);

    try std.testing.expect(col.getAs(Velocity, 0) == null);
    try std.testing.expectError(error.TypeMismatch, col.pushAs(Velocity, .{ .dx = 0, .dy = 0 }));
}

test "Column pushFromPtr rejects misaligned pointer" {
    const Position = fixtures.Position;
    var col = try Self.init(Position, std.testing.allocator);
    defer col.deinit();

    var buf: [@sizeOf(Position) + 1]u8 = undefined;
    const misaligned_ptr: *const anyopaque = @ptrCast(buf[1..].ptr);
    try std.testing.expectError(error.MisalignedPointer, col.pushFromPtr(misaligned_ptr));
}

test "Column swapRemoveTake doesn't call deinit" {
    var deinit_count: usize = 0;
    const R = DeinitCounter(16);

    var col = try Self.init(R, std.testing.allocator);
    errdefer col.deinit();

    try col.pushAs(R, try R.init(std.testing.allocator, &deinit_count));
    try col.pushAs(R, try R.init(std.testing.allocator, &deinit_count));

    var out: R = undefined;
    try std.testing.expect(try col.swapRemoveTake(0, @ptrCast(&out)));
    try std.testing.expectEqual(@as(usize, 0), deinit_count);

    out.deinit();
    try std.testing.expectEqual(@as(usize, 1), deinit_count);

    col.deinit();
    try std.testing.expectEqual(@as(usize, 2), deinit_count);
}

test "Column swapRemoveTake rejects misaligned out_ptr" {
    const Position = fixtures.Position;
    var col = try Self.init(Position, std.testing.allocator);
    defer col.deinit();

    try col.pushAs(Position, .{ .x = 1, .y = 2 });

    var buf: [@sizeOf(Position) + 1]u8 = undefined;
    const misaligned_out: *anyopaque = @ptrCast(buf[1..].ptr);
    try std.testing.expectError(error.MisalignedPointer, col.swapRemoveTake(0, misaligned_out));
}

test "Column swapRemoveDeinit calls deinit when present" {
    var deinit_count: usize = 0;
    const R = DeinitCounter(16);

    var col = try Self.init(R, std.testing.allocator);
    errdefer col.deinit();

    try col.pushAs(R, try R.init(std.testing.allocator, &deinit_count));
    try col.pushAs(R, try R.init(std.testing.allocator, &deinit_count));

    try std.testing.expect(col.swapRemoveDeinit(0));
    try std.testing.expectEqual(@as(usize, 1), deinit_count);

    col.deinit();
    try std.testing.expectEqual(@as(usize, 2), deinit_count);
}

test "Column swapRemoveTake works with enum components" {
    const Component = fixtures.State;

    var col = try Self.init(Component, std.testing.allocator);
    defer col.deinit();

    try col.pushAs(Component, .idle);
    try col.pushAs(Component, .active);

    var out: Component = .paused;
    try std.testing.expect(try col.swapRemoveTake(0, @ptrCast(&out)));
    try std.testing.expect(out == .idle or out == .active);
    try std.testing.expectEqual(@as(usize, 1), col.len());
}

fn DeinitCounter(comptime N: usize) type {
    return struct {
        allocator: std.mem.Allocator,
        data: []u8,
        counter: *usize,

        pub const __traits__ = .{
            struct { pub const __trait__ = traits.Deinit; },
        };

        pub fn init(allocator: std.mem.Allocator, counter: *usize) !@This() {
            return .{
                .allocator = allocator,
                .data = try allocator.alloc(u8, N),
                .counter = counter,
            };
        }

        pub fn deinit(self: *@This()) void {
            self.allocator.free(self.data);
            self.counter.* += 1;
            self.* = undefined;
        }
    };
}

// Imports
const std = @import("std");
const meta = @import("../meta.zig");
const traits = @import("../Trait.zig");
const typed_column = @import("typed_column.zig");
const fixtures = @import("common").fixtures;
