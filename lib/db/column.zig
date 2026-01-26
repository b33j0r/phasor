const meta = @import("meta.zig");

pub fn Column(T: type) type {
    return struct {
        const Self = @This();

        pub const type_id: meta.TypeId = meta.typeId(T);
    };
}
