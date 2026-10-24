#!/usr/bin/env python3
"""
generate-capability-map.py — Generate `.scm/` (Savia Capability Map) from
workspace resources (commands, skills, agents, scripts).

Drop-in replacement for the Bash version (`generate-capability-map.sh`) that
was O(resources × process_spawn) slow on Windows — often >1 hour for 1000
resources. This Python version runs the same logic in-process and completes
in seconds.

Outputs:
  .scm/INDEX.scm                      — flat index, one line per resource
  .scm/categories/<category>.scm      — grouped by coarse category
  .scm/categories/resources.json      — machine-readable mirror (NEW)

Categories: analysis, communication, development, governance, memory,
planning, quality.
"""
from __future__ import annotations

import hashlib
import json
import re
import os
import sys
import tempfile
import time
from pathlib import Path
from typing import Iterable

# ── Regexes (precompiled once) ────────────────────────────────────────────
# Matches YAML frontmatter at the top of a markdown file.
FRONTMATTER_RE = re.compile(r"^---\s*\n(.*?)\n---\s*\n", re.DOTALL)
# Matches a simple `key: value` line inside frontmatter.
KV_RE = re.compile(r"^(?P<key>[A-Za-z_][A-Za-z0-9_-]*)\s*:\s*(?P<value>.*)$")
# Tokens for intent extraction (Spanish+English alphabet + accents).
INTENT_TOKEN_RE = re.compile(r"[a-záéíóúñüàèìòùâêîôûäëïöüçãæøå]{4,}")

# Stop-words that are too generic to serve as "intents" when surfacing
# a resource to an agent routing a user request.
STOPWORDS = frozenset(
    "para este esta desde como cada tiene puede cuando antes after with from "
    "that this will been have more than your into also sobre entre menos todos "
    "todas donde hasta tras sino pues luego mucho poco mismo cualquier "
    "necesita genera usa usar uso".split()
)


def classify_resource(resource_name: str, resource_description: str) -> str:
    """
    Pick one coarse category (development/quality/...) from the resource
    name + description. Name-prefix rules win over substring fallbacks so
    that `test-runner` classifies as 'quality' even if its description
    mentions 'deploy'.
    """
    name = resource_name.lower()
    # 1) Name-prefix rules (fast path, deterministic).
    prefix_rules: list[tuple[tuple[str, ...], str]] = [
        (("test-", "pr-", "security-", "a11y-", "qa-", "visual-", "coverage-", "perf-"), "quality"),
        (("spec-", "dev-", "arch-", "code-", "pipeline-", "deploy-", "dag-", "worktree-"), "development"),
        (("sprint-", "pbi-", "capacity-", "project-", "backlog-", "epic-", "flow-"), "planning"),
        (("report-", "dora-", "debt-", "risk-", "kpi-", "metric-", "trace-", "agent-"), "analysis"),
        (("memory-", "context-", "nl-", "session-", "compact-", "cache-"), "memory"),
        (("msg-", "notify-", "meeting-", "inbox-", "chat-", "slack-", "nctalk-", "savia-"), "communication"),
        (("compliance-", "governance-", "aepd-", "bias-", "equality-", "audit-"), "governance"),
    ]
    for prefixes, category in prefix_rules:
        if any(name.startswith(p) for p in prefixes):
            return category

    # 2) Substring fallback in combined text.
    combined = (name + " " + resource_description).lower()
    substring_rules: list[tuple[re.Pattern[str], str]] = [
        (re.compile(r"test|review|audit|security|lint|coverage"), "quality"),
        (re.compile(r"implement|code|build|deploy|spec|design"), "development"),
        (re.compile(r"sprint|capacity|estimat|decompos|assign|backlog"), "planning"),
        (re.compile(r"trace|metric|performance|debt|risk|report"), "analysis"),
        (re.compile(r"recall|save|search|consolidat|context|memory"), "memory"),
        (re.compile(r"notify|message|digest|meeting|inbox|chat"), "communication"),
        (re.compile(r"compliance|policy|governance|equality|aepd"), "governance"),
    ]
    for pattern, category in substring_rules:
        if pattern.search(combined):
            return category

    # 3) Default bucket.
    return "planning"


