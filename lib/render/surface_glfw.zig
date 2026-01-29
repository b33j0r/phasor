const std = @import("std");
const builtin = @import("builtin");
const glfw = @import("glfw").c;
const utils = @import("utils.zig");
const SurfaceTarget = utils.SurfaceTarget;
const NativeSurface = utils.NativeSurface;
const NativeHandle = utils.NativeHandle;
const NativeKind = utils.NativeKind;
const Size = utils.Size;

extern "c" fn glfwGetCocoaWindow(window: ?*anyopaque) ?*anyopaque;
extern "c" fn glfwGetWin32Window(window: ?*anyopaque) ?*anyopaque;
extern "c" fn glfwGetX11Display() ?*anyopaque;
extern "c" fn glfwGetX11Window(window: ?*anyopaque) u64;
extern "c" fn createMetalLayer(ns_window: ?*anyopaque) ?*anyopaque;

pub fn fromGlfwWindow(window: *glfw.GLFWwindow) !SurfaceTarget {
    var fb_w: i32 = 0;
    var fb_h: i32 = 0;
    glfw.glfwGetFramebufferSize(window, &fb_w, &fb_h);
    if (fb_w <= 0 or fb_h <= 0) return error.InvalidSurfaceSize;

    const size = Size{
        .width = @intCast(fb_w),
        .height = @intCast(fb_h),
    };

    if (builtin.os.tag == .macos) {
        // GLFW provides the NSWindow; we attach a CAMetalLayer for WebGPU.
        const ns_window = glfwGetCocoaWindow(@ptrCast(window)) orelse return error.GlfwNativeWindowError;
        const layer = createMetalLayer(ns_window) orelse return error.MetalLayerCreationFailed;
        return SurfaceTarget{
            .native = NativeSurface{
                .kind = .metal,
                .handle = NativeHandle{ .metal = .{ .layer = layer } },
                .size = size,
            },
        };
    }

    if (builtin.os.tag == .windows) {
        const hwnd = glfwGetWin32Window(@ptrCast(window)) orelse return error.GlfwNativeWindowError;
        const hinstance = std.os.windows.kernel32.GetModuleHandleW(null) orelse return error.GlfwNativeWindowError;
        return SurfaceTarget{
            .native = NativeSurface{
                .kind = .win32,
                .handle = NativeHandle{ .win32 = .{ .hwnd = hwnd, .hinstance = hinstance } },
                .size = size,
            },
        };
    }

    const display = glfwGetX11Display() orelse return error.GlfwNativeWindowError;
    const x_window = glfwGetX11Window(@ptrCast(window));
    return SurfaceTarget{
        .native = NativeSurface{
            .kind = .x11,
            .handle = NativeHandle{ .x11 = .{ .display = display, .window = x_window } },
            .size = size,
        },
    };
}
