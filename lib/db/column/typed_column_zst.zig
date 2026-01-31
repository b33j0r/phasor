/// ZST-specialized column. Stores only a count and returns a shared instance.
pub fn TypedColumnZst(comptime T: type) type {
    return struct {
        allocator: std.mem.Allocator,
        type_id: meta.TypeId = meta.typeId(T),
        len_count: usize = 0,

        const Self = @This();
        const zst_value: T = .{};
        const has_deinit = traits.hasDeinit(T);

        const has_init_default = switch (@typeInfo(T)) {
            .@"struct", .@"enum", .@"union", .@"opaque" => @hasDecl(T, "initDefault"),
            else => false,
        };

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{ .allocator = allocator };
        }

        pub fn deinit(self: *Self) void {
            if (has_deinit and !has_init_default) {
                @compileError("ZST with deinit must provide initDefault()");
            }
            if (has_deinit) {
                var i: usize = 0;
                while (i < self.len_count) : (i += 1) {
                    var value = T.initDefault();
                    value.deinit();
                }
            }
            self.* = undefined;
        }

        pub fn len(self: *const Self) usize {
            return self.len_count;
        }

        pub fn ensureTotalCapacity(_: *Self, _: usize) !void {}

        pub fn items(self: *const Self) []T {
            if (self.len_count == 0) return &[_]T{};
            return @as([*]T, @ptrCast(@constCast(&zst_value)))[0..self.len_count];
        }

        pub fn itemsConst(self: *const Self) []const T {
            if (self.len_count == 0) return &[_]T{};
            return @as([*]const T, @ptrCast(&zst_value))[0..self.len_count];
        }

        pub fn get(self: *Self, index: usize) ?*T {
            if (index >= self.len_count) return null;
            return @constCast(&zst_value);
        }

        pub fn getConst(self: *const Self, index: usize) ?*const T {
            if (index >= self.len_count) return null;
            return &zst_value;
        }

        pub fn push(self: *Self, _: T) !void {
            self.len_count += 1;
        }

        pub fn swapRemoveTake(self: *Self, index: usize) ?T {
            if (index >= self.len_count) return null;
            self.len_count -= 1;
            return .{};
        }

        pub fn swapRemoveDeinit(self: *Self, index: usize) bool {
            if (index >= self.len_count) return false;
            if (has_deinit and !has_init_default) {
                @compileError("ZST with deinit must provide initDefault()");
            }
            if (has_deinit) {
                var value = T.initDefault();
                value.deinit();
            }
            self.len_count -= 1;
            return true;
        }
    };
}

test "TypedColumnZst basic ops" {
    const C = TypedColumnZst(fixtures.ShipIsOnFire);

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

test "TypedColumnZst deinit calls deinit when present" {
    const Counter = struct {
        var value: usize = 0;
    };
    const Zst = struct {
        pub const __traits__ = .{
            struct { pub const __trait__ = traits.Deinit; },
        };

        pub fn initDefault() @This() {
            return .{};
        }

        pub fn deinit(_: *@This()) void {
            Counter.value += 1;
        }
    };
    const C = TypedColumnZst(Zst);

    Counter.value = 0;
    var col = C.init(std.testing.allocator);
    try col.push(.{});
    try col.push(.{});

    col.deinit();
    try std.testing.expectEqual(@as(usize, 2), Counter.value);
}

// Imports
const std = @import("std");
const meta = @import("../meta.zig");
const fixtures = @import("common").fixtures;
const traits = @import("../Trait.zig");
