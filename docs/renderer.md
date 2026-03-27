# Renderer

The renderer revolves around a small set of pieces you touch early: cameras decide what gets seen, layers decide which drawables belong together, `MeshInstance` carries most 3D content, and `Sprite` and `Text` cover the 2D side.

If you are trying to get something on screen, start with one startup system, one renderable, and one camera. The `triangle` example is the shortest version of that path.

{{ include_lines path="examples/triangle/main.zig" start="1" end="27" }}

From there, the next renderer decisions are usually:

- do I need a `Triangle`, `Sprite`, `Text`, or `MeshInstance`
- which `CameraLayer` should this draw on
- do I need a material or a custom shader yet
- is this still a single-camera scene, or do I need overlays and debug layers

The full render module surface is available at [lib/render/root.zig](/code/lib/render/root.zig), and the surrounding module tree is browsable at [/code/lib/render/](/code/lib/render/index.html).

The shared tags used across renderer examples and other guide pages are documented on the [Features](features.md) page.
