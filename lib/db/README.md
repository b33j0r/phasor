# phasor-lite db

A compact ECS storage layer focused on readable, predictable data movement.

## Goals

- Make row movement between tables fast and explicit.
- Keep schemas immutable and comparable at compile time.
- Separate storage from higher-level scheduling or query policy.

## Core types

- `meta.TypeId` and `meta.typeIdSet`: compile-time identifiers and schema sets.
- `Column`: owning, type-erased column storage.
- `Table`: owns columns + entity rows; supports copy/move semantics.
- `Database`: owns tables and entity locations; orchestrates moves.

## Table overview

- Schema is a `TypeIdSet` (sorted, unique, immutable).
- Rows are stored densely; removal uses swap-remove.
- `copyRowTo` copies shared components only (schema intersection).
- `MovePlan` is an ephemeral mapping of shared column indices.

## Database overview

- Tables are keyed by schema hash.
- Entity locations are tracked as `{table_index, row}`.
- `moveEntity` is the canonical operation for changing tables.
- Entity IDs are unique; creating an existing ID returns `Error.EntityAlreadyExists`.

## Invariants

- Table schema never changes.
- Moves copy shared components and do not create missing ones.
- Swap-remove updates the moved entity’s row.

## Notes

This module is designed to be a foundation for higher-level ECS features
(queries, schedules, and systems) without embedding policy in storage.
