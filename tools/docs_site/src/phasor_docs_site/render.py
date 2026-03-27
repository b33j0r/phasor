from __future__ import annotations

import html
import json
import shutil
from pathlib import Path

from .models import ExampleRecord, FeatureManifestEntry, NavigationItem, PageRecord


def render_site(
    repo_root: Path,
    output_root: Path,
    pages: list[PageRecord],
    examples: list[ExampleRecord],
    features: dict[str, FeatureManifestEntry],
    navigation: list[NavigationItem],
) -> Path:
    output_root.mkdir(parents=True, exist_ok=True)
    copy_static_assets(output_root, Path(__file__).resolve().parents[4] / "docs" / "site" / "static")
    code_files = copy_code_tree(repo_root, output_root)
    copy_live_examples(examples, output_root)
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
        target_path.write_text(
            render_document(example.title, nav_html, render_example_page(example, features, relative_path), relative_path)
        )

    render_code_pages(output_root, navigation, code_files)

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
    sunset_css = relative_href(current_path, Path("static/css/sunset-wave.css"))
    solar_css = relative_href(current_path, Path("static/css/solar-wave.css"))
    print_css = relative_href(current_path, Path("static/css/print.css"))
    favicon_svg = relative_href(current_path, Path("static/images/favicon.svg"))
    site_js = relative_href(current_path, Path("static/js/site.js"))
    prism_core = relative_href(current_path, Path("static/js/prism/prism.min.js"))
    prism_zig = relative_href(current_path, Path("static/js/prism/prism-zig.min.js"))
    prism_wgsl = relative_href(current_path, Path("static/js/prism/prism-wgsl.min.js"))
    prism_markdown = relative_href(current_path, Path("static/js/prism/prism-markdown.min.js"))
    prism_json = relative_href(current_path, Path("static/js/prism/prism-json.min.js"))
    return (
        "<!doctype html>\n"
        "<html lang=\"en\" data-theme=\"sunset-wave-dark\">\n"
        "<head>\n"
        "  <meta charset=\"utf-8\">\n"
        "  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n"
        f"  <title>{html.escape(title)}</title>\n"
        "  <link rel=\"preconnect\" href=\"https://fonts.googleapis.com\">\n"
        "  <link rel=\"preconnect\" href=\"https://fonts.gstatic.com\" crossorigin>\n"
        "  <link href=\"https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500&family=Space+Grotesk:wght@400;500;700&display=swap\" rel=\"stylesheet\">\n"
        f"  <link rel=\"icon\" href=\"{html.escape(favicon_svg)}\" type=\"image/svg+xml\" sizes=\"any\">\n"
        f"  <link rel=\"stylesheet\" href=\"{html.escape(site_css)}\">\n"
        f"  <link rel=\"stylesheet\" href=\"{html.escape(sunset_css)}\">\n"
        f"  <link rel=\"stylesheet\" href=\"{html.escape(solar_css)}\">\n"
        f"  <link rel=\"stylesheet\" href=\"{html.escape(print_css)}\">\n"
        "</head>\n"
        "<body>\n"
        "  <div class=\"page-shell\">\n"
        "    <header class=\"site-header\">\n"
        "      <div class=\"site-header-top\">\n"
        "        <div>\n"
        "          <div class=\"brand\">phasor</div>\n"
        "          <div class=\"tagline\">ECS-first Zig game engine docs</div>\n"
        "        </div>\n"
        "        <label class=\"theme-picker\">\n"
        "          <span>Theme</span>\n"
        "          <select data-theme-select>\n"
        "            <option value=\"sunset-wave-dark\">Sunset Wave (Dark)</option>\n"
        "            <option value=\"solar-wave-light\">Solar Wave (Light)</option>\n"
        "            <option value=\"print\">Print</option>\n"
        "          </select>\n"
        "        </label>\n"
        "      </div>\n"
        f"      {nav_html}\n"
        "    </header>\n"
        "    <main class=\"page-body\">\n"
        f"      {body_html}\n"
        "    </main>\n"
        "  </div>\n"
        f"  <script src=\"{html.escape(prism_core)}\"></script>\n"
        f"  <script src=\"{html.escape(prism_zig)}\"></script>\n"
        f"  <script src=\"{html.escape(prism_wgsl)}\"></script>\n"
        f"  <script src=\"{html.escape(prism_markdown)}\"></script>\n"
        f"  <script src=\"{html.escape(prism_json)}\"></script>\n"
        f"  <script src=\"{html.escape(site_js)}\"></script>\n"
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


def copy_code_tree(repo_root: Path, output_root: Path) -> list[Path]:
    code_root = output_root / "code"
    if code_root.exists():
        shutil.rmtree(code_root)
    code_root.mkdir(parents=True, exist_ok=True)
    copied_files: list[Path] = []

    for source_path in repo_root.rglob("*"):
        if not source_path.is_file():
            continue
        rel_path = source_path.relative_to(repo_root)
        if should_skip_code_path(rel_path):
            continue
        if source_path.suffix not in CODE_FILE_SUFFIXES:
            continue
        target_path = code_root / rel_path
        target_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source_path, target_path)
        copied_files.append(rel_path)
    return copied_files


