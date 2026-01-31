pub const Deinit = struct {};

pub fn Group(comptime TraitT: type) type {
    return struct {
        pub const __group_trait__ = TraitT;
    };
}
