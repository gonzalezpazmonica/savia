#!/usr/bin/env python3
"""
agent-frontmatter-update.py — SE-270 Slice 4: Programmatic YAML frontmatter update.

Reads all 81 agents from .opencode/agents/*.md and updates/adds:
    maxSteps: N              (based on model tier: fast→8, mid→15, heavy→from maxTurns)
    permission.task:         (allowlist with reasonable subagent targets)

Does NOT modify agent body text, only frontmatter.
Preserves existing YAML structure and formatting.

Ref: SE-270
"""

import os
import sys
import re
import shutil
from pathlib import Path

REPO_ROOT = os.environ.get("REPO_ROOT", os.getcwd())
AGENTS_DIR = os.path.join(REPO_ROOT, ".opencode", "agents")
BACKUP_DIR = os.path.join(REPO_ROOT, "output", "agent-frontmatter-backup")

def parse_frontmatter(text):
    """Parse YAML frontmatter from text. Returns (dict, body_text)."""
    match = re.match(r'^---\s*\n(.*?)\n---\s*\n(.*)', text, re.DOTALL)
    if not match:
        raise ValueError("No frontmatter found")
    yaml_text = match.group(1)
    body = match.group(2)
    return yaml_text, body

def parse_yaml_simple(text):
    """Parse simple YAML key-value pairs from frontmatter text.
    Preserves ordering. Handles nested structures minimally."""
    lines = text.split('\n')
    result = {}
    current_key = None
    current_indent = 0
    in_nested = False
    nested_lines = []

    for line in lines:
        stripped = line.rstrip()
        if not stripped:
            if in_nested:
                nested_lines.append('')
            continue

        indent = len(line) - len(line.lstrip())

        if in_nested:
            if indent > current_indent:
                nested_lines.append(stripped)
                continue
            else:
                # End of nested block
                result[current_key] = '\n'.join(nested_lines)
                in_nested = False
                nested_lines = []

        # Match key: value (simple scalar)
        m = re.match(r'^(\w[\w_-]*):\s*(.*)', stripped)
        if not m:
            if in_nested:
                nested_lines.append(stripped)
            continue

        key = m.group(1)
        val = m.group(2).strip()

        if val == '':
            # Could be start of nested block (next line indented)
            # Check if next non-empty line is more indented
            current_key = key
            current_indent = indent
            in_nested = True
            nested_lines = []
        elif val in ('true', 'false'):
            result[key] = val == 'true'
        elif val.startswith('"') and val.endswith('"'):
            result[key] = val[1:-1]
        elif val.isdigit():
            result[key] = int(val)
        elif val.startswith('[') and val.endswith(']'):
            result[key] = parse_list(val)
        else:
            result[key] = val

    if in_nested:
        result[current_key] = '\n'.join(nested_lines)

    return result

def parse_list(s):
    """Parse a simple YAML list like [a, b, c]."""
    s = s.strip('[] ')
    if not s:
        return []
    items = []
    for item in s.split(','):
        item = item.strip().strip('"').strip("'")
        if item:
            items.append(item)
    return items

def render_frontmatter(entries, existing_yaml_text):
    """Update existing YAML frontmatter text with new entries.
    Preserves existing structure as much as possible.
    Returns (rendered_yaml_text, consumed_keys).
    consumed_keys are entries that were merged into existing fields (e.g., maxSteps replaced maxTurns)."""
    lines = existing_yaml_text.split('\n')
    new_lines = []
    consumed = set()
    i = 0

    while i < len(lines):
        line = lines[i]
        stripped = line.rstrip()
        indent = len(line) - len(line.lstrip())

        m = re.match(r'^(\w[\w_-]*):', stripped)
        if m:
            key = m.group(1)

            if key == 'maxTurns' and 'maxSteps' in entries:
                # Replace maxTurns with maxSteps
                new_lines.append(f'{" " * indent}maxSteps: {entries["maxSteps"]}')
                consumed.add('maxSteps')
                i += 1
                continue

            new_lines.append(line)
            i += 1
        else:
            new_lines.append(line)
            i += 1

    # Append remaining new entries before the closing ---
    remaining = {k: v for k, v in entries.items() if k not in consumed}
    if remaining:
        while new_lines and new_lines[-1].strip() == '':
            new_lines.pop()

        for key, value in remaining.items():
            if key == 'permission.task':
                new_lines.append(f'{key}:')
                new_lines.append(f'  allowlist: {render_list(value)}')
            elif isinstance(value, bool):
                new_lines.append(f'{key}: {"true" if value else "false"}')
            elif isinstance(value, int):
                new_lines.append(f'{key}: {value}')
            elif isinstance(value, list):
                new_lines.append(f'{key}: {render_list(value)}')
            else:
                new_lines.append(f'{key}: {value}')

    return '\n'.join(new_lines), consumed