def copy_live_examples(examples: list[ExampleRecord], output_root: Path) -> None:
    live_root = output_root / "live" / "examples"
    if live_root.exists():
        shutil.rmtree(live_root)
    live_root.mkdir(parents=True, exist_ok=True)

    for example in examples:
        if not example.live_demo_path:
            continue
        source_root = example.directory / "zig-out" / "web"
        if not source_root.is_dir():
            continue
        target_root = live_root / example.name
        shutil.copytree(source_root, target_root)


def render_code_pages(output_root: Path, navigation: list[NavigationItem], code_files: list[Path]) -> None:
    directories: set[Path] = {Path("code")}
    for file_path in code_files:
        parent = Path("code") / file_path.parent
        while True:
            directories.add(parent)
            if parent == Path("code"):
                break
            parent = parent.parent

    for directory in sorted(directories, key=lambda path: (len(path.parts), path.as_posix())):
        current_path = directory / "index.html"
        target_path = output_root / current_path
        target_path.parent.mkdir(parents=True, exist_ok=True)
        nav_html = render_nav(navigation, current_path)
        body_html = render_code_directory_page(directory, current_path, directories, code_files)
        target_path.write_text(render_document(f"Code · {directory.as_posix()}", nav_html, body_html, current_path))


def render_code_directory_page(
    directory: Path,
    current_path: Path,
    directories: set[Path],
    code_files: list[Path],
) -> str:
    code_dir = directory.relative_to("code")
    title = "<h1>Code Browser</h1>" if directory == Path("code") else f"<h1>{html.escape(directory.as_posix())}</h1>"
    intro = (
        "<p>Browse the generated repository tree here. Directory pages link deeper into the tree, and file entries open the raw copied source.</p>"
    )
    parent_html = ""
    if directory != Path("code"):
        parent_directory = directory.parent
        parent_href = relative_href(current_path, parent_directory / "index.html")
        parent_html = f'<div class="commands"><a class="nav-link" href="{html.escape(parent_href)}">Up one level</a></div>'

    child_dirs = sorted(
        child for child in directories
        if child.parent == directory and child != directory
    )
    child_files = sorted(
        file_path for file_path in code_files
        if (Path("code") / file_path).parent == directory
    )

    dir_items = "".join(
        '<li class="code-entry">'
        f'<a href="{html.escape(relative_href(current_path, child / "index.html"))}">{html.escape(child.name)}/</a>'
        "</li>"
        for child in child_dirs
    )
    file_items = "".join(
        '<li class="code-entry">'
        f'<a href="{html.escape(relative_href(current_path, Path("code") / file_path))}">{html.escape(file_path.name)}</a>'
        f'<span class="code-entry-path">{html.escape(file_path.as_posix())}</span>'
        "</li>"
        for file_path in child_files
    )

    sections = []
    if child_dirs:
        sections.append(
            '<section class="code-directory-card"><h2>Directories</h2><ul class="code-entry-list">'
            f"{dir_items}</ul></section>"
        )
    if child_files:
        sections.append(
            '<section class="code-directory-card"><h2>Files</h2><ul class="code-entry-list">'
            f"{file_items}</ul></section>"
        )
    if not sections:
        sections.append('<section class="code-directory-card"><p>This directory is empty.</p></section>')

    return title + intro + parent_html + '<div class="code-directory-grid">' + "".join(sections) + "</div>"


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


