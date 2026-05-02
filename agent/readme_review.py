"""
readme_review.py
Deterministic README drift checker for Push Hook events.

On pushes to the configured branch (default: dev), this module inspects changed
files and posts an advisory comment when code-impacting changes were made
without updating README.md.
"""

from __future__ import annotations

import os
from collections.abc import Iterable

from agent.gitlab_api import post_commit_comment


DEFAULT_README_PATH = os.getenv("README_REVIEW_PATH", "README.md")


def _collect_changed_files(payload: dict) -> set[str]:
    """Collect changed files from Push Hook payload commits."""
    files: set[str] = set()
    for commit in payload.get("commits", []):
        for key in ("added", "modified", "removed"):
            for path in commit.get(key, []):
                if path:
                    files.add(path)
    return files


def _has_docs_skip(payload: dict) -> bool:
    """Return True when any commit message contains [docs-skip]."""
    for commit in payload.get("commits", []):
        message = commit.get("message", "")
        if isinstance(message, str) and "[docs-skip]" in message.lower():
            return True
    return False


def _matches_any(path: str, patterns: Iterable[str]) -> bool:
    return any(path.startswith(prefix) for prefix in patterns)


def _is_docs_relevant(path: str) -> bool:
    """
    Heuristic for changes that commonly require README updates.
    Conservative by design to keep signal high and noise low.
    """
    lower = path.lower()

    if lower.startswith("tests/"):
        return False

    if lower in {
        "requirements.txt",
        "dockerfile",
        "docker-compose.yml",
        ".env.example",
        ".gitlab-ci.yml",
    }:
        return True

    if _matches_any(lower, ("agent/", "api/", "src/", "app/", "cli/", "config/")):
        return True

    if lower.endswith((".py", ".sh", ".yml", ".yaml", ".json", ".toml")):
        return True

    return False


def _suggestions_for(files: list[str]) -> list[str]:
    """Generate section-level README suggestions from changed paths."""
    lower_files = [f.lower() for f in files]
    suggestions: list[str] = []

    if any(
        f in {"requirements.txt", "dockerfile", "docker-compose.yml"}
        for f in lower_files
    ):
        suggestions.append(
            "Update Setup/Deployment docs for dependency or container changes."
        )

    if any(f in {".env.example", ".gitlab-ci.yml"} for f in lower_files) or any(
        f.startswith("config/") for f in lower_files
    ):
        suggestions.append(
            "Update Configuration docs for new or changed environment/runtime settings."
        )

    if any(
        f.startswith(("agent/", "api/", "src/", "app/", "cli/")) for f in lower_files
    ):
        suggestions.append(
            "Update Usage/Behavior docs to reflect changed runtime flow or interfaces."
        )

    if not suggestions:
        suggestions.append(
            "Review README sections affected by this change set and document new behavior."
        )

    return suggestions


def evaluate_readme_drift(
    payload: dict, readme_path: str = DEFAULT_README_PATH
) -> dict:
    """Return deterministic drift analysis for a Push Hook payload."""
    if _has_docs_skip(payload):
        return {
            "status": "skipped",
            "reason": "docs-skip token found in commit message",
            "changed_files": sorted(_collect_changed_files(payload)),
            "docs_relevant_files": [],
            "readme_updated": False,
            "suggestions": [],
        }

    changed_files = sorted(_collect_changed_files(payload))
    lower_changed = {p.lower() for p in changed_files}

    readme_updated = readme_path.lower() in lower_changed
    docs_relevant_files = [p for p in changed_files if _is_docs_relevant(p)]

    if not changed_files:
        return {
            "status": "skipped",
            "reason": "no changed files found in push payload",
            "changed_files": [],
            "docs_relevant_files": [],
            "readme_updated": False,
            "suggestions": [],
        }

    if not docs_relevant_files:
        return {
            "status": "up_to_date",
            "reason": "no docs-relevant files changed",
            "changed_files": changed_files,
            "docs_relevant_files": [],
            "readme_updated": readme_updated,
            "suggestions": [],
        }

    if readme_updated:
        return {
            "status": "up_to_date",
            "reason": "README updated in same push",
            "changed_files": changed_files,
            "docs_relevant_files": docs_relevant_files,
            "readme_updated": True,
            "suggestions": [],
        }

    return {
        "status": "outdated",
        "reason": "docs-relevant changes detected without README update",
        "changed_files": changed_files,
        "docs_relevant_files": docs_relevant_files,
        "readme_updated": False,
        "suggestions": _suggestions_for(docs_relevant_files),
    }


def build_readme_review_comment(
    result: dict, branch: str, commit_sha: str, readme_path: str
) -> str:
    """Build markdown comment body from drift analysis."""
    if result["status"] == "up_to_date":
        return (
            "### README Review\n"
            f"Commit `{commit_sha[:8]}` on `{branch}` looks documented enough.\n\n"
            f"Reason: {result['reason']}"
        )

    lines = [
        "### README Review",
        f"Commit `{commit_sha[:8]}` on `{branch}` may have documentation drift.",
        "",
        f"Reason: {result['reason']}",
        "",
        "Changed docs-relevant files:",
    ]

    for path in result["docs_relevant_files"][:12]:
        lines.append(f"- `{path}`")

    lines.extend(
        [
            "",
            "Suggested README updates:",
        ]
    )
    for suggestion in result["suggestions"]:
        lines.append(f"- {suggestion}")

    lines.extend(
        [
            "",
            f"If this is intentional, update `{readme_path}` in a follow-up commit or annotate commit message with `[docs-skip]`.",
        ]
    )
    return "\n".join(lines)


def run_readme_review_for_push(
    payload: dict, readme_path: str = DEFAULT_README_PATH
) -> dict:
    """
    Evaluate drift for a push and post a commit comment when needed.
    Returns the evaluation result for logging/testing.
    """
    branch_ref = payload.get("ref", "")
    branch = (
        branch_ref.replace("refs/heads/", "")
        if branch_ref.startswith("refs/heads/")
        else branch_ref
    )
    commit_sha = payload.get("after", "")

    result = evaluate_readme_drift(payload, readme_path=readme_path)

    if not commit_sha:
        return result

    if result["status"] == "outdated":
        comment = build_readme_review_comment(
            result, branch=branch, commit_sha=commit_sha, readme_path=readme_path
        )
        post_commit_comment(commit_sha, comment)

    return result
