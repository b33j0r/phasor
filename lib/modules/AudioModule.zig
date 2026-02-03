const AudioModule = @This();

pub fn install(app: *AppCommands, commands: *Commands) !void {
    if (!commands.hasResource(AudioState)) {
        try commands.insertResource(AudioState.init(commands.allocator));
    }
    try app.addSystem(schedule.DefaultSchedule.WindowCreate, initSystem);
    try app.addSystem(schedule.DefaultSchedule.Update, startSounds);
    try app.addSystem(schedule.DefaultSchedule.Update, updateSounds);
    try app.addSystem(schedule.DefaultSchedule.Shutdown, shutdownSystem);
}

pub fn uninstall(app: *AppCommands) void {
    app.removeSystem(initSystem);
    app.removeSystem(startSounds);
    app.removeSystem(updateSounds);
    app.removeSystem(shutdownSystem);
}

const AudioState = struct {
    allocator: std.mem.Allocator,
    initialized: bool = false,
    engine: Native.Engine = undefined,

    fn init(allocator: std.mem.Allocator) AudioState {
        return .{ .allocator = allocator };
    }
};

const SoundInstanceNative = Native.SoundInstance;
const SoundInstanceWeb = struct {
    handle: u32,
};

fn initSystem(audio_state: ResMut(AudioState)) !void {
    try Native.init(audio_state.ptr);
}

fn shutdownSystem(audio_state: ResMut(AudioState), instances: Query(.{ SoundInstanceNative })) !void {
    Native.shutdown(audio_state.ptr, instances);
}

fn startSounds(
    commands: *Commands,
    audio_state: ResMut(AudioState),
    assets_ctx_opt: ResOpt(assets.AssetsContext),
    players: Query(.{ audio.SoundPlayer, ecs.system_params.Without(SoundInstanceNative), ecs.system_params.Without(SoundInstanceWeb) }),
) !void {
    if (players.isEmpty()) return;

    if (builtin.target.cpu.arch.isWasm()) {
        var it = players.iterator();
        while (it.next()) |row| {
            const player = row.get(audio.SoundPlayer) orelse continue;
            const handle = try startSoundWeb(player.*);
            if (handle == 0) continue;
            try commands.addComponent(row.entity_id, SoundInstanceWeb{ .handle = handle });
        }
        return;
    }

    if (!audio_state.ptr.initialized) return;
    const assets_ctx = assets_ctx_opt.ptr orelse return;

    var it = players.iterator();
    while (it.next()) |row| {
        const player = row.get(audio.SoundPlayer) orelse continue;
        const inst = try Native.start(player.*, audio_state.ptr, assets_ctx.*);
        if (inst) |native_inst| {
            try commands.addComponent(row.entity_id, native_inst);
        }
    }
}

fn updateSounds(
    commands: *Commands,
    audio_state: ResMut(AudioState),
    players: Query(.{ audio.SoundPlayer, SoundInstanceNative }),
    web_players: Query(.{ audio.SoundPlayer, SoundInstanceWeb }),
) !void {
    if (!builtin.target.cpu.arch.isWasm()) {
        var it = players.iterator();
        while (it.next()) |row| {
            const player = row.get(audio.SoundPlayer) orelse continue;
            const inst = row.get(SoundInstanceNative) orelse continue;
            if (!player.one_shot) continue;
            if (Native.atEnd(inst)) {
                Native.uninit(audio_state.ptr, inst);
                try commands.removeEntity(row.entity_id);
            }
        }
        return;
    }

    var wit = web_players.iterator();
    while (wit.next()) |row| {
        const player = row.get(audio.SoundPlayer) orelse continue;
        const inst = row.get(SoundInstanceWeb) orelse continue;
        if (!player.one_shot) continue;
        if (!wasmAudioIsPlaying(inst.handle)) {
            try commands.removeEntity(row.entity_id);
        }
    }
}

fn startSoundWeb(player: audio.SoundPlayer) !u32 {
    var sound = player.source;
    if (sound.wasm_id == null) {
        const bytes = sound.bytesSlice() orelse return 0;
        sound.wasm_id = wasmAudioLoad(bytes.ptr, bytes.len);
    }
    const id = sound.wasm_id orelse return 0;
    return wasmAudioPlay(id, player.volume, if (player.loop) 1 else 0);
}

extern "env" fn wasmAudioLoad(ptr: [*]const u8, len: usize) u32;
extern "env" fn wasmAudioPlay(id: u32, volume: f32, loop: u32) u32;
extern "env" fn wasmAudioIsPlaying(handle: u32) bool;

