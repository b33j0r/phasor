from __future__ import annotations

import html
import json
import shutil
from pathlib import Path

from .models import ExampleRecord, NavigationItem, PageRecord


def render_site(
    output_root: Path,
    pages: list[PageRecord],
    examples: list[ExampleRecord],
    navigation: list[NavigationItem],
) -> Path:
    output_root.mkdir(parents=True, exist_ok=True)
    copy_static_assets(output_root, Path(__file__).resolve().parents[4] / "docs" / "site" / "static")
    write_search_index(output_root, pages, examples)

    nav_html = render_nav(navigation)
    for page in pages:
        target_path = output_root / page.relative_path.with_suffix(".html")
        target_path.parent.mkdir(parents=True, exist_ok=True)
        target_path.write_text(render_document(page.title, nav_html, page.rendered_html))

    index_page = next((page for page in pages if page.relative_path.as_posix() == "index.md"), None)
    return output_root / (index_page.relative_path.with_suffix(".html") if index_page else Path("index.html"))


def render_nav(navigation: list[NavigationItem]) -> str:
    links = "".join(
        f'<a class="nav-link" href="{html.escape(Path(item.path).with_suffix(".html").as_posix())}">{html.escape(item.title)}</a>'
        for item in navigation
    )
    return f'<nav class="site-nav">{links}</nav>'


def render_document(title: str, nav_html: str, body_html: str) -> str:
    return (
        "<!doctype html>\n"
        "<html lang=\"en\">\n"
        "<head>\n"
        "  <meta charset=\"utf-8\">\n"
        "  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n"
        f"  <title>{html.escape(title)}</title>\n"
        "  <link rel=\"preconnect\" href=\"https://fonts.googleapis.com\">\n"
        "  <link rel=\"preconnect\" href=\"https://fonts.gstatic.com\" crossorigin>\n"
        "  <link href=\"https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500&family=Space+Grotesk:wght@400;500;700&display=swap\" rel=\"stylesheet\">\n"
        "  <link rel=\"stylesheet\" href=\"static/css/site.css\">\n"
        "  <link rel=\"stylesheet\" href=\"static/css/sunset-wave.css\">\n"
        "</head>\n"
        "<body>\n"
        "  <div class=\"page-shell\">\n"
        "    <header class=\"site-header\">\n"
        "      <div class=\"brand\">phasor</div>\n"
        "      <div class=\"tagline\">ECS-first Zig game engine docs</div>\n"
        f"      {nav_html}\n"
        "    </header>\n"
        "    <main class=\"page-body\">\n"
        f"      {body_html}\n"
        "    </main>\n"
        "  </div>\n"
        "</body>\n"
        "</html>\n"
    )


def copy_static_assets(output_root: Path, static_root: Path) -> None:
    if not static_root.is_dir():
        return
    target_root = output_root / "static"
    if target_root.exists():
        shutil.rmtree(target_root)
    shutil.copytree(static_root, target_root)


def write_search_index(output_root: Path, pages: list[PageRecord], examples: list[ExampleRecord]) -> None:
    payload = {
        "pages": [
            {
                "title": page.title,
                "path": page.relative_path.with_suffix(".html").as_posix(),
                "body": page.body,
            }
            for page in pages
        ],
        "examples": [
            {
                "title": example.title,
                "path": f"data/examples/{example.name}.json",
                "summary": example.summary,
                "feature_tags": example.feature_tags,
            }
            for example in examples
        ],
    }
    (output_root / "search-index.json").write_text(json.dumps(payload, indent=2) + "\n")
