# `phasor-lite`

## Overview

A game library in zig latest based on ECS and WebGPU.

## Example

```zig
const phasor = @import("phasor");
const App = phasor.App;

pub fn main() !void {
    var app = try App.init();
    try app.run();
}
```