def render_list(items):
    """Render a Python list as YAML inline list string."""
    if not items:
        return '[]'
    quoted = [f'"{item}"' for item in items]
    return '[' + ', '.join(quoted) + ']'

def get_max_steps(model, max_turns):
    """Determine maxSteps based on model tier and existing maxTurns."""
    if model == 'fast':
        return 8
    elif model == 'mid':
        return 15
    elif model == 'heavy':
        if max_turns:
            return max_turns
        return None  # Will be inferred below
    return None

def get_allowlist(agent_name, model, permission_level, description):
    """Determine reasonable subagent allowlist based on agent role and type."""
    # Fast agents: minimal delegation
    # Mid agents: moderate delegation based on role
    # Heavy agents: broader delegation for orchestrators

    is_orchestrator = any(kw in description.lower() for kw in [
        'orchestrator', 'orchestrat', 'convene', 'convenes',
        'orquestación', 'orquestador'
    ])
    is_judge = 'judge' in agent_name
    is_developer = any(kw in agent_name for kw in [
        'developer', 'engineer'
    ]) and agent_name not in ('architect', 'diagram-architect')
    is_security = any(kw in agent_name for kw in [
        'security', 'pentester', 'guardian'
    ])
    is_digest = any(kw in agent_name for kw in [
        'digest', 'pdf', 'word', 'pptx', 'archive'
    ]) and 'visual-qa' not in agent_name
    is_architect = any(kw in agent_name for kw in [
        'architect', 'diagram'
    ])

    if is_orchestrator:
        # Orchestrators can call their pool of judges/workers
        if 'court' in agent_name:
            return [
                "architecture-judge", "cognitive-judge", "correctness-judge",
                "security-judge", "spec-judge", "fix-assigner", "pr-agent-judge"
            ]
        elif 'truth' in agent_name:
            return [
                "factuality-judge", "coherence-judge", "completeness-judge",
                "compliance-judge", "calibration-judge", "hallucination-judge",
                "source-traceability-judge"
            ]
        elif 'recommendation' in agent_name:
            return [
                "sycophancy-judge", "concession-judge", "repetition-truth-judge",
                "authority-claim-judge", "hallucination-fast-judge",
                "memory-conflict-judge", "rule-violation-judge",
                "expertise-asymmetry-judge", "fiction-framing-judge",
                "structural-framing-judge"
            ]
        elif 'dev' in agent_name:
            return [
                "dotnet-developer", "java-developer", "python-developer",
                "typescript-developer", "go-developer", "rust-developer",
                "frontend-developer", "mobile-developer", "php-developer",
                "ruby-developer", "cobol-developer", "terraform-developer",
                "test-architect", "test-engineer", "sdd-spec-writer"
            ]
    elif is_judge:
        return []
    elif is_developer:
        targets = set(["test-engineer", "test-architect"])
        targets.discard(agent_name)
        return sorted(targets)
    elif is_security:
        if agent_name != "security-auditor":
            return ["security-auditor"]
        return []
    elif is_digest and agent_name != 'archive-digest':
        return ["archive-digest"]
    elif agent_name == 'configurator':
        return []
    elif agent_name == 'memory-agent':
        return []
    elif agent_name == 'commit-guardian':
        return ["security-guardian", "confidentiality-auditor", "dotnet-developer",
                "java-developer", "python-developer", "typescript-developer"]
    elif agent_name == 'drift-auditor':
        return ["reconciler"]
    elif agent_name == 'confidentiality-auditor':
        return ["security-guardian"]
    elif agent_name == 'model-upgrade-auditor':
        return ["dotnet-developer", "java-developer", "python-developer", "typescript-developer"]
    elif agent_name == 'feasibility-probe':
        return ["dotnet-developer", "python-developer", "typescript-developer"]

    # Default: no delegation for simple agents
    return []