CODE_FILE_SUFFIXES = {
    ".c",
    ".cpp",
    ".css",
    ".h",
    ".hpp",
    ".html",
    ".js",
    ".json",
    ".md",
    ".py",
    ".sh",
    ".svg",
    ".toml",
    ".txt",
    ".wgsl",
    ".yaml",
    ".yml",
    ".zig",
    ".zon",
}

SKIPPED_CODE_PARTS = {
    ".git",
    ".venv",
    "__pycache__",
    ".zig-cache",
    "zig-out",
    "zig-pkg",
    "_build",
}


def should_skip_code_path(rel_path: Path) -> bool:
    return any(part in SKIPPED_CODE_PARTS for part in rel_path.parts)


def render_example_page(
    example: ExampleRecord,
    features: dict[str, FeatureManifestEntry],
    current_path: Path,
) -> str:
    support = "WASM + Native" if example.wasm_supported else "Native only"
    feature_badges = "".join(
        render_feature_badge(tag, relative_href(current_path, Path("features.html")) + f"#{feature_anchor(tag)}")
        for tag in example.feature_tags
    )
    feature_list = "".join(
        '<li><a href="'
        f'{html.escape(relative_href(current_path, Path("features.html")) + f"#{feature_anchor(tag)}")}'
        f'"><code>{html.escape(tag)}</code></a></li>'
        for tag in example.feature_tags
    )
    source_index = "".join(
        f'<li><code>{html.escape(path)}</code></li>' for path in example.source_files
    )
    source_browser = render_source_browser(example, current_path)
    return (
        "<section class=\"hero-block hero-block-example\">"
        f'<div class="eyebrow">Example</div>'
        f"<h1>{html.escape(example.title)}</h1>\n"
        f"<p class=\"lede\">{html.escape(example.summary)}</p>\n"
        "<div class=\"hero-actions\">"
        f"<div><div class=\"support\">{html.escape(support)}</div><div class=\"badges\">{feature_badges}</div></div>"
        f'<a class="nav-link" href="../data/examples/{html.escape(example.name)}.json">Source bundle JSON</a>'
        "</div>"
        "</section>\n"
        "<section class=\"example-layout\">"
        "<div class=\"example-main-column\">"
        "<article class=\"info-card example-stage-card\">"
        "<h2>Live Demo</h2>\n"
        f"{render_live_demo(example, current_path)}\n"
        "</article>"
        "<article class=\"info-card example-source-card\">"
        "<div class=\"section-heading-row\">"
        "<h2>Source Walkthrough</h2>"
        f'<a class="nav-link" href="{html.escape(relative_href(current_path, Path("code") / "examples" / example.name / "main.zig"))}">Open example code tree</a>'
        "</div>"
        "<p>The browser below includes the full example project tree. Raw file links point into the generated "
        "<code>/code</code> copy of the repo.</p>"
        f"{source_browser}\n"
        "</article>"
        "</div>"
        "<aside class=\"example-side-column\">"
        "<article class=\"info-card\">"
        "<h2>Build And Run</h2>\n"
        "<p>Each command block says where it should be run so the root build graph and the standalone example project layout are both clear.</p>"
        f"{render_command_group(example)}\n"
        "</article>"
        "<article class=\"info-card\">"
        "<h2>Highlighted Files</h2>"
        "<p>The walkthrough starts with the files most likely to answer how the example is put together.</p>"
        f"<ul>{source_index}</ul>"
        "</article>"
        "<article class=\"info-card\">"
        "<h2>Feature Coverage</h2>"
        "<p>These tags link to the shared feature definitions page.</p>"
        f'<ul>{feature_list}</ul>'
        "</article>"
        "</aside>"
        "</section>\n"
    )


