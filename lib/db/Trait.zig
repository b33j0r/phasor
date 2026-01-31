const std = @import("std");
const common = @import("common");
const meta = @import("meta.zig");

pub const Deinit = common.Deinit;
pub const Group = common.Group;

pub const GroupTrait = struct {
    trait_id: meta.TypeId,
    key: i32,
};

pub const TraitInfo = struct {
    group_traits: []const GroupTrait,
    has_deinit: bool,
};

pub fn info(comptime ComponentT: type) TraitInfo {
    if (!@hasDecl(ComponentT, "__traits__")) {
        return .{ .group_traits = &.{}, .has_deinit = false };
    }

    const traits_value = ComponentT.__traits__;
    const traits_type = if (@TypeOf(traits_value) == type) traits_value else @TypeOf(traits_value);
    const traits_info = @typeInfo(traits_type);
    if (traits_info != .@"struct" or !traits_info.@"struct".is_tuple) {
        @compileError("__traits__ must be a tuple of trait entry types");
    }

    const fields = std.meta.fields(traits_type);

    return comptime blk: {
        var tmp: [fields.len]GroupTrait = undefined;
        var count: usize = 0;
        var has_deinit = false;

        for (fields) |field| {
            const raw = @field(traits_value, field.name);
            const EntryT = if (@TypeOf(raw) == type) raw else @TypeOf(raw);
            if (!@hasDecl(EntryT, "__trait__")) {
                @compileError("Trait entry missing __trait__");
            }

            const TraitT = EntryT.__trait__;
            if (TraitT == Deinit) {
                has_deinit = true;
                continue;
            }

            if (@hasDecl(TraitT, "__group_trait__")) {
                if (!@hasDecl(EntryT, "key")) {
                    @compileError("Group trait entry missing key");
                }
                tmp[count] = .{
                    .trait_id = meta.typeId(TraitT.__group_trait__),
                    .key = EntryT.key,
                };
                count += 1;
            }
        }

        if (has_deinit) {
            const has_decl = switch (@typeInfo(ComponentT)) {
                .@"struct", .@"enum", .@"union", .@"opaque" => @hasDecl(ComponentT, "deinit"),
                else => false,
            };
            if (!has_decl) {
                @compileError("Deinit trait requires a deinit() declaration on " ++ @typeName(ComponentT));
            }
        }

        var i: usize = 0;
        while (i < count) : (i += 1) {
            var j: usize = i + 1;
            while (j < count) : (j += 1) {
                if (tmp[i].trait_id == tmp[j].trait_id) {
                    @compileError("Duplicate Group trait for " ++ @typeName(ComponentT));
                }
            }
        }

        const final: [count]GroupTrait = tmp[0..count].*;

        break :blk TraitInfo{
            .group_traits = &final,
            .has_deinit = has_deinit,
        };
    };
}

pub fn groupTraits(comptime ComponentT: type) []const GroupTrait {
    return info(ComponentT).group_traits;
}

pub fn hasDeinit(comptime ComponentT: type) bool {
    return info(ComponentT).has_deinit;
}

test "traits group parsing" {
    const LayerN = struct {};
    const Component = struct {
        pub const __traits__ = .{
            struct {
                pub const __trait__ = Group(LayerN);
                pub const key: i32 = 7;
            },
        };
    };

    const traits = info(Component);
    try std.testing.expectEqual(@as(usize, 1), traits.group_traits.len);
    try std.testing.expectEqual(meta.typeId(LayerN), traits.group_traits[0].trait_id);
    try std.testing.expectEqual(@as(i32, 7), traits.group_traits[0].key);
}

test "traits deinit marker" {
    const Component = struct {
        pub const __traits__ = .{struct { pub const __trait__ = Deinit; }};
        pub fn deinit(_: *@This()) void {}
    };

    try std.testing.expect(info(Component).has_deinit);
}
