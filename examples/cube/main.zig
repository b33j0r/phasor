//! A simple cube example using explicit mesh and shader data in the Phasor game engine.

pub fn main(init: std.process.Init) !u8 {
    var app = try App.init(&init, .{
        // This is the maximum number of commands that a system can issue in a single frame.
        // If this limit is exceeded, the app will crash with an error.
        .command_queue_capacity = 64,

        // Enabling parallel systems allows the app to execute systems in parallel when possible,
        // which can improve performance on multi-core CPUs. It won't make a difference in this example.
        .parallel_systems = true,
    });

    // Clean up the app at the end of this function.
    defer app.deinit();

    // Several of the modules use one or more resources for configuration.
    // WindowSettings works with the WindowModule to configure the window.
    try app.insertResource(WindowSettings{
        .title = "Cube",
        .width = 900,
        .height = 700,
    });

    // TODO: move VSync into the WindowSettings resource.
    try app.insertResource(VSync{ .enabled = false });

    // ClearColor is used by the RenderModule to clear the screen at the beginning of each frame.
    try app.insertResource(ClearColor{ .color = Color.BLACK });

    // This installs the time, timer, window, render, input, audio, and parent modules.
    try app.installDefaultModules();

    // AssetsModule loads the mesh and shader data declared in the Assets struct below.
    try app.installModule(AssetsModule(Assets));

    // This displays diagnostic text such as the FPS counter and frame time in the
    // bottom-right corner of the screen.
    try app.installModule(MetricsModuleLayered(Layer(1000)){
        .font_size = 24.0,
        .text_color = Color.WHITE,
    });

    // Register our system functions. The first argument is the schedule that the system should
    // run in, and the second argument is the system function itself.

    // Startup happens once when the app starts.
    try app.addSystem("Startup", setup);

    // Update happens every frame after Startup.
    try app.addSystem("Update", spinCube);

    // Finally, run the app. This will block until the app is exited.
    return try app.run();
}

// Components

// Cube marks which mesh should rotate.
const Cube = struct {};

// Assets

// This struct declares the assets that AssetsModule should load.
const Assets = struct {
    // The cube mesh uses 3D positions and colors. Vertices are duplicated per
    // face so each face can have its own color.
    cube_mesh: Mesh = .{
        .pos3_color_vertices = cube_vertices[0..],
        .indices = cube_indices[0..],
    },

    // The shader uses the vertex colors for each face and derives a grid from
    // the local cube position, so the example can show custom mesh data without
    // also needing a texture file.
    cube_shader: Shader = .{
        .wgsl_source = cube_shader_wgsl,
        .vertex_layout = .pos3_color4,
        .binding_mode = .none,
    },
};

// Systems

fn setup(
    commands: *Commands,
    r_assets: Res(Assets),
) !void {
    const assets = r_assets.ptr;
    if (!assets.cube_mesh.handle.isValid()) return error.CubeMeshMissing;
    if (!assets.cube_shader.handle.isValid()) return error.CubeShaderMissing;

    // Create the cube entity.
    _ = try commands.createEntity(.{
        Cube{},
        Transform{ .translation = .{ .x = 0.0, .y = 0.0, .z = -4.0 } },
        MeshInstance{
            .mesh_handle = assets.cube_mesh.handle,
            .material = Material.withShader(assets.cube_shader.handle),
        },
    });

    // Create a perspective camera looking down the negative Z axis.
    _ = try commands.createEntity(.{
        Transform{},
        Camera3d{ .Perspective = .{
            .fov = std.math.pi / 3.0,
            .near = 0.1,
            .far = 100.0,
        } },
        CameraLayer(0){},
    });

    // Create a viewport camera for 2D overlay text such as the FPS counter.
    _ = try commands.createEntity(.{
        Transform{},
        Camera3d{ .Viewport = .{ .mode = .TopLeft } },
        CameraLayer(1000){},
    });
}

