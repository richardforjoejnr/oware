#!/usr/bin/env python3
"""The next app version, worked out from Conventional Commit PR titles since the last release.

    python3 scripts/next_version.py            # e.g. 1.2.0
    python3 scripts/next_version.py --notes    # release notes for TestFlight / GitHub Release

Releases are git tags vX.Y.Z (the App Store workflow creates them). Since the last tag:
  - any "feat!:" / "fix!:" title or "BREAKING CHANGE" → next major (2.0.0)
  - otherwise any "feat:"                           → next minor (1.3.0)
  - otherwise anything else                         → next patch (1.2.4)
With no release yet the answer is 1.0.0. PRs are merged with merge commits, whose body starts with
the PR title, so only PR titles need to follow the convention (checked by the PR-title workflow).
"""
from __future__ import annotations

import re
import subprocess
import sys

FIRST_VERSION = "1.0.0"
TITLE = re.compile(r"^(?P<type>[a-z]+)(?:\((?P<scope>[^)]*)\))?(?P<bang>!)?:\s*(?P<text>.+)$")
LABELS = {"feat": "New", "fix": "Fixed", "perf": "Faster"}


def git(*args: str) -> str:
    return subprocess.run(["git", *args], check=True, capture_output=True, text=True).stdout


def last_release() -> str | None:
    tags = [t for t in git("tag", "--list", "v*", "--sort=-v:refname").split() if re.fullmatch(r"v\d+\.\d+\.\d+", t)]
    return tags[0] if tags else None


def titles_since(tag: str | None) -> list[tuple[str, str]]:
    """(title, body) of each change on the main line since `tag`: PR titles for merge commits."""
    rev = f"{tag}..HEAD" if tag else "HEAD"
    out = git("log", rev, "--first-parent", "--format=%s%x1f%b%x1e")
    changes = []
    for record in filter(None, (r.strip("\n") for r in out.split("\x1e"))):
        subject, _, body = record.partition("\x1f")
        if subject.startswith("Merge pull request") or subject.startswith("Merge branch"):
            lines = [l for l in body.splitlines() if l.strip()]
            if not lines:
                continue
            subject, body = lines[0], "\n".join(lines[1:])
        changes.append((subject.strip(), body))
    return changes


def bump(version: str | None, changes: list[tuple[str, str]]) -> str:
    if version is None:
        return FIRST_VERSION
    if not changes:
        return version
    major, minor, patch = (int(x) for x in version.split("."))
    parsed = [TITLE.match(t) for t, _ in changes]
    if any((m and m.group("bang")) or "BREAKING CHANGE" in body for m, (_, body) in zip(parsed, changes)):
        return f"{major + 1}.0.0"
    if any(m and m.group("type") == "feat" for m in parsed):
        return f"{major}.{minor + 1}.0"
    return f"{major}.{minor}.{patch + 1}"


def notes(changes: list[tuple[str, str]], limit: int = 3500) -> str:
    """Grouped release notes, newest first, kept under TestFlight's 4,000-character limit."""
    groups: dict[str, list[str]] = {}
    for title, _ in changes:
        m = TITLE.match(title)
        kind = LABELS.get(m.group("type"), "Also") if m else "Also"
        text = m.group("text") if m else title
        groups.setdefault(kind, []).append(text[0].upper() + text[1:])
    order = ["New", "Fixed", "Faster", "Also"]
    text = "\n".join(f"{k}:\n" + "\n".join(f"- {t}" for t in groups[k]) for k in order if k in groups)
    if len(text) > limit:
        text = text[:limit].rsplit("\n", 1)[0] + "\n- …and more"
    return text


def main() -> None:
    tag = last_release()
    changes = titles_since(tag)
    if "--notes" in sys.argv:
        print(notes(changes) or "Small improvements.")
    else:
        print(bump(tag[1:] if tag else None, changes))


if __name__ == "__main__":
    main()