def process_agents(dry_run=False):
    """Process all agents."""
    agents_dir = Path(AGENTS_DIR)
    if not agents_dir.exists():
        print(f"ERROR: agents directory not found: {AGENTS_DIR}", file=sys.stderr)
        sys.exit(2)

    agent_files = sorted(agents_dir.glob("*.md"))
    if not agent_files:
        print(f"ERROR: no agents found in {AGENTS_DIR}", file=sys.stderr)
        sys.exit(2)

    modified = 0
    skipped = 0
    errors = 0

    if not dry_run:
        os.makedirs(BACKUP_DIR, exist_ok=True)

    for agent_file in agent_files:
        agent_name = agent_file.stem

        try:
            with open(agent_file, 'r', encoding='utf-8') as f:
                content = f.read()

            yaml_text, body = parse_frontmatter(content)
            fm = parse_yaml_simple(yaml_text)

            model = fm.get('model_tier', fm.get('model', 'unknown'))
            max_turns = fm.get('maxTurns', None)
            has_max_steps = 'maxSteps' in fm
            has_permission_task = 'permission.task' in fm
            has_task = 'task' in fm
            description = fm.get('description', '')

            permission_level = fm.get('permission_level', 'L1')

            # Determine maxSteps
            max_steps = get_max_steps(model, max_turns)
            if max_steps is None and model == 'heavy':
                perm = fm.get('permission_level', 'L1')
                if perm in ('L3', 'L4'):
                    max_steps = 30
                elif perm == 'L2':
                    max_steps = 25
                else:
                    max_steps = 20

            # Determine allowlist
            allowlist = get_allowlist(agent_name, model, permission_level, description)

            updates = {}
            if not has_max_steps and max_steps is not None:
                updates['maxSteps'] = max_steps
            if not has_permission_task:
                updates['permission.task'] = allowlist

            if not updates:
                skipped += 1
                continue

            # Capture values before render_frontmatter consumes them
            dry_max_steps = updates.get('maxSteps', None)
            dry_allowlist = updates.get('permission.task', None)

            # Backup original
            if not dry_run:
                backup_path = os.path.join(BACKUP_DIR, f"{agent_name}.md.bak")
                shutil.copy2(str(agent_file), backup_path)

            # Render new frontmatter
            new_yaml, consumed = render_frontmatter(updates, yaml_text)
            new_content = f"---\n{new_yaml}\n---\n{body}"

            if dry_run:
                print(f"[DRY-RUN] Would update: {agent_name}")
                if dry_max_steps is not None:
                    print(f"  + maxSteps: {dry_max_steps}")
                if dry_allowlist is not None:
                    print(f"  + permission.task.allowlist: {dry_allowlist}")
                modified += 1
            else:
                with open(agent_file, 'w', encoding='utf-8') as f:
                    f.write(new_content)
                modified += 1
                print(f"UPDATED: {agent_name}")

        except Exception as e:
            errors += 1
            print(f"ERROR processing {agent_name}: {e}", file=sys.stderr)

    print(f"\nagent-frontmatter-update: total={len(agent_files)} modified={modified} skipped={skipped} errors={errors}")
    if not dry_run:
        print(f"  backups: {BACKUP_DIR}")
    return errors == 0


def main():
    dry_run = '--dry-run' in sys.argv
    args = [a for a in sys.argv[1:] if a != '--dry-run']

    if '-h' in args or '--help' in args:
        print(__doc__)
        print("Usage: agent-frontmatter-update.py [--dry-run]")
        print("  --dry-run  Preview changes without writing files")
        sys.exit(0)

    success = process_agents(dry_run=dry_run)
    sys.exit(0 if success else 1)


if __name__ == '__main__':
    main()
