pub const CommandBatch = Commands.CommandBatch;

test "import tests" {
    _ = App;
    _ = AppCommands;
    _ = Commands;
    _ = Command;
    _ = World;
    _ = schedule;
    _ = system;
    _ = system_params;
    _ = Module;
    _ = resources;
}

// Imports
pub const App = @import("ecs/App.zig");
pub const AppCommands = @import("ecs/AppCommands.zig").AppCommands;
pub const Command = @import("ecs/Command.zig");
pub const Commands = @import("ecs/Commands.zig");
pub const World = @import("ecs/World.zig");
pub const schedule = @import("ecs/schedule.zig");
pub const system = @import("ecs/system.zig");
pub const system_params = @import("ecs/system_params.zig");
pub const Module = @import("ecs/Module.zig");
pub const resources = @import("ecs/resources.zig");
