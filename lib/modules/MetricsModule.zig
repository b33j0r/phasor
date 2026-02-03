pub fn MetricsModule(comptime LayerT: ?type) type {
    return struct {
        update_ms: u32 = 250,
        font_size: f32 = 60.0,
        text_color: common.Color = common.Color.BLACK,
        margin: f32 = 12.0,
        buffer_capacity: usize = 512,
        use_default_lines: bool = true,
        extra_lines: []const MetricLine = &[_]MetricLine{},
        bus_capacity: usize = 256,
        bus_enabled: bool = true,
        log_interval_seconds: f64 = 0.0,

        pub fn install(self: *const @This(), app: *AppCommands, cmds: *Commands) !void {
            if (!cmds.hasResource(TimeModule.DeltaTime) or !cmds.hasResource(TimeModule.ElapsedTime)) {
                return error.MissingTimeModule;
            }

            if (!cmds.hasResource(metrics.Bus)) {
                try cmds.insertResource(try metrics.Bus.init(cmds.allocator, cmds.io, .{
                    .capacity = self.bus_capacity,
                    .enabled = self.bus_enabled,
                }));
            }
            if (!cmds.hasResource(metrics.Store)) {
                try cmds.insertResource(metrics.Store.init(cmds.allocator));
            }
            if (!cmds.hasResource(metrics.Metrics)) {
                try cmds.insertResource(metrics.Metrics{});
            }

            try cmds.insertResource(MetricsConfig{
                .update_interval = @as(f64, @floatFromInt(self.update_ms)) / 1000.0,
                .font_size = self.font_size,
                .text_color = self.text_color,
                .margin = self.margin,
                .buffer_capacity = self.buffer_capacity,
                .use_default_lines = self.use_default_lines,
                .extra_lines = self.extra_lines,
                .log_interval_seconds = self.log_interval_seconds,
            });

            const components = if (LayerT) |Layer| .{
                render.Text{
                    .content = "FPS: 0.0",
                    .color = self.text_color,
                    .font_size = self.font_size,
                    .horizontal_alignment = .Right,
                    .vertical_alignment = .Bottom,
                },
                common.Transform{},
                MetricsTextTag{},
                Layer{},
            } else .{
                render.Text{
                    .content = "FPS: 0.0",
                    .color = self.text_color,
                    .font_size = self.font_size,
                    .horizontal_alignment = .Right,
                    .vertical_alignment = .Bottom,
                },
                common.Transform{},
                MetricsTextTag{},
            };

            const text_entity = try cmds.createEntity(components);

            const buffer = try cmds.allocator.alloc(u8, self.buffer_capacity);
            try cmds.insertResource(MetricsState{
                .allocator = cmds.allocator,
                .text_entity = text_entity,
                .text_buffer = buffer,
            });
            try app.addSystem("Update", updateMetricsText);
        }

        pub fn uninstall(_: *const @This(), app: *AppCommands, cmds: *Commands) void {
            app.removeSystem(updateMetricsText);

            if (cmds.getResource(MetricsState)) |state| {
                cmds.removeEntity(state.text_entity) catch {};
            }

            _ = cmds.removeResource(MetricsState);
            _ = cmds.removeResource(MetricsConfig);
            _ = cmds.removeResource(metrics.Metrics);
        }
    };
}

const MetricsConfig = struct {
    update_interval: f64,
    font_size: f32,
    text_color: common.Color,
    margin: f32,
    buffer_capacity: usize,
    use_default_lines: bool,
    extra_lines: []const MetricLine,
    log_interval_seconds: f64,
};

const MetricsState = struct {
    allocator: std.mem.Allocator,
    text_entity: Entity.Id = 0,
    timer: f64 = 0.0,
    frames: u32 = 0,
    text_buffer: []u8 = &[_]u8{},
    next_log_time: f64 = 0.0,

    pub fn deinit(self: *MetricsState) void {
        if (self.text_buffer.len > 0) {
            self.allocator.free(self.text_buffer);
        }
        self.* = undefined;
    }
};

const MetricsTextTag = struct {};

const Bounds = struct {
    width: f32,
    height: f32,
};