def render_command_group(example: ExampleRecord) -> str:
    local_dir = f"examples/{example.name}"
    root_commands = [example.run_step]
    local_commands = [example.local_run_step]
    if example.web_step:
        root_commands.append(example.web_step)
        if example.local_web_step:
            local_commands.append(example.local_web_step)

    def render_command_block(title: str, location: str, commands: list[str]) -> str:
        items = "".join(
            '<div class="command-entry">'
            f'<div class="command-context">{html.escape(location)}</div>'
            f'<pre><code>{html.escape(command)}</code></pre>'
            "</div>"
            for command in commands
        )
        return (
            '<section class="command-group">'
            f"<h3>{html.escape(title)}</h3>"
            f"{items}"
            "</section>"
        )

    return (
        '<div class="command-groups">'
        + render_command_block("From Repo Root", "cwd: <repo root>", root_commands)
        + render_command_block("From Example Directory", f"cwd: {local_dir}", local_commands)
        + "</div>"
    )


def render_live_demo(example: ExampleRecord, current_path: Path) -> str:
    if example.live_demo_path:
        iframe_src = relative_href(current_path, Path(example.live_demo_path))
        return (
            '<div class="live-demo-frame">'
            f'<iframe src="{html.escape(iframe_src)}" title="{html.escape(example.title)} live demo" loading="lazy"></iframe>'
            "</div>"
        )
    if example.wasm_supported:
        return (
            '<div class="live-demo-note">'
            "<p>This example supports wasm, but the live bundle is not in the docs build yet.</p>"
            "<p>Build it first from the repo root with "
            f"<code>{html.escape(example.web_step or '')}</code>"
            " or from the example directory with "
            f"<code>{html.escape(example.local_web_step or '')}</code>."
            "</p>"
            "</div>"
        )
    return (
        '<div class="live-demo-note">'
        "<p>This example is native-only, so the docs page focuses on commands, source, and feature coverage.</p>"
        "</div>"
    )


def feature_anchor(tag: str) -> str:
    return f"feature-{tag}"


def render_feature_badge(tag: str, href: str) -> str:
    return (
        f'<a class="badge" href="{html.escape(href)}">'
        f"{html.escape(tag)}"
        "</a>"
    )


def render_source_panel(example: ExampleRecord, rel_path: str, *, include_label: bool = True) -> str:
    content = (example.directory / rel_path).read_text()
    language = code_language_for_path(rel_path)
    label_html = f"<div class=\"code-label\">{html.escape(rel_path)}</div>" if include_label else ""
    return (
        "<section class=\"source-panel\">"
        f"{label_html}"
        f'<pre class="language-{language}"><code class="language-{language}">{html.escape(content)}</code></pre>'
        "</section>"
    )


def render_source_browser(example: ExampleRecord, current_path: Path) -> str:
    ordered_files = list(dict.fromkeys([*example.source_files, *example.extra_files]))
    buttons: list[str] = []
    panes: list[str] = []
    for index, rel_path in enumerate(ordered_files):
        active_class = " is-active" if index == 0 else ""
        item_id = f"file-{index}"
        raw_href = relative_href(current_path, Path("code") / "examples" / example.name / rel_path)
        buttons.append(
            '<button type="button" class="source-file'
            f'{active_class}" data-source-target="{html.escape(item_id)}">'
            f"{html.escape(rel_path)}"
            "</button>"
        )
        panes.append(
            '<article class="source-pane'
            f'{active_class}" data-source-pane="{html.escape(item_id)}">'
            '<div class="source-pane-header">'
            f'<div class="code-label">{html.escape(rel_path)}</div>'
            f'<a class="nav-link" href="{html.escape(raw_href)}">Raw file</a>'
            "</div>"
            + render_source_panel(example, rel_path, include_label=False)
            + "</article>"
        )
    return (
        '<section class="source-browser" data-source-browser>'
        '<aside class="source-browser-sidebar">'
        '<div class="source-browser-title">Files</div>'
        f'<div class="source-browser-files">{"".join(buttons)}</div>'
        "</aside>"
        '<div class="source-browser-main">'
        f'{"".join(panes)}'
        "</div>"
        "</section>"
    )


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
