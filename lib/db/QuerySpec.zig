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
    };
}

const ExtractedSets = struct {
    with: meta.TypeIdSet,
    without: meta.TypeIdSet,
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
            tmp[count] = meta.typeId(T.__without__);
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
    };
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
}

// Imports
const std = @import("std");
const meta = @import("meta.zig");
const fixtures = @import("common").fixtures;
