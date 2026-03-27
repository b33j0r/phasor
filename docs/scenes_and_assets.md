# Scenes And Assets

This part of the engine covers the path from authored content to runtime entities and renderables.

For most projects, that means three layers of concern:

- where the source data comes from
- how imported data becomes ECS entities and meshes
- whether scene preparation happens eagerly or as a staged workflow

## Importing A Scene

The `gltf` example shows the direct path. A scene asset becomes parsed scene data, then `ImportedScene.instantiate` turns that data into runtime entities under a pivot entity.

{{ include_lines path="examples/gltf/main.zig" start="49" end="79" }}

## What To Read Next

- `gltf` for the direct import path
- `sponza` for the prepared-scene and large-scene workflow
- `wasm` for the browser-specific asset packaging constraints
