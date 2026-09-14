#!/usr/bin/env python3
"""CLI adapter for the SE-397 read-only Savia Architecture Model."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import sys
import tempfile

from sam_model import (
    SamValidationError,
    _read_json,
    _validate_model,
    build_model,
    query_node,
    serialized_outputs,
    validate_model,
)


def _root_parser(subparsers, name: str, help_text: str):
    parser = subparsers.add_parser(name, help=help_text)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    return parser


def _atomic_write(root: Path, outputs: dict[str, bytes]) -> None:
    staged: list[tuple[Path, Path]] = []
    try:
        for relative, content in outputs.items():
            destination = root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            with tempfile.NamedTemporaryFile(
                dir=destination.parent, prefix=f".{destination.name}.", delete=False
            ) as handle:
                handle.write(content)
                handle.flush()
                os.fsync(handle.fileno())
                staged.append((Path(handle.name), destination))
        for temporary, destination in staged:
            temporary.replace(destination)
    except OSError as exc:
        for temporary, _ in staged:
            temporary.unlink(missing_ok=True)
        raise SamValidationError("WRITE_FAILED", ".scm") from exc


def _generate(root: Path) -> int:
    model = build_model(root)
    _atomic_write(root, serialized_outputs(model))
    print(f"SAM: GENERATED ({len(model['nodes'])} nodes, revision {model['model_revision'][:12]})")
    return 0


def _check(root: Path) -> int:
    expected_model = build_model(root)
    expected = serialized_outputs(expected_model)
    for relative in expected:
        path = root / relative
        if not path.is_file():
            raise SamValidationError("INVALID_MODEL", relative)
    committed = _read_json(root / ".scm/sam.json", "INVALID_MODEL")
    _validate_model(committed, root, verify_sources=False)
    for relative, content in expected.items():
        try:
            actual = (root / relative).read_bytes()
        except OSError as exc:
            raise SamValidationError("INVALID_MODEL", relative) from exc
        if actual != content:
            print(f"SAM: STALE ({relative})")
            return 1
    print(f"SAM: FRESH ({len(expected_model['nodes'])} nodes)")
    return 0


def _query(root: Path, node_id: str) -> int:
    model = _read_json(root / ".scm/sam.json", "INVALID_MODEL")
    try:
        validated = validate_model(model, root)
    except SamValidationError as exc:
        raise SamValidationError("INVALID_MODEL", exc.path) from exc
    print(json.dumps(query_node(validated, node_id), ensure_ascii=False, sort_keys=True))
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="SE-397 Savia Architecture Model")
    commands = parser.add_subparsers(dest="command", required=True)
    _root_parser(commands, "generate", "generate deterministic SAM artifacts")
    _root_parser(commands, "check", "check committed artifacts without writing")
    query = _root_parser(commands, "query", "query a committed SAM node")
    query.add_argument("--node", required=True)
    args = parser.parse_args(argv)
    root = args.root.resolve()
    try:
        if args.command == "generate":
            return _generate(root)
        if args.command == "check":
            return _check(root)
        return _query(root, args.node)
    except SamValidationError as exc:
        print(f"SAM ERROR {exc.code}: {exc.path}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