def extract_intents(description: str, max_tokens: int = 5) -> list[str]:
    """
    Return up to `max_tokens` "intent" keywords extracted from a description,
    sorted alphabetically and deduplicated. Lowercased, stopwords removed,
    only tokens of length >= 4. Used for quick fuzzy matching between user
    intent and resources at routing time.
    """
    tokens = INTENT_TOKEN_RE.findall(description.lower())
    unique = sorted({token for token in tokens if token not in STOPWORDS})
    return unique[:max_tokens]


def parse_frontmatter(file_path: Path) -> dict[str, str]:
    """
    Read a markdown file and return frontmatter keys as a flat dict
    (only top-level simple scalar values; nested YAML is ignored here
    because we never need it for indexing purposes).
    """
    try:
        text = file_path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return {}
    match = FRONTMATTER_RE.search(text)
    if not match:
        return {}
    body = match.group(1)
    fields: dict[str, str] = {}
    for line in body.splitlines():
        # Skip continuation / list item lines; we only care about root scalars.
        if not line or line[0] in (" ", "\t", "-"):
            continue
        kv = KV_RE.match(line)
        if not kv:
            continue
        key = kv.group("key").lower()
        value = kv.group("value").strip()
        # Strip surrounding quotes.
        if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
            value = value[1:-1]
        fields[key] = value[:240]
    return fields


def extract_script_description(file_path: Path) -> str:
    """
    Try to extract a short description from a shell script by reading the
    first few `#` comment lines (skipping the shebang line).
    """
    try:
        with file_path.open("r", encoding="utf-8", errors="replace") as handle:
            for i, line in enumerate(handle):
                if i >= 6:
                    break
                # Skip shebang; otherwise return the first comment payload.
                if line.startswith("#!"):
                    continue
                stripped = line.strip()
                if stripped.startswith("#"):
                    return stripped.lstrip("#").strip()[:240]
    except OSError:
        pass
    return ""


class ResourceEntry:
    """One discovered resource (command/skill/agent/script) with its metadata."""

    __slots__ = ("category", "name", "intents", "kind", "rel_path", "description")

    def __init__(self, category: str, name: str, intents: list[str], kind: str,
                 rel_path: str, description: str) -> None:
        self.category = category
        self.name = name
        self.intents = intents
        self.kind = kind
        self.rel_path = rel_path
        self.description = description

    def index_line(self) -> str:
        """Render the one-line representation used in INDEX.scm."""
        joined_intents = ",".join(self.intents)
        return f"[{self.category}] {self.name} — {joined_intents} — {self.kind}:{self.rel_path}"

    def category_line(self) -> str:
        """Render the longer representation used in category files."""
        return f"- **{self.name}** ({self.kind}): {self.description}"

    def to_dict(self) -> dict[str, object]:
        """Serializable mirror for resources.json."""
        return {
            "category": self.category,
            "name": self.name,
            "intents": self.intents,
            "kind": self.kind,
            "path": self.rel_path,
            "description": self.description,
        }


def scan_markdown_resources(pattern_glob: Path, kind: str, rel_root: Path,
                            name_fallback) -> Iterable[ResourceEntry]:
    """
    Yield ResourceEntry objects for each markdown file matched by the glob.
    `name_fallback(path)` is called when frontmatter has no `name` key.

    SE-253 Slice 1: commands with tier=extended are excluded from the core
    index (they are loaded on-demand via /catalog). Skills and agents are
    always included regardless of tier.
    """
    for file_path in pattern_glob:
        if not file_path.is_file():
            continue
        fields = parse_frontmatter(file_path)
        # SE-253: skip extended-tier commands from core session index
        if kind == "cmd" and fields.get("tier", "core").strip() == "extended":
            continue
        description = fields.get("description", "").strip()
        if not description:
            continue
        name = fields.get("name", "").strip() or name_fallback(file_path)
        if not name:
            continue
        intents = extract_intents(description)
        category = classify_resource(name, description)
        rel_path = file_path.relative_to(rel_root).as_posix()
        yield ResourceEntry(category, name, intents, kind, rel_path, description)


