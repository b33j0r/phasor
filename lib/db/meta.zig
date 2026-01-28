pub const TypeId = u64;

pub fn typeId(comptime T: type) TypeId {
    return comptime blk: {
        const type_name = @typeName(T);
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(type_name);
        break :blk hasher.final();
    };
}

/// Sorted, unique set of TypeId values, built entirely at comptime.
pub const TypeIdSet = struct {
    items: []const TypeId,

    const Self = @This();

    pub fn len(self: *const Self) usize {
        return self.items.len;
    }

    pub fn slice(self: *const Self) []const TypeId {
        return self.items;
    }

    pub fn eql(self: *const Self, other: *const Self) bool {
        return std.mem.eql(TypeId, self.items, other.items);
    }

    pub fn contains(self: *const Self, id: TypeId) bool {
        return binarySearch(self.items, id);
    }

    pub fn hasAll(self: *const Self, other: *const Self) bool {
        var i: usize = 0;
        var j: usize = 0;
        const a = self.items;
        const b = other.items;
        while (i < a.len and j < b.len) {
            if (a[i] == b[j]) {
                i += 1;
                j += 1;
            } else if (a[i] < b[j]) {
                i += 1;
            } else {
                return false;
            }
        }
        return j == b.len;
    }

    pub fn hasAny(self: *const Self, other: *const Self) bool {
        var i: usize = 0;
        var j: usize = 0;
        const a = self.items;
        const b = other.items;
        while (i < a.len and j < b.len) {
            if (a[i] == b[j]) return true;
            if (a[i] < b[j]) {
                i += 1;
            } else {
                j += 1;
            }
        }
        return false;
    }

    pub fn hash(self: *const Self) u64 {
        var hasher = std.hash.Wyhash.init(0);
        for (self.items) |id| {
            hasher.update(std.mem.asBytes(&id));
        }
        return hasher.final();
    }
};

/// Build a sorted, unique TypeIdSet at comptime.
pub fn typeIdSet(comptime Types: anytype) TypeIdSet {
    const HasValue = @TypeOf(Types) != type;
    const Tup = if (HasValue) @TypeOf(Types) else Types;
    const fields = std.meta.fields(Tup);

    const ids = comptime blk: {
        var tmp: [fields.len]TypeId = undefined;
        for (fields, 0..) |field, i| {
            const T = if (HasValue) blk2: {
                const value = @field(Types, field.name);
                break :blk2 if (@TypeOf(value) == type) value else @TypeOf(value);
            } else field.type;
            tmp[i] = typeId(T);
        }

        // Sort deterministically at comptime.
        std.sort.pdq(TypeId, &tmp, {}, std.sort.asc(TypeId));

        // Reject duplicate type ids.
        var idx: usize = 1;
        while (idx < tmp.len) : (idx += 1) {
            if (tmp[idx] == tmp[idx - 1]) {
                @compileError("typeIdSet contains duplicate TypeId values");
            }
        }

        break :blk tmp;
    };

    return .{ .items = &ids };
}

fn binarySearch(items: []const TypeId, target: TypeId) bool {
    var left: usize = 0;
    var right: usize = items.len;
    while (left < right) {
        const mid = left + (right - left) / 2;
        const value = items[mid];
        if (value == target) return true;
        if (value < target) {
            left = mid + 1;
        } else {
            right = mid;
        }
    }
    return false;
}

test "typeId produces consistent ids for the same type" {
    const id1 = typeId(fixtures.Position);
    const id2 = typeId(fixtures.Position);
    try std.testing.expect(id1 == id2);
}

test "typeId produces different ids for different types" {
    const id1 = typeId(fixtures.Position);
    const id2 = typeId(fixtures.Velocity);
    try std.testing.expect(id1 != id2);
}

test "typeIdSet sorts" {
    const set = typeIdSet(.{ fixtures.Position, fixtures.Velocity, fixtures.Health });
    const ids = set.slice();
    try std.testing.expect(ids.len == 3);
    try std.testing.expect(ids[0] < ids[1] and ids[1] < ids[2]);
}

test "typeIdSet matches same type set" {
    const set_a = typeIdSet(.{ fixtures.Position, fixtures.Velocity });
    const set_b = typeIdSet(struct { a: fixtures.Position, b: fixtures.Velocity });
    try std.testing.expect(set_a.eql(&set_b));
}

test "TypeIdSet contains/hasAll/hasAny" {
    const a = typeIdSet(.{ fixtures.Position, fixtures.Velocity, fixtures.Health });
    const b = typeIdSet(.{ fixtures.Velocity });
    const c = typeIdSet(.{ fixtures.Tag, fixtures.ShipIsOnFire });

    try std.testing.expect(a.contains(typeId(fixtures.Velocity)));
    try std.testing.expect(!a.contains(typeId(fixtures.Tag)));
    try std.testing.expect(a.hasAll(&b));
    try std.testing.expect(!a.hasAll(&c));
    try std.testing.expect(a.hasAny(&b));
    try std.testing.expect(!a.hasAny(&c));
}

test "TypeIdSet hash is stable for same items" {
    const a = typeIdSet(.{ fixtures.Position, fixtures.Velocity, fixtures.Health });
    const b = typeIdSet(.{ fixtures.Health, fixtures.Position, fixtures.Velocity });
    try std.testing.expect(a.hash() == b.hash());
}

// Imports
const std = @import("std");
const fixtures = @import("column/fixtures.zig");
