# Getting Started

The shortest path into `phasor` is to start from one of the example projects, then strip it down until only the pieces you need are left.

## What The Minimal App Looks Like

The `triangle` example is small enough to read top to bottom. It installs the default platform modules, adds one startup system, and spawns a triangle plus a camera.

{{ include_lines path="examples/triangle/main.zig" start="1" end="27" }}

## The First Commands To Care About

{{ command_block value="zig build run-triangle" }}

For the browser:

{{ command_block value="zig build run-triangle-wasm" }}

## What To Change First

- replace the startup scene with your own entities
- keep one camera and one layer until you need more structure
- use the example `build.zig` and `build.zig.zon` as the starting project shape