fn spinCube(elapsed: Res(ElapsedTime), query: Query(.{ Transform, Cube })) !void {
    // ElapsedTime tells us how long the app has been running.
    const t: f32 = @floatCast(elapsed.deref().seconds);

    // Query gives us every entity that has both Transform and Cube.
    var it = query.iterator();
    while (it.next()) |row| {
        const transform = row.get(Transform) orelse continue;

        // Rotate around two axes so the cube exposes all six faces over time.
        const rot_x = Quat.fromAxisAngle(.{ .x = 1.0 }, t * 0.7);
        const rot_y = Quat.fromAxisAngle(.{ .y = 1.0 }, t * 1.1);
        transform.rotation = rot_y.mul(rot_x).normalize();
    }
}

// Mesh data

// Each face has its own four vertices. That lets every face have its own color
// without sharing vertices with its neighbors.
const cube_vertices = [_]VertexPos3Color{
    // Front face.
    .{ .position = .{ -1.0, -1.0, 1.0 }, .color = neon_cyan },
    .{ .position = .{ 1.0, -1.0, 1.0 }, .color = neon_cyan },
    .{ .position = .{ 1.0, 1.0, 1.0 }, .color = neon_cyan },
    .{ .position = .{ -1.0, 1.0, 1.0 }, .color = neon_cyan },

    // Back face.
    .{ .position = .{ 1.0, -1.0, -1.0 }, .color = neon_violet },
    .{ .position = .{ -1.0, -1.0, -1.0 }, .color = neon_violet },
    .{ .position = .{ -1.0, 1.0, -1.0 }, .color = neon_violet },
    .{ .position = .{ 1.0, 1.0, -1.0 }, .color = neon_violet },

    // Right face.
    .{ .position = .{ 1.0, -1.0, 1.0 }, .color = neon_green },
    .{ .position = .{ 1.0, -1.0, -1.0 }, .color = neon_green },
    .{ .position = .{ 1.0, 1.0, -1.0 }, .color = neon_green },
    .{ .position = .{ 1.0, 1.0, 1.0 }, .color = neon_green },

    // Left face.
    .{ .position = .{ -1.0, -1.0, -1.0 }, .color = neon_magenta },
    .{ .position = .{ -1.0, -1.0, 1.0 }, .color = neon_magenta },
    .{ .position = .{ -1.0, 1.0, 1.0 }, .color = neon_magenta },
    .{ .position = .{ -1.0, 1.0, -1.0 }, .color = neon_magenta },

    // Top face.
    .{ .position = .{ -1.0, 1.0, 1.0 }, .color = neon_yellow },
    .{ .position = .{ 1.0, 1.0, 1.0 }, .color = neon_yellow },
    .{ .position = .{ 1.0, 1.0, -1.0 }, .color = neon_yellow },
    .{ .position = .{ -1.0, 1.0, -1.0 }, .color = neon_yellow },

    // Bottom face.
    .{ .position = .{ -1.0, -1.0, -1.0 }, .color = neon_orange },
    .{ .position = .{ 1.0, -1.0, -1.0 }, .color = neon_orange },
    .{ .position = .{ 1.0, -1.0, 1.0 }, .color = neon_orange },
    .{ .position = .{ -1.0, -1.0, 1.0 }, .color = neon_orange },
};

const neon_cyan = .{ 0.0, 0.95, 1.0, 1.0 };
const neon_violet = .{ 0.45, 0.2, 1.0, 1.0 };
const neon_green = .{ 0.0, 1.0, 0.35, 1.0 };
const neon_magenta = .{ 1.0, 0.1, 0.75, 1.0 };
const neon_yellow = .{ 1.0, 0.95, 0.15, 1.0 };
const neon_orange = .{ 1.0, 0.35, 0.0, 1.0 };

// Each face is drawn as two triangles.
const cube_indices = [_]u16{
    0,  1,  2,  0,  2,  3,
    4,  5,  6,  4,  6,  7,
    8,  9,  10, 8,  10, 11,
    12, 13, 14, 12, 14, 15,
    16, 17, 18, 16, 18, 19,
    20, 21, 22, 20, 22, 23,
};

// Shader data