fn updateMetricsText(
    dt: Res(TimeModule.DeltaTime),
    elapsed: Res(TimeModule.ElapsedTime),
    viewport_opt: ResOpt(ViewportSize),
    window_bounds_opt: ResOpt(common.WindowBounds),
    render_bounds_opt: ResOpt(common.RenderBounds),
    render_state_opt: ResOpt(RenderState),
    world: WorldRef,
    mesh_library_opt: ResOpt(render.MeshLibrary),
    render_queue_opt: ResOpt(render.RenderQueue),
    default_font_opt: ResOpt(render.DefaultFont),
    config: Res(MetricsConfig),
    state: ResMut(MetricsState),
    bus: ResMut(metrics.Bus),
    store: ResMut(metrics.Store),
    metrics_res: ResMut(metrics.Metrics),
    query: Query(.{ render.Text, common.Transform, MetricsTextTag }),
) void {
    const bounds = resolveBounds(viewport_opt, window_bounds_opt, render_bounds_opt, render_state_opt) orelse return;
    const dt_seconds = dt.deref().seconds;
    metrics_res.ptr.frame_ms = @floatCast(dt_seconds * 1000.0);

    var iter = query.iterator();
    while (iter.next()) |row| {
        const text = row.get(render.Text) orelse continue;
        const transform = row.get(common.Transform) orelse continue;

        transform.translation.x = bounds.width - config.ptr.margin;
        transform.translation.y = bounds.height - config.ptr.margin;

        text.color = config.ptr.text_color;
        text.font_size = config.ptr.font_size;
        text.horizontal_alignment = .Right;
        text.vertical_alignment = .Bottom;
    }

    if (dt_seconds <= 0.0) return;
    state.ptr.timer += dt_seconds;
    state.ptr.frames += 1;

    if (state.ptr.timer < config.ptr.update_interval) return;

    const fps = @as(f32, @floatFromInt(state.ptr.frames)) / @as(f32, @floatCast(state.ptr.timer));
    const max_fps = if (fps > metrics_res.ptr.max_fps) fps else metrics_res.ptr.max_fps;
    metrics.emitBus(true, bus.ptr, .{
        .fps = metrics.stat(fps),
        .max_fps = metrics.stat(max_fps),
        .frame_ms = metrics.stat(metrics_res.ptr.frame_ms),
        .elapsed_seconds = metrics.stat(elapsed.ptr.seconds),
    });
    emitRenderMetrics(bus.ptr, mesh_library_opt.ptr, render_queue_opt.ptr);
    if (render_state_opt.ptr) |state_ptr| {
        emitRendererStats(bus.ptr, &state_ptr.renderer);
    }
    emitWasmRuntimeMetrics(bus.ptr);
    emitEcsMetrics(bus.ptr, world.ptr);
    emitStoreMetrics(bus.ptr, store.ptr);
    state.ptr.timer = 0.0;
    state.ptr.frames = 0;

    drainMetrics(bus.ptr, store.ptr);
    maybeLogSnapshot(config.ptr, state.ptr, elapsed.ptr.seconds, store.ptr);

    const fps_value = metricF64(store.ptr, "fps", fps);
    const frame_ms_value = metricF64(store.ptr, "frame_ms", metrics_res.ptr.frame_ms);
    const max_fps_value = metricF64(store.ptr, "max_fps", max_fps);
    const elapsed_value = metricF64(store.ptr, "elapsed_seconds", elapsed.ptr.seconds);

    metrics_res.ptr.fps = @floatCast(fps_value);
    metrics_res.ptr.frame_ms = @floatCast(frame_ms_value);
    metrics_res.ptr.max_fps = @floatCast(max_fps_value);

    var font_name: ?[]const u8 = null;
    var font_pixel_height: f32 = 0.0;
    var font_atlas_width: u32 = 0;
    var font_atlas_height: u32 = 0;
    if (default_font_opt.ptr) |default_font| {
        font_name = default_font.font.name;
        font_pixel_height = default_font.font.pixel_height;
        font_atlas_width = default_font.font.atlas_width;
        font_atlas_height = default_font.font.atlas_height;
    }

    const ctx = MetricContext{
        .fps = @floatCast(fps_value),
        .frame_ms = @floatCast(frame_ms_value),
        .elapsed_seconds = elapsed_value,
        .max_fps = @floatCast(max_fps_value),
        .font_name = font_name,
        .font_pixel_height = font_pixel_height,
        .font_atlas_width = font_atlas_width,
        .font_atlas_height = font_atlas_height,
        .font_size = config.ptr.font_size,
        .line_height = config.ptr.font_size,
        .store = store.ptr,
    };

    const fmt_buf = writeMetricLines(config.ptr, &ctx, state.ptr.text_buffer);

    iter = query.iterator();
    while (iter.next()) |row| {
        const text = row.get(render.Text) orelse continue;
        text.content = fmt_buf;
    }
}

