from __future__ import annotations

import json
import re
from pathlib import Path

from .config import SitePaths
from .models import ExampleManifestEntry, ExampleRecord, FeatureCodeExample, FeatureManifestEntry, NavigationItem


MANAGED_PROJECT_RE = re.compile(
    r'\.\{\s*\.name = "([^"]+)",\s*\.dir = "([^"]+)",\s*\.enable_wasm = (true|false),',
    re.MULTILINE,
)


def load_example_manifest(paths: SitePaths) -> dict[str, ExampleManifestEntry]:
    raw = json.loads(paths.example_manifest.read_text())
    result: dict[str, ExampleManifestEntry] = {}
    for name, entry in raw["examples"].items():
        result[name] = ExampleManifestEntry(
            title=entry["title"],
            summary=entry["summary"],
            feature_tags=list(entry["feature_tags"]),
            screenshots=list(entry.get("screenshots", [])),
            source_files=list(entry["source_files"]),
            detail_priority=int(entry.get("detail_priority", 0)),
        )
    return result


def load_feature_manifest(paths: SitePaths) -> dict[str, FeatureManifestEntry]:
    raw = json.loads(paths.feature_manifest.read_text())
    result: dict[str, FeatureManifestEntry] = {}
    for name, entry in raw["features"].items():
        result[name] = FeatureManifestEntry(
            title=entry["title"],
            summary=entry["summary"],
            paragraphs=list(entry["paragraphs"]),
            code_example=FeatureCodeExample(
                path=entry["code_example"]["path"],
                start=int(entry["code_example"]["start"]),
                end=int(entry["code_example"]["end"]),
                caption=entry["code_example"]["caption"],
            ),
        )
    return result


def load_navigation(paths: SitePaths) -> list[NavigationItem]:
    raw = json.loads(paths.navigation_manifest.read_text())
    return [NavigationItem(title=item["title"], path=item["path"]) for item in raw["items"]]


def discover_examples(paths: SitePaths, manifests: dict[str, ExampleManifestEntry]) -> list[ExampleRecord]:
    build_text = (paths.repo_root / "build.zig").read_text()
    records: list[ExampleRecord] = []
    for name, relative_dir, wasm_supported_text in MANAGED_PROJECT_RE.findall(build_text):
        manifest = manifests.get(name)
        example_dir = paths.repo_root / relative_dir
        discovered_files = discover_example_files(example_dir)
        highlighted_files = sorted(
            {
                "build.zig",
                "build.zig.zon",
                "build_phasor.zig",
                "main.zig",
                *(manifest.source_files if manifest else []),
            }
        )
        inferred_tags = infer_example_feature_tags(name, example_dir)
        feature_tags = manifest.feature_tags if manifest else inferred_tags
        extra_files = [path for path in discovered_files if path not in highlighted_files]
        records.append(
            ExampleRecord(
                name=name,
                directory=example_dir,
                wasm_supported=wasm_supported_text == "true",
                run_step=f"zig build run-{name}",
                web_step=f"zig build web-{name}" if wasm_supported_text == "true" else None,
                local_run_step="zig build run",
                local_web_step="zig build web" if wasm_supported_text == "true" else None,
                title=manifest.title if manifest else name,
                summary=manifest.summary if manifest else f"{name} example",
                feature_tags=feature_tags,
                source_files=highlighted_files,
                detail_priority=manifest.detail_priority if manifest else 0,
                screenshots=manifest.screenshots if manifest else [],
                extra_files=extra_files,
                all_source_files=discovered_files,
                live_demo_path=discover_live_demo_path(name, example_dir, wasm_supported_text == "true"),
            )
        )
    records.sort(key=lambda item: item.name)
    return records


def discover_example_files(example_dir: Path) -> list[str]:
    return sorted(
        path.relative_to(example_dir).as_posix()
        for path in example_dir.rglob("*")
        if path.is_file()
        and not any(part in {".zig-cache", "zig-out", "zig-pkg", ".git"} for part in path.relative_to(example_dir).parts)
        and path.suffix in {".zig", ".wgsl", ".md", ".zon"}
    )


def discover_live_demo_path(name: str, example_dir: Path, wasm_supported: bool) -> str | None:
    if not wasm_supported:
        return None
    web_root = example_dir / "zig-out" / "web"
    index_path = web_root / "index.html"
    if not index_path.is_file():
        return None
    return f"live/examples/{name}/index.html"


def infer_example_feature_tags(name: str, example_dir: Path) -> list[str]:
    tags: set[str] = set()
    main_source = example_dir / "main.zig"
    contents = main_source.read_text() if main_source.is_file() else ""
    full_text = contents
    for path in example_dir.rglob("*.zig"):
        if path == main_source:
            continue
        full_text += "\n" + path.read_text()
    if "Triangle" in full_text or name == "triangle":
        tags.add("render-bootstrap")
    if "Camera3d" in full_text or "CameraLayer" in full_text:
        tags.add("camera")
    if "Sprite" in full_text:
        tags.add("sprites")
    if "buildParticleGeometry" in full_text or "Particle" in full_text:
        tags.add("particles")
    if "PhysicsModule" in full_text or "physics." in full_text:
        tags.add("physics")
    if "ImportedScene" in full_text or "assets.Scene" in full_text:
        tags.add("scene-import")
    if "PreparedImportedScene" in full_text:
        tags.add("prepared-scene")
    if "SkyModule.PanoramaSky" in full_text:
        tags.add("panorama-sky")
    if "SkyModule.ProceduralSky" in full_text:
        tags.add("procedural-sky")
    if "ColorGradingSettings" in full_text:
        tags.add("color-grading")
    if "NormalMapScale" in full_text:
        tags.add("normal-maps")
    if "EnvironmentLight" in full_text or "SceneEnvironmentMap" in full_text:
        tags.add("lighting")
    if "SoundPlayer" in full_text or "AudioModule" in full_text:
        tags.add("audio")
    if "FpsPhysicsModule" in full_text:
        tags.add("fps-controller")
    if "assets.Scene" in full_text or "MeshInstance" in full_text:
        tags.add("renderer-3d")
    if "embedded_assets" in full_text or "builtin.target.cpu.arch.isWasm()" in full_text:
        tags.add("wasm-assets")
    if "scene_pbr_lit" in full_text or "pbr_params" in full_text:
        tags.add("pbr")
    return sorted(tags)
