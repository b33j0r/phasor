test "import tests" {
    _ = RuntimeApp;
    _ = RuntimePlatformSettings;
    _ = WindowSettings;
    _ = WindowFlags;
}

pub const RuntimeApp = @import("entry.zig").RuntimeApp;
pub const RuntimePlatformSettings = @import("entry.zig").RuntimePlatformSettings;
pub const installDefaultModules = @import("entry.zig").installDefaultModules;
pub const installPlatformModules = @import("entry.zig").installPlatformModules;
pub const PlatformModuleSettings = @import("entry.zig").PlatformModuleSettings;
pub const WindowSettings = @import("entry.zig").WindowSettings;
pub const WindowFlags = @import("entry.zig").WindowFlags;
