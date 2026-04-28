test "import tests" {
    _ = EntryPoint;
    _ = main;
    _ = exportWasm;
    _ = exportWasmWith;
    _ = RuntimeBuilder;
    _ = RuntimeApp;
    _ = RuntimePlatformSettings;
    _ = Options;
    _ = WindowSettings;
    _ = WindowFlags;
}

pub const EntryPoint = @import("entry.zig").EntryPoint;
pub const main = @import("entry.zig").main;
pub const exportWasm = @import("entry.zig").exportWasm;
pub const exportWasmWith = @import("entry.zig").exportWasmWith;
pub const RuntimeBuilder = @import("entry.zig").RuntimeBuilder;
pub const RuntimeApp = @import("entry.zig").RuntimeApp;
pub const RuntimePlatformSettings = @import("entry.zig").RuntimePlatformSettings;
pub const installDefaultModules = @import("entry.zig").installDefaultModules;
pub const installPlatformModules = @import("entry.zig").installPlatformModules;
pub const PlatformModuleSettings = @import("entry.zig").PlatformModuleSettings;
pub const Options = @import("entry.zig").Options;
pub const WindowSettings = @import("entry.zig").WindowSettings;
pub const WindowFlags = @import("entry.zig").WindowFlags;
