const builtin = @import("builtin");
const utils = @import("utils.zig");
const SurfaceTarget = utils.SurfaceTarget;
const Size = utils.Size;
const WebSurface = utils.WebSurface;

extern "env" fn webgpu_canvas_size(
    canvas_id_ptr: [*]const u8,
    canvas_id_len: usize,
    out_width: *u32,
    out_height: *u32,
) void;

pub fn fromCanvasId(canvas_id: []const u8) SurfaceTarget {
    if (!builtin.target.cpu.arch.isWasm()) {
        @panic("fromCanvasId only supported on wasm targets");
    }
    var width: u32 = 1;
    var height: u32 = 1;
    webgpu_canvas_size(canvas_id.ptr, canvas_id.len, &width, &height);
    return SurfaceTarget{
        .web = WebSurface{
            .canvas_id = canvas_id,
            .size = Size{ .width = width, .height = height },
        },
    };
}

pub fn pollSize(surface: *SurfaceTarget) void {
    if (!builtin.target.cpu.arch.isWasm()) return;
    switch (surface.*) {
        .web => |*web| {
            var width: u32 = web.size.width;
            var height: u32 = web.size.height;
            webgpu_canvas_size(web.canvas_id.ptr, web.canvas_id.len, &width, &height);
            web.size = .{ .width = width, .height = height };
        },
        else => {},
    }
}
