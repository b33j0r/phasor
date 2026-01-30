pub inline fn resolveStructType(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .pointer => |p| resolveStructType(p.child),
        else => T,
    };
}

pub inline fn structHasField(comptime T: type, comptime field_name: []const u8) bool {
    const S = resolveStructType(T);
    const info = @typeInfo(S);
    if (info != .@"struct") return false;

    inline for (info.@"struct".fields) |f| {
        if (std.mem.eql(u8, f.name, field_name)) {
            return true;
        }
    }
    return false;
}

pub inline fn convertValue(comptime ToT: type, value: anytype) ToT {
    const FromT = @TypeOf(value);
    const to_info = @typeInfo(ToT);
    const from_info = @typeInfo(FromT);

    return switch (to_info) {
        .int, .comptime_int => switch (from_info) {
            .int, .comptime_int => @intCast(value),
            .float, .comptime_float => @intFromFloat(value),
            else => @compileError("Unsupported conversion to integer field"),
        },
        .float, .comptime_float => switch (from_info) {
            .int, .comptime_int => @floatFromInt(value),
            .float, .comptime_float => @floatCast(value),
            else => @compileError("Unsupported conversion to float field"),
        },
        else => @compileError("Unsupported destination field type in conversion"),
    };
}

// Imports
const std = @import("std");
