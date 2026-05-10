test "import tests" {
    _ = fixtures;
    _ = vec;
    _ = mat4;
    _ = quat;
    _ = channel;
    _ = agent;
    _ = logging;
    _ = camera;
    _ = layout;
    _ = transform;
    _ = parent;
    _ = traits;
    _ = gradient;
    _ = Color;
}

// Imports
pub const fixtures = @import("fixtures.zig");
pub const vec = @import("vec.zig");
pub const mat4 = @import("mat4.zig");
pub const quat = @import("quat.zig");
pub const channel = @import("channel.zig");
pub const agent = @import("agent.zig");
pub const logging = @import("logging.zig");
pub const camera = @import("camera.zig");
pub const layout = @import("layout.zig");
pub const transform = @import("transform.zig");
pub const parent = @import("parent.zig");
pub const traits = @import("traits.zig");
pub const gradient = @import("gradient.zig");
pub const Color = @import("Color.zig");
pub const Gradient = gradient;
pub const ComptimeGradient = gradient.ComptimeGradient;

pub const Vec2 = vec.Vec2;
pub const Vec3 = vec.Vec3;
pub const Mat4 = mat4.Mat4;
pub const Quat = quat.Quat;
pub const Channel = channel.Channel;
pub const Broadcast = channel.Broadcast;
pub const Agent = agent.Agent;
pub const Camera3d = camera.Camera3d;
pub const ViewportLayout = layout.ViewportLayout;
pub const LayoutValue = layout.LayoutValue;
pub const Transform = transform.Transform;
pub const Parent = parent.Parent;
pub const LocalTransform = parent.LocalTransform;
pub const Deinit = traits.Deinit;
pub const Group = traits.Group;
pub const Paused = struct {};

pub const ClearColor = struct {
    color: Color = Color.BSOD,
};

pub const WindowFlags = struct {
    pub const Resizable: u32 = 1 << 0;
    pub const HighDPI: u32 = 1 << 1;
};

pub const WindowSettings = struct {
    width: u32 = 800,
    height: u32 = 450,
    title: []const u8 = "Phasor",
    flags: u32 = WindowFlags.Resizable | WindowFlags.HighDPI,
};

pub const RenderBounds = struct {
    width: f32,
    height: f32,

    pub fn widthInt(self: RenderBounds) i32 {
        return @intFromFloat(self.width);
    }

    pub fn heightInt(self: RenderBounds) i32 {
        return @intFromFloat(self.height);
    }
};

pub const WindowBounds = struct {
    width: u32,
    height: u32,
};

pub const ContentScale = struct {
    x: f32,
    y: f32,
};

pub const WindowResized = struct {
    width: u32,
    height: u32,
    framebuffer_width: u32,
    framebuffer_height: u32,
};

pub const ContentScaleChanged = struct {
    x: f32,
    y: f32,
};
