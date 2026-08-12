#!/usr/bin/env python3
"""Inventory local guidance and report exact repeated prose candidates.

The default behavior is read-only. The token figure is a rough ``characters / 4``
proxy, not a tokenizer measurement or a claim about how a host loads guidance.
The script uses only the Python standard library and never accesses the network.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import sys
from collections import defaultdict
from pathlib import Path

EXACT_NAMES = frozenset(
    {
        "AGENTS.md",
        "OPERATING.md",
        "CLAUDE.md",
        ".cursorrules",
        "SKILL.md",
        "copilot-instructions.md",
    }
)
GUIDANCE_ROOTS = frozenset({".agents", ".clinerules", ".codex", ".kilo", ".opencode"})
SKIP_DIRS = frozenset(
    {
        ".git",
        ".gradle",
        ".idea",
        ".openai",
        ".worktrees",
        "build",
        "node_modules",
        "out",
        "tmp",
    }
)
HEADING_RE = re.compile(r"^(#{1,6})\s+(.+?)\s*$")
WORD_RE = re.compile(r"\S+")
LINK_RE = re.compile(r"\[[^\]]+\]\(([^)]+)\)")
FRONTMATTER_NAME_RE = re.compile(r"^name:\s*['\"]?([^'\"\n]+)", re.MULTILINE)


def is_candidate(root: Path, path: Path) -> bool:
    relative = path.relative_to(root)
    parts = relative.parts
    if path.name in EXACT_NAMES:
        return True
    if ".cursor" in parts and "rules" in parts and path.suffix == ".mdc":
        return True
    if ".agents" in parts and path.suffix == ".md":
        return ".agents" in parts[:2] or "skills" in parts
    if any(directory in parts for directory in GUIDANCE_ROOTS) and path.suffix in {
        ".md",
        ".mdc",
    }:
        return True
    return relative == Path(".github/copilot-instructions.md")


def scope_for(root: Path, path: Path) -> str:
    relative = path.relative_to(root)
    parts = relative.parts
    if path.name.endswith("-backlog.md") or "memory" in parts:
        return "archive/related"
    if relative in {
        Path(".agents/AGENTS.md"),
        Path(".agents/OPERATING.md"),
        Path("AGENTS.md"),
        Path("CLAUDE.md"),
        Path(".github/copilot-instructions.md"),
    }:
        return "core entrypoint"
    if ".cursor" in parts or ".clinerules" in parts:
        return "harness projection"
    if ".agents" in parts and "skills" in parts:
        return "conditional skill"
    if ".kilo" in parts or ".opencode" in parts:
        return "harness-specific"
    return "related"


def role_for(root: Path, path: Path) -> str:
    relative = path.relative_to(root)
    parts = relative.parts
    if path.name == "SKILL.md":
        return "skill"
    if ".cursor" in parts or ".clinerules" in parts:
        return "harness projection"
    if relative == Path(".agents/AGENTS.md"):
        return "canonical rules/index"
    if relative == Path(".agents/OPERATING.md"):
        return "canonical operating norms"
    if path.name in {"AGENTS.md", "OPERATING.md", "CLAUDE.md", ".cursorrules"}:
        return "entrypoint/rules"
    if "skills" in parts:
        return "skill reference"
    if path.name.endswith("-backlog.md") or "memory" in parts:
        return "archive/related guidance"
    return "harness/agent guidance"


def iter_files(root: Path):
    for directory, dirnames, filenames in os.walk(
        root, topdown=True, followlinks=False
    ):
        base = Path(directory)
        dirnames[:] = sorted(
            name
            for name in dirnames
            if name not in SKIP_DIRS and not (base / name).is_symlink()
        )
        for filename in sorted(filenames):
            path = base / filename
            if not path.is_symlink() and path.is_file() and is_candidate(root, path):
                yield path


def frontmatter_name(text: str) -> str:
    if not text.startswith("---\n"):
        return ""
    end = text.find("\n---", 4)
    if end < 0:
        return ""
    match = FRONTMATTER_NAME_RE.search(text[4:end])
    return match.group(1).strip() if match else ""


def headings(text: str) -> list[str]:
    return [
        match.group(2)
        for line in text.splitlines()
        if (match := HEADING_RE.match(line))
    ]


def normalized_blocks(text: str):
    in_fence = False
    blocks: list[str] = []
    current: list[str] = []
    for line in text.splitlines():
        if line.strip().startswith("```"):
            in_fence = not in_fence
            if current:
                blocks.append(" ".join(current))
                current = []
            continue
        if in_fence or not line.strip():
            if current:
                blocks.append(" ".join(current))
                current = []
            continue
        current.append(line.strip())
    if current:
        blocks.append(" ".join(current))
    for block in blocks:
        normalized = re.sub(r"\s+", " ", block).strip()
        if len(normalized) < 100 or normalized.startswith("#"):
            continue
        if normalized.count("|") >= 2:
            continue
        yield normalized


def read_records(root: Path, scope: str):
    records = []
    blocks: defaultdict[str, list[str]] = defaultdict(list)
    for path in iter_files(root):
        file_scope = scope_for(root, path)
        if scope == "active" and file_scope == "archive/related":
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        relative = path.relative_to(root).as_posix()
        characters = len(text)
        records.append(
            {
                "path": relative,
                "scope": file_scope,
                "role": role_for(root, path),
                "lines": len(text.splitlines()),
                "words": len(WORD_RE.findall(text)),
                "characters": characters,
                "proxy_tokens": math.ceil(characters / 4),
                "headings": headings(text),
                "links": len(LINK_RE.findall(text)),
                "frontmatter_name": frontmatter_name(text),
            }
        )
        for block in normalized_blocks(text):
            if relative not in blocks[block]:
                blocks[block].append(relative)
    repeated = [
        {
            "characters": len(block),
            "proxy_tokens": math.ceil(len(block) / 4),
            "possible_saved_characters": len(block) * (len(paths) - 1),
            "paths": paths,
            "text": block,
        }
        for block, paths in blocks.items()
        if len(paths) > 1
    ]
    repeated.sort(
        key=lambda item: (
            item["possible_saved_characters"],
            item["characters"],
            item["paths"],
        ),
        reverse=True,
    )
    records.sort(key=lambda item: item["path"])
    return records, repeated


def as_markdown(root: Path, records, repeated) -> str:
    totals = {
        key: sum(record[key] for record in records)
        for key in ("lines", "words", "characters", "proxy_tokens")
    }
    active = [record for record in records if record["scope"] != "archive/related"]
    active_totals = {
        key: sum(record[key] for record in active)
        for key in ("lines", "words", "characters", "proxy_tokens")
    }
    lines = [
        "# Guidance inventory",
        "",
        f"Root: `{root}`",
        (
            f"Files: **{len(records):,}** | Lines: **{totals['lines']:,}** | "
            f"Words: **{totals['words']:,}** | Characters: **{totals['characters']:,}** | "
            f"Rough tokens (`characters / 4`): **{totals['proxy_tokens']:,}**"
        ),
        (
            f"Active guidance subset: **{len(active):,}** files | "
            f"Lines: **{active_totals['lines']:,}** | Words: **{active_totals['words']:,}** | "
            f"Rough tokens: **{active_totals['proxy_tokens']:,}**"
        ),
        "",
        "| File | Scope | Role | Lines | Words | Rough tokens | Headings | Links |",
        "| :--- | :--- | :--- | ---: | ---: | ---: | ---: | ---: |",
    ]
    for record in records:
        lines.append(
            f"| `{record['path']}` | {record['scope']} | {record['role']} | "
            f"{record['lines']:,} | {record['words']:,} | {record['proxy_tokens']:,} | "
            f"{len(record['headings'])} | {record['links']} |"
        )
    lines.extend(["", "## Exact repeated prose candidates", ""])
    if not repeated:
        lines.append("No repeated prose blocks met the 100-character threshold.")
    else:
        for index, item in enumerate(repeated[:20], start=1):
            excerpt = item["text"][:240]
            if len(item["text"]) > 240:
                excerpt += "..."
            lines.extend(
                [
                    (
                        f"{index}. **{item['characters']:,} chars / "
                        f"~{item['proxy_tokens']:,} proxy tokens**; possible duplicate "
                        "saving if one copy remains: "
                        f"**{item['possible_saved_characters']:,} chars**"
                    ),
                    f"   Files: {', '.join(f'`{path}`' for path in item['paths'])}",
                    f"   Text: {excerpt}",
                ]
            )
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=".", help="Repository root to inspect")
    parser.add_argument("--format", choices=("markdown", "json"), default="markdown")
    parser.add_argument(
        "--scope",
        choices=("active", "all"),
        default="active",
        help="Inspect active guidance (default) or include archive/related files",
    )
    parser.add_argument(
        "--output", help="Optional output file; stdout is used otherwise"
    )
    args = parser.parse_args(argv)
    root = Path(args.root).resolve()
    if not root.is_dir():
        print(f"error: root is not a directory: {root}", file=sys.stderr)
        return 2
    records, repeated = read_records(root, args.scope)
    if args.format == "json":
        output = (
            json.dumps(
                {
                    "root": str(root),
                    "scope": args.scope,
                    "files": records,
                    "repeated_blocks": repeated,
                },
                indent=2,
                sort_keys=True,
            )
            + "\n"
        )
    else:
        output = as_markdown(root, records, repeated)
    if args.output:
        output_path = Path(args.output)
        try:
            with output_path.open("x", encoding="utf-8") as handle:
                handle.write(output)
        except FileExistsError:
            print(
                f"error: output file already exists (refusing to overwrite): {output_path}",
                file=sys.stderr,
            )
            return 2
    else:
        sys.stdout.write(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
