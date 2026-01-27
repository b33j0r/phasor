pub const BenchmarkConfig = struct {
    max_entities: usize = 200_000,
    initial_entities: usize = 50_000,
    gravity: f32 = -9.8,

    warmup_frames: u64 = 120,
    sample_frames: u64 = 600,

    rate_per_second: f32 = 30_000,
    sine_frequency: f32 = 2.0,
    burst_period: f32 = 2.5,
    burst_width: f32 = 0.2,
    ramp_rate: f32 = 10_000,
};
