const std = @import("std");

pub const Camera3d = union(enum) {
    /// An orthographic camera with traditional left/right/top/bottom bounds.
    Orthographic: struct {
        left: f32 = -1.0,
        right: f32 = 1.0,
        bottom: f32 = -1.0,
        top: f32 = 1.0,
        near: f32 = 0.1,
        far: f32 = 100.0,
        zoom: f32 = 1.0,
    },
    /// A perspective camera.
    Perspective: struct {
        /// Field of view in radians.
        fov: f32 = std.math.pi / 4.0,
        near: f32 = 0.1,
        far: f32 = 100.0,
        zoom: f32 = 1.0,
    },
    /// Pixel-perfect camera using logical window coordinates.
    /// Coordinates are DPI-independent: a point at (640, 360) stays centered in a 1280x720 window
    /// even when the physical framebuffer is larger on a HiDPI display.
    /// The renderer scales these logical coordinates into the physical framebuffer automatically.
    Viewport: struct {
        mode: enum {
            /// Top-left is (0,0), y increases downwards.
            TopLeft,
            /// Center is (0,0), y increases upwards.
            Center,
        } = .TopLeft,
        near: f32 = -10.0,
        far: f32 = 10.0,
        zoom: f32 = 1.0,
    },
};