const Native = if (builtin.target.cpu.arch.isWasm()) struct {
    const Engine = void;
    const SoundInstance = struct {};

    fn init(_: *AudioState) !void {}

    fn shutdown(_: *AudioState, _: Query(.{ SoundInstance })) void {}

    fn start(_: audio.SoundPlayer, _: *AudioState, _: assets.AssetsContext) !?SoundInstance {
        return null;
    }

    fn atEnd(_: *SoundInstance) bool {
        return true;
    }

    fn uninit(_: *AudioState, _: *SoundInstance) void {}
} else struct {
    const ma = @import("miniaudio").c;
    const Engine = ma.ma_engine;

    const SoundInstance = struct {
        sound: *ma.ma_sound,
        buffer: *ma.ma_audio_buffer_ref,
    };

    fn init(audio_state: *AudioState) !void {
        if (audio_state.initialized) return;
        var config = ma.ma_engine_config_init();
        const result = ma.ma_engine_init(&config, &audio_state.engine);
        if (result != ma.MA_SUCCESS) return error.AudioInitFailed;
        _ = ma.ma_engine_start(&audio_state.engine);
        audio_state.initialized = true;
    }

    fn shutdown(audio_state: *AudioState, instances: Query(.{ SoundInstance })) void {
        var it = instances.iterator();
        while (it.next()) |row| {
            const inst = row.get(SoundInstance) orelse continue;
            ma.ma_sound_uninit(inst.sound);
            audio_state.allocator.destroy(inst.sound);
            ma.ma_audio_buffer_ref_uninit(inst.buffer);
            audio_state.allocator.destroy(inst.buffer);
        }
        if (audio_state.initialized) {
            ma.ma_engine_uninit(&audio_state.engine);
            audio_state.initialized = false;
        }
    }

    fn start(player: audio.SoundPlayer, audio_state: *AudioState, assets_ctx: assets.AssetsContext) !?SoundInstance {
        const sound_asset = player.source;
        try ensureDecoded(sound_asset, assets_ctx);
        const decoded = sound_asset.decoded orelse return null;

        const buffer = try audio_state.allocator.create(ma.ma_audio_buffer_ref);
        buffer.* = undefined;
        const format = @as(ma.ma_format, @intCast(decoded.format));
        const channels: ma.ma_uint32 = @intCast(decoded.channels);
        const frame_count: ma.ma_uint64 = @intCast(decoded.frame_count);
        const result_buffer = ma.ma_audio_buffer_ref_init(format, channels, decoded.pcm.ptr, frame_count, buffer);
        if (result_buffer != ma.MA_SUCCESS) {
            std.log.warn("AudioModule: buffer init failed ({d})", .{result_buffer});
            audio_state.allocator.destroy(buffer);
            return null;
        }

        const sound = try audio_state.allocator.create(ma.ma_sound);
        sound.* = undefined;
        const result_sound = ma.ma_sound_init_from_data_source(&audio_state.engine, @ptrCast(buffer), 0, null, sound);
        if (result_sound != ma.MA_SUCCESS) {
            std.log.warn("AudioModule: sound init failed ({d})", .{result_sound});
            ma.ma_audio_buffer_ref_uninit(buffer);
            audio_state.allocator.destroy(buffer);
            audio_state.allocator.destroy(sound);
            return null;
        }

        ma.ma_sound_set_volume(sound, player.volume);
        ma.ma_sound_set_looping(sound, if (player.loop) ma.MA_TRUE else ma.MA_FALSE);
        _ = ma.ma_sound_start(sound);

        return SoundInstance{ .sound = sound, .buffer = buffer };
    }

    fn atEnd(inst: *SoundInstance) bool {
        return ma.ma_sound_at_end(inst.sound) == ma.MA_TRUE;
    }

    fn uninit(audio_state: *AudioState, inst: *SoundInstance) void {
        ma.ma_sound_uninit(inst.sound);
        audio_state.allocator.destroy(inst.sound);
        ma.ma_audio_buffer_ref_uninit(inst.buffer);
        audio_state.allocator.destroy(inst.buffer);
    }

    fn ensureDecoded(sound: *assets.Sound, ctx: assets.AssetsContext) !void {
        if (sound.decoded != null) return;

        const bytes = sound.bytesSlice() orelse return;

        var decoder: ma.ma_decoder = undefined;
        var config = ma.ma_decoder_config_init(ma.ma_format_f32, 0, 0);
        if (bytes.len < 4) {
            std.log.warn("AudioModule: decoder init failed (empty bytes)", .{});
            return;
        }
        const init_result = ma.ma_decoder_init_memory(bytes.ptr, bytes.len, &config, &decoder);
        if (init_result != ma.MA_SUCCESS) {
            std.log.warn("AudioModule: decoder init failed ({d}) len={d} header={x:0>2} {x:0>2} {x:0>2} {x:0>2}", .{
                init_result,
                bytes.len,
                bytes[0],
                bytes[1],
                bytes[2],
                bytes[3],
            });
            return;
        }
        defer _ = ma.ma_decoder_uninit(&decoder);

        var length: ma.ma_uint64 = 0;
        _ = ma.ma_decoder_get_length_in_pcm_frames(&decoder, &length);
        if (length == 0) return;

        const channels: u32 = @intCast(decoder.outputChannels);
        const sample_rate: u32 = @intCast(decoder.outputSampleRate);
        const frame_count: u64 = @intCast(length);
        const sample_count: usize = @intCast(frame_count * @as(u64, channels));

        const pcm = try ctx.allocator.alloc(f32, sample_count);
        errdefer ctx.allocator.free(pcm);

        var frames_read: ma.ma_uint64 = 0;
        _ = ma.ma_decoder_read_pcm_frames(&decoder, pcm.ptr, length, &frames_read);
        if (frames_read == 0) {
            std.log.warn("AudioModule: decoder read zero frames", .{});
            return;
        }

        const final_frames: u64 = @intCast(frames_read);
        sound.decoded = .{
            .format = @intCast(ma.ma_format_f32),
            .channels = channels,
            .sample_rate = sample_rate,
            .frame_count = final_frames,
            .pcm = pcm,
        };
    }
};

const std = @import("std");
const builtin = @import("builtin");
const ecs = @import("ecs");
const audio = @import("audio");
const assets = @import("assets");
const schedule = ecs.schedule;
const AppCommands = ecs.AppCommands;
const Commands = ecs.Commands;
const Query = ecs.system_params.Query;
const ResMut = ecs.system_params.ResMut;
const ResOpt = ecs.system_params.ResOpt;
