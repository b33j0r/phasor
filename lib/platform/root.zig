test "import tests" {
    _ = App;
    _ = main;
    _ = exportWasm;
    _ = Options;
    _ = WindowSettings;
    _ = WindowFlags;
}

pub const App = @import("entry.zig").EntryPoint;
pub const main = @import("entry.zig").main;
pub const exportWasm = @import("entry.zig").exportWasm;
pub const installDefaultModules = @import("entry.zig").installDefaultModules;
pub const Options = @import("entry.zig").Options;
pub const WindowSettings = @import("entry.zig").WindowSettings;
pub const WindowFlags = @import("entry.zig").WindowFlags;
