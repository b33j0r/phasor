pub const FastNoise = fastnoise.Noise(f32);

pub const NoiseResource = struct {
    noise: FastNoise = .{},
};

pub const NoiseModule = struct {
    seed: i32 = 1337,
    frequency: f32 = 0.01,
    noise_type: fastnoise.NoiseType = .simplex,
    rotation_type: fastnoise.RotationType = .none,
    fractal_type: fastnoise.FractalType = .none,
    octaves: u32 = 3,
    lacunarity: f32 = 2.0,
    gain: f32 = 0.5,
    weighted_strength: f32 = 0.0,
    ping_pong_strength: f32 = 2.0,
    cellular_distance: fastnoise.CellularDistanceFunc = .euclidean_sq,
    cellular_return: fastnoise.CellularReturnType = .distance,

    pub fn install(self: *const @This(), app: *AppCommands, cmds: *Commands) !void {
        _ = app;
        var noise: FastNoise = .{};
        noise.seed = self.seed;
        noise.frequency = self.frequency;
        noise.noise_type = self.noise_type;
        noise.rotation_type = self.rotation_type;
        noise.fractal_type = self.fractal_type;
        noise.octaves = self.octaves;
        noise.lacunarity = self.lacunarity;
        noise.gain = self.gain;
        noise.weighted_strength = self.weighted_strength;
        noise.ping_pong_strength = self.ping_pong_strength;
        noise.cellular_distance = self.cellular_distance;
        noise.cellular_return = self.cellular_return;

        try cmds.insertResource(NoiseResource{ .noise = noise });
    }

    pub fn uninstall(_: *const @This(), _: *AppCommands, cmds: *Commands) void {
        _ = cmds.removeResource(NoiseResource);
    }
};

const ecs = @import("ecs");
const fastnoise = @import("fastnoise");
const AppCommands = ecs.AppCommands;
const Commands = ecs.Commands;
