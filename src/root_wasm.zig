test "import tests" {
    _ = common;
    _ = db;
    _ = ecs;
    _ = graph;
    _ = metrics;
    _ = modules;
    _ = platform;
    _ = renderer;
    _ = assets;
}

// Imports
pub const common = @import("common");
pub const db = @import("db");
pub const ecs = @import("ecs");
pub const graph = @import("graph");
pub const metrics = @import("metrics");
pub const modules = @import("modules");
pub const platform = @import("platform");
pub const renderer = @import("render");
pub const assets = @import("assets");
