test "import tests" {
    _ = App;
    _ = main;
    _ = exportWasm;
    _ = Options;
    _ = WindowConfig;
    _ = WindowFlags;
}

pub const App = @import("entry.zig").EntryPoint;
pub const main = @import("entry.zig").main;
pub const exportWasm = @import("entry.zig").exportWasm;
pub const Options = @import("entry.zig").Options;
pub const WindowConfig = @import("entry.zig").WindowConfig;
pub const WindowFlags = @import("entry.zig").WindowFlags;
