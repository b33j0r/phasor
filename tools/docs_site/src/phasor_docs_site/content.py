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
    code_language = "text"
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
                parts.append(
                    f'<pre class="language-{code_language}"><code class="language-{code_language}">'
                    + html.escape("\n".join(code_lines))
                    + "</code></pre>"
                )
                code_lines = []
                in_code = False
            else:
                code_language = normalize_language_name(stripped[3:].strip())
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
        return render_code_block(rel_path, content)
    if embed.kind == "include_lines":
        rel_path = embed.attributes["path"]
        start_line = int(embed.attributes["start"])
        end_line = int(embed.attributes["end"])
        file_path = paths.repo_root / rel_path
        file_lines = file_path.read_text().splitlines()
        snippet = "\n".join(file_lines[start_line - 1 : end_line])
        return render_code_block(f"{rel_path}:{start_line}-{end_line}", snippet, code_language_for_path(rel_path))
    if embed.kind == "example_grid":
        featured_only = embed.attributes.get("featured", "").lower() == "true"
        limit = int(embed.attributes["limit"]) if "limit" in embed.attributes else None
        selected_examples = sorted(
            examples,
            key=lambda item: (-item.detail_priority, item.title.lower(), item.name),
        )
        if featured_only:
            selected_examples = [example for example in selected_examples if example.detail_priority > 0]
        if limit is not None:
            selected_examples = selected_examples[:limit]
        cards = []
        for example in selected_examples:
            badge_html = "".join(render_feature_badge(tag, feature_href(tag)) for tag in example.feature_tags)
            support = "WASM + Native" if example.wasm_supported else "Native only"
            cards.append(
                '<article class="example-card">'
                f'<div class="eyebrow">Example</div>'
                f'<h3><a href="examples/{html.escape(example.name)}.html">{html.escape(example.title)}</a></h3>'
                f'<p>{html.escape(example.summary)}</p>'
                f'<div class="support">{html.escape(support)}</div>'
                f'<div class="badges">{badge_html}</div>'
                '<div class="commands">'
                '<div class="command-context">Repo root</div>'
                f'<code>{html.escape(example.run_step)}</code>'
                "</div>"
                f'<div class="commands"><a class="nav-link" href="examples/{html.escape(example.name)}.html">Open example</a></div>'
                "</article>"
            )
        return '<section class="example-grid">' + "".join(cards) + "</section>"
    if embed.kind == "overview_cards":
        cards = [
            (
                "Native and wasm apps",
                "The build graph supports native targets and browser builds, with examples used to prove the real startup and asset-loading paths.",
            ),
            (
                "2D and 3D rendering",
                "Examples cover the path from a single triangle to imported scenes, layered cameras, materials, lighting, and post-process tuning.",
            ),
            (
                "Scenes, skies, and simulation",
                "glTF import, prepared scene workflows, panoramic skies, procedural skies, physics, audio, and first-person movement all show up in the example set.",
            ),
        ]
        return (
            '<section class="callout-grid">'
            + "".join(
                '<article class="callout-card">'
                f"<h3>{html.escape(title)}</h3>"
                f"<p>{html.escape(summary)}</p>"
                "</article>"
                for title, summary in cards
            )
            + "</section>"
        )
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
    if embed.kind == "feature_catalog":
        entries = []
        for key, feature in sorted(features.items()):
            related_examples = [
                example
                for example in sorted(examples, key=lambda item: (-item.detail_priority, item.title.lower(), item.name))
                if key in example.feature_tags
            ]
            paragraphs = "".join(f"<p>{render_inline(paragraph)}</p>" for paragraph in feature.paragraphs)
            snippet = render_code_example(paths, feature)
            related = render_related_examples(related_examples)
            entries.append(
                '<article class="feature-definition" '
                f'id="{html.escape(feature_anchor(key))}">'
                f'<div class="feature-tag"><code>{html.escape(key)}</code></div>'
                f"<h2>{html.escape(feature.title)}</h2>"
                f'<p class="feature-summary">{render_inline(feature.summary)}</p>'
                f"{paragraphs}"
                f"{snippet}"
                f"{related}"
                "</article>"
            )
        return '<section class="feature-catalog">' + "".join(entries) + "</section>"
    if embed.kind == "command_block":
        command = embed.attributes.get("value", "")
        return f'<pre><code>{html.escape(command)}</code></pre>'
    return f"<pre><code>{html.escape(embed.raw)}</code></pre>"


def render_code_block(label: str, content: str, language: str | None = None) -> str:
    resolved_language = language if language is not None else code_language_for_path(label)
    return (
        '<section class="code-block">'
        f'<div class="code-label">{html.escape(label)}</div>'
        f'<pre class="language-{resolved_language}"><code class="language-{resolved_language}">{html.escape(content)}</code></pre>'
        "</section>"
    )


def render_code_example(paths: SitePaths, feature: FeatureManifestEntry) -> str:
    code_example = feature.code_example
    file_lines = (paths.repo_root / code_example.path).read_text().splitlines()
    snippet = "\n".join(file_lines[code_example.start - 1 : code_example.end])
    return (
        '<section class="feature-code-example">'
        f'<div class="feature-code-caption">{render_inline(code_example.caption)}</div>'
        f"{render_code_block(f'{code_example.path}:{code_example.start}-{code_example.end}', snippet, code_language_for_path(code_example.path))}"
        "</section>"
    )


def render_related_examples(examples: list[ExampleRecord]) -> str:
    if not examples:
        return ""
    cards = []
    for example in examples:
        support = "WASM + Native" if example.wasm_supported else "Native only"
        cards.append(
            '<article class="related-example-card">'
            f'<h3><a href="examples/{html.escape(example.name)}.html">{html.escape(example.title)}</a></h3>'
            f'<p>{html.escape(example.summary)}</p>'
            f'<div class="support">{html.escape(support)}</div>'
            "</article>"
        )
    return (
        '<section class="feature-related-examples">'
        "<h3>Related Examples</h3>"
        '<div class="feature-related-grid">'
        + "".join(cards)
        + "</div></section>"
    )


def render_inline(text: str) -> str:
    escaped = html.escape(text)
    escaped = re.sub(r"`([^`]+)`", lambda m: f"<code>{m.group(1)}</code>", escaped)
    escaped = re.sub(
        r"\[([^\]]+)\]\(([^)]+)\)",
        lambda m: f'<a href="{html.escape(normalize_href(m.group(2)))}">{m.group(1)}</a>',
        escaped,
    )
    return escaped


def normalize_href(target: str) -> str:
    if target.endswith(".md"):
        return f"{target[:-3]}.html"
    return target


def feature_anchor(tag: str) -> str:
    return f"feature-{tag}"


def feature_href(tag: str) -> str:
    return f"features.html#{feature_anchor(tag)}"


def render_feature_badge(tag: str, href: str) -> str:
    return (
        f'<a class="badge" href="{html.escape(href)}">'
        f"{html.escape(tag)}"
        "</a>"
    )


def normalize_language_name(language: str) -> str:
    if not language:
        return "text"
    if language == "md":
        return "markdown"
    if language == "zon":
        return "zig"
    return language


def code_language_for_path(rel_path: str) -> str:
    suffix = Path(rel_path).suffix
    if suffix == ".zig":
        return "zig"
    if suffix == ".wgsl":
        return "wgsl"
    if suffix == ".md":
        return "markdown"
    if suffix == ".json":
        return "json"
    if suffix == ".zon":
        return "zig"
    return "text"
