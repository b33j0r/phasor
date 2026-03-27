# WASM

Browser builds use the same example projects, but the constraints are different enough that it helps to treat wasm as its own target instead of a checkbox on the side.

The main things to care about are:

- how the example is built and served
- whether assets are embedded or served in a browser-friendly way
- which startup path is being exercised by the wasm build

The `gltf` example is the clearest current reference because it has to solve both scene import and wasm asset packaging at the same time.
