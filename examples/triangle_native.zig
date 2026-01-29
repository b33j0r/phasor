const std = @import("std");
const phasor = @import("phasor");
const glfw = @import("glfw").c;

const renderer = phasor.renderer;

pub fn main() !void {
    if (glfw.glfwInit() == 0) return error.GlfwInitFailed;
    defer glfw.glfwTerminate();

    glfw.glfwWindowHint(glfw.GLFW_CLIENT_API, glfw.GLFW_NO_API);
    const window = glfw.glfwCreateWindow(800, 600, "Phasor Lite - Triangle", null, null) orelse {
        return error.WindowCreateFailed;
    };
    defer glfw.glfwDestroyWindow(window);

    const target = try renderer.surface_glfw.fromGlfwWindow(window);
    var gfx = try renderer.Renderer.init(std.heap.c_allocator, target, .{
        .present_mode = .fifo,
        .enable_validation = false,
    });
    defer gfx.deinit();

    while (glfw.glfwWindowShouldClose(window) == 0) {
        glfw.glfwPollEvents();

        var fb_w: i32 = 0;
        var fb_h: i32 = 0;
        glfw.glfwGetFramebufferSize(window, &fb_w, &fb_h);
        if (fb_w > 0 and fb_h > 0) {
            gfx.resize(@intCast(fb_w), @intCast(fb_h));
        }

        var frame = try gfx.beginFrame(.{ .r = 0.08, .g = 0.1, .b = 0.12, .a = 1.0 });
        frame.draw(.{ .triangle = .{
            .vertices = .{
                .{ .position = .{ 0.0, 0.6 }, .color = .{ 1.0, 0.2, 0.2 } },
                .{ .position = .{ -0.6, -0.6 }, .color = .{ 0.2, 1.0, 0.2 } },
                .{ .position = .{ 0.6, -0.6 }, .color = .{ 0.2, 0.4, 1.0 } },
            },
        } });
        try frame.endFrame();
    }
}
