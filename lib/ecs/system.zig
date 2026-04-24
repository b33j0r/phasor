pub const System = struct {
    run: *const fn (commands: *Commands) anyerror!void,
    register: *const fn (world: *World) anyerror!void,
    unregister: *const fn (world: *World) anyerror!void,
    access: system_access.AccessDescriptor,

    pub fn from(comptime system_fn: anytype) !System {
        const fn_type = @TypeOf(system_fn);
        const type_info = @typeInfo(fn_type);
        if (type_info != .@"fn") return error.InvalidSystemFunction;

        const registerFn = &struct {
            pub fn register(world: *World) !void {
                const ArgsTupleType = std.meta.ArgsTuple(@TypeOf(system_fn));
                inline for (std.meta.fields(ArgsTupleType)) |field| {
                    const ParamType = field.type;
                    const param_type_info = @typeInfo(ParamType);
                    if (param_type_info == .@"struct" or param_type_info == .@"union" or param_type_info == .@"enum") {
                        if (@hasDecl(ParamType, "register_system_param")) {
                            try ParamType.register_system_param(system_fn, world);
                        }
                    }
                }
            }
        }.register;

        const runFn = &struct {
            pub fn run(commands: *Commands) !void {
                const ArgsTupleType = std.meta.ArgsTuple(@TypeOf(system_fn));
                var args_tuple: ArgsTupleType = undefined;

                inline for (std.meta.fields(ArgsTupleType), 0..) |field, i| {
                    const ParamType = field.type;

                    if (ParamType == *Commands) {
                        args_tuple[i] = commands;
                    } else if (@hasDecl(ParamType, "init_system_param")) {
                        var param_instance: ParamType = undefined;
                        try param_instance.init_system_param(system_fn, commands);
                        args_tuple[i] = param_instance;
                    } else {
                        @compileError("Unsupported system parameter type: " ++ @typeName(ParamType));
                    }
                }

                defer {
                    inline for (std.meta.fields(ArgsTupleType), 0..) |field, i| {
                        const ParamType = field.type;
                        if (ParamType != *Commands and @hasDecl(ParamType, "deinit")) {
                            (&args_tuple[i]).deinit();
                        }
                    }
                }

                return @call(.auto, system_fn, args_tuple);
            }
        }.run;

        const unregisterFn = &struct {
            pub fn unregister(world: *World) !void {
                const ArgsTupleType = std.meta.ArgsTuple(@TypeOf(system_fn));
                inline for (std.meta.fields(ArgsTupleType)) |field| {
                    const ParamType = field.type;
                    const param_type_info = @typeInfo(ParamType);
                    if (param_type_info == .@"struct" or param_type_info == .@"union" or param_type_info == .@"enum") {
                        if (@hasDecl(ParamType, "unregister_system_param")) {
                            try ParamType.unregister_system_param(system_fn, world);
                        }
                    }
                }
            }
        }.unregister;

        return .{
            .run = runFn,
            .register = registerFn,
            .unregister = unregisterFn,
            .access = comptime system_access.analyzeAccess(system_fn),
        };
    }
};

// Imports
const std = @import("std");
const system_access = @import("system_access.zig");
const Commands = @import("Commands.zig");
const World = @import("World.zig");
