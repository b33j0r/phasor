pub const ResourceEntry = struct {
    ptr: *anyopaque,
    deinit_fn: ?*const fn (allocator: std.mem.Allocator, ptr: *anyopaque) void,
};

pub const Exit = struct {
    code: u8 = 0,
};

pub fn resourceEntry(comptime T: type, allocator: std.mem.Allocator, value: T) !ResourceEntry {
    const p = try allocator.create(T);
    p.* = value;

    const can_have_decls = switch (@typeInfo(T)) {
        .@"struct", .@"enum", .@"union", .@"opaque" => true,
        else => false,
    };

    const deinit_fn = if (can_have_decls and @hasDecl(T, "deinit")) struct {
        fn call(a: std.mem.Allocator, ptr: *anyopaque) void {
            const typed: *T = @ptrCast(@alignCast(ptr));
            typed.deinit();
            a.destroy(typed);
        }
    }.call else struct {
        fn call(a: std.mem.Allocator, ptr: *anyopaque) void {
            const typed: *T = @ptrCast(@alignCast(ptr));
            a.destroy(typed);
        }
    }.call;

    return .{ .ptr = p, .deinit_fn = deinit_fn };
}

pub fn resourceTypeId(comptime T: type) meta.TypeId {
    return meta.typeId(T);
}

// Imports
const std = @import("std");
const meta = @import("db").meta;
