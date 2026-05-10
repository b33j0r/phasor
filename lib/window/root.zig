//! Window module built on GLFW.

pub const std_options = @import("common").logging.moduleStdOptions();

test "import tests" {
    _ = WindowModule;
}

pub const WindowFlags = common.WindowFlags;
pub const WindowSettings = common.WindowSettings;

pub const Window = struct {
    handle: ?*glfw.GLFWwindow = null,
    title: []const u8,
    flags: u32,
};

pub const WindowBounds = common.WindowBounds;
pub const RenderBounds = common.RenderBounds;
pub const ContentScale = common.ContentScale;
pub const WindowResized = common.WindowResized;
pub const ContentScaleChanged = common.ContentScaleChanged;

pub const WindowModule = struct {
    pub fn install(app: *AppCommands, cmds: *Commands) !void {
        try cmds.registerEvent(WindowResized, 8);
        try cmds.registerEvent(ContentScaleChanged, 8);

        if (!cmds.hasResource(WindowSettings)) {
            try cmds.insertResource(WindowSettings{});
        }

        try app.addSystem(schedule.DefaultSchedule.WindowCreate, initSystem);
        try app.addSystem("BeforeFrame", updateSystem);
        try app.addSystem(schedule.DefaultSchedule.WindowDestroy, shutdownSystem);
    }

    pub fn uninstall(app: *AppCommands) void {
        app.removeSystem(initSystem);
        app.removeSystem(updateSystem);
        app.removeSystem(shutdownSystem);
    }
};

fn initSystem(commands: *Commands, settings_opt: ResOpt(WindowSettings)) !void {
    const settings = if (settings_opt.ptr) |s| s.* else WindowSettings{};

    if (glfw.glfwInit() == 0) return error.InitFailed;
    glfw.glfwWindowHint(glfw.GLFW_CLIENT_API, glfw.GLFW_NO_API);
    if ((settings.flags & WindowFlags.Resizable) != 0) {
        glfw.glfwWindowHint(glfw.GLFW_RESIZABLE, 1);
    } else {
        glfw.glfwWindowHint(glfw.GLFW_RESIZABLE, 0);
    }

    const window = glfw.glfwCreateWindow(
        @intCast(settings.width),
        @intCast(settings.height),
        settings.title.ptr,
        null,
        null,
    );
    if (window == null) return error.CreateFailed;

    var window_w: i32 = 0;
    var window_h: i32 = 0;
    glfw.glfwGetWindowSize(window, &window_w, &window_h);

    var fb_w: i32 = 0;
    var fb_h: i32 = 0;
    glfw.glfwGetFramebufferSize(window, &fb_w, &fb_h);

    var xscale: f32 = 1.0;
    var yscale: f32 = 1.0;
    glfw.glfwGetWindowContentScale(window, &xscale, &yscale);

    try commands.insertResource(Window{
        .handle = window,
        .title = settings.title,
        .flags = settings.flags,
    });
    try commands.insertResource(WindowBounds{
        .width = @intCast(window_w),
        .height = @intCast(window_h),
    });
    try commands.insertResource(RenderBounds{
        .width = @floatFromInt(fb_w),
        .height = @floatFromInt(fb_h),
    });
    try commands.insertResource(ContentScale{ .x = xscale, .y = yscale });

    std.log.info(
        "GLFW window initialized: {d}x{d} logical, {d}x{d} physical, scale={d:.2}x{d:.2}",
        .{ window_w, window_h, fb_w, fb_h, xscale, yscale },
    );
}

fn updateSystem(
    commands: *Commands,
    window_opt: ResOpt(Window),
    bounds_opt: ResOpt(WindowBounds),
    render_bounds_opt: ResOpt(RenderBounds),
    scale_opt: ResOpt(ContentScale),
    resize_writer: EventWriter(WindowResized),
    scale_writer: EventWriter(ContentScaleChanged),
) !void {
    const window_res = window_opt.ptr orelse return;
    const handle = window_res.handle orelse return;

    if (glfw.glfwWindowShouldClose(handle) != 0) {
        try commands.insertResource(resources.Exit{ .code = 0 });
        return;
    }

    glfw.glfwPollEvents();

    var window_w: i32 = 0;
    var window_h: i32 = 0;
    glfw.glfwGetWindowSize(handle, &window_w, &window_h);

    var fb_w: i32 = 0;
    var fb_h: i32 = 0;
    glfw.glfwGetFramebufferSize(handle, &fb_w, &fb_h);

    if (window_w <= 0 or window_h <= 0 or fb_w <= 0 or fb_h <= 0) return;

    const new_window_bounds = WindowBounds{
        .width = @intCast(window_w),
        .height = @intCast(window_h),
    };
    const new_render_bounds = RenderBounds{
        .width = @floatFromInt(fb_w),
        .height = @floatFromInt(fb_h),
    };

    const logical_size_changed = if (bounds_opt.ptr) |old_bounds|
        old_bounds.width != new_window_bounds.width or old_bounds.height != new_window_bounds.height
    else
        true;
    const framebuffer_size_changed = if (render_bounds_opt.ptr) |old_bounds|
        old_bounds.widthInt() != new_render_bounds.widthInt() or old_bounds.heightInt() != new_render_bounds.heightInt()
    else
        true;

    try commands.insertResource(new_window_bounds);
    try commands.insertResource(new_render_bounds);

    if (logical_size_changed or framebuffer_size_changed) {
        try resize_writer.send(.{
            .width = new_window_bounds.width,
            .height = new_window_bounds.height,
            .framebuffer_width = @intCast(fb_w),
            .framebuffer_height = @intCast(fb_h),
        });
        std.log.info(
            "Window resized: {d}x{d} logical, {d}x{d} physical",
            .{ window_w, window_h, fb_w, fb_h },
        );
    }

    var xscale: f32 = 1.0;
    var yscale: f32 = 1.0;
    glfw.glfwGetWindowContentScale(handle, &xscale, &yscale);
    const new_scale = ContentScale{ .x = xscale, .y = yscale };

    const scale_changed = if (scale_opt.ptr) |old_scale|
        @abs(old_scale.x - xscale) > 0.001 or @abs(old_scale.y - yscale) > 0.001
    else
        true;

    try commands.insertResource(new_scale);

    if (scale_changed) {
        try scale_writer.send(.{
            .x = xscale,
            .y = yscale,
        });
        std.log.info("Content scale changed: {d:.2}x{d:.2}", .{ xscale, yscale });
    }
}

fn shutdownSystem(window_opt: ResOpt(Window)) void {
    if (window_opt.ptr) |window_res| {
        if (window_res.handle) |handle| {
            glfw.glfwDestroyWindow(handle);
        }
    }
    glfw.glfwTerminate();
    std.log.info("GLFW window closed", .{});
}

const std = @import("std");
const glfw = @import("glfw").c;
const ecs = @import("ecs");
const common = @import("common");
const AppCommands = ecs.AppCommands;
const Commands = ecs.Commands;
const schedule = ecs.schedule;
const resources = ecs.resources;
const events = ecs.events;
const EventWriter = events.EventWriter;
const system_params = ecs.system_params;
const ResOpt = system_params.ResOpt;
