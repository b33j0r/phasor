pub fn main(init: std.process.Init) !u8 {
    const allocator = std.heap.c_allocator;

    var app = try EcsApp.init(allocator, &init.io);
    defer app.deinit();

    var commands = ecs.Commands.init(allocator, app.io, &app.world);
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

const EcsApp = ecs.App;
const WindowSettings = window.WindowSettings;
