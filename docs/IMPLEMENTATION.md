# Docs Site Implementation Notes

This document records the concrete repo surfaces that anchor the docs-site rollout.

## Current Source Of Truth

- prose seed: `docs/index.md`
- shared wasm template: `assets/web/index.html`
- wasm server: `lib/web/wasm_server.zig`
- public engine surface:
  - `src/root.zig`
  - `lib/modules/root.zig`
  - `lib/render/root.zig`
  - `lib/assets/root.zig`
- example build graph:
  - `build.zig`
  - `build_examples.zig`
  - `examples.zig`
- example projects: `examples/*`
- generated site output: `docs/_build/`

## Docs Tool Layout

- `tools/docs_site/`
  - `README.md`: package usage notes
  - `src/phasor_docs_site/`
    - `cli.py`: entrypoint
    - `config.py`: repo/output paths
    - `models.py`: shared dataclasses
    - `discovery.py`: repo and example discovery
    - `validation.py`: manifest/embed/discovery validation
    - `content.py`: markdown loading and embed expansion
    - `packaging.py`: example/source bundle generation
    - `render.py`: HTML site rendering

## Checked-In Metadata Scope

- `docs/site/features.json`
  - curated feature taxonomy shown on example cards and feature pages
- `docs/site/examples.json`
  - curated example metadata such as title, summary, screenshots, feature tags, and source file preferences
- `docs/site/navigation.json`
  - top-level site navigation and page ordering

## CLI Entry Points

- `uv run phasor-docs-site validate`
- `uv run phasor-docs-site generate`
- `uv run phasor-docs-site serve`

Matching Zig steps should call the same commands so docs validation can be run with the normal build workflow.