def scan_scripts(scripts_dir: Path, rel_root: Path) -> Iterable[ResourceEntry]:
    """Yield ResourceEntry objects for shell scripts in scripts/ (recursive).

    Scans top-level scripts/*.sh AND immediate subdirs scripts/<name>/*.sh
    so feature-grouped scripts (e.g. scripts/recommendation-tribunal/*.sh)
    are indexed too. Recursion is depth-1 to avoid pulling in node_modules
    or hidden caches. Symlinked dirs and dotted dirs are skipped.
    """
    sh_files: list[Path] = []
    # Top level
    sh_files.extend(sorted(scripts_dir.glob("*.sh")))
    # Depth-1 subdirs (excluding hidden + node_modules + __pycache__)
    for subdir in sorted(scripts_dir.iterdir()):
        if not subdir.is_dir():
            continue
        if subdir.is_symlink():
            continue
        if subdir.name.startswith(".") or subdir.name in {"node_modules", "__pycache__"}:
            continue
        sh_files.extend(sorted(subdir.glob("*.sh")))

    for file_path in sh_files:
        if not file_path.is_file():
            continue
        description = extract_script_description(file_path)
        if not description:
            continue
        # Use stem for top-level, prefix with subdir for nested to avoid name clashes
        rel = file_path.relative_to(scripts_dir)
        if rel.parent == Path("."):
            name = file_path.stem
        else:
            name = f"{rel.parent.as_posix()}/{file_path.stem}"
        intents = extract_intents(description)
        category = classify_resource(name, description)
        rel_path = file_path.relative_to(rel_root).as_posix()
        yield ResourceEntry(category, name, intents, "script", rel_path, description)


def write_index_file(index_path: Path, resources: list[ResourceEntry]) -> None:
    """Write the flat INDEX.scm file with a summary header."""
    by_kind: dict[str, int] = {}
    for resource in resources:
        by_kind[resource.kind] = by_kind.get(resource.kind, 0) + 1

    # Stable content hash over the sorted resource body — replaces the
    # mutable `generated: today` timestamp. Same inputs → same hash → same
    # file bytes → no git drift between sessions. See docs/rules/domain/
    # deterministic-artifacts.md (SE-031 lesson).
    sorted_resources = sorted(resources, key=lambda r: (r.category, r.name))
    body_lines = [resource.index_line() for resource in sorted_resources]
    content_hash = hashlib.sha256(
        ("\n".join(body_lines)).encode("utf-8")
    ).hexdigest()[:12]

    header_lines = [
        "# Savia Capability Map — INDEX",
        f"> hash: {content_hash} | resources: {len(resources)}",
        "> " + " · ".join(
            f"{by_kind.get(k, 0)} {label}"
            for k, label in (("cmd", "commands"), ("skill", "skills"),
                             ("agent", "agents"), ("script", "scripts"))
        ),
        "",
    ]
    index_path.write_text("\n".join(header_lines + body_lines) + "\n", encoding="utf-8")


