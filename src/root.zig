const std = @import("std");
pub const std_options = @import("common").logging.moduleStdOptions();

test "import tests" {
    _ = common;
    _ = db;
    _ = ecs;
    _ = graph;
    _ = metrics;
    _ = physics;
    _ = lighting;
    _ = modules;
    _ = platform;
    _ = renderer;
    _ = gui;
    _ = assets;
    _ = audio;
    _ = window;
}

// Imports
pub const common = @import("common");
pub const db = @import("db");
pub const ecs = @import("ecs");
pub const graph = @import("graph");
pub const metrics = @import("metrics");
pub const physics = @import("physics");
pub const lighting = @import("lighting");
pub const modules = @import("modules");
pub const platform = @import("platform");
pub const renderer = @import("render");
pub const gui = @import("gui");
pub const assets = @import("assets");
pub const audio = @import("audio");
pub const window = @import("window");

pub const Sound = assets.Sound;
pub const SoundPlayer = audio.SoundPlayer;
