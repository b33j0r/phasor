# Sponza Asset Policy

Merge note:

- delete this branch-local planning note before merging `codex/physics`
- if needed, keep only a durable asset-source note in final merged docs

The target deliverable for the `codex/physics` branch is a simple FPS demo running in Sponza.

Asset policy:

- do not vendor Sponza assets into this repository
- download them from the upstream GitHub repository on first use
- keep downloaded assets in a local cache/work directory, not under tracked source control
- any build or runtime helper should make the first-use fetch explicit and repeatable

Physics/collision requirement:

- support a natural path for precompiled collision meshes
- prefer Zig build-step generation or comptime-assisted embedding for baked collision data where practical
- separate render meshes from baked collision meshes so gameplay startup does not need to rebuild large static collision data every run
