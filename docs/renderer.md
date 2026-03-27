# Renderer

The renderer is built around a few core pieces. Cameras decide what gets seen. Layers decide which drawables belong together. `MeshInstance` carries most 3D scene content. `Sprite` and `Text` cover the 2D side. Materials and shaders decide how those things are drawn.

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