def write_category_files(category_dir: Path, resources: list[ResourceEntry]) -> None:
    """Write one .scm file per category with a human-readable listing."""
    all_categories = ("quality", "development", "planning", "analysis",
                      "memory", "communication", "governance")
    grouped: dict[str, list[ResourceEntry]] = {cat: [] for cat in all_categories}
    for resource in resources:
        grouped.setdefault(resource.category, []).append(resource)

    for category in all_categories:
        entries = sorted(grouped.get(category, []), key=lambda r: r.name)
        lines = [
            f"# {category} — Savia Capability Map (L1)",
            f"> {len(entries)} resources",
            "",
        ]
        lines.extend(entry.category_line() for entry in entries)
        (category_dir / f"{category}.scm").write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_resources_json(json_path: Path, resources: list[ResourceEntry]) -> None:
    """Write a machine-readable JSON mirror (used by hooks / fast lookups).

    Uses a stable content hash instead of a timestamp so the file is
    byte-identical across regenerations when inputs haven't changed.
    """
    sorted_resources = sorted(resources, key=lambda r: (r.category, r.name))
    resource_dicts = [r.to_dict() for r in sorted_resources]
    content_hash = hashlib.sha256(
        json.dumps(resource_dicts, ensure_ascii=False, sort_keys=True).encode("utf-8")
    ).hexdigest()[:12]
    payload = {
        "hash": content_hash,
        "total": len(resources),
        "resources": resource_dicts,
    }
    json_path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def write_registry_json(scm_dir: Path, resources: list[ResourceEntry]) -> None:
    """SE-375 — Canonical Capability Registry (machine-readable, deterministic).

    Evoluciona .scm (no compite): mismo hash estable que resources.json.
    Campos por capability: id, kind, source, status, owner_domain, intents,
    risk_level, frontend_support, depends_on, tests, replaced_by.
    Kinds diferidos (S2): rule, hook — documentados en deferred_kinds.
    """
    sorted_resources = sorted(resources, key=lambda r: (r.category, r.name))
    content_hash = hashlib.sha256(
        json.dumps([r.to_dict() for r in sorted_resources], ensure_ascii=False, sort_keys=True).encode("utf-8")
    ).hexdigest()[:12]

    capabilities = []
    for r in sorted_resources:
        risk = None
        status = "active"
        src = Path(r.rel_path)
        if r.kind == "agent":
            try:
                text = src.read_text(encoding="utf-8", errors="replace")[:2000]
                m = re.search(r"^(permission|permission_level):\s*(L[0-4])", text, re.MULTILINE)
                risk = m.group(2) if m else None
                if re.search(r"^deprecated:\s*true", text, re.MULTILINE):
                    status = "deprecated"
            except OSError:
                pass
        elif r.kind == "skill":
            try:
                text = src.read_text(encoding="utf-8", errors="replace")[:2000]
                if re.search(r"^deprecated:\s*true", text, re.MULTILINE):
                    status = "deprecated"
            except OSError:
                pass
        if r.kind == "cmd":
            frontend = ["claude", "opencode"]
        elif str(src).startswith(".claude"):
            frontend = ["claude"]
        else:
            frontend = ["opencode"]
        stem = str(src)[:-len(src.suffix)] if src.suffix else str(src)
        capabilities.append({
            "id": f"{r.kind}:{stem}",
            "kind": r.kind,
            "source": str(src),
            "status": status,
            "owner_domain": r.category,
            "intents": sorted(set(r.intents)),
            "risk_level": risk,
            "frontend_support": frontend,
            "depends_on": [],
            "tests": [],
            "replaced_by": None,
        })

    payload = {
        "registry_version": 1,
        "content_hash": content_hash,
        "kinds_included": ["command", "skill", "agent", "script"],
        "deferred_kinds": ["rule", "hook"],
        "capabilities": capabilities,
    }
    (scm_dir / "registry.json").write_text(
        json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def main(argv: list[str]) -> int:
    # Parse flags
    check_mode = False
    output_arg = None
    for arg in argv[1:]:
        if arg == "--check":
            check_mode = True
        elif arg.startswith("-"):
            print(f"Unknown flag: {arg}", file=sys.stderr)
            print("Usage: generate-capability-map.py [--check] [output_dir]", file=sys.stderr)
            return 2
        else:
            output_arg = arg

    if check_mode and output_arg is not None:
        print("Error: --check and output path are mutually exclusive", file=sys.stderr)
        return 2

    start_time = time.monotonic()
    repo_root = Path(output_arg).resolve() if output_arg else Path(__file__).resolve().parents[1]
    if not repo_root.is_dir():
        print(f"Error: directory not found: {repo_root}", file=sys.stderr)
        return 2
    scm_dir = repo_root / ".scm"
    categories_dir = scm_dir / "categories"

    # ── --check mode: regenerate in temp dir, compare, NEVER write to real .scm/ ──
    # SAVIA_SCM_DIR compares against another .scm copy (tests mutate a copy,
    # never the repo). Byte comparison: a hand edit in the body of INDEX.scm
    # or resources.json is stale too, not only a header hash change.
    if check_mode:
        compare_dir = Path(os.environ["SAVIA_SCM_DIR"]) if os.environ.get("SAVIA_SCM_DIR") else scm_dir
        index_file = compare_dir / "INDEX.scm"
        if not index_file.exists():
            print(f"SCM: MISSING (no {index_file})")
            return 2

        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_scm = Path(tmpdir) / ".scm"
            tmp_cat = tmp_scm / "categories"
            tmp_cat.mkdir(parents=True, exist_ok=True)

            resources = _collect_resources(repo_root)
            write_index_file(tmp_scm / "INDEX.scm", resources)
            write_category_files(tmp_cat, resources)
            write_resources_json(tmp_scm / "resources.json", resources)
            write_registry_json(tmp_scm, resources)

            stale = [
                name for name in ("INDEX.scm", "registry.json", "resources.json")
                if (compare_dir / name).exists()
                and (compare_dir / name).read_bytes() != (tmp_scm / name).read_bytes()
            ]
            if not stale:
                print(f"SCM: FRESH ({len(resources)} resources)")
                return 0
            print(f"SCM: STALE (distinto de una generación nueva: {', '.join(stale)})")
            return 1
        # tempdir auto-cleaned

    # ── Normal mode: regenerate into real .scm/ ──
    categories_dir.mkdir(parents=True, exist_ok=True)

    resources = _collect_resources(repo_root)

    write_index_file(scm_dir / "INDEX.scm", resources)
    write_category_files(categories_dir, resources)
    write_resources_json(scm_dir / "resources.json", resources)
    write_registry_json(scm_dir, resources)

    elapsed_seconds = time.monotonic() - start_time
    kind_totals = {k: sum(1 for r in resources if r.kind == k)
                   for k in ("cmd", "skill", "agent", "script")}
    print(
        f"SCM generated: {len(resources)} resources in {scm_dir}/  "
        f"({elapsed_seconds:.2f}s)"
    )
    print(
        f"  {kind_totals['cmd']} commands · {kind_totals['skill']} skills · "
        f"{kind_totals['agent']} agents · {kind_totals['script']} scripts"
    )
    return 0


def _collect_resources(repo_root: Path) -> list[ResourceEntry]:
    """Collect all resources from the 4 sources (shared by normal + check modes)."""
    resources: list[ResourceEntry] = []

    commands_glob = (repo_root / ".claude" / "commands").glob("*.md")
    resources.extend(scan_markdown_resources(
        commands_glob, "cmd", repo_root,
        name_fallback=lambda path: path.stem,
    ))

    skills_glob = (repo_root / ".claude" / "skills").glob("*/SKILL.md")
    resources.extend(scan_markdown_resources(
        skills_glob, "skill", repo_root,
        name_fallback=lambda path: path.parent.name,
    ))

    # SE-220: source of truth = .opencode/agents/ (consistent with
    # agents-md-generate.sh and agents-catalog-sync.sh).
    agents_glob = (repo_root / ".opencode" / "agents").glob("*.md")
    resources.extend(scan_markdown_resources(
        agents_glob, "agent", repo_root,
        name_fallback=lambda path: path.stem,
    ))

    resources.extend(scan_scripts(repo_root / "scripts", repo_root))

    return resources


def _read_index_hash(index_path: Path) -> str:
    """Read the content hash from the header of INDEX.scm."""
    try:
        for line in index_path.read_text(encoding="utf-8").splitlines():
            if line.startswith("> hash: "):
                return line.split("hash: ")[1].split()[0]
    except OSError:
        return "none"
    return "none"


if __name__ == "__main__":
    sys.exit(main(sys.argv))
