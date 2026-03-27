# Scenes And Assets

This part of the engine covers the path from authored content to something the renderer can draw.

That usually means three layers of concern:

- how assets are loaded or embedded
- how imported scene data becomes runtime entities and renderables
- how large scenes are prepared, staged, and applied without turning startup into one long blocking step

The `gltf` and `sponza` examples are the best current anchors for this section.
