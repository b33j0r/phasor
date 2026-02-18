# `phasor-lite`

ECS-first game library for Zig with native + wasm WebGPU backends.

## Quick Start

Run examples:

```bash
zig build run-triangle
zig build run-bouncing-ball
zig build run-cube
zig build run-ecs
zig build run-window
```

Wasm builds:

```bash
zig build run-triangle-wasm
zig build run-bouncing-ball-wasm
zig build run-cube-wasm
```

## ECS Tutorial

### 1. Build an app with modules and systems

From `examples/cube/main.zig`:

```zig
const App = struct {
    pub fn configure(app: *ecs.App) !void {
        try app.installModule(modules.TimeModule);
        try app.installModule(modules.ParentModule);
        try app.installModule(modules.RenderModule);

        try app.addSystemTo("Startup", setupScene);
        try app.addSystemTo("Update", spinCube);
    }
};

pub const main = platform.main(App);
```

### 2. Spawn entities as component tuples

From `examples/bouncing-ball/main.zig`:

```zig
const ball_entity = try commands.createEntity(.{
    Ball{ .radius = radius },
    Velocity{ .v = .{ .x = 220.0, .y = 160.0 } },
    Transform{ .translation = start },
    MeshInstance{ .mesh_handle = outer_mesh, .color = Color.BLACK },
});
```

### 3. Update state with typed queries and resources

From `examples/bouncing-ball/main.zig`:

```zig
fn integrateMotion(dt: Res(DeltaTime), query: Query(.{ Transform, Velocity })) void {
    const step: f32 = @floatCast(dt.deref().seconds);
    var it = query.iterator();
    while (it.next()) |row| {
        const transform = row.get(Transform) orelse continue;
        const velocity = row.get(Velocity) orelse continue;
        transform.translation.x += velocity.v.x * step;
        transform.translation.y += velocity.v.y * step;
    }
}
```

### 4. Use hierarchy components for local-space transforms

From `examples/cube/main.zig` and `examples/bouncing-ball/main.zig`:

```zig
_ = try commands.createEntity(.{
    Parent{ .id = parent_entity },
    LocalTransform{ .translation = .{ .x = 0.0, .y = 0.0, .z = 1.0 } },
    Transform{},
    Sprite{ .size_mode = .{ .Manual = .{ .width = 60.0, .height = 60.0 } } },
    MaterialInstance{ .material = material },
});
```

### 5. Use tags to scope system behavior

From `examples/cube/main.zig`:

```zig
const CubeRoot = struct {};

fn spinCube(elapsed: Res(ElapsedTime), query: Query(.{ Transform, CubeRoot })) void {
    // rotate only entities explicitly tagged as cube roots
}
```

## Examples at a Glance

- `triangle`: smallest render setup
- `bouncing-ball`: motion, collision, parent/child local transforms
- `cube`: 3D parent hierarchy + tag-scoped rotation
- `ecs`: pure ECS systems/events/phases (no rendering)
- `window`: window module only

## Serve WebGPU over HTTPS (LAN / Phone)

WebGPU requires a secure context for non-localhost devices.

```bash
mkcert -install
zig build run-cube-wasm -- --host 0.0.0.0 --https --no-open
```

Browse to your LAN hostname/IP over `https://...:8443`.

Notes:
- `0.0.0.0` is bind-only; do not browse to it directly.
- HTTPS proxy requires `python3`.
- To include a LAN IP in the cert:

```bash
mkcert -cert-file local/tls/phasor.pem -key-file local/tls/phasor-key.pem b3.local <LAN-IP> 127.0.0.1 ::1 localhost
```
