# Lighting And Skies

Lighting in `phasor` sits inside scene setup rather than off to the side. Cameras, materials, environment light, sky choice, and shadow settings all contribute to the final frame.

The examples currently show two sky workflows directly.

## Panorama Sky

The `warehouse` example uses a panorama texture as a sky entity that follows the camera and sits on its own layer behind the rest of the scene.

{{ include_lines path="examples/warehouse/main.zig" start="87" end="107" }}

## Procedural Sky

The `shadows` example uses `ProceduralSky` together with directional lighting, exposure settings, environment light, and shadow-map configuration.

{{ include_lines path="examples/shadows/main.zig" start="115" end="172" }}

{{ include_lines path="examples/shadows/main.zig" start="202" end="215" }}

## Main Reference Examples

- `warehouse` for panorama sky, audio, and first-person movement
- `shadows` for procedural sky, lighting, and shadows
- `sponza` for the deeper renderer tuning path
