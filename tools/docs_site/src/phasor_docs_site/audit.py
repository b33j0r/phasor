from __future__ import annotations

import json
import re
from collections import Counter
from dataclasses import asdict, dataclass
from pathlib import Path

from .config import SitePaths


REGISTRATION_PATTERNS = (
    re.compile(r"\bapp\.addSystemTo\((?P<schedule>[^,]+),\s*(?P<ref>[A-Za-z_][A-Za-z0-9_\.]*)\s*\)"),
    re.compile(r"\bctx\.addSystem\((?P<schedule>[^,]+),\s*(?P<ref>[A-Za-z_][A-Za-z0-9_\.]*)\s*\)"),
    re.compile(r"\bapp\.addSystem\((?P<ref>[A-Za-z_][A-Za-z0-9_\.]*)\s*\)"),
)

IMPORT_RE = re.compile(r'const\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*@import\("([^"]+)"\);')
FN_RE = re.compile(r"(?m)^[ \t]*(?:pub\s+)?fn\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(")

SYSTEM_PARAM_PREFIXES = (
    "Res(",
    "ResMut(",
    "ResOpt(",
    "ResMutOpt(",
    "Query(",
    "GroupBy(",
    "HasResource(",
    "EventReader(",
    "EventWriter(",
)

MUTATION_PATTERNS = (
    "commands.insertResource(",
    "commands.createEntity(",
    "commands.addComponent(",
    "commands.addComponents(",
    "commands.removeComponent(",
    "commands.removeComponents(",
    "commands.removeEntity(",
    "commands.removeResource(",
)

LIVE_READ_PATTERNS = (
    "commands.getResource(",
    "commands.getResourceMut(",
    "commands.query(",
    "commands.groupBy(",
)


@dataclass(frozen=True)
class FunctionSpec:
    file: str
    name: str
    line: int
    params: list[str]
    body: str


@dataclass(frozen=True)
class SystemRegistration:
    registrar_file: str
    registrar_line: int
    schedule: str
    reference: str
    target_file: str | None
    target_function: str | None
    params: list[str]
    resolved: bool


@dataclass(frozen=True)
class AuditFinding:
    category: str
    severity: str
    file: str
    line: int
    function: str
    message: str


@dataclass(frozen=True)
class AuditReport:
    registrations: list[SystemRegistration]
    findings: list[AuditFinding]
    lifecycle_findings: list[AuditFinding]
    param_kind_counts: dict[str, int]
    param_signature_counts: dict[str, int]


def run_system_audit(paths: SitePaths) -> AuditReport:
    zig_files = list(iter_zig_files(paths.repo_root))
    file_text = {path: path.read_text() for path in zig_files}
    imports = {path: parse_imports(text) for path, text in file_text.items()}
    functions = {path: parse_functions(path, text) for path, text in file_text.items()}

    registrations: list[SystemRegistration] = []
    findings: list[AuditFinding] = []
    lifecycle_findings: list[AuditFinding] = []
    param_kind_counts: Counter[str] = Counter()
    param_signature_counts: Counter[str] = Counter()

    for file_path, text in file_text.items():
        for registration in parse_registrations(file_path, text):
            target_file, target_name = resolve_reference(file_path, registration.reference, imports[file_path])
            function = functions.get(target_file, {}).get(target_name) if target_file and target_name else None
            params = function.params if function else []
            registrations.append(
                SystemRegistration(
                    registrar_file=file_path.relative_to(paths.repo_root).as_posix(),
                    registrar_line=registration.registrar_line,
                    schedule=registration.schedule,
                    reference=registration.reference,
                    target_file=target_file.relative_to(paths.repo_root).as_posix() if target_file else None,
                    target_function=target_name,
                    params=params,
                    resolved=function is not None,
                )
            )
            if function is None:
                findings.append(
                    AuditFinding(
                        category="unresolved-system-reference",
                        severity="warn",
                        file=file_path.relative_to(paths.repo_root).as_posix(),
                        line=registration.registrar_line,
                        function=registration.reference,
                        message="Could not resolve system function to a Zig source definition.",
                    )
                )
                continue
            for param in function.params:
                param_kind_counts[param_kind(param)] += 1
                param_signature_counts[param.strip()] += 1
            findings.extend(findings_for_function(paths.repo_root, function))

    for file_path, function_map in functions.items():
        rel_file = file_path.relative_to(paths.repo_root).as_posix()
        if not rel_file.startswith("examples/"):
            continue
        for function in function_map.values():
            if function.name not in {"enter", "exit"}:
                continue
            lifecycle_findings.extend(lifecycle_findings_for_function(paths.repo_root, function))

    registrations.sort(key=lambda item: (item.target_file or item.registrar_file, item.target_function or item.reference, item.schedule))
    findings.sort(key=lambda item: (item.file, item.line, item.category))
    lifecycle_findings.sort(key=lambda item: (item.file, item.line, item.category))

    return AuditReport(
        registrations=registrations,
        findings=findings,
        lifecycle_findings=lifecycle_findings,
        param_kind_counts=dict(sorted(param_kind_counts.items())),
        param_signature_counts=dict(sorted(param_signature_counts.items())),
    )


