# `phasor`

`phasor` is an ECS-first Zig game engine with native and browser WebGPU backends.

Zig `0.16-dev` APIs are assumed throughout the codebase.

The documentation and examples are being rewritten for the first release. The
previous generated docs site and example projects are preserved on the
`docs-old` branch and in the sibling checkout `../phasor_docs-old`.

## Package Name

Downstream projects should depend on `phasor` as dependency name `phasor` and import it with:

```zig
const phasor = @import("phasor");
```

## Build And Run

From `phasor/`:

```bash
zig build test
```
