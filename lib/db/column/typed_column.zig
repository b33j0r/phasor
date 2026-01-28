/// Internal. A typed, owning column for a single component type `T`. Used by `Column`.
pub fn TypedColumn(comptime T: type) type {
    if (@sizeOf(T) == 0) return zst_impl.TypedColumnZst(T);
    return struct {
        allocator: std.mem.Allocator,
        type_id: meta.TypeId = meta.typeId(T),
        data: std.ArrayList(T) = .empty,

        const Self = @This();

        const has_deinit = switch (@typeInfo(T)) {
            .@"struct", .@"enum", .@"union", .@"opaque" => @hasDecl(T, "deinit"),
            else => false,
        };

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{ .allocator = allocator };
        }

        pub fn deinit(self: *Self) void {
            if (has_deinit) {
                for (self.data.items) |*item| item.deinit();
            }
            self.data.deinit(self.allocator);
            self.data = .empty;
        }

        pub fn len(self: *const Self) usize {
            return self.data.items.len;
        }

        pub fn ensureTotalCapacity(self: *Self, needed: usize) !void {
            try self.data.ensureTotalCapacity(self.allocator, needed);
        }

        pub fn items(self: *const Self) []T {
            return self.data.items;
        }

        pub fn itemsConst(self: *const Self) []const T {
            return self.data.items;
        }

        pub fn get(self: *Self, index: usize) ?*T {
            if (index >= self.data.items.len) return null;
            return &self.data.items[index];
        }

        pub fn getConst(self: *const Self, index: usize) ?*const T {
            if (index >= self.data.items.len) return null;
            return &self.data.items[index];
        }

        pub fn push(self: *Self, value: T) !void {
            try self.data.append(self.allocator, value);
        }

        /// Removes by swapping with the last element and returns the removed value.
        /// Does NOT call `deinit` on the removed value (caller owns it).
        pub fn swapRemoveTake(self: *Self, index: usize) ?T {
            if (index >= self.data.items.len) return null;
            return self.data.swapRemove(index);
        }

        /// Removes by swapping with the last element.
        /// Calls `deinit` on the removed value iff `T` has a `deinit` decl.
        pub fn swapRemoveDeinit(self: *Self, index: usize) bool {
            if (index >= self.data.items.len) return false;

            if (has_deinit) {
                var removed = self.data.swapRemove(index);
                removed.deinit();
                return true;
            }

            _ = self.data.swapRemove(index);
            return true;
        }
    };
}

test "TypedColumn push/get basics" {
    const Position = fixtures.Position;
    const C = TypedColumn(Position);
    var col = C.init(std.testing.allocator);
    defer col.deinit();

    try std.testing.expectEqual(@as(usize, 0), col.len());
    try std.testing.expect(col.get(0) == null);

    try col.push(.{ .x = 1, .y = 2 });
    try col.push(.{ .x = 3, .y = 4 });

    try std.testing.expectEqual(@as(usize, 2), col.len());
    try std.testing.expectEqual(@as(f32, 1), col.get(0).?.*.x);
    try std.testing.expectEqual(@as(f32, 4), col.get(1).?.*.y);
}

test "TypedColumn swapRemoveDeinit swaps and removes" {
    const Position = fixtures.Position;
    const C = TypedColumn(Position);
    var col = C.init(std.testing.allocator);
    defer col.deinit();

    try col.push(.{ .x = 1, .y = 1 });
    try col.push(.{ .x = 2, .y = 2 });
    try col.push(.{ .x = 3, .y = 3 });

    try std.testing.expect(col.swapRemoveDeinit(1));
    try std.testing.expectEqual(@as(usize, 2), col.len());
    try std.testing.expectEqual(@as(f32, 1), col.get(0).?.*.x);
    try std.testing.expectEqual(@as(f32, 3), col.get(1).?.*.x);
}

test "TypedColumn swapRemoveDeinit calls deinit when present" {
    var deinit_count: usize = 0;
    const R = fixtures.DeinitCounterForTests(16);

    const C = TypedColumn(R);
    var col = C.init(std.testing.allocator);
    errdefer col.deinit();

    try col.push(try R.init(std.testing.allocator, &deinit_count));
    try col.push(try R.init(std.testing.allocator, &deinit_count));

    try std.testing.expect(col.swapRemoveDeinit(0));
    try std.testing.expectEqual(@as(usize, 1), deinit_count);

    col.deinit();
    try std.testing.expectEqual(@as(usize, 2), deinit_count);
}

test "TypedColumn swapRemoveTake doesn't call deinit" {
    var deinit_count: usize = 0;
    const R = fixtures.DeinitCounterForTests(8);

    const C = TypedColumn(R);
    var col = C.init(std.testing.allocator);
    errdefer col.deinit();

    try col.push(try R.init(std.testing.allocator, &deinit_count));
    try col.push(try R.init(std.testing.allocator, &deinit_count));

    var removed = col.swapRemoveTake(0).?;
    try std.testing.expectEqual(@as(usize, 0), deinit_count);

    removed.deinit();
    try std.testing.expectEqual(@as(usize, 1), deinit_count);

    col.deinit();
    try std.testing.expectEqual(@as(usize, 2), deinit_count);
}

test "TypedColumn deinit calls deinit when present" {
    var deinit_count: usize = 0;

    const Component = fixtures.DeinitCounterForTests(8);
    const C = TypedColumn(Component);
    var col = C.init(std.testing.allocator);
    try col.push(try Component.init(std.testing.allocator, &deinit_count));
    try col.push(try Component.init(std.testing.allocator, &deinit_count));

    col.deinit();
    try std.testing.expectEqual(@as(usize, 2), deinit_count);
}

test "TypedColumn ZST basics" {
    const C = TypedColumn(fixtures.ShipIsOnFire);

    var col = C.init(std.testing.allocator);
    defer col.deinit();

    try std.testing.expectEqual(@as(usize, 0), col.len());
    try std.testing.expect(col.get(0) == null);

    try col.push(.{});
    try col.push(.{});
    try std.testing.expectEqual(@as(usize, 2), col.len());
    try std.testing.expect(col.get(1) != null);

    _ = col.swapRemoveTake(0).?;
    try std.testing.expectEqual(@as(usize, 1), col.len());
    try std.testing.expect(col.swapRemoveDeinit(0));
    try std.testing.expectEqual(@as(usize, 0), col.len());
}

// Imports
const std = @import("std");
const meta = @import("../meta.zig");
const fixtures = @import("fixtures.zig");
const zst_impl = @import("typed_column_zst.zig");
