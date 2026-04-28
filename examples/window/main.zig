pub fn main(init: std.process.Init) !u8 {
    var app = try phasor.App.default(&init);
    defer app.deinit();

    var commands = app.commands();
    defer commands.deinit();

    try commands.insertResource(WindowSettings{
        .title = "Phasor Window",
    });
    if (!commands.isEmpty()) {
        try commands.apply();
    }

    try app.installModule(window.WindowModule);
    return try app.run();
}

// Imports
const std = @import("std");
const phasor = @import("phasor");
const ecs = phasor.ecs;
const window = phasor.window;

const WindowSettings = window.WindowSettings;
