from __future__ import annotations

import html
import json
from pathlib import Path

from .models import ExampleRecord, NavigationItem, PageRecord


def render_site(
    output_root: Path,
    pages: list[PageRecord],
    examples: list[ExampleRecord],
    navigation: list[NavigationItem],
) -> Path:
    output_root.mkdir(parents=True, exist_ok=True)
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
        "  <style>"
        + base_css() +
        "  </style>\n"
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


def base_css() -> str:
    return """
      :root {
        --bg: #f4efe7;
        --paper: rgba(255, 252, 247, 0.92);
        --ink: #1b1c1d;
        --muted: #605a52;
        --line: rgba(27, 28, 29, 0.12);
        --accent: #bd4f2e;
        --accent-2: #0f6b5c;
      }
      * { box-sizing: border-box; }
      body {
        margin: 0;
        background:
          radial-gradient(circle at top left, rgba(189, 79, 46, 0.15), transparent 28%),
          radial-gradient(circle at 80% 10%, rgba(15, 107, 92, 0.13), transparent 25%),
          linear-gradient(180deg, #f6f1ea 0%, #efe7dc 100%);
        color: var(--ink);
        font-family: "Space Grotesk", sans-serif;
      }
      .page-shell { max-width: 1160px; margin: 0 auto; padding: 32px 20px 64px; }
      .site-header {
        display: grid;
        gap: 10px;
        padding: 18px 22px;
        border: 1px solid var(--line);
        background: var(--paper);
        backdrop-filter: blur(12px);
        border-radius: 24px;
        box-shadow: 0 18px 70px rgba(66, 47, 31, 0.08);
      }
      .brand { font-size: 2rem; font-weight: 700; letter-spacing: -0.04em; }
      .tagline { color: var(--muted); }
      .site-nav { display: flex; gap: 10px; flex-wrap: wrap; }
      .nav-link {
        color: var(--ink);
        text-decoration: none;
        padding: 8px 12px;
        border-radius: 999px;
        border: 1px solid var(--line);
        background: rgba(255,255,255,0.5);
      }
      .page-body {
        margin-top: 24px;
        padding: 28px;
        border: 1px solid var(--line);
        background: var(--paper);
        border-radius: 28px;
        box-shadow: 0 18px 70px rgba(66, 47, 31, 0.08);
      }
      h1, h2, h3 { line-height: 1.05; letter-spacing: -0.04em; margin: 0 0 16px; }
      h1 { font-size: clamp(2.6rem, 5vw, 4.4rem); }
      h2 { margin-top: 34px; font-size: 1.75rem; }
      h3 { font-size: 1.2rem; }
      p, li { font-size: 1.04rem; line-height: 1.65; color: #2f2f2f; }
      a { color: var(--accent); }
      code, pre { font-family: "IBM Plex Mono", monospace; }
      code {
        background: rgba(27, 28, 29, 0.06);
        padding: 0.16rem 0.34rem;
        border-radius: 0.35rem;
      }
      pre {
        overflow-x: auto;
        padding: 18px;
        border-radius: 20px;
        border: 1px solid var(--line);
        background: #fffaf3;
      }
      .example-grid {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
        gap: 16px;
        margin-top: 18px;
      }
      .example-card {
        border: 1px solid var(--line);
        border-radius: 22px;
        padding: 18px;
        background: linear-gradient(180deg, rgba(255,255,255,0.9), rgba(248,243,236,0.92));
      }
      .badges { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 14px; }
      .badge {
        display: inline-block;
        padding: 5px 9px;
        border-radius: 999px;
        background: rgba(15, 107, 92, 0.10);
        color: var(--accent-2);
        font-size: 0.84rem;
        font-weight: 500;
      }
      .support { color: var(--accent); font-weight: 700; margin-top: 10px; }
      .commands { margin-top: 14px; }
      .code-block .code-label {
        font-family: "IBM Plex Mono", monospace;
        color: var(--muted);
        margin-bottom: 10px;
      }
      .feature-matrix table { width: 100%; border-collapse: collapse; margin-top: 14px; }
      .feature-matrix th, .feature-matrix td {
        text-align: left;
        padding: 12px 10px;
        border-bottom: 1px solid var(--line);
        vertical-align: top;
      }
      @media (max-width: 720px) {
        .page-shell { padding: 18px 12px 48px; }
        .page-body { padding: 20px; border-radius: 22px; }
      }
    """


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