def write_system_audit(paths: SitePaths, report: AuditReport) -> tuple[Path, Path]:
    output_root = paths.output_root / "system-audit"
    output_root.mkdir(parents=True, exist_ok=True)
    json_path = output_root / "report.json"
    md_path = output_root / "report.md"
    json_path.write_text(json.dumps(asdict(report), indent=2) + "\n")
    md_path.write_text(render_markdown_report(report))
    return json_path, md_path


def render_markdown_report(report: AuditReport) -> str:
    lines = [
        "# System Audit",
        "",
        f"- Registered systems: {len(report.registrations)}",
        f"- System findings: {len(report.findings)}",
        f"- Lifecycle findings: {len(report.lifecycle_findings)}",
        "",
        "## System Param Kinds",
        "",
    ]
    for kind, count in report.param_kind_counts.items():
        lines.append(f"- `{kind}`: {count}")

    lines.extend(["", "## Top Param Signatures", ""])
    for signature, count in sorted(report.param_signature_counts.items(), key=lambda item: (-item[1], item[0]))[:40]:
        lines.append(f"- `{signature}`: {count}")

    lines.extend(["", "## Findings", ""])
    if report.findings:
        for finding in report.findings:
            lines.append(
                f"- `{finding.category}` {finding.file}:{finding.line} `{finding.function}`: {finding.message}"
            )
    else:
        lines.append("- none")

    lines.extend(["", "## Lifecycle Findings", ""])
    if report.lifecycle_findings:
        for finding in report.lifecycle_findings:
            lines.append(
                f"- `{finding.category}` {finding.file}:{finding.line} `{finding.function}`: {finding.message}"
            )
    else:
        lines.append("- none")

    lines.extend(["", "## Registered Systems", ""])
    for registration in report.registrations:
        target = registration.target_file or registration.registrar_file
        params = ", ".join(registration.params) if registration.params else "unresolved"
        lines.append(
            f"- `{registration.schedule}` `{registration.reference}` -> `{target}` params: {params}"
        )
    lines.append("")
    return "\n".join(lines)


def findings_for_function(repo_root: Path, function: FunctionSpec) -> list[AuditFinding]:
    findings: list[AuditFinding] = []
    rel_file = Path(function.file).relative_to(repo_root).as_posix()

    for param in function.params:
        stripped = param.strip()
        if "ResOpt(" in stripped:
            severity = "warn"
            message = f"Optional resource system param should be reviewed: `{stripped}`"
            category = "optional-resource-param"
            if "CurrentPhase" in stripped:
                severity = "error"
                category = "optional-phase-resource"
                message = "Current phase is being treated as optional in a registered system."
            findings.append(
                AuditFinding(
                    category=category,
                    severity=severity,
                    file=rel_file,
                    line=function.line,
                    function=function.name,
                    message=message,
                )
            )

    findings.extend(pattern_findings(rel_file, function, "commands.getResource(", "hidden-resource-read", "System reads a resource through `Commands` instead of declaring it as a system param."))
    findings.extend(pattern_findings(rel_file, function, "commands.getResourceMut(", "hidden-resource-mutation", "System reads a mutable resource through `Commands` instead of declaring it as a system param."))
    findings.extend(pattern_findings(rel_file, function, "commands.query(", "hidden-query", "System creates a query through `Commands` instead of declaring it as a `Query(...)` system param."))
    findings.extend(pattern_findings(rel_file, function, "commands.groupBy(", "hidden-groupby", "System creates a group query through `Commands` instead of declaring it as a `GroupBy(...)` system param."))
    findings.extend(pattern_findings(rel_file, function, "commands.world", "world-escape", "System reaches through `Commands` into the world directly, which bypasses the system param contract."))
    findings.extend(pattern_findings(rel_file, function, "dbMut(", "database-escape", "Function reaches directly into the database, which hides data dependencies from scheduling."))

    mutation_positions = sorted(find_position(function.body, token) for token in MUTATION_PATTERNS if find_position(function.body, token) is not None)
    read_positions = sorted(find_position(function.body, token) for token in LIVE_READ_PATTERNS if find_position(function.body, token) is not None)
    if mutation_positions and read_positions and mutation_positions[0] < read_positions[-1]:
        findings.append(
            AuditFinding(
                category="queued-mutation-followed-by-live-read",
                severity="error",
                file=rel_file,
                line=function.line + line_offset(function.body, read_positions[0]),
                function=function.name,
                message="Function queues mutations and also performs live reads via `Commands`, which makes the visible state order-dependent.",
            )
        )

    return findings