// This shader takes 3D position and color vertex data. The renderer provides the
// transform matrix and per-instance color after the vertex attributes.
const cube_shader_wgsl =
    \\struct VertexIn {
    \\    @location(0) position: vec3<f32>,
    \\    @location(1) color: vec4<f32>,
    \\    @location(2) model0: vec4<f32>,
    \\    @location(3) model1: vec4<f32>,
    \\    @location(4) model2: vec4<f32>,
    \\    @location(5) model3: vec4<f32>,
    \\    @location(6) instance_color: vec4<f32>,
    \\};
    \\
    \\struct VertexOut {
    \\    @builtin(position) position: vec4<f32>,
    \\    @location(0) local_position: vec3<f32>,
    \\    @location(1) face_color: vec4<f32>,
    \\    @location(2) instance_color: vec4<f32>,
    \\};
    \\
    \\@vertex
    \\fn vs_main(input: VertexIn) -> VertexOut {
    \\    let model = mat4x4<f32>(input.model0, input.model1, input.model2, input.model3);
    \\    var out: VertexOut;
    \\    out.position = model * vec4<f32>(input.position, 1.0);
    \\    out.local_position = input.position;
    \\    out.face_color = input.color;
    \\    out.instance_color = input.instance_color;
    \\    return out;
    \\}
    \\
    \\fn faceUv(position: vec3<f32>) -> vec2<f32> {
    \\    if (position.x > 0.9) {
    \\        return position.zy * vec2<f32>(-0.5, 0.5) + vec2<f32>(0.5);
    \\    }
    \\    if (position.x < -0.9) {
    \\        return position.zy * vec2<f32>(0.5, 0.5) + vec2<f32>(0.5);
    \\    }
    \\    if (position.y > 0.9) {
    \\        return position.xz * vec2<f32>(0.5, -0.5) + vec2<f32>(0.5);
    \\    }
    \\    if (position.y < -0.9) {
    \\        return position.xz * vec2<f32>(0.5, 0.5) + vec2<f32>(0.5);
    \\    }
    \\    if (position.z > 0.9) {
    \\        return position.xy * vec2<f32>(0.5, -0.5) + vec2<f32>(0.5);
    \\    }
    \\    return position.xy * vec2<f32>(-0.5, -0.5) + vec2<f32>(0.5);
    \\}
    \\
    \\fn internalGridLine(coord: f32) -> f32 {
    \\    let scaled = coord * 6.0;
    \\    let cell = fract(scaled);
    \\    let distance = min(cell, 1.0 - cell);
    \\    let line = 1.0 - smoothstep(0.018, 0.045, distance);
    \\    let not_border = step(0.08, scaled) * step(0.08, 6.0 - scaled);
    \\    return line * not_border;
    \\}
    \\
    \\@fragment
    \\fn fs_main(input: VertexOut) -> @location(0) vec4<f32> {
    \\    let uv = faceUv(input.local_position);
    \\    let base = input.face_color.rgb;
    \\    let grid = max(internalGridLine(uv.x), internalGridLine(uv.y));
    \\    let color = base * 0.5 + vec3<f32>(0.1, 0.95, 1.0) * grid * 0.72 + vec3<f32>(0.05, 0.08, 0.12);
    \\    return vec4<f32>(color, 1.0) * input.instance_color;
    \\}
;

// Imports
const std = @import("std");
const phasor = @import("phasor");

const App = phasor.App;

const AssetsModule = phasor.AssetsModule;
const Camera3d = phasor.Camera3d;
const CameraLayer = phasor.CameraLayer;
const ClearColor = phasor.ClearColor;
const Color = phasor.Color;
const Commands = phasor.Commands;
const ElapsedTime = phasor.ElapsedTime;
const Layer = phasor.Layer;
const Material = phasor.Material;
const Mesh = phasor.Mesh;
const MeshInstance = phasor.MeshInstance;
const MetricsModuleLayered = phasor.MetricsModuleLayered;
const Query = phasor.Query;
const Quat = phasor.Quat;
const Res = phasor.Res;
const Shader = phasor.Shader;
const Transform = phasor.Transform;
const VertexPos3Color = phasor.VertexPos3Color;
const VSync = phasor.VSync;
const WindowSettings = phasor.WindowSettings;
