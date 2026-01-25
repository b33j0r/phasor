const std = @import("std");

pub const TypeId = u64;

pub fn typeId(comptime T: type) TypeId {
    const type_name = @typeName(T);
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(type_name);
    return hasher.final();
}

test "typeId produces consistent ids for the same type" {
    const id1 = typeId(i32);
    const id2 = typeId(i32);
    try std.testing.expect(id1 == id2);
}
