from __future__ import annotations

import html
import re
from pathlib import Path

from .config import SitePaths
from .models import EmbedDirective, ExampleRecord, FeatureManifestEntry, PageRecord


EMBED_RE = re.compile(r"\{\{\s*([a-z_]+)(.*?)\}\}")
ATTRIBUTE_RE = re.compile(r'([a-z_]+)="([^"]*)"')


def load_pages(paths: SitePaths) -> list[PageRecord]:
    pages: list[PageRecord] = []
    for source_path in sorted(paths.docs_root.rglob("*.md")):
        if source_path.is_relative_to(paths.site_root):
            continue
        body = source_path.read_text()
        embeds = parse_embeds(body)
        title = extract_title(body, source_path)
        pages.append(
            PageRecord(
                source_path=source_path,
                relative_path=source_path.relative_to(paths.docs_root),
                title=title,
                body=body,
                embeds=embeds,
            )
        )
    return pages


def render_pages(
    paths: SitePaths,
    pages: list[PageRecord],
    examples: list[ExampleRecord],
    features: dict[str, FeatureManifestEntry],
) -> list[PageRecord]:
    rendered: list[PageRecord] = []
    for page in pages:
        rendered.append(
            PageRecord(
                source_path=page.source_path,
                relative_path=page.relative_path,
                title=page.title,
                body=page.body,
                embeds=page.embeds,
                rendered_html=render_markdown(paths, page.body, examples, features),
            )
        )
    return rendered


def parse_embeds(body: str) -> list[EmbedDirective]:
    directives: list[EmbedDirective] = []
    for match in EMBED_RE.finditer(body):
        kind = match.group(1)
        attributes = {key: value for key, value in ATTRIBUTE_RE.findall(match.group(2))}
        directives.append(EmbedDirective(kind=kind, attributes=attributes, raw=match.group(0)))
    return directives


def extract_title(body: str, source_path: Path) -> str:
    for line in body.splitlines():
        if line.startswith("# "):
            return line[2:].strip()
    return source_path.stem.replace("_", " ").title()


def render_markdown(
    paths: SitePaths,
    body: str,
    examples: list[ExampleRecord],
    features: dict[str, FeatureManifestEntry],
) -> str:
    lines = body.splitlines()
    parts: list[str] = []
    in_code = False
    code_lines: list[str] = []
    paragraph_lines: list[str] = []
    list_lines: list[str] = []

    def flush_paragraph() -> None:
        nonlocal paragraph_lines
        if paragraph_lines:
            text = " ".join(line.strip() for line in paragraph_lines)
            parts.append(f"<p>{render_inline(text)}</p>")
            paragraph_lines = []

    def flush_list() -> None:
        nonlocal list_lines
        if list_lines:
            items = "".join(f"<li>{render_inline(item[2:].strip())}</li>" for item in list_lines)
            parts.append(f"<ul>{items}</ul>")
            list_lines = []

    for line in lines:
        stripped = line.strip()

        if stripped.startswith("```"):
            flush_paragraph()
            flush_list()
            if in_code:
                parts.append("<pre><code>" + html.escape("\n".join(code_lines)) + "</code></pre>")
                code_lines = []
                in_code = False
            else:
                in_code = True
            continue

        if in_code:
            code_lines.append(line)
            continue

        if stripped.startswith("{{") and stripped.endswith("}}"):
            flush_paragraph()
            flush_list()
            embed = parse_embeds(stripped)[0]
            parts.append(render_embed(paths, embed, examples, features))
            continue

        if not stripped:
            flush_paragraph()
            flush_list()
            continue

        if stripped.startswith("# "):
            flush_paragraph()
            flush_list()
            parts.append(f"<h1>{render_inline(stripped[2:])}</h1>")
            continue
        if stripped.startswith("## "):
            flush_paragraph()
            flush_list()
            parts.append(f"<h2>{render_inline(stripped[3:])}</h2>")
            continue
        if stripped.startswith("### "):
            flush_paragraph()
            flush_list()
            parts.append(f"<h3>{render_inline(stripped[4:])}</h3>")
            continue
        if stripped.startswith("- "):
            flush_paragraph()
            list_lines.append(stripped)
            continue

        paragraph_lines.append(line)

    flush_paragraph()
    flush_list()
    return "\n".join(parts)


def render_embed(
    paths: SitePaths,
    embed: EmbedDirective,
    examples: list[ExampleRecord],
    features: dict[str, FeatureManifestEntry],
) -> str:
    if embed.kind == "include_file":
        rel_path = embed.attributes["path"]
        file_path = paths.repo_root / rel_path
        content = file_path.read_text()
        return (
            '<section class="code-block">'
            f'<div class="code-label">{html.escape(rel_path)}</div>'
            f"<pre><code>{html.escape(content)}</code></pre>"
            "</section>"
        )
    if embed.kind == "example_grid":
        cards = []
        for example in examples:
            badge_html = "".join(
                f'<span class="badge">{html.escape(tag)}</span>' for tag in example.feature_tags
            )
            support = "WASM + Native" if example.wasm_supported else "Native only"
            cards.append(
                '<article class="example-card">'
                f'<h3>{html.escape(example.title)}</h3>'
                f'<p>{html.escape(example.summary)}</p>'
                f'<div class="support">{html.escape(support)}</div>'
                f'<div class="badges">{badge_html}</div>'
                f'<div class="commands"><code>{html.escape(example.run_step)}</code></div>'
                "</article>"
            )
        return '<section class="example-grid">' + "".join(cards) + "</section>"
    if embed.kind == "feature_matrix":
        rows = []
        for key, feature in sorted(features.items()):
            rows.append(
                "<tr>"
                f"<td><code>{html.escape(key)}</code></td>"
                f"<td>{html.escape(feature.title)}</td>"
                f"<td>{html.escape(feature.summary)}</td>"
                "</tr>"
            )
        return (
            '<section class="feature-matrix"><table><thead><tr><th>Tag</th><th>Feature</th><th>Summary</th></tr></thead>'
            f"<tbody>{''.join(rows)}</tbody></table></section>"
        )
    if embed.kind == "command_block":
        command = embed.attributes.get("value", "")
        return f'<pre><code>{html.escape(command)}</code></pre>'
    return f"<pre><code>{html.escape(embed.raw)}</code></pre>"


def render_inline(text: str) -> str:
    escaped = html.escape(text)
    escaped = re.sub(r"`([^`]+)`", lambda m: f"<code>{m.group(1)}</code>", escaped)
    escaped = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", lambda m: f'<a href="{html.escape(m.group(2))}">{m.group(1)}</a>', escaped)
    return escaped
