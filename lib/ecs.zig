pub const App = @import("ecs/App.zig");
pub const World = @import("ecs/World.zig");
pub const schedule = @import("ecs/schedule.zig");
pub const system = @import("ecs/system.zig");

test "import tests" {
    _ = App;
    _ = World;
    _ = schedule;
    _ = system;
}
