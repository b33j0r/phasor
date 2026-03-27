from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class SitePaths:
    repo_root: Path
    docs_root: Path
    site_root: Path
    example_manifest: Path
    feature_manifest: Path
    navigation_manifest: Path
    output_root: Path


def detect_paths(repo_root: Path | None = None, output_root: Path | None = None) -> SitePaths:
    root = (repo_root or Path(__file__).resolve().parents[4]).resolve()
    docs_root = root / "docs"
    site_root = docs_root / "site"
    return SitePaths(
        repo_root=root,
        docs_root=docs_root,
        site_root=site_root,
        example_manifest=site_root / "examples.json",
        feature_manifest=site_root / "features.json",
        navigation_manifest=site_root / "navigation.json",
        output_root=(output_root or docs_root / "_build").resolve(),
    )