pub const MetricContext = struct {
    fps: f32,
    frame_ms: f32,
    elapsed_seconds: f64,
    max_fps: f32,
    font_name: ?[]const u8,
    font_pixel_height: f32,
    font_atlas_width: u32,
    font_atlas_height: u32,
    font_size: f32,
    line_height: f32,
    store: *metrics.Store,
};

pub const MetricValueFormat = enum {
    Auto,
    Float1,
    Float2,
    Int,
    Bool,
};

pub const MetricLineStore = struct {
    name: []const u8,
    label: []const u8,
    format: MetricValueFormat = .Auto,
};

pub const MetricLine = union(enum) {
    format: *const fn (ctx: *const MetricContext, out: []u8) []const u8,
    store: MetricLineStore,
};

pub const MetricLineFps = MetricLine{ .format = formatFpsLine };
pub const MetricLineFrameMs = MetricLine{ .format = formatFrameMsLine };
pub const MetricLineElapsedTime = MetricLine{ .format = formatElapsedTimeLine };
pub const MetricLineFontName = MetricLine{ .format = formatFontNameLine };
pub const MetricLineFontMetrics = MetricLine{ .format = formatFontMetricsLine };
pub const MetricLineFontAtlas = MetricLine{ .format = formatFontAtlasLine };

pub const DefaultLines: []const MetricLine = &[_]MetricLine{
    MetricLineFps,
    MetricLineFrameMs,
    MetricLineFontName,
    MetricLineFontMetrics,
    MetricLineFontAtlas,
};

fn writeMetricLines(config: *const MetricsConfig, ctx: *const MetricContext, buffer: []u8) []const u8 {
    var offset: usize = 0;
    var wrote_any = false;

    if (config.use_default_lines) {
        offset = appendMetricLines(ctx, buffer, offset, DefaultLines);
        wrote_any = offset > 0;
    }

    if (config.extra_lines.len > 0 and offset < buffer.len) {
        if (wrote_any and offset + 1 <= buffer.len) {
            buffer[offset] = '\n';
            offset += 1;
        }
        offset = appendMetricLines(ctx, buffer, offset, config.extra_lines);
    }

    return buffer[0..offset];
}

fn appendMetricLines(ctx: *const MetricContext, buffer: []u8, start: usize, lines: []const MetricLine) usize {
    var offset = start;
    for (lines, 0..) |line, idx| {
        if (offset >= buffer.len) break;
        const slice = switch (line) {
            .format => |formatFn| formatFn(ctx, buffer[offset..]),
            .store => |store_line| formatStoreLine(ctx, store_line, buffer[offset..]),
        };
        if (slice.len == 0) continue;
        offset += slice.len;
        if (idx + 1 < lines.len and offset + 1 <= buffer.len) {
            buffer[offset] = '\n';
            offset += 1;
        }
    }
    return offset;
}

fn formatFpsLine(ctx: *const MetricContext, out: []u8) []const u8 {
    return std.fmt.bufPrint(out, "FPS: {d:0.1}", .{ctx.fps}) catch copyLine(out, "FPS: ERR");
}

fn formatFrameMsLine(ctx: *const MetricContext, out: []u8) []const u8 {
    return std.fmt.bufPrint(out, "Frame: {d:0.2} ms", .{ctx.frame_ms}) catch copyLine(out, "Frame: ERR");
}

fn formatElapsedTimeLine(ctx: *const MetricContext, out: []u8) []const u8 {
    const total_seconds: u64 = @intFromFloat(@max(ctx.elapsed_seconds, 0.0));
    const hours: u64 = total_seconds / 3600;
    const minutes: u64 = (total_seconds / 60) % 60;
    const seconds: u64 = total_seconds % 60;
    return std.fmt.bufPrint(out, "Elapsed: {d:0>2}:{d:0>2}:{d:0>2}", .{ hours, minutes, seconds }) catch copyLine(out, "Elapsed: ERR");
}

