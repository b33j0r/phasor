from __future__ import annotations

from dataclasses import dataclass

from .config import SitePaths
from .content import load_pages
from .discovery import discover_examples, load_example_manifest, load_feature_manifest, load_navigation


@dataclass(frozen=True)
class ValidationIssue:
    message: str


def validate(paths: SitePaths) -> list[ValidationIssue]:
    issues: list[ValidationIssue] = []
    example_manifest = load_example_manifest(paths)
    feature_manifest = load_feature_manifest(paths)
    navigation = load_navigation(paths)
    examples = discover_examples(paths, example_manifest)
    pages = load_pages(paths)
    example_names = {example.name for example in examples}

    for manifest_name in sorted(example_manifest):
        if manifest_name not in example_names:
            issues.append(ValidationIssue(f"Manifest example '{manifest_name}' is not present in build.zig managed child projects"))

    for example in examples:
        if not example.directory.is_dir():
            issues.append(ValidationIssue(f"Example directory missing: {example.directory}"))
            continue

        for source_file in example.source_files:
            candidate = example.directory / source_file
            if not candidate.is_file():
                issues.append(ValidationIssue(f"Missing source file for example '{example.name}': {candidate}"))

        for tag in example.feature_tags:
            if tag not in feature_manifest:
                issues.append(ValidationIssue(f"Unknown feature tag '{tag}' used by example '{example.name}'"))

    for page in pages:
        for embed in page.embeds:
            if embed.kind == "include_file":
                path_attr = embed.attributes.get("path")
                if not path_attr:
                    issues.append(ValidationIssue(f"Embed missing path attribute in {page.relative_path}: {embed.raw}"))
                    continue
                target = paths.repo_root / path_attr
                if not target.is_file():
                    issues.append(ValidationIssue(f"Embed path does not exist in {page.relative_path}: {path_attr}"))
            elif embed.kind in {"example_grid", "feature_matrix", "command_block"}:
                continue
            else:
                issues.append(ValidationIssue(f"Unknown embed kind in {page.relative_path}: {embed.kind}"))

    page_paths = {page.relative_path.as_posix() for page in pages}
    for item in navigation:
        if item.path not in page_paths:
            issues.append(ValidationIssue(f"Navigation path does not exist: {item.path}"))

    return issues
