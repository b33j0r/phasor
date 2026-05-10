# Assets

Assets are ordinary fields in a user-defined struct. Installing
`AssetsModule(YourAssets)` inserts that struct as a resource, loads its fields in
`AssetsLoad` and `BeforeFrame`, and unloads them in `AssetsUnload`.

```zig
const Assets = struct {
    logo: Texture = Texture.embedded(@embedFile("assets/logo.png")).asBlended(),
    font: Font = Font.embedded("Ui", @embedFile("assets/ui.ttf")).withPixelHeight(32.0),
    click: Sound = .{ .data = @embedFile("assets/click.wav") },
    quad: Mesh = .{
        .uv_vertices = &quad_vertices,
        .indices = &quad_indices,
    },
    shader: Shader = .{
        .wgsl_source = @embedFile("assets/custom.wgsl"),
        .vertex_layout = .pos3_color4,
        .binding_mode = .none,
    },
    bloom: PostProcessShader = .{
        .wgsl_fragment = @embedFile("assets/bloom.frag.wgsl"),
    },
    scene: Scene = Scene.embedded(@embedFile("assets/scene.gltf")),
};
```

Supported asset field types:

- `Texture`: LDR or HDR image data. Produces `texture_handle`, `material_handle`,
  dimensions, and `material` for `Sprite.material` or `MeshInstance.material`.
- `Font`: TrueType font data. Produces a `FontHandle` and atlas-backed render font.
- `Sound`: Audio bytes for playback through the audio module.
- `Mesh`: Static mesh data using supported render vertex layouts.
- `Shader`: Custom mesh shader source and binding/layout metadata.
- `PostProcessShader`: Fragment snippet compiled into a post-process shader.
- `Scene`: Parsed GLTF scene data for imported-scene preparation.

Files can be loaded with constructors such as `Texture.file("logo.png")` or
embedded with `@embedFile`. On WASM, prefer embedded sources for assets that need
to be available inside the bundle.
