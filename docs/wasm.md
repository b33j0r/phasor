# WASM

Browser builds use the same example projects, but they force a few decisions into the open earlier than native builds do.

The main ones are:

- how the app is served
- how assets are made available to the browser runtime
- whether the example still exercises the same renderer and scene path as native

## Representative Example

The `gltf` example is the clearest current reference because it has to solve scene import and wasm asset delivery at the same time.

## Embedded Asset Hydration

The wasm path does not assume a native-style filesystem read for the FlightHelmet scene. Instead, it embeds the source assets and hydrates missing buffer and image bytes before import.

{{ include_lines path="examples/gltf/main.zig" start="41" end="77" }}

{{ include_lines path="examples/gltf/main.zig" start="156" end="195" }}

## Build Commands

{{ command_block value="zig build web-gltf" }}

{{ command_block value="zig build run-gltf" }}
