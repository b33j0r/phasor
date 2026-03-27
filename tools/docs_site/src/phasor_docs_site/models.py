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
class FeatureManifestEntry:
    title: str
    summary: str


@dataclass(frozen=True)
class ExampleRecord:
    name: str
    directory: Path
    wasm_supported: bool
    run_step: str
    web_step: str | None
    title: str
    summary: str
    feature_tags: list[str]
    source_files: list[str]
    detail_priority: int = 0
    screenshots: list[str] = field(default_factory=list)
    extra_files: list[str] = field(default_factory=list)
    all_source_files: list[str] = field(default_factory=list)


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
