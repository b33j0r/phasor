const Self = @This();

pub const Mutator = struct {
    ptr: ?*anyopaque,
    vtable: VTable,

    pub const Error = error{
        OutOfMemory,
    };

    pub fn error_message(err: Error) []const u8 {
        return switch (err) {
            .OutOfMemory => "Out of memory",
        };
    }

    pub const VTable = struct {
        reserveEntity: *const fn (mutator: *Mutator) Error!Entity.Id,

        addComponents: *const fn (mutator: *Mutator, id: Entity.Id, components: []AddComponent) Error!void,
        removeComponents: *const fn (mutator: *Mutator, id: Entity.Id, type_ids: []phasor.db.meta.TypeId) Error!void,
        getComponent: *const fn (mutator: *Mutator, id: Entity.Id, type_id: phasor.db.meta.TypeId) ?[]const u8,

        insertResource: *const fn (mutator: *Mutator, type_id: phasor.db.meta.TypeId, data: []const u8) Error!void,
        removeResource: *const fn (mutator: *Mutator, type_id: phasor.db.meta.TypeId) Error!void,
        getResource: *const fn (mutator: *Mutator, type_id: phasor.db.meta.TypeId) ?[]const u8,

        pub const AddComponent = struct {
            type_id: phasor.db.meta.TypeId,
            data: []const u8,
        };
    };
};


pub fn init() Self {
    return Self{};
}

pub fn deinit(_: *Self) void {

}

// Imports
const std = @import("std");
const phasor = @import("../root.zig");
const Entity = phasor.db.Entity;
