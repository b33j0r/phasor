pub const MetricsViewport = union(enum) {
    Screen,
    Layer: i32,

    pub fn screen() MetricsViewport {
        return .Screen;
    }

    pub fn layer(layer_index: i32) MetricsViewport {
        return .{ .Layer = layer_index };
    }
};

pub fn MetricsModule(comptime LayerT: ?type) type {
    return struct {
        update_ms: u32 = 250,
        max_dt_seconds: f64 = 0.25,
        font_size: f32 = 60.0,
        text_color: common.Color = common.Color.BLACK,
        margin: f32 = 12.0,
        buffer_capacity: usize = 512,
        use_default_lines: bool = true,
        extra_builtin_lines: []const BuiltinMetricLineItem = &[_]BuiltinMetricLineItem{},
        prepend_lines: []const MetricLine = &[_]MetricLine{},
        extra_lines: []const MetricLine = &[_]MetricLine{},
        bus_capacity: usize = 256,
        bus_enabled: bool = true,
        log_interval_seconds: f64 = 0.0,
        viewport: MetricsViewport = defaultViewportMode(LayerT),

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
                .max_dt_seconds = self.max_dt_seconds,
                .font_size = self.font_size,
                .text_color = self.text_color,
                .margin = self.margin,
                .buffer_capacity = self.buffer_capacity,
                .use_default_lines = self.use_default_lines,
                .extra_builtin_lines = self.extra_builtin_lines,
                .prepend_lines = self.prepend_lines,
                .extra_lines = self.extra_lines,
                .log_interval_seconds = self.log_interval_seconds,
                .viewport = self.viewport,
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
            try cmds.addComponents(text_entity, .{
                TimerModule.StopwatchTimer{ .clock = .real },
                TimerModule.CountdownTimer{
                    .remaining = self.log_interval_seconds,
                    .finished = self.log_interval_seconds <= 0.0,
                    .clock = .real,
                },
            });

            const buffer = try cmds.allocator.alloc(u8, self.buffer_capacity);
            try cmds.insertResource(MetricsState{
                .allocator = cmds.allocator,
                .text_entity = text_entity,
                .text_buffer = buffer,
            });
            try app.addSystem("BeforeFrame", emitSceneMetrics);
            try app.addSystem("Update", updateMetricsText);
        }

        pub fn uninstall(_: *const @This(), app: *AppCommands, cmds: *Commands) void {
            app.removeSystem(emitSceneMetrics);
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

fn emitSceneMetrics(
    bus_opt: ResMutOpt(metrics.Bus),
    scene_stats_mode_opt: ResOpt(render.SceneStatsMode),
    scene_stats_snapshot_opt: ResOpt(render.SceneStatsSnapshot),
) void {
    const bus = bus_opt.ptr orelse return;
    const mode = scene_stats_mode_opt.ptr orelse return;
    if (!mode.enabled) return;

    const snapshot = if (scene_stats_snapshot_opt.ptr) |stats| stats.* else render.SceneStatsSnapshot{};
    const size = snapshot.size();
    metrics.emitBus(true, bus, .{
        .scene_mesh_count = metrics.gauge(snapshot.mesh_count),
        .scene_size_x = metrics.gauge(size.x),
        .scene_size_y = metrics.gauge(size.y),
        .scene_size_z = metrics.gauge(size.z),
    });
}

fn defaultViewportMode(comptime LayerT: ?type) MetricsViewport {
    if (LayerT) |Layer| {
        if (@hasDecl(Layer, "__traits__")) {
            inline for (Layer.__traits__) |Trait| {
                if (@hasDecl(Trait, "key")) {
                    return MetricsViewport.layer(Trait.key);
                }
            }
        }
    }
    return MetricsViewport.screen();
}

const MetricsConfig = struct {
    update_interval: f64,
    max_dt_seconds: f64,
    font_size: f32,
    text_color: common.Color,
    margin: f32,
    buffer_capacity: usize,
    use_default_lines: bool,
    extra_builtin_lines: []const BuiltinMetricLineItem,
    prepend_lines: []const MetricLine,
    extra_lines: []const MetricLine,
    log_interval_seconds: f64,
    viewport: MetricsViewport,
};

const MetricsState = struct {
    allocator: std.mem.Allocator,
    text_entity: Entity.Id = 0,
    frames: u32 = 0,
    text_buffer: []u8 = &[_]u8{},

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
    layer_viewports_opt: ResOpt(LayerViewports),
    window_bounds_opt: ResOpt(common.WindowBounds),
    render_bounds_opt: ResOpt(common.RenderBounds),
    render_state_opt: ResOpt(RenderState),
    default_font_opt: ResOpt(render.DefaultFont),
    config: Res(MetricsConfig),
    state: ResMut(MetricsState),
    bus: ResMut(metrics.Bus),
    store: ResMut(metrics.Store),
    metrics_res: ResMut(metrics.Metrics),
    query: Query(.{
        render.Text,
        common.Transform,
        MetricsTextTag,
        TimerModule.StopwatchTimer,
        TimerModule.CountdownTimer,
    }),
) void {
    const bounds = resolveBounds(config.ptr.viewport, layer_viewports_opt, viewport_opt, window_bounds_opt, render_bounds_opt, render_state_opt) orelse return;
    const clamped_dt = dt.deref().clampedSeconds32(config.ptr.max_dt_seconds);
    metrics_res.ptr.frame_ms = clamped_dt * 1000.0;
    var fps_window_timer: ?*TimerModule.StopwatchTimer = null;
    var log_timer: ?*TimerModule.CountdownTimer = null;

    var iter = query.iterator();
    while (iter.next()) |row| {
        const text = row.get(render.Text) orelse continue;
        const transform = row.get(common.Transform) orelse continue;
        const stopwatch = row.get(TimerModule.StopwatchTimer) orelse continue;
        const countdown = row.get(TimerModule.CountdownTimer) orelse continue;
        if (fps_window_timer == null) fps_window_timer = stopwatch;
        if (log_timer == null) log_timer = countdown;

        transform.translation.x = bounds.width - config.ptr.margin;
        transform.translation.y = bounds.height - config.ptr.margin;

        text.color = config.ptr.text_color;
        text.font_size = config.ptr.font_size;
        text.horizontal_alignment = .Right;
        text.vertical_alignment = .Bottom;
    }

    const fps_timer = fps_window_timer orelse return;

    var should_emit_fps_window = false;
    if (clamped_dt > 0.0) {
        state.ptr.frames += 1;
        should_emit_fps_window = fps_timer.elapsedAs(f64) >= config.ptr.update_interval;
    }

    if (should_emit_fps_window) {
        const elapsed_seconds = @max(fps_timer.elapsed32(), clamped_dt);
        const fps = @as(f32, @floatFromInt(state.ptr.frames)) / elapsed_seconds;
        const max_fps = if (fps > metrics_res.ptr.max_fps) fps else metrics_res.ptr.max_fps;
        metrics.emitBus(true, bus.ptr, .{
            .fps = metrics.stat(fps),
            .max_fps = metrics.stat(max_fps),
            .frame_ms = metrics.stat(metrics_res.ptr.frame_ms),
            .elapsed_seconds = metrics.stat(elapsed.ptr.secondsAs(f64)),
        });
        fps_timer.reset();
        state.ptr.frames = 0;
    } else {
        // Keep elapsed text monotonic even when a frame reports zero/invalid dt.
        metrics.emitBus(true, bus.ptr, .{
            .elapsed_seconds = metrics.stat(elapsed.ptr.secondsAs(f64)),
        });
    }

    drainMetrics(bus.ptr, store.ptr);
    maybeLogSnapshot(config.ptr, log_timer, elapsed.ptr.secondsAs(f64), store.ptr);

    const fps_value = metricF64(store.ptr, "fps", metrics_res.ptr.fps);
    const frame_ms_value = metricF64(store.ptr, "frame_ms", metrics_res.ptr.frame_ms);
    const max_fps_value = metricF64(store.ptr, "max_fps", metrics_res.ptr.max_fps);
    const elapsed_value = metricF64(store.ptr, "elapsed_seconds", elapsed.ptr.secondsAs(f64));

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

pub const MetricLineKind = union(enum) {
    format: *const fn (ctx: *const MetricContext, out: []u8) []const u8,
    store: MetricLineStore,
};

pub const MetricLine = struct {
    sort_key: i32 = 0,
    kind: MetricLineKind,
    extra_text: ?[]const u8 = null,
};

pub fn withSort(line: MetricLine, sort_key: i32) MetricLine {
    var copy = line;
    copy.sort_key = sort_key;
    return copy;
}

pub fn lineFormat(sort_key: i32, formatFn: *const fn (ctx: *const MetricContext, out: []u8) []const u8) MetricLine {
    return .{ .sort_key = sort_key, .kind = .{ .format = formatFn }, .extra_text = null };
}

pub fn lineStore(sort_key: i32, store: MetricLineStore) MetricLine {
    return .{ .sort_key = sort_key, .kind = .{ .store = store }, .extra_text = null };
}

pub fn withExtraText(line: MetricLine, extra_text: []const u8) MetricLine {
    var copy = line;
    copy.extra_text = extra_text;
    return copy;
}

pub const MetricLineFps = lineFormat(0, formatFpsLine);
pub const MetricLineFrameMs = lineFormat(0, formatFrameMsLine);
pub const MetricLineElapsedTime = lineFormat(0, formatElapsedTimeLine);
pub const MetricLineFontName = lineFormat(0, formatFontNameLine);
pub const MetricLineFontMetrics = lineFormat(0, formatFontMetricsLine);
pub const MetricLineFontAtlas = lineFormat(0, formatFontAtlasLine);

pub const BuiltinMetricLine = enum {
    fps,
    frame_time,
    elapsed_time,
    font_name,
    font_size,
    font_atlas,
    mouse_look,
    scene_stats,
    light_stats,
    color_grade,
};

pub const BuiltinMetricLineItem = struct {
    line: BuiltinMetricLine,
    extra_text: ?[]const u8 = null,
};

pub fn builtinLine(line: BuiltinMetricLine) BuiltinMetricLineItem {
    return .{ .line = line };
}

pub fn builtinLineWithExtraText(line: BuiltinMetricLine, extra_text: []const u8) BuiltinMetricLineItem {
    return .{
        .line = line,
        .extra_text = extra_text,
    };
}

pub const DefaultBuiltinLines: []const BuiltinMetricLineItem = &[_]BuiltinMetricLineItem{
    builtinLine(.fps),
    builtinLine(.frame_time),
};

pub const DefaultLines: []const MetricLine = &[_]MetricLine{
    MetricLineFps,
    MetricLineFrameMs,
};

fn writeMetricLines(config: *const MetricsConfig, ctx: *const MetricContext, buffer: []u8) []const u8 {
    var offset: usize = 0;
    var wrote_any = false;

    if (config.prepend_lines.len > 0) {
        offset = appendMetricLines(ctx, buffer, offset, config.prepend_lines);
        wrote_any = offset > 0;
    }

    if (config.use_default_lines) {
        offset = appendMetricLines(ctx, buffer, offset, DefaultLines);
        wrote_any = offset > 0;
    }

    if (config.extra_builtin_lines.len > 0 and offset < buffer.len) {
        if (wrote_any and offset + 1 <= buffer.len) {
            buffer[offset] = '\n';
            offset += 1;
        }
        offset = appendBuiltinMetricLines(ctx, buffer, offset, config.extra_builtin_lines);
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
    const max_sort_lines = 128;

    var needs_sort = false;
    for (lines) |line| {
        if (line.sort_key != 0) {
            needs_sort = true;
            break;
        }
    }

    if (!needs_sort or lines.len > max_sort_lines) {
        for (lines, 0..) |line, idx| {
            if (offset >= buffer.len) break;
            const slice = switch (line.kind) {
                .format => |formatFn| formatFn(ctx, buffer[offset..]),
                .store => |store_line| formatStoreLine(ctx, store_line, buffer[offset..]),
            };
            if (slice.len == 0) continue;
            offset += slice.len;
            offset = appendExtraText(buffer, offset, line.extra_text);
            if (idx + 1 < lines.len and offset + 1 <= buffer.len) {
                buffer[offset] = '\n';
                offset += 1;
            }
        }
        return offset;
    }

    var used: [max_sort_lines]bool = .{false} ** max_sort_lines;
    var produced: usize = 0;
    while (produced < lines.len) : (produced += 1) {
        var best_idx: ?usize = null;
        var best_key: i32 = 0;
        var idx: usize = 0;
        while (idx < lines.len) : (idx += 1) {
            if (used[idx]) continue;
            const key = lines[idx].sort_key;
            if (best_idx == null or key < best_key) {
                best_idx = idx;
                best_key = key;
            }
        }
        if (best_idx == null) break;
        const line = lines[best_idx.?];
        used[best_idx.?] = true;
        if (offset >= buffer.len) break;
        const slice = switch (line.kind) {
            .format => |formatFn| formatFn(ctx, buffer[offset..]),
            .store => |store_line| formatStoreLine(ctx, store_line, buffer[offset..]),
        };
        if (slice.len == 0) continue;
        offset += slice.len;
        offset = appendExtraText(buffer, offset, line.extra_text);
        if (produced + 1 < lines.len and offset + 1 <= buffer.len) {
            buffer[offset] = '\n';
            offset += 1;
        }
    }
    return offset;
}

fn appendBuiltinMetricLines(ctx: *const MetricContext, buffer: []u8, start: usize, lines: []const BuiltinMetricLineItem) usize {
    var offset = start;
    for (lines, 0..) |item, idx| {
        if (offset >= buffer.len) break;
        const slice = switch (item.line) {
            .fps => formatFpsLine(ctx, buffer[offset..]),
            .frame_time => formatFrameMsLine(ctx, buffer[offset..]),
            .elapsed_time => formatElapsedTimeLine(ctx, buffer[offset..]),
            .font_name => formatFontNameLine(ctx, buffer[offset..]),
            .font_size => formatFontMetricsLine(ctx, buffer[offset..]),
            .font_atlas => formatFontAtlasLine(ctx, buffer[offset..]),
            .mouse_look => formatMouseLookLine(ctx, buffer[offset..]),
            .scene_stats => formatSceneStatsLine(ctx, buffer[offset..]),
            .light_stats => formatLightStatsLine(ctx, buffer[offset..]),
            .color_grade => formatColorGradeLine(ctx, buffer[offset..]),
        };
        if (slice.len == 0) continue;
        offset += slice.len;
        offset = appendExtraText(buffer, offset, item.extra_text);
        if (idx + 1 < lines.len and offset + 1 <= buffer.len) {
            buffer[offset] = '\n';
            offset += 1;
        }
    }
    return offset;
}

fn appendExtraText(buffer: []u8, start: usize, extra_text: ?[]const u8) usize {
    const text = extra_text orelse return start;
    if (text.len == 0) return start;

    var offset = start;
    if (offset + 1 > buffer.len) return offset;
    buffer[offset] = ' ';
    offset += 1;

    const count = @min(text.len, buffer.len - offset);
    if (count == 0) return offset;
    @memcpy(buffer[offset .. offset + count], text[0..count]);
    offset += count;
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

fn formatMouseLookLine(ctx: *const MetricContext, out: []u8) []const u8 {
    const available = metricBool(ctx.store, "mouse_look_available", false);
    if (!available) return copyLine(out, "Mouse Look: unavailable");
    const captured = metricBool(ctx.store, "mouse_look_captured", false);
    if (captured) return copyLine(out, "Mouse Look: on");
    const enabled = metricBool(ctx.store, "mouse_look_capture_enabled", false);
    if (enabled) return copyLine(out, "Mouse Look: pending");
    return copyLine(out, "Mouse Look: off");
}

fn formatSceneStatsLine(ctx: *const MetricContext, out: []u8) []const u8 {
    const meshes = metricU64(ctx.store, "scene_mesh_count", 0);
    const size_x = metricF64Store(ctx.store, "scene_size_x", 0.0);
    const size_y = metricF64Store(ctx.store, "scene_size_y", 0.0);
    const size_z = metricF64Store(ctx.store, "scene_size_z", 0.0);
    return std.fmt.bufPrint(out, "Scene: {d} meshes  {d:.1}m x {d:.1}m x {d:.1}m", .{ meshes, size_x, size_y, size_z }) catch copyLine(out, "Scene: ERR");
}

fn formatLightStatsLine(ctx: *const MetricContext, out: []u8) []const u8 {
    const total = metricU64(ctx.store, "lights_total", 0);
    const dynamic = metricU64(ctx.store, "lights_dynamic", 0);
    const point = metricU64(ctx.store, "lights_point", 0);
    const spot = metricU64(ctx.store, "lights_spot", 0);
    return std.fmt.bufPrint(out, "Lights: {d} total  {d} dynamic  {d} point  {d} spot", .{ total, dynamic, point, spot }) catch copyLine(out, "Lights: ERR");
}

fn formatColorGradeLine(ctx: *const MetricContext, out: []u8) []const u8 {
    const grade_value = metricU64(ctx.store, "color_grade", 0);
    const grade_name = switch (grade_value) {
        0 => "none",
        1 => "filmic",
        2 => "aces_fitted",
        3 => "agx",
        4 => "pbr_neutral",
        else => "unknown",
    };
    return std.fmt.bufPrint(out, "Color Grade: {s} ({d})", .{ grade_name, grade_value }) catch copyLine(out, "Color Grade: ERR");
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

fn metricF64Store(store: *metrics.Store, name: []const u8, fallback: f64) f64 {
    const sample = store.get(name) orelse return fallback;
    return sample.value.asF64();
}

fn metricU64(store: *metrics.Store, name: []const u8, fallback: u64) u64 {
    const sample = store.get(name) orelse return fallback;
    return @intFromFloat(sample.value.asF64());
}

fn metricBool(store: *metrics.Store, name: []const u8, fallback: bool) bool {
    const sample = store.get(name) orelse return fallback;
    return sample.value.asF64() != 0.0;
}

fn drainMetrics(bus: *metrics.Bus, store: *metrics.Store) void {
    while (bus.channel.tryRecv()) |event| {
        store.applyEvent(event);
    }
}

fn metricF64(store: *metrics.Store, name: []const u8, fallback: f64) f64 {
    if (store.get(name)) |sample| {
        return sample.value.asF64();
    }
    return fallback;
}

fn maybeLogSnapshot(
    config: *const MetricsConfig,
    log_timer: ?*TimerModule.CountdownTimer,
    elapsed_seconds: f64,
    store: *metrics.Store,
) void {
    if (config.log_interval_seconds <= 0) return;
    const timer = log_timer orelse return;
    if (!timer.finished) return;
    timer.reset(config.log_interval_seconds);
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
    viewport_mode: MetricsViewport,
    layer_viewports_opt: ResOpt(LayerViewports),
    viewport_opt: ResOpt(ViewportSize),
    window_bounds_opt: ResOpt(common.WindowBounds),
    render_bounds_opt: ResOpt(common.RenderBounds),
    render_state_opt: ResOpt(RenderState),
) ?Bounds {
    switch (viewport_mode) {
        .Layer => |layer| {
            if (layer_viewports_opt.ptr) |viewports| {
                if (viewports.map.get(layer)) |rect| {
                    return .{ .width = rect.width, .height = rect.height };
                }
            }
        },
        .Screen => {},
    }
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

// Imports
const std = @import("std");
const common = @import("common");
const ecs = @import("ecs");
const metrics = @import("./root.zig");
const render = @import("render");
const schedule = ecs.schedule;
const AppCommands = ecs.AppCommands;
const Commands = ecs.Commands;
const Query = ecs.system_params.Query;
const Res = ecs.system_params.Res;
const ResMut = ecs.system_params.ResMut;
const ResMutOpt = ecs.system_params.ResMutOpt;
const ResOpt = ecs.system_params.ResOpt;
const Entity = @import("db").Entity;
const TimeModule = @import("modules").TimeModule;
const TimerModule = @import("modules").TimerModule;
const RenderModule = render.RenderModule;
const ViewportSize = RenderModule.ViewportSize;
const RenderState = RenderModule.RenderState;
const LayerViewports = RenderModule.LayerViewports;
