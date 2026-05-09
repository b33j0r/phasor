# WASM in Phasor

Phasor runs browser builds as a split runtime:

- Zig app code compiles to `app.wasm`.
- Browser/platform integration lives in JS (`webgpu.js`, `jolt_bridge.js`).

## Build and Run

Use `examples/ball/build.zig` as the canonical minimal pattern.

The important parts are:

- native executable + `run` step,
- wasm executable (`wasm32-wasi`) emitting `app.wasm`,
- install steps for web runtime files/assets,
- `wasm_server` run step as `run-wasm`.

For the ball example:

- `zig build run`
- `zig build run-wasm`

Phasor provides a dev server in `lib/web/wasm_server.zig`, but you should
use your own for production, or adapt it to your needs.

### What Gets Generated

For wasm runs, the build writes a web bundle under `zig-out/web/...`, including:

- `app.wasm` (generated from your Zig root source).
- copied web runtime files from `phasor/assets/web`.
- copied shader files needed by the web runtime.

### What's in the Assets

- `lib/web/wasm_server.zig`: local dev server used by `run-wasm` steps.
- `assets/web/index.html`: shell page with canvas and startup script reference.
- `assets/web/webgpu.js`: WebGPU + wasm host runtime.
- `extra/phasor-physics/*`: the optional physics library.
- `assets/web/jolt_bridge.js`: Jolt bridge imported by `webgpu.js`.
- `assets/web/vendor/jolt/*`: vendored Jolt JS runtime.

These are referenced from your `build.zig` file, so you can easily
swap any of them out for your own.