fn formatFontNameLine(ctx: *const MetricContext, out: []u8) []const u8 {
    if (ctx.font_name) |name| {
        return std.fmt.bufPrint(out, "Font: {s}", .{name}) catch copyLine(out, "Font: ERR");
    }
    return copyLine(out, "Font: (none)");
}

fn formatFontMetricsLine(ctx: *const MetricContext, out: []u8) []const u8 {
    if (ctx.font_name == null) return copyLine(out, "Font Size: (none)");
    return std.fmt.bufPrint(
        out,
        "Font Size: {d:0.1} Line: {d:0.1} Px: {d:0.1}",
        .{ ctx.font_size, ctx.line_height, ctx.font_pixel_height },
    ) catch copyLine(out, "Font Size: ERR");
}

fn formatFontAtlasLine(ctx: *const MetricContext, out: []u8) []const u8 {
    if (ctx.font_name == null) return copyLine(out, "Atlas: (none)");
    return std.fmt.bufPrint(out, "Atlas: {d}x{d}", .{ ctx.font_atlas_width, ctx.font_atlas_height }) catch copyLine(out, "Atlas: ERR");
}

fn formatStoreLine(ctx: *const MetricContext, line: MetricLineStore, out: []u8) []const u8 {
    const sample = ctx.store.get(line.name) orelse {
        return copyLine(out, line.label);
    };
    const value = sample.value;
    return switch (line.format) {
        .Float1 => std.fmt.bufPrint(out, "{s}: {d:0.1}", .{ line.label, value.asF64() }) catch copyLine(out, line.label),
        .Float2 => std.fmt.bufPrint(out, "{s}: {d:0.2}", .{ line.label, value.asF64() }) catch copyLine(out, line.label),
        .Int => std.fmt.bufPrint(out, "{s}: {d}", .{ line.label, @as(i64, @intFromFloat(value.asF64())) }) catch copyLine(out, line.label),
        .Bool => std.fmt.bufPrint(out, "{s}: {s}", .{ line.label, if (value.asF64() != 0.0) "true" else "false" }) catch copyLine(out, line.label),
        .Auto => std.fmt.bufPrint(out, "{s}: {d}", .{ line.label, value.asF64() }) catch copyLine(out, line.label),
    };
}

fn copyLine(out: []u8, text: []const u8) []const u8 {
    const len = @min(out.len, text.len);
    if (len == 0) return out[0..0];
    @memcpy(out[0..len], text[0..len]);
    return out[0..len];
}

fn drainMetrics(bus: *metrics.Bus, store: *metrics.Store) void {
    var buffer: [8]metrics.Event = undefined;
    while (true) {
        const count = bus.queue.get(bus.io.*, &buffer, 0) catch |err| switch (err) {
            error.Closed, error.Canceled => return,
        };
        if (count == 0) return;
        for (buffer[0..count]) |event| {
            store.applyEvent(event);
        }
    }
}

fn metricF64(store: *metrics.Store, name: []const u8, fallback: f64) f64 {
    if (store.get(name)) |sample| {
        return sample.value.asF64();
    }
    return fallback;
}

const MeshStats = struct {
    slots: usize,
    alive: usize,
    free: usize,
};

fn meshStats(library: *const render.MeshLibrary) MeshStats {
    var alive: usize = 0;
    for (library.slots.items) |slot| {
        if (slot.alive) alive += 1;
    }
    return .{
        .slots = library.slots.items.len,
        .alive = alive,
        .free = library.free_list.items.len,
    };
}

fn emitRenderMetrics(
    bus: *metrics.Bus,
    mesh_library_opt: ?*const render.MeshLibrary,
    render_queue_opt: ?*const render.RenderQueue,
) void {
    if (mesh_library_opt) |library| {
        const stats = meshStats(library);
        metrics.emitBus(true, bus, .{
            .mesh_slots = metrics.gauge(stats.slots),
            .mesh_alive = metrics.gauge(stats.alive),
            .mesh_free = metrics.gauge(stats.free),
        });
    }
    if (render_queue_opt) |queue| {
        metrics.emitBus(true, bus, .{
            .render_queue_items = metrics.gauge(queue.items.items.len),
            .render_queue_capacity = metrics.gauge(queue.items.capacity),
        });
    }
}

