const std = @import("std");

pub const TypeId = u64;
pub const TypeIdSet = []const u64;

pub fn typeId(comptime T: type) TypeId {
    return comptime blk: {
        const type_name = @typeName(T);
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(type_name);
        break :blk hasher.final();
    };
}

test "typeId produces consistent ids for the same type" {
    const id1 = typeId(i32);
    const id2 = typeId(i32);
    try std.testing.expect(id1 == id2);
}

test "typeId produces different ids for different types" {
    const id1 = typeId(i32);
    const id2 = typeId(u32);
    try std.testing.expect(id1 != id2);
}
