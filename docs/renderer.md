# Renderer

The renderer is the part of `phasor` that turns your world into something visible. In practice that means a small set of primitives matters much more than the full export list: cameras decide what gets seen, layers decide draw grouping, meshes and mesh instances carry most 3D scene content, sprites and text cover the 2D/UI side, and materials/shaders control how those things are drawn.

If you are trying to get something on screen, the first questions are usually:

- which camera is rendering this layer
- am I spawning a `MeshInstance`, `Sprite`, or `Text`
- which material or shader is attached
- do I need scene lighting, post-process, or debug views yet

The rest of this page should help the reader recognize those building blocks quickly before drilling into the larger API surface.

## Public Render API Surface

{{ include_file path="lib/render/root.zig" }}

## Feature Tags Used Across The Site

{{ feature_matrix }}
