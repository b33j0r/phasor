# Renderer

The renderer is exposed as a public surface in `lib/render/root.zig`, coordinated by `RenderModule`, and then implemented per backend. That split is one of the main things the docs should surface clearly.

## Public Render API Surface

{{ include_file path="lib/render/root.zig" }}

## Feature Tags Used Across The Site

{{ feature_matrix }}
