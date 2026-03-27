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

    for page in pages:
        target_path = output_root / page.relative_path.with_suffix(".html")
        target_path.parent.mkdir(parents=True, exist_ok=True)
        nav_html = render_nav(navigation, page.relative_path.with_suffix(".html"))
        target_path.write_text(render_document(page.title, nav_html, page.rendered_html, page.relative_path.with_suffix(".html")))

    for example in examples:
        relative_path = Path("examples") / f"{example.name}.html"
        target_path = output_root / relative_path
        target_path.parent.mkdir(parents=True, exist_ok=True)
        nav_html = render_nav(navigation, relative_path)
        target_path.write_text(render_document(example.title, nav_html, render_example_page(example), relative_path))

    index_page = next((page for page in pages if page.relative_path.as_posix() == "index.md"), None)
    return output_root / (index_page.relative_path.with_suffix(".html") if index_page else Path("index.html"))


def render_nav(navigation: list[NavigationItem], current_path: Path) -> str:
    links = "".join(
        f'<a class="nav-link" href="{html.escape(relative_href(current_path, Path(item.path).with_suffix(".html")))}">{html.escape(item.title)}</a>'
        for item in navigation
    )
    return f'<nav class="site-nav">{links}</nav>'


def render_document(title: str, nav_html: str, body_html: str, current_path: Path) -> str:
    site_css = relative_href(current_path, Path("static/css/site.css"))
    theme_css = relative_href(current_path, Path("static/css/sunset-wave.css"))
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
        f"  <link rel=\"stylesheet\" href=\"{html.escape(site_css)}\">\n"
        f"  <link rel=\"stylesheet\" href=\"{html.escape(theme_css)}\">\n"
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


def relative_href(from_path: Path, to_path: Path) -> str:
    from_dir = from_path.parent
    return Path(
        *(
            [".."] * len(from_dir.parts)
            + list(to_path.parts)
        )
    ).as_posix() if from_dir.parts else to_path.as_posix()


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
                "path": f"examples/{example.name}.html",
                "summary": example.summary,
                "feature_tags": example.feature_tags,
            }
            for example in examples
        ],
    }
    (output_root / "search-index.json").write_text(json.dumps(payload, indent=2) + "\n")


def render_example_page(example: ExampleRecord) -> str:
    support = "WASM + Native" if example.wasm_supported else "Native only"
    feature_badges = "".join(f'<span class="badge">{html.escape(tag)}</span>' for tag in example.feature_tags)
    build_lines = [example.run_step]
    if example.web_step:
        build_lines.append(example.web_step)
    command_html = "".join(f"<li><code>{html.escape(line)}</code></li>" for line in build_lines)
    curated_files = "".join(render_source_panel(example, rel_path) for rel_path in example.source_files)
    extra_links = "".join(
        f'<li><code>{html.escape(path)}</code></li>' for path in example.extra_files
    )
    extra_section = (
        "<h2>Additional Files</h2><ul>" + extra_links + "</ul>"
        if extra_links
        else ""
    )
    return (
        f"<h1>{html.escape(example.title)}</h1>\n"
        f"<p>{html.escape(example.summary)}</p>\n"
        "<section class=\"example-hero\">"
        f"<div><div class=\"support\">{html.escape(support)}</div><div class=\"badges\">{feature_badges}</div></div>"
        f"<div><a class=\"nav-link\" href=\"../data/examples/{html.escape(example.name)}.json\">Source bundle JSON</a></div>"
        "</section>\n"
        "<h2>Build And Run</h2>\n"
        f"<ul>{command_html}</ul>\n"
        "<h2>Highlighted Source</h2>\n"
        f"{curated_files}\n"
        f"{extra_section}\n"
    )


def render_source_panel(example: ExampleRecord, rel_path: str) -> str:
    content = (example.directory / rel_path).read_text()
    return (
        "<section class=\"source-panel\">"
        f"<div class=\"code-label\">{html.escape(rel_path)}</div>"
        f"<pre><code>{html.escape(content)}</code></pre>"
        "</section>"
    )
