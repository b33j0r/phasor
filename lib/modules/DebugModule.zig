//! Holistic debug module that layers on top of MetricsModule.

pub const DebugSettings = struct {
    enabled: bool = true,
    emit_render_metrics: bool = true,
    emit_renderer_stats: bool = true,
    emit_wasm_metrics: bool = true,
    emit_ecs_metrics: bool = true,
    emit_store_metrics: bool = true,
    emit_webgpu_errors: bool = true,
};

pub fn DebugModule(comptime LayerT: ?type) type {
    const MetricsModuleT = MetricsModule.MetricsModule(LayerT);
    return struct {
        metrics: MetricsModuleT = .{},
        settings: DebugSettings = .{},

        pub fn install(self: *const @This(), app: *AppCommands, cmds: *Commands) !void {
            if (!cmds.hasResource(DebugSettings)) {
                try cmds.insertResource(self.settings);
            }
            try self.metrics.install(app, cmds);
            try app.addSystem("Update", emitDebugMetrics);
        }

        pub fn uninstall(self: *const @This(), app: *AppCommands, cmds: *Commands) void {
            app.removeSystem(emitDebugMetrics);
            self.metrics.uninstall(app, cmds);
            _ = cmds.removeResource(DebugSettings);
        }
    };
}

fn emitDebugMetrics(
    render_state_opt: ResOpt(RenderState),
    mesh_library_opt: ResOpt(render.MeshLibrary),
    render_queue_opt: ResOpt(render.RenderQueue),
    world: WorldRef,
    bus: ResMut(metrics.Bus),
    store: ResMut(metrics.Store),
    settings: Res(DebugSettings),
) void {
    if (!settings.ptr.enabled) return;

    if (settings.ptr.emit_render_metrics) {
        emitRenderMetrics(bus.ptr, mesh_library_opt.ptr, render_queue_opt.ptr);
    }
    if (settings.ptr.emit_renderer_stats) {
        if (render_state_opt.ptr) |state_ptr| {
            emitRendererStats(bus.ptr, &state_ptr.renderer);
        }
    }
    if (settings.ptr.emit_wasm_metrics) {
        emitWasmRuntimeMetrics(bus.ptr, settings.ptr.emit_webgpu_errors);
    }
    if (settings.ptr.emit_ecs_metrics) {
        emitEcsMetrics(bus.ptr, world.ptr);
    }
    if (settings.ptr.emit_store_metrics) {
        emitStoreMetrics(bus.ptr, store.ptr);
    }
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

fn emitWasmRuntimeMetrics(bus: *metrics.Bus, emit_errors: bool) void {
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

    if (emit_errors) {
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

    var creates: [13]u32 = .{0} ** 13;
    var destroys: [5]u32 = .{0} ** 5;
    WasmImports.webgpuResourceCounts(&creates, &destroys);
    metrics.emitBus(true, bus, .{
        .webgpu_create_buffers = metrics.gauge(creates[0]),
        .webgpu_create_textures = metrics.gauge(creates[1]),
        .webgpu_create_views = metrics.gauge(creates[2]),
        .webgpu_create_samplers = metrics.gauge(creates[3]),
        .webgpu_create_bind_groups = metrics.gauge(creates[4]),
        .webgpu_create_pipelines = metrics.gauge(creates[5]),
        .webgpu_create_encoders = metrics.gauge(creates[6]),
        .webgpu_create_passes = metrics.gauge(creates[7]),
        .webgpu_frames_begun = metrics.gauge(creates[8]),
        .webgpu_frames_ended = metrics.gauge(creates[9]),
        .webgpu_frames_inflight = metrics.gauge(creates[10]),
        .webgpu_queue_wait_ms = metrics.gauge(creates[11]),
        .webgpu_queue_wait_max_ms = metrics.gauge(creates[12]),
    });
    metrics.emitBus(true, bus, .{
        .webgpu_destroy_buffers = metrics.gauge(destroys[0]),
        .webgpu_destroy_textures = metrics.gauge(destroys[1]),
        .webgpu_destroy_samplers = metrics.gauge(destroys[2]),
        .webgpu_destroy_bind_groups = metrics.gauge(destroys[3]),
        .webgpu_destroy_pipelines = metrics.gauge(destroys[4]),
    });
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

const WasmImports = if (builtin.target.cpu.arch.isWasm()) struct {
    extern "env" fn wasm_memory_bytes() u32;
    extern "env" fn wasm_js_heap(out_used: *u32, out_total: *u32) void;
    extern "env" fn wasm_audio_counts(out_buffers: *u32, out_active: *u32) void;
    extern "env" fn webgpu_device_lost(out_flag: *u32) void;
    extern "env" fn webgpu_error_counts(out_validation: *u32, out_out_of_memory: *u32, out_internal: *u32) void;
    extern "env" fn webgpu_resource_counts(out_creates: [*]u32, out_destroys: [*]u32) void;

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

    pub fn webgpuResourceCounts(out_creates: *[13]u32, out_destroys: *[5]u32) void {
        webgpu_resource_counts(out_creates.ptr, out_destroys.ptr);
    }
} else struct {
    pub fn memoryBytes() u64 {
        return 0;
    }

    pub fn audioCounts(_: *u32, _: *u32) void {}

    pub fn jsHeap(_: *u32, _: *u32) void {}

    pub fn deviceLost(_: *u32) void {}

    pub fn webgpuErrors(_: *u32, _: *u32, _: *u32) void {}

    pub fn webgpuResourceCounts(_: *[13]u32, _: *[5]u32) void {}
};

const builtin = @import("builtin");
const ecs = @import("ecs");
const metrics = @import("metrics");
const render = @import("render");
const MetricsModule = @import("MetricsModule.zig");
const RenderModule = @import("RenderModule.zig");
const RenderState = RenderModule.RenderState;
const Commands = ecs.Commands;
const AppCommands = ecs.AppCommands;
const Res = ecs.system_params.Res;
const ResMut = ecs.system_params.ResMut;
const ResOpt = ecs.system_params.ResOpt;
const WorldRef = ecs.system_params.WorldRef;
