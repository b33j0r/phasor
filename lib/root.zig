pub const db = @import("db.zig");
pub const ecs = @import("ecs.zig");

test "import tests" {
    _ = db;
    _ = ecs;
}