fn emitRendererStats(bus: *metrics.Bus, renderer: *const render.Renderer) void {
    const stats = render.rendererStats(renderer);
    metrics.emitBus(true, bus, .{
        .webgpu_mesh_alive = metrics.gauge(stats.meshes_alive),
        .webgpu_mesh_slots = metrics.gauge(stats.meshes_slots),
        .webgpu_mesh_free = metrics.gauge(stats.meshes_free),
        .webgpu_texture_alive = metrics.gauge(stats.textures_alive),
        .webgpu_texture_slots = metrics.gauge(stats.textures_slots),
        .webgpu_material_alive = metrics.gauge(stats.materials_alive),
        .webgpu_material_slots = metrics.gauge(stats.materials_slots),
        .webgpu_sampler_alive = metrics.gauge(stats.samplers_alive),
        .webgpu_sampler_slots = metrics.gauge(stats.samplers_slots),
    });
}

fn emitWasmRuntimeMetrics(bus: *metrics.Bus) void {
    const mem_bytes: u64 = WasmImports.memoryBytes();
    if (mem_bytes > 0) {
        const mem_mb: f64 = @as(f64, @floatFromInt(mem_bytes)) / (1024.0 * 1024.0);
        metrics.emitBus(true, bus, .{
            .wasm_mem_bytes = metrics.gauge(mem_bytes),
            .wasm_mem_mb = metrics.gauge(mem_mb),
        });
    }

    var js_used: u32 = 0;
    var js_total: u32 = 0;
    WasmImports.jsHeap(&js_used, &js_total);
    if (js_total > 0) {
        const used_mb: f64 = @as(f64, @floatFromInt(js_used)) / (1024.0 * 1024.0);
        const total_mb: f64 = @as(f64, @floatFromInt(js_total)) / (1024.0 * 1024.0);
        metrics.emitBus(true, bus, .{
            .js_heap_used_mb = metrics.gauge(used_mb),
            .js_heap_total_mb = metrics.gauge(total_mb),
        });
    }

    var buffers: u32 = 0;
    var active: u32 = 0;
    WasmImports.audioCounts(&buffers, &active);
    if (buffers > 0 or active > 0) {
        metrics.emitBus(true, bus, .{
            .wasm_audio_buffers = metrics.gauge(buffers),
            .wasm_audio_active = metrics.gauge(active),
        });
    }

    var lost_flag: u32 = 0;
    WasmImports.deviceLost(&lost_flag);
    metrics.emitBus(true, bus, .{
        .webgpu_device_lost = metrics.gauge(lost_flag),
    });

    var validation_errors: u32 = 0;
    var out_of_memory_errors: u32 = 0;
    var internal_errors: u32 = 0;
    WasmImports.webgpuErrors(&validation_errors, &out_of_memory_errors, &internal_errors);
    if (validation_errors > 0 or out_of_memory_errors > 0 or internal_errors > 0) {
        metrics.emitBus(true, bus, .{
            .webgpu_validation_errors = metrics.gauge(validation_errors),
            .webgpu_oom_errors = metrics.gauge(out_of_memory_errors),
            .webgpu_internal_errors = metrics.gauge(internal_errors),
        });
    }
}

fn emitEcsMetrics(bus: *metrics.Bus, world: *const ecs.World) void {
    const db = &world.database;
    metrics.emitBus(true, bus, .{
        .ecs_entities = metrics.gauge(db.entityCount()),
        .ecs_tables = metrics.gauge(db.tableCount()),
        .ecs_rows = metrics.gauge(db.totalRowCount()),
    });
}

fn emitStoreMetrics(bus: *metrics.Bus, store: *metrics.Store) void {
    metrics.emitBus(true, bus, .{
        .metrics_store_entries = metrics.gauge(store.map.count()),
    });
}

fn maybeLogSnapshot(
    config: *const MetricsConfig,
    state: *MetricsState,
    elapsed_seconds: f64,
    store: *metrics.Store,
) void {
    if (config.log_interval_seconds <= 0) return;
    if (elapsed_seconds < state.next_log_time) return;
    state.next_log_time = elapsed_seconds + config.log_interval_seconds;
    logSnapshot(elapsed_seconds, store);
}

