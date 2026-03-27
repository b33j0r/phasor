from __future__ import annotations

import argparse
from pathlib import Path

import uvicorn

from .audit import run_system_audit, write_system_audit
from .config import detect_paths
from .content import load_pages, render_pages
from .discovery import discover_examples, load_example_manifest, load_feature_manifest, load_navigation
from .packaging import build_example_bundles, build_example_index
from .render import render_site
from .server import create_app
from .validation import validate


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="phasor docs site generator")
    parser.add_argument("--repo-root", type=Path, default=None)
    parser.add_argument("--output", type=Path, default=None)
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("validate", help="Validate manifests, embeds, and discovered examples")
    subparsers.add_parser("generate", help="Generate the docs site scaffold and machine-readable example index")
    subparsers.add_parser("audit-systems", help="Audit registered systems, their params, and hidden data access patterns")
    serve_parser = subparsers.add_parser("serve", help="Generate and serve the docs site with a FastAPI static server")
    serve_parser.add_argument("--host", default="127.0.0.1")
    serve_parser.add_argument("--port", type=int, default=8011)
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    paths = detect_paths(repo_root=args.repo_root, output_root=args.output)

    if args.command == "validate":
        issues = validate(paths)
        if issues:
            for issue in issues:
                print(f"error: {issue.message}")
            return 1
        print("validation ok")
        return 0

    if args.command == "generate":
        issues = validate(paths)
        if issues:
            for issue in issues:
                print(f"error: {issue.message}")
            return 1
        example_manifest = load_example_manifest(paths)
        feature_manifest = load_feature_manifest(paths)
        navigation = load_navigation(paths)
        examples = discover_examples(paths, example_manifest)
        pages = render_pages(paths, load_pages(paths), examples, feature_manifest)
        data_root = paths.output_root / "data"
        build_example_index(examples, data_root)
        build_example_bundles(examples, data_root)
        index_path = render_site(paths.repo_root, paths.output_root, pages, examples, feature_manifest, navigation)
        print(f"generated site: {index_path}")
        return 0

    if args.command == "audit-systems":
        report = run_system_audit(paths)
        json_path, md_path = write_system_audit(paths, report)
        print(f"system audit written: {md_path}")
        print(f"json report written: {json_path}")
        print(
            "summary: "
            f"{len(report.registrations)} systems, "
            f"{len(report.findings)} system findings, "
            f"{len(report.lifecycle_findings)} lifecycle findings"
        )
        return 0

    if args.command == "serve":
        generate_code = main([
            *(["--repo-root", str(args.repo_root)] if args.repo_root else []),
            *(["--output", str(args.output)] if args.output else []),
            "generate",
        ])
        if generate_code != 0:
            return generate_code
        app = create_app(paths)
        uvicorn.run(app, host=args.host, port=args.port)
        return 0

    parser.error(f"unsupported command: {args.command}")
    return 2
