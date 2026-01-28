# `phasor-lite`

## Overview

Lightweight ECS + storage layer for Zig, with a small example app and benchmarks.
Targets recent Zig nightlies.

## Example

```zig
const std = @import("std");
const phasor = @import("phasor");

pub fn main(init: std.process.Init) !u8 {
    var app = phasor.ecs.App.init(init.gpa, &init.io);
    defer app.deinit();

    return try app.run();
}
```

Use `ecs.resources.Exit{ .code = N }` from a system to end the run loop.

## Build & test

```
zig build
zig build run
zig build test
```

## ECS mutation

Direct database mutation is internal; systems should use `Commands`.

## Code conventions

- Place imports at the bottom of every file.

```zig
// ...
pub fn resourceTypeId(comptime T: type) meta.TypeId {
    return meta.typeId(T);
}

// Imports
const std = @import("std");
const meta = @import("../db/meta.zig");
```
