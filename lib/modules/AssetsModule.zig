pub fn AssetsModule(comptime T: type) type {
    return struct {
        const Self = @This();

        pub fn install(app: *AppCommands, commands: *Commands) !void {
            if (!commands.hasResource(T)) {
                try commands.insertResource(T{});
            }
            try app.addSystem(schedule.DefaultSchedule.BeforeFrame, Self.loadAssets);
            try app.addSystem(schedule.DefaultSchedule.Shutdown, Self.unloadAssets);
        }

        pub fn uninstall(app: *AppCommands) void {
            app.removeSystem(Self.loadAssets);
            app.removeSystem(Self.unloadAssets);
        }

        fn loadAssets(assets: ResMut(T), assets_ctx: ResOpt(assets_mod.AssetsContext)) !void {
            const ctx_res = assets_ctx.ptr orelse return;
            const ctx = ctx_res.*;
            inline for (std.meta.fields(T)) |field| {
                const asset = &@field(assets.ptr, field.name);
                try asset.load(ctx);
            }
        }

        fn unloadAssets(assets: ResMut(T), assets_ctx: ResOpt(assets_mod.AssetsContext)) !void {
            const ctx_res = assets_ctx.ptr orelse return;
            const ctx = ctx_res.*;
            inline for (std.meta.fields(T)) |field| {
                const asset = &@field(assets.ptr, field.name);
                try asset.unload(ctx);
            }
        }
    };
}

// Imports
const std = @import("std");
const ecs = @import("ecs");
const assets_mod = @import("assets");
const AppCommands = ecs.AppCommands;
const Commands = ecs.Commands;
const schedule = ecs.schedule;
const ResMut = ecs.system_params.ResMut;
const ResOpt = ecs.system_params.ResOpt;
