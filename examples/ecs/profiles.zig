const std = @import("std");
const BenchmarkConfig = @import("bench_config.zig").BenchmarkConfig;

pub fn sine(cfg: BenchmarkConfig, frame: u64, dt: f32) i32 {
    const t = @as(f64, @floatFromInt(frame)) * @as(f64, dt);
    const wave = std.math.sin(t * @as(f64, cfg.sine_frequency));
    const rate = @as(f64, cfg.rate_per_second) * wave;
    return @as(i32, @intFromFloat(rate * @as(f64, dt)));
}

pub fn step(cfg: BenchmarkConfig, _: u64, dt: f32) i32 {
    const rate = @as(f64, cfg.rate_per_second);
    return @as(i32, @intFromFloat(rate * @as(f64, dt)));
}

pub fn burst(cfg: BenchmarkConfig, frame: u64, dt: f32) i32 {
    const t = @as(f64, @floatFromInt(frame)) * @as(f64, dt);
    const phase = @mod(t, @as(f64, cfg.burst_period));
    if (phase > @as(f64, cfg.burst_width)) return 0;
    const rate = @as(f64, cfg.rate_per_second) * 4.0;
    return @as(i32, @intFromFloat(rate * @as(f64, dt)));
}

pub fn ramp(cfg: BenchmarkConfig, frame: u64, dt: f32) i32 {
    const t = @as(f64, @floatFromInt(frame)) * @as(f64, dt);
    const rate = @as(f64, cfg.ramp_rate) * t;
    return @as(i32, @intFromFloat(rate * @as(f64, dt)));
}
