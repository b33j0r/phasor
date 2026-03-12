pub fn Without(comptime ComponentT: type) type {
    return struct {
        pub const __without__ = ComponentT;
    };
}

pub fn Spec(comptime Parts: anytype) type {
    const sets = extractTypeIdSets(Parts);
    return struct {
        pub const with = sets.with;
        pub const without = sets.without;
        pub const without_group_traits = sets.without_group_traits;
    };
}

const ExtractedSets = struct {
    with: meta.TypeIdSet,
    without: meta.TypeIdSet,
    without_group_traits: meta.TypeIdSet,
};

fn extractTypeIdSets(comptime Parts: anytype) ExtractedSets {
    const HasValue = @TypeOf(Parts) != type;
    const Tup = if (HasValue) @TypeOf(Parts) else Parts;
    const fields = std.meta.fields(Tup);

    const with_ids = comptime blk: {
        var tmp: [fields.len]meta.TypeId = undefined;
        var count: usize = 0;
        for (fields) |field| {
            const raw = if (HasValue) @field(Parts, field.name) else field.type;
            const T = if (@TypeOf(raw) == type) raw else @TypeOf(raw);
            if (@hasDecl(T, "__without__")) continue;
            tmp[count] = meta.typeId(T);
            count += 1;
        }

        if (count == 0) break :blk [_]meta.TypeId{};
        var slice = tmp[0..count];
        std.sort.pdq(meta.TypeId, slice, {}, std.sort.asc(meta.TypeId));

        var i: usize = 1;
        while (i < slice.len) : (i += 1) {
            if (slice[i] == slice[i - 1]) {
                @compileError("QuerySpec includes duplicate component types");
            }
        }

        var final: [count]meta.TypeId = undefined;
        for (slice, 0..) |id, idx| {
            final[idx] = id;
        }
        break :blk final;
    };

    const without_ids = comptime blk: {
        var tmp: [fields.len]meta.TypeId = undefined;
        var count: usize = 0;
        for (fields) |field| {
            const raw = if (HasValue) @field(Parts, field.name) else field.type;
            const T = if (@TypeOf(raw) == type) raw else @TypeOf(raw);
            if (!@hasDecl(T, "__without__")) continue;
            const filter_type = T.__without__;
            if (groupTraitFilterTypeId(filter_type)) |_| continue;
            tmp[count] = meta.typeId(filter_type);
            count += 1;
        }

        if (count == 0) break :blk [_]meta.TypeId{};
        var slice = tmp[0..count];
        std.sort.pdq(meta.TypeId, slice, {}, std.sort.asc(meta.TypeId));

        var i: usize = 1;
        while (i < slice.len) : (i += 1) {
            if (slice[i] == slice[i - 1]) {
                @compileError("QuerySpec includes duplicate Without components");
            }
        }

        var final: [count]meta.TypeId = undefined;
        for (slice, 0..) |id, idx| {
            final[idx] = id;
        }
        break :blk final;
    };

    const without_group_trait_ids = comptime blk: {
        var tmp: [fields.len]meta.TypeId = undefined;
        var count: usize = 0;
        for (fields) |field| {
            const raw = if (HasValue) @field(Parts, field.name) else field.type;
            const T = if (@TypeOf(raw) == type) raw else @TypeOf(raw);
            if (!@hasDecl(T, "__without__")) continue;
            const filter_type = T.__without__;
            const trait_id = groupTraitFilterTypeId(filter_type) orelse continue;
            tmp[count] = trait_id;
            count += 1;
        }

        if (count == 0) break :blk [_]meta.TypeId{};
        var slice = tmp[0..count];
        std.sort.pdq(meta.TypeId, slice, {}, std.sort.asc(meta.TypeId));

        var i: usize = 1;
        while (i < slice.len) : (i += 1) {
            if (slice[i] == slice[i - 1]) {
                @compileError("QuerySpec includes duplicate Without group traits");
            }
        }

        var final: [count]meta.TypeId = undefined;
        for (slice, 0..) |id, idx| {
            final[idx] = id;
        }
        break :blk final;
    };

    comptime {
        var i: usize = 0;
        var j: usize = 0;
        while (i < with_ids.len and j < without_ids.len) {
            if (with_ids[i] == without_ids[j]) {
                @compileError("QuerySpec component appears in both with and without");
            }
            if (with_ids[i] < without_ids[j]) {
                i += 1;
            } else {
                j += 1;
            }
        }
    }

    return .{
        .with = .{ .items = &with_ids },
        .without = .{ .items = &without_ids },
        .without_group_traits = .{ .items = &without_group_trait_ids },
    };
}

fn groupTraitFilterTypeId(comptime T: type) ?meta.TypeId {
    const info = @typeInfo(T);
    const can_have_decls = switch (info) {
        .@"struct", .@"enum", .@"union", .@"opaque" => true,
        else => false,
    };
    if (!can_have_decls) return null;
    if (!@hasDecl(T, "__query_group_trait__")) return null;
    if (@TypeOf(T.__query_group_trait__) != bool or !T.__query_group_trait__) {
        @compileError(@typeName(T) ++ ".__query_group_trait__ must be bool = true");
    }
    return meta.typeId(T);
}

test "QuerySpec builds with/without sets" {
    const SpecType = Spec(.{
        fixtures.Position,
        fixtures.Velocity,
        Without(fixtures.Health),
    });

    try std.testing.expect(SpecType.with.contains(meta.typeId(fixtures.Position)));
    try std.testing.expect(SpecType.with.contains(meta.typeId(fixtures.Velocity)));
    try std.testing.expect(!SpecType.with.contains(meta.typeId(fixtures.Health)));
    try std.testing.expect(SpecType.without.contains(meta.typeId(fixtures.Health)));
    try std.testing.expect(!SpecType.without.contains(meta.typeId(fixtures.Tag)));

    const SpecType2 = Spec(.{fixtures.Position});
    try std.testing.expect(SpecType2.without.items.len == 0);
    try std.testing.expect(SpecType2.without_group_traits.items.len == 0);
}

test "QuerySpec routes Without group trait markers separately" {
    const LayerMarker = struct {
        pub const __query_group_trait__ = true;
    };

    const SpecType = Spec(.{
        fixtures.Position,
        Without(LayerMarker),
    });

    try std.testing.expect(SpecType.with.contains(meta.typeId(fixtures.Position)));
    try std.testing.expectEqual(@as(usize, 0), SpecType.without.items.len);
    try std.testing.expectEqual(@as(usize, 1), SpecType.without_group_traits.items.len);
    try std.testing.expectEqual(meta.typeId(LayerMarker), SpecType.without_group_traits.items[0]);
}

// Imports
const std = @import("std");
const meta = @import("meta.zig");
const fixtures = @import("common").fixtures;
