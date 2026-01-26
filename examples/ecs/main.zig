const std = @import("std");
const phasor = @import("phasor");

const App = phasor.ecs.App;

pub fn main(init: std.process.Init) u8 {
    var app = App.init();
    defer app.deinit();

    _ = init;

    app.run() catch |err| {
        switch (err) {
            error.NotImplemented => {
                std.debug.print("Error: Not Implemented\n", .{});
            }
        }
        return 1;
    };

    return 0;
}