fn logSnapshot(elapsed_seconds: f64, store: *metrics.Store) void {
    var buffer: [2048]u8 = undefined;
    var offset: usize = 0;

    const header = std.fmt.bufPrint(buffer[offset..], "metric ts={d:0.3}", .{elapsed_seconds}) catch return;
    offset += header.len;

    var it = store.map.iterator();
    while (it.next()) |entry| {
        if (offset + 1 >= buffer.len) break;
        buffer[offset] = ' ';
        offset += 1;

        const sample = entry.value_ptr.*;
        const unit = sample.unit orelse "-";
        const written = std.fmt.bufPrint(
            buffer[offset..],
            "{s}={d} {s}#{d}",
            .{ sample.name, sample.value.asF64(), unit, sample.count },
        ) catch break;
        offset += written.len;
    }

    std.log.info("{s}", .{buffer[0..offset]});
}

fn resolveBounds(
    viewport_opt: ResOpt(ViewportSize),
    window_bounds_opt: ResOpt(common.WindowBounds),
    render_bounds_opt: ResOpt(common.RenderBounds),
    render_state_opt: ResOpt(RenderState),
) ?Bounds {
    if (viewport_opt.ptr) |vp| {
        return .{ .width = vp.width, .height = vp.height };
    }
    if (window_bounds_opt.ptr) |bounds| {
        return .{
            .width = @floatFromInt(bounds.width),
            .height = @floatFromInt(bounds.height),
        };
    }
    if (render_bounds_opt.ptr) |bounds| {
        return .{ .width = bounds.width, .height = bounds.height };
    }
    if (render_state_opt.ptr) |state| {
        const size = state.surface.size();
        return .{
            .width = @floatFromInt(size.width),
            .height = @floatFromInt(size.height),
        };
    }
    return null;
}

const std = @import("std");
const common = @import("common");
const ecs = @import("ecs");
const metrics = @import("metrics");
const render = @import("render");
const builtin = @import("builtin");
const schedule = ecs.schedule;
const AppCommands = ecs.AppCommands;
const Commands = ecs.Commands;
const Query = ecs.system_params.Query;
const Res = ecs.system_params.Res;
const ResMut = ecs.system_params.ResMut;
const ResOpt = ecs.system_params.ResOpt;
const WorldRef = ecs.system_params.WorldRef;
const Entity = @import("db").Entity;
const TimeModule = @import("TimeModule.zig");
const RenderModule = @import("RenderModule.zig");
const ViewportSize = RenderModule.ViewportSize;
const RenderState = RenderModule.RenderState;

const WasmImports = if (builtin.target.cpu.arch.isWasm()) struct {
    extern "env" fn wasm_memory_bytes() u32;
    extern "env" fn wasm_js_heap(out_used: *u32, out_total: *u32) void;
    extern "env" fn wasm_audio_counts(out_buffers: *u32, out_active: *u32) void;
    extern "env" fn webgpu_device_lost(out_flag: *u32) void;
    extern "env" fn webgpu_error_counts(out_validation: *u32, out_out_of_memory: *u32, out_internal: *u32) void;

    pub fn memoryBytes() u64 {
        return @intCast(wasm_memory_bytes());
    }

    pub fn audioCounts(out_buffers: *u32, out_active: *u32) void {
        wasm_audio_counts(out_buffers, out_active);
    }

    pub fn jsHeap(out_used: *u32, out_total: *u32) void {
        wasm_js_heap(out_used, out_total);
    }

    pub fn deviceLost(out_flag: *u32) void {
        webgpu_device_lost(out_flag);
    }

    pub fn webgpuErrors(out_validation: *u32, out_out_of_memory: *u32, out_internal: *u32) void {
        webgpu_error_counts(out_validation, out_out_of_memory, out_internal);
    }
} else struct {
    pub fn memoryBytes() u64 {
        return 0;
    }

    pub fn audioCounts(_: *u32, _: *u32) void {}

    pub fn jsHeap(_: *u32, _: *u32) void {}

    pub fn deviceLost(_: *u32) void {}

    pub fn webgpuErrors(_: *u32, _: *u32, _: *u32) void {}
};
