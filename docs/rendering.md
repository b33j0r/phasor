# Rendering

Rendering in Phasor is ECS-first. Game code adds render components to entities;
the render module prepares meshes, extracts visible data into a `RenderQueue`,
and submits that queue to the native or WASM backend.

Keep user code at the component level:

- Use `ClearColor` for the frame background.
- Use `Sprite` for image-like quads; put the material on the sprite.
- Use `MeshInstance` for explicit mesh rendering.
- Use `BuildContext.meshFactory()` for generated meshes.
- Use asset-loaded `Texture.material` or `BuildContext.createMaterial()` for textured materials.
- Use `Layer`, `CameraLayer`, and `LayerSortKey` when draw order or multi-camera rendering matters.

Asset loading is covered in [assets.md](assets.md).

## Setup

Install the default modules, add a camera, and set a clear color:

```zig
pub fn main(init: std.process.Init) !u8 {
    var app = try App.init(&init, .{});
    defer app.deinit();

    try app.insertResource(WindowSettings{
        .title = "Rendering",
        .width = 800,
        .height = 600,
    });
    try app.insertResource(ClearColor{ .color = Color.WHITE });
    try app.installDefaultModules();
    try app.installModule(AssetsModule(Assets));

    try app.addSystem("Startup", setup);
    return try app.run();
}
```

```zig
fn setup(commands: *Commands) !void {
    _ = try commands.createEntity(.{
        Transform{},
        Camera3d{ .Viewport = .{ .mode = .TopLeft } },
        CameraLayer(0){},
    });
}
```

## Sprites

A sprite is a generated quad. `Sprite` owns the quad size, tint, and optional
material. The render module creates and maintains the underlying `MeshInstance`
for you.

```zig
const Assets = struct {
    logo: Texture = Texture.embedded(@embedFile("assets/logo.png")).asBlended(),
};

fn spawnLogo(commands: *Commands, assets: Res(Assets)) !void {
    _ = try commands.createEntity(.{
        Transform{ .translation = .{ .x = 400.0, .y = 300.0, .z = 0.0 } },
        Sprite{
            .material = assets.ptr.logo.material,
            .size_mode = .{ .Manual = .{ .width = 128.0, .height = 128.0 } },
            .source_size = .{ .width = assets.ptr.logo.width, .height = assets.ptr.logo.height },
        },
        Layer(0){},
    });
}
```

Use `.Auto` when `source_size` is available and you want image-sized quads. Use
`.Manual` for fixed world or screen dimensions.

## Meshes

Use `BuildContext.meshFactory()` for common generated shapes. Mesh handles are
stored on `MeshInstance`.

```zig
fn setupMesh(commands: *Commands, build_ctx: ResMut(BuildContext)) !void {
    var factory = build_ctx.ptr.meshFactory();
    const circle = try factory.circle(40.0, 48);

    _ = try commands.createEntity(.{
        Transform{ .translation = .{ .x = 200.0, .y = 160.0, .z = 0.0 } },
        MeshInstance{
            .mesh_handle = circle,
            .color = Color.RED,
        },
        Layer(0){},
    });
}
```

For custom geometry, call `BuildContext.addMesh*` with the vertex layout that
matches your shader or material path.

## Materials

`assets.Texture` creates both a texture handle and a `Material` value. The
material is usually what user code attaches to entities:

```zig
MeshInstance{
    .mesh_handle = mesh_handle,
    .material = assets.ptr.crate.material,
}
```

Sprites carry their material directly:

```zig
Sprite{
    .material = assets.ptr.icon.material,
    .size_mode = .{ .Manual = .{ .width = 32.0, .height = 32.0 } },
}
```

When building textures manually, create a material from a texture handle:

```zig
const texture = try build_ctx.ptr.createTextureRgba8(width, height, rgba);
const material_handle = try build_ctx.ptr.createMaterial(texture, null);
const material = Material.withTextured(material_handle);
```

Use `Material.AlphaMode.Opaque` for fully opaque assets and `.Blend` for
transparent sprites, particles, UI, and soft edges.

## Layers and Order

`Layer(0){}` is the default explicit layer. A camera with `CameraLayer(0){}` draws
that layer. Add `LayerSortKey` when entities in the same layer need stable
ordering:

```zig
_ = try commands.createEntity(.{
    Transform{ .translation = .{ .x = 40.0, .y = 40.0, .z = 0.0 } },
    Sprite{
        .material = assets.ptr.icon.material,
        .size_mode = .{ .Manual = .{ .width = 32.0, .height = 32.0 } },
    },
    Layer(0){},
    LayerSortKey{ .value = 10.0 },
});
```

## Practical Rules

Prefer the highest-level component that expresses the thing you are drawing.
Use `Sprite` for textured quads, `Text` for text, generated meshes for simple
shapes, and imported scenes for GLTF content. Keep backend objects behind
handles and assets; gameplay systems should rarely touch renderer backend types
directly.