def lifecycle_findings_for_function(repo_root: Path, function: FunctionSpec) -> list[AuditFinding]:
    findings: list[AuditFinding] = []
    rel_file = Path(function.file).relative_to(repo_root).as_posix()
    if "ctx.world.dbMut()" in function.body or ".createEntityWithId(" in function.body or ".reserveEntityId(" in function.body:
        findings.append(
            AuditFinding(
                category="phase-lifecycle-database-escape",
                severity="warn",
                file=rel_file,
                line=function.line,
                function=function.name,
                message="Phase lifecycle callback reaches directly into the database instead of using queued `Commands` helpers.",
            )
        )
    if "ctx.world.insertResource(" in function.body and "commands.createEntity(" in function.body:
        findings.append(
            AuditFinding(
                category="mixed-world-and-commands-writes",
                severity="warn",
                file=rel_file,
                line=function.line,
                function=function.name,
                message="Callback mixes direct world writes with queued `Commands` writes in the same function.",
            )
        )
    return findings


def pattern_findings(rel_file: str, function: FunctionSpec, token: str, category: str, message: str) -> list[AuditFinding]:
    position = find_position(function.body, token)
    if position is None:
        return []
    return [
        AuditFinding(
            category=category,
            severity="warn",
            file=rel_file,
            line=function.line + line_offset(function.body, position),
            function=function.name,
            message=message,
        )
    ]


def param_kind(param: str) -> str:
    stripped = param.strip()
    for prefix in SYSTEM_PARAM_PREFIXES:
        if prefix in stripped:
            return prefix[:-1]
    if stripped.startswith("*ecs.Commands") or stripped.startswith("*Commands"):
        return "*Commands"
    return "other"


def iter_zig_files(repo_root: Path) -> list[Path]:
    roots = (repo_root / "examples", repo_root / "lib")
    files: list[Path] = []
    for root in roots:
        if not root.is_dir():
            continue
        files.extend(sorted(root.rglob("*.zig")))
    return files


@dataclass(frozen=True)
class ParsedRegistration:
    registrar_line: int
    schedule: str
    reference: str


def parse_registrations(file_path: Path, text: str) -> list[ParsedRegistration]:
    registrations: list[ParsedRegistration] = []
    for line_number, line in enumerate(text.splitlines(), start=1):
        for pattern in REGISTRATION_PATTERNS:
            match = pattern.search(line)
            if not match:
                continue
            schedule = normalize_schedule(match.groupdict().get("schedule"))
            registrations.append(
                ParsedRegistration(
                    registrar_line=line_number,
                    schedule=schedule,
                    reference=match.group("ref"),
                )
            )
    return registrations


def normalize_schedule(raw_schedule: str | None) -> str:
    if raw_schedule is None:
        return "DefaultSchedule.Update"
    return " ".join(raw_schedule.strip().split())


def parse_imports(text: str) -> dict[str, str]:
    return {alias: target for alias, target in IMPORT_RE.findall(text)}


def resolve_reference(file_path: Path, reference: str, imports: dict[str, str]) -> tuple[Path | None, str | None]:
    if "." not in reference:
        return file_path, reference
    prefix, function_name = reference.split(".", 1)
    import_target = imports.get(prefix)
    if import_target is None:
        return None, function_name
    target_path = (file_path.parent / import_target).resolve()
    return target_path, function_name


def parse_functions(file_path: Path, text: str) -> dict[str, FunctionSpec]:
    functions: dict[str, FunctionSpec] = {}
    for match in FN_RE.finditer(text):
        name = match.group(1)
        param_start = match.end() - 1
        param_end = find_matching(text, param_start, "(", ")")
        if param_end is None:
            continue
        body_start = text.find("{", param_end)
        if body_start == -1:
            continue
        body_end = find_matching(text, body_start, "{", "}")
        if body_end is None:
            continue
        params = split_top_level(text[param_start + 1 : param_end])
        line = text.count("\n", 0, match.start()) + 1
        functions[name] = FunctionSpec(
            file=str(file_path),
            name=name,
            line=line,
            params=params,
            body=text[body_start + 1 : body_end],
        )
    return functions


def split_top_level(text: str) -> list[str]:
    parts: list[str] = []
    current: list[str] = []
    depth_paren = 0
    depth_brace = 0
    depth_bracket = 0
    for char in text:
        if char == "," and depth_paren == 0 and depth_brace == 0 and depth_bracket == 0:
            item = "".join(current).strip()
            if item:
                parts.append(item)
            current = []
            continue
        current.append(char)
        if char == "(":
            depth_paren += 1
        elif char == ")":
            depth_paren -= 1
        elif char == "{":
            depth_brace += 1
        elif char == "}":
            depth_brace -= 1
        elif char == "[":
            depth_bracket += 1
        elif char == "]":
            depth_bracket -= 1
    item = "".join(current).strip()
    if item:
        parts.append(item)
    return parts


def find_matching(text: str, start: int, open_char: str, close_char: str) -> int | None:
    depth = 0
    for index in range(start, len(text)):
        char = text[index]
        if char == open_char:
            depth += 1
        elif char == close_char:
            depth -= 1
            if depth == 0:
                return index
    return None


def find_position(text: str, token: str) -> int | None:
    position = text.find(token)
    return position if position >= 0 else None


def line_offset(text: str, position: int) -> int:
    return text.count("\n", 0, position)
