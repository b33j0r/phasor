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
            elif embed.kind == "include_lines":
                path_attr = embed.attributes.get("path")
                start_attr = embed.attributes.get("start")
                end_attr = embed.attributes.get("end")
                if not path_attr or not start_attr or not end_attr:
                    issues.append(ValidationIssue(f"include_lines missing attributes in {page.relative_path}: {embed.raw}"))
                    continue
                target = paths.repo_root / path_attr
                if not target.is_file():
                    issues.append(ValidationIssue(f"Embed path does not exist in {page.relative_path}: {path_attr}"))
                    continue
                try:
                    start_line = int(start_attr)
                    end_line = int(end_attr)
                except ValueError:
                    issues.append(ValidationIssue(f"include_lines has non-integer bounds in {page.relative_path}: {embed.raw}"))
                    continue
                line_count = len(target.read_text().splitlines())
                if start_line < 1 or end_line < start_line or end_line > line_count:
                    issues.append(
                        ValidationIssue(
                            f"include_lines range out of bounds in {page.relative_path}: {path_attr}:{start_line}-{end_line}"
                        )
                    )
            elif embed.kind in {"example_grid", "overview_cards", "feature_matrix", "feature_catalog", "command_block"}:
                continue
            else:
                issues.append(ValidationIssue(f"Unknown embed kind in {page.relative_path}: {embed.kind}"))

    page_paths = {page.relative_path.as_posix() for page in pages}
    for item in navigation:
        if item.path not in page_paths:
            issues.append(ValidationIssue(f"Navigation path does not exist: {item.path}"))

    return issues
