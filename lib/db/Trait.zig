//! Trait metadata for grouped and marker components.
const std = @import("std");
const meta = @import("meta.zig");

id: meta.TypeId,
kind: Kind,

const Trait = @This();

pub const Kind = union(enum) {
    Marker,
    Grouped: struct {
        group_key: i32,
    },
};

pub fn maybeFrom(comptime ComponentT: anytype) ?Trait {
    if (!@hasDecl(ComponentT, "__trait__")) return null;

    const TraitT = ComponentT.__trait__;
    const trait_id = meta.typeId(TraitT);

    const trait_kind = switch (@typeInfo(TraitT)) {
        .@"struct" => blk: {
            if (@hasDecl(ComponentT, "__group_key__")) {
                break :blk Trait.Kind{ .Grouped = .{ .group_key = ComponentT.__group_key__ } };
            }
            if (@sizeOf(TraitT) == 0) {
                break :blk Trait.Kind.Marker;
            }
            @compileError("Trait struct layout must be zero-sized or grouped");
        },
        else => @compileError("Trait must be a struct"),
    };

    return Trait{
        .id = trait_id,
        .kind = trait_kind,
    };
}

test "Trait grouped" {
    const TraitN = struct {};
    const Component = struct {
        pub const __group_key__ = 42;
        pub const __trait__ = TraitN;
    };

    const trait = Trait.maybeFrom(Component).?;
    try std.testing.expect(trait.id == meta.typeId(TraitN));
    switch (trait.kind) {
        .Grouped => |grouped| try std.testing.expectEqual(@as(i32, 42), grouped.group_key),
        else => return error.Unexpected,
    }
}
