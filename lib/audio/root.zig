//! Audio types for phasor.

pub const SoundPlayer = struct {
    source: *assets.Sound,
    volume: f32 = 1.0,
    one_shot: bool = true,
    loop: bool = false,
};

const assets = @import("assets");
