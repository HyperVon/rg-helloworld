#!/usr/bin/env python3
"""Index a target repository's Agent Guidance Kit adoption against the catalog.

Read-only, deterministic, network-free. Produces a plain index: every skill in
the kit catalog that the target has **not** already adopted (recorded in
receipts) and that is **not** reserved for kit maintainers (``SOURCE_ONLY``),
each with the path to its ``SKILL.md``. It deliberately makes **no** applicability
or exclusion decision by language, framework, or name — the active agent reads
each candidate ``SKILL.md`` and decides whether to adopt it as a straight copy,
integrate it into existing guidance, or skip it.

``SOURCE_ONLY`` skills (for example ``catalog-discovery``) are intentionally
**omitted** from the index and **refused by the installer**, so a target can never
adopt a maintainer-only skill by mistake. A candidate that shares a name with a
skill already present in the target is reported as a ``collisions`` entry — an
evaluate-don't-drop signal (``KEEP_LOCAL`` / ``ADAPT`` / ``REPLACE``), never an
exclusion.

This is the target-facing mirror of ``catalog-discovery``: that skill expands the
kit's own catalog and is ``SOURCE_ONLY``, while this index helps an adopted target
discover net-new guidance it should consider. Adoption of any candidate still
requires the normal plan/approval gate via bootstrap-project.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Optional

_HERE = Path(__file__).resolve().parent
_BOOTSTRAP = _HERE.parents[1] / "bootstrap-project" / "scripts"
for _p in (_HERE, _BOOTSTRAP):
    _s = str(_p)
    if _s not in sys.path:
        sys.path.insert(0, _s)

import inventory_project  # noqa: E402
import resolve_source  # noqa: E402

try:
    import yaml  # type: ignore
except ImportError:  # pragma: no cover - PyYAML is a declared dev dependency
    yaml = None  # type: ignore


CATALOG_SKILLS = Path(".agents/skills")
RECEIPTS = Path(".agents/.agent-guidance-kit/receipts")

# Fallback matcher only. The authoritative SOURCE_ONLY signal is the frontmatter
# `source_only: true` flag (see read_catalog). This regex remains as a backstop
# for skills whose prose says "is `SOURCE_ONLY`" but predate the structured flag,
# and must not be the sole gate — the installer shares an equivalent backstop.
SOURCE_ONLY_RE = re.compile(r"(?:is|this skill) `SOURCE_ONLY`")


# --------------------------------------------------------------------------- #
# Catalog and receipt reading
# --------------------------------------------------------------------------- #
def _parse_frontmatter(text: str) -> tuple[Optional[dict], Optional[str]]:
    if not text.startswith("---"):
        return None, "missing frontmatter delimiters"
    end = text.find("\n---", 3)
    if end == -1:
        return None, "unterminated frontmatter"
    body = text[3:end]
    if yaml is not None:
        try:
            values = yaml.safe_load(body)
        except yaml.YAMLError as error:  # type: ignore[attr-defined]
            return None, f"invalid YAML: {error}"
        if not isinstance(values, dict):
            return None, "frontmatter must be a mapping"
        return values, None
    values: dict[str, object] = {}
    for line in body.splitlines():
        if line.startswith("name:"):
            values["name"] = line.split(":", 1)[1].strip()
        elif line.startswith("description:"):
            values["description"] = line.split(":", 1)[1].strip()
        elif line.startswith("source_only:"):
            # Mirror the installer's flag detection when PyYAML is unavailable, so
            # a flag-only SOURCE_ONLY skill is still omitted from candidates.
            flag = line.split(":", 1)[1].strip().lower()
            values["source_only"] = flag in {"true", "yes", "1", "on"}
    return values, None


def read_catalog(kit_root: Path) -> list[dict]:
    skills_root = Path(kit_root) / CATALOG_SKILLS
    catalog: list[dict] = []
    if not skills_root.is_dir() or skills_root.is_symlink():
        return catalog
    for directory in sorted(skills_root.iterdir()):
        if directory.name.startswith(".") or directory.is_symlink():
            continue
        if not directory.is_dir():
            continue
        skill_md = directory / "SKILL.md"
        if skill_md.is_symlink() or not skill_md.is_file():
            continue
        try:
            text = skill_md.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        values, error = _parse_frontmatter(text)
        if values is None:
            continue
        name = values.get("name", "")
        description = values.get("description", "")
        if not isinstance(name, str) or not isinstance(description, str):
            continue
        # A skill is SOURCE_ONLY when its frontmatter declares `source_only: true`
        # (the structured, authoritative marker) or, as a fallback for skills that
        # predate it, when its prose describes itself that way. The structured
        # marker is the source of truth so the audit no longer depends on phrasing.
        raw_source_only = values.get("source_only")
        structured_source_only = raw_source_only is True or str(
            raw_source_only
        ).strip().lower() in {"true", "yes", "1"}
        catalog.append(
            {
                "name": name,
                "description": description,
                "path": f".agents/skills/{directory.name}/SKILL.md",
                "directory": directory.name,
                "source_only": structured_source_only
                or bool(SOURCE_ONLY_RE.search(text)),
            }
        )
    catalog.sort(key=lambda item: item["name"])
    return catalog


def local_skill_names(target: Path) -> set[str]:
    """Names of skills already present in the target as project-local skills.

    These live under ``.agents/skills/`` or ``.kilo/skills/`` (not the kit
    catalog). A catalog candidate that shares a name with a local skill is a
    *collision to evaluate* (KEEP_LOCAL / ADAPT / REPLACE), never an
    applicability exclusion — the agent must still read it and decide.
    """
    names: set[str] = set()
    for root in (
        Path(target) / ".agents" / "skills",
        Path(target) / ".kilo" / "skills",
    ):
        if not root.is_dir() or root.is_symlink():
            continue
        for directory in root.iterdir():
            if directory.name.startswith(".") or directory.is_symlink():
                continue
            if not directory.is_dir():
                continue
            skill_md = directory / "SKILL.md"
            if skill_md.is_file() and not skill_md.is_symlink():
                try:
                    text = skill_md.read_text(encoding="utf-8")
                except (OSError, UnicodeDecodeError):
                    continue
                values, parse_error = _parse_frontmatter(text)
                name = values.get("name") if isinstance(values, dict) else None
                if not (isinstance(name, str) and name):
                    # A physically-present local skill with no usable name cannot
                    # be matched against catalog collisions; surface it instead of
                    # silently losing the evaluate-don't-drop signal.
                    sys.stderr.write(
                        f"[adoption-audit] skipping local skill with no name "
                        f"frontmatter: {directory}\n"
                    )
                    continue
                names.add(name)
    return names


def read_adopted(target: Path) -> set[str]:
    names: set[str] = set()
    directory = Path(target) / RECEIPTS
    if not directory.is_dir() or directory.is_symlink():
        return names
    for path in sorted(directory.glob("*.json")):
        if path.is_symlink() or not path.is_file():
            continue
        try:
            value = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, UnicodeDecodeError, json.JSONDecodeError):
            continue
        skills = value.get("skills") if isinstance(value, dict) else None
        if not isinstance(skills, list):
            continue
        for item in skills:
            if not isinstance(item, dict):
                continue
            name = item.get("name")
            if isinstance(name, str) and name:
                names.add(name)
    return names


def select_candidates(
    catalog: list[dict], adopted: set[str], local_skills: set[str]
) -> tuple[list[dict], list[str]]:
    """Split the catalog into adoptable candidates and name collisions.

    ``catalog`` entries are the shape produced by :func:`read_catalog` (including
    ``directory`` and ``source_only``). ``adopted`` holds receipt skill names,
    which are directory names. A skill is excluded when it is ``SOURCE_ONLY`` or
    already adopted, matched by either its directory name (the receipt key) or its
    frontmatter ``name`` (an alias), so adoption is never keyed on a divergent
    display name. Same-name local skills become *collisions to evaluate*, never
    exclusions.
    """
    candidates = [
        {
            "name": skill["name"],
            "description": skill["description"],
            "skill_path": skill["path"],
        }
        for skill in catalog
        if not skill["source_only"]
        and skill["directory"] not in adopted
        and skill["name"] not in adopted
    ]
    candidates.sort(key=lambda item: item["name"])
    collisions = sorted({c["name"] for c in candidates if c["name"] in local_skills})
    return candidates, collisions


# --------------------------------------------------------------------------- #
# Report assembly
# --------------------------------------------------------------------------- #
def git_revision(root: Path) -> str:
    try:
        commit = subprocess.run(
            ["git", "-C", str(root), "rev-parse", "--short=12", "HEAD"],
            check=False,
            capture_output=True,
            text=True,
            timeout=5,
        )
        status = subprocess.run(
            ["git", "-C", str(root), "status", "--short"],
            check=False,
            capture_output=True,
            text=True,
            timeout=5,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return "unknown"
    if commit.returncode != 0:
        return "uncommitted"
    revision = commit.stdout.strip()
    if status.returncode == 0 and status.stdout.strip():
        revision += "+dirty"
    return revision


def run_audit(kit_root: Path, target: Path) -> dict:
    kit_root = resolve_source.validate_kit_root(Path(kit_root))
    target_path = Path(target).expanduser().resolve()
    if target_path.is_symlink() or not target_path.is_dir():
        raise ValueError(f"target must be a real directory: {target_path}")
    catalog = read_catalog(kit_root)
    adopted = read_adopted(target_path)
    inventory = inventory_project.inventory(target_path, 50_000)

    # Adoption is keyed by the skill *directory* name in receipts (the install
    # identity used by install_skills), not the frontmatter `name`. Match on both
    # so an adopted skill is never re-suggested even if its frontmatter name ever
    # diverges from its directory name.
    candidates, collisions = select_candidates(
        catalog, adopted, local_skill_names(target_path)
    )

    return {
        "schema_version": 4,
        "kit_root": str(kit_root),
        "kit_revision": git_revision(kit_root),
        "target": str(target_path),
        "catalog_total": len(catalog),
        "adopted": sorted(adopted),
        "adopted_count": len(adopted),
        "candidates": candidates,
        "collisions": collisions,
        "repo_signals": {
            "languages": inventory.get("languages_by_file_count", {}),
            "build_files": inventory.get("build_files", []),
            "test_roots": inventory.get("test_roots", []),
            "ci_files": inventory.get("ci_files", []),
            "harness_markers": inventory.get("harness_markers", []),
        },
    }


def _first_sentence(description: str) -> str:
    trimmed = description.strip()
    index = trimmed.find(". ")
    if index != -1:
        return trimmed[: index + 1]
    return trimmed


def markdown_report(report: dict) -> str:
    lines = [
        "# Agent Guidance Kit adoption audit",
        "",
        f"- Target: `{report['target']}`",
        f"- Kit: `{report['kit_root']}` @ `{report['kit_revision']}`",
        f"- Adopted: **{report['adopted_count']}** of "
        f"**{report['catalog_total']}** catalog skills",
        "",
        f"## Candidate skills to evaluate ({len(report['candidates'])})",
        "",
        "This is a plain index; **you decide applicability**. Read each "
        "candidate's `SKILL.md` (path in parentheses) and judge whether to "
        "adopt it as a straight copy, integrate it into existing guidance, or "
        "skip it. Skills reserved for kit maintainers are intentionally "
        "omitted from this list and refused by the installer, so no "
        "maintainer-only skill can be adopted by mistake. Many skills (for "
        "example code-review, ai-slop-detector, reduce-code-size, "
        "architecture-review, systematic-debugging, documentation-review) "
        "apply to most software repositories regardless of detected language "
        "or framework. A candidate that shares a name with a skill already in "
        "the target is listed under **Name collisions** below — it is still a "
        "candidate to evaluate, not an exclusion.",
        "",
    ]
    for skill in report["candidates"]:
        lines.append(
            f"- **{skill['name']}** — {_first_sentence(skill['description'])} "
            f"(`{skill['skill_path']}`)"
        )
    if report.get("collisions"):
        lines.extend(
            [
                "",
                "## Name collisions (evaluate, do not drop)",
                "",
                "These candidates share a name with a skill already present in "
                "the target (under `.agents/skills/` or `.kilo/skills/`). They "
                "are **not** excluded — read the catalog `SKILL.md` and decide: "
                "keep the local version (`KEEP_LOCAL`), merge kit improvements "
                "into it (`ADAPT`), or replace it with the kit version "
                "(`REPLACE`). A same name does not imply inapplicability.",
                "",
            ]
        )
        for name in report["collisions"]:
            lines.append(
                f"- **{name}** — collision with an existing local skill; "
                f"evaluate KEEP_LOCAL / ADAPT / REPLACE"
            )

    lines.extend(
        [
            "",
            "## Canonical guidance to review",
            "",
            "Compare source-owned `.agents/AGENTS.md` and `.agents/OPERATING.md` "
            "against the target (agent-guidance-maintenance step 4) and decide "
            "ADAPT / KEEP_LOCAL / DEFER for any changed section.",
            "",
            "Adoption of any applicable candidate still requires the normal "
            "plan/approval gate via bootstrap-project.",
            "",
        ]
    )
    return "\n".join(lines)


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", required=True, help="Target repository root")
    parser.add_argument(
        "--kit-root",
        default=None,
        help="Kit checkout root (resolved automatically when omitted)",
    )
    parser.add_argument("--format", choices=("json", "markdown"), default="json")
    args = parser.parse_args()

    target = Path(args.target).expanduser()
    if target.is_symlink() or not target.is_dir():
        print(f"error: target must be a real directory: {target}", file=sys.stderr)
        return 2
    try:
        if args.kit_root:
            kit_root = resolve_source.validate_kit_root(
                Path(args.kit_root).expanduser()
            )
        else:
            kit_root, _method = resolve_source.resolve_source(target)
    except resolve_source.SourceResolutionError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2

    try:
        report = run_audit(kit_root, target)
    except ValueError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2

    if args.format == "markdown":
        sys.stdout.write(markdown_report(report))
    else:
        json.dump(report, sys.stdout, indent=2)
        sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
