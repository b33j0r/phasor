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
    /// Pixel-perfect camera using window coordinates.
    /// Window coordinates are DPI-independent.
    /// The system automatically scales to fill the physical framebuffer.
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
