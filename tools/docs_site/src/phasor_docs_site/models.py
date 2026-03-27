from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path


@dataclass(frozen=True)
class ExampleManifestEntry:
    title: str
    summary: str
    feature_tags: list[str]
    screenshots: list[str]
    source_files: list[str]
    detail_priority: int = 0


@dataclass(frozen=True)
class FeatureCodeExample:
    path: str
    start: int
    end: int
    caption: str


@dataclass(frozen=True)
class FeatureManifestEntry:
    title: str
    summary: str
    paragraphs: list[str]
    code_example: FeatureCodeExample


@dataclass(frozen=True)
class ExampleRecord:
    name: str
    directory: Path
    wasm_supported: bool
    run_step: str
    wasm_build_step: str | None
    wasm_run_step: str | None
    local_run_step: str
    local_wasm_build_step: str | None
    local_wasm_run_step: str | None
    title: str
    summary: str
    feature_tags: list[str]
    source_files: list[str]
    detail_priority: int = 0
    screenshots: list[str] = field(default_factory=list)
    extra_files: list[str] = field(default_factory=list)
    all_source_files: list[str] = field(default_factory=list)
    live_demo_path: str | None = None


@dataclass(frozen=True)
class ExampleSourceFile:
    path: str
    language: str
    role: str
    highlighted: bool
    content: str


@dataclass(frozen=True)
class EmbedDirective:
    kind: str
    attributes: dict[str, str]
    raw: str


@dataclass(frozen=True)
class PageRecord:
    source_path: Path
    relative_path: Path
    title: str
    body: str
    embeds: list[EmbedDirective]
    rendered_html: str = ""


@dataclass(frozen=True)
class NavigationItem:
    title: str
    path: str
