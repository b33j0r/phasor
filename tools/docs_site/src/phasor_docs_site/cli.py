from __future__ import annotations

import argparse
import threading
import webbrowser
from pathlib import Path

import uvicorn

from .audit import run_system_audit, write_system_audit
from .capture import capture_example_screenshots
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
    capture_parser = subparsers.add_parser(
        "capture-screenshots",
        help="Capture example screenshots from built wasm live demos into docs/site/static/images/examples",
    )
    capture_parser.add_argument("--example", action="append", default=[], help="Capture only the named example")
    capture_parser.add_argument("--chrome-bin", type=Path, default=None, help="Path to a Chrome or Chromium executable")
    capture_parser.add_argument("--host", default="127.0.0.1")
    capture_parser.add_argument("--port", type=int, default=8765)
    capture_parser.add_argument("--width", type=int, default=1600)
    capture_parser.add_argument("--height", type=int, default=1000)
    capture_parser.add_argument("--settle", type=float, default=4.0, help="Seconds to wait after navigation before capture")
    capture_parser.add_argument("--headed", action="store_true", help="Launch a visible browser instead of headless mode")
    capture_parser.add_argument("--chrome-arg", action="append", default=[], help="Extra Chrome arguments for capture")
    serve_parser = subparsers.add_parser("serve", help="Generate and serve the docs site with a FastAPI static server")
    serve_parser.add_argument("--host", default="127.0.0.1")
    serve_parser.add_argument("--port", type=int, default=8011)
    serve_parser.add_argument("--no-browser", action="store_true", help="Serve without opening a browser")
    serve_parser.add_argument("--no-open", action="store_true", help=argparse.SUPPRESS)
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

    if args.command == "capture-screenshots":
        generate_code = main([
            *(["--repo-root", str(args.repo_root)] if args.repo_root else []),
            *(["--output", str(args.output)] if args.output else []),
            "generate",
        ])
        if generate_code != 0:
            return generate_code
        manifest = load_example_manifest(paths)
        examples = discover_examples(paths, manifest)
        count = capture_example_screenshots(
            paths,
            examples,
            only_examples=args.example,
            chrome_bin=args.chrome_bin,
            host=args.host,
            port=args.port,
            viewport_width=args.width,
            viewport_height=args.height,
            settle_seconds=args.settle,
            headed=args.headed,
            extra_chrome_args=args.chrome_arg,
        )
        refresh_code = main([
            *(["--repo-root", str(args.repo_root)] if args.repo_root else []),
            *(["--output", str(args.output)] if args.output else []),
            "generate",
        ])
        if refresh_code != 0:
            return refresh_code
        print(f"captured screenshots: {count}")
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
        open_browser = not (args.no_browser or args.no_open)
        url = f"http://{args.host}:{args.port}/"
        if open_browser:
            print(f"opening browser: {url}")
            threading.Timer(0.35, lambda: webbrowser.open(url)).start()
        uvicorn.run(app, host=args.host, port=args.port)
        return 0

    parser.error(f"unsupported command: {args.command}")
    return 2
