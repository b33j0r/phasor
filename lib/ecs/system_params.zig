pub fn ResMut(comptime T: type) type {
    return struct {
        ptr: *T,

        pub fn init_system_param(self: *@This(), comptime _: anytype, commands: *Commands) !void {
            self.ptr = commands.getResourceMut(T).?;
        }

        pub fn deref(self: @This()) *T {
            return self.ptr;
        }
    };
}

pub fn Res(comptime T: type) type {
    return struct {
        ptr: *const T,

        pub fn init_system_param(self: *@This(), comptime _: anytype, commands: *Commands) !void {
            self.ptr = commands.getResource(T).?;
        }

        pub fn deref(self: @This()) *const T {
            return self.ptr;
        }
    };
}

pub fn ResOpt(comptime T: type) type {
    return struct {
        ptr: ?*const T,

        pub fn init_system_param(self: *@This(), comptime _: anytype, commands: *Commands) !void {
            self.ptr = commands.getResource(T);
        }

        pub fn deref(self: @This()) ?*const T {
            return self.ptr;
        }
    };
}

pub fn Query(comptime T: type) type {
    return struct {
        pub const spec = T;
    };
}

// Imports
const Commands = @import("Commands.zig").Commands;
