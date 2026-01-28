//! A type-erased command that can be queued in Commands.
allocator: std.mem.Allocator,
ptr: *anyopaque,
vtable: VTable,

const Self = @This();

const VTable = struct {
    execute: *const fn (ctx: *anyopaque, world: *World) anyerror!void,
    cleanup: ?*const fn (ctx: *anyopaque, allocator: std.mem.Allocator) void,
    destroy: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator) void,
};

pub fn from(allocator: std.mem.Allocator, context: anytype) !Self {
    const T = @TypeOf(context);

    const vtable = VTable{
        .execute = struct {
            fn f(ctx: *anyopaque, world: *World) anyerror!void {
                const typed: *T = @ptrCast(@alignCast(ctx));
                try typed.execute(world);
            }
        }.f,
        .cleanup = if (@hasDecl(T, "cleanup"))
            &struct {
                fn f(ctx: *anyopaque, alloc: std.mem.Allocator) void {
                    const typed: *T = @ptrCast(@alignCast(ctx));
                    typed.cleanup(alloc);
                }
            }.f
        else
            null,
        .destroy = struct {
            fn f(ctx: *anyopaque, alloc: std.mem.Allocator) void {
                const typed: *T = @ptrCast(@alignCast(ctx));
                alloc.destroy(typed);
            }
        }.f,
    };

    const ctx_ptr = try allocator.create(T);
    ctx_ptr.* = context;

    return .{
        .allocator = allocator,
        .ptr = @ptrCast(ctx_ptr),
        .vtable = vtable,
    };
}

pub fn execute(self: *Self, world: *World) anyerror!void {
    try self.vtable.execute(self.ptr, world);
}

pub fn cleanup(self: *Self) void {
    if (self.vtable.cleanup) |cl| cl(self.ptr, self.allocator);
    self.vtable.destroy(self.ptr, self.allocator);
}

// Imports
const std = @import("std");
const World = @import("World.zig");
