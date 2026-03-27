from __future__ import annotations

import json
from pathlib import Path

from .models import ExampleRecord, ExampleSourceFile


def build_example_index(examples: list[ExampleRecord], output_root: Path) -> Path:
    output_root.mkdir(parents=True, exist_ok=True)
    output_path = output_root / "examples.json"
    payload = {
        "examples": [
            {
                "name": example.name,
                "title": example.title,
                "summary": example.summary,
                "wasm_supported": example.wasm_supported,
                "run_step": example.run_step,
                "web_step": example.web_step,
                "feature_tags": example.feature_tags,
                "source_files": example.source_files,
                "extra_files": example.extra_files,
                "bundle_path": f"examples/{example.name}.json",
            }
            for example in examples
        ]
    }
    output_path.write_text(json.dumps(payload, indent=2) + "\n")
    return output_path


def build_example_bundles(examples: list[ExampleRecord], output_root: Path) -> list[Path]:
    bundles_root = output_root / "examples"
    bundles_root.mkdir(parents=True, exist_ok=True)
    written: list[Path] = []
    for example in examples:
        bundle_path = bundles_root / f"{example.name}.json"
        files = [
            serialize_source_file(example, rel_path, highlighted=True)
            for rel_path in example.source_files
        ]
        files.extend(
            serialize_source_file(example, rel_path, highlighted=False)
            for rel_path in example.extra_files
        )
        payload = {
            "name": example.name,
            "title": example.title,
            "summary": example.summary,
            "wasm_supported": example.wasm_supported,
            "run_step": example.run_step,
            "web_step": example.web_step,
            "feature_tags": example.feature_tags,
            "files": files,
        }
        bundle_path.write_text(json.dumps(payload, indent=2) + "\n")
        written.append(bundle_path)
    return written


def serialize_source_file(example: ExampleRecord, rel_path: str, *, highlighted: bool) -> dict[str, str | bool]:
    source = ExampleSourceFile(
        path=rel_path,
        language=language_for_path(rel_path),
        role=role_for_path(rel_path),
        highlighted=highlighted,
        content=(example.directory / rel_path).read_text(),
    )
    return {
        "path": source.path,
        "language": source.language,
        "role": source.role,
        "highlighted": source.highlighted,
        "content": source.content,
    }


def language_for_path(rel_path: str) -> str:
    suffix = Path(rel_path).suffix
    if suffix == ".zig":
        return "zig"
    if suffix == ".wgsl":
        return "wgsl"
    if suffix == ".md":
        return "markdown"
    if suffix == ".zon":
        return "zig"
    return "text"


def role_for_path(rel_path: str) -> str:
    name = Path(rel_path).name
    if name == "build.zig":
        return "build"
    if name == "build.zig.zon":
        return "dependency-config"
    if name == "build_phasor.zig":
        return "example-support"
    if name == "main.zig":
        return "entrypoint"
    if rel_path.endswith(".wgsl"):
        return "shader"
    return "source"
