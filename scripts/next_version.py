#!/usr/bin/env python3
"""The next app version, worked out from Conventional Commit PR titles since the last release.

    python3 scripts/next_version.py            # e.g. 1.2.0
    python3 scripts/next_version.py --notes    # release notes for TestFlight / GitHub Release
    python3 scripts/next_version.py --store-notes   # "What's New" on the App Store (players only)

Releases are git tags vX.Y.Z (the App Store workflow creates them). Since the last tag:
  - any "feat!:" / "fix!:" title or "BREAKING CHANGE" → next major (2.0.0)
  - otherwise any "feat:"                           → next minor (1.3.0)
  - otherwise any fix/perf/refactor/build/revert    → next patch (1.2.4)
  - docs/chore/ci/test/style only                   → no new version, and not in the notes
With no release yet the answer is 1.0.0. `--build` (used for TestFlight) moves past the last
released version whenever anything was merged since it: Apple refuses new builds for a version that
is already out. With nothing merged since the tag it prints the released version itself, and the
TestFlight workflow then skips ("nothing to build").

PRs are merged with merge commits, whose body starts with the PR title, so only PR titles need to
follow the convention (checked by the PR-title workflow). The PR description is not in the merge
commit by default, so mark a breaking change with "!" in the PR title ("feat!: …"). A
"BREAKING CHANGE" / "BREAKING-CHANGE" note in a commit body is still honoured when it does get there.

Titles from before the convention are read leniently: "Docs: …" or "Fix: …" count as docs / fix,
and anything else ("Accessibility: VoiceOver", "Milestone 2: …") is a player-facing change listed in
full under "Also". Before the first release every merged PR is in the notes; trim them in the
GitHub Release if that is too long.
"""
from __future__ import annotations

import os
import pathlib
import re
import subprocess
import sys

FIRST_VERSION = "1.0.0"
# Changes that do not reach players: no version bump, no release-note line.
QUIET = {"docs", "chore", "ci", "test", "style"}
TYPES = QUIET | {"feat", "fix", "perf", "refactor", "build", "revert"}
_TITLE = re.compile(r"^(?P<type>[A-Za-z]+)(?:\((?P<scope>[^)]*)\))?(?P<bang>!)?:\s*(?P<text>.+)$")
BREAKING = re.compile(r"BREAKING[ -]CHANGE")
LABELS = {"feat": "New", "fix": "Fixed", "perf": "Faster"}


class Title:
    """A parsed Conventional Commit title. The type is matched case-insensitively ("Docs:" from before
    the convention counts as docs); unknown types ("Accessibility: …") are not conventional."""

    def __init__(self, m: re.Match[str]):
        self.type = m.group("type").lower()
        self.bang = bool(m.group("bang"))
        self.text = m.group("text")

    @staticmethod
    def parse(title: str) -> "Title | None":
        m = _TITLE.match(title)
        return Title(m) if m and m.group("type").lower() in TYPES else None


def breaking(title: Title | None, body: str) -> bool:
    return bool(title and title.bang) or bool(BREAKING.search(body))


def git(*args: str) -> str:
    return subprocess.run(["git", *args], check=True, capture_output=True, text=True).stdout


def last_release() -> str | None:
    tags = [t for t in git("tag", "--list", "v*", "--sort=-v:refname").split() if re.fullmatch(r"v\d+\.\d+\.\d+", t)]
    return tags[0] if tags else None


# What belongs to each app: its folder and the packages it is built from. A PR counts towards an
# app's version and notes only if it changed one of these (so a Lelu Ludo feature never bumps Lelu
# Oware's version or shows in its App Store "What's New").
APP_PATHS = {
    "lelu-oware": ["apps/lelu-oware", "packages/OwareEngine", "packages/SupportKit"],
    # Not SupportKit yet: Lelu Ludo doesn't use it (add it back with Ludo's tip jar), and its Oware
    # changes were showing in Lelu Ludo's TestFlight notes.
    "lelu-ludo": ["apps/lelu-ludo", "packages/LudoEngine"],
}


def current_app(argv: list[str], cwd: str) -> str | None:
    """`--app=<slug>`, else the app folder the script is run from (the workflows run it from
    apps/<slug>), else None: the whole repository, as before there were two apps."""
    for a in argv:
        if a.startswith("--app="):
            return a.split("=", 1)[1]
    parts = pathlib.PurePath(cwd).parts
    if "apps" in parts and parts.index("apps") + 1 < len(parts):
        slug = parts[parts.index("apps") + 1]
        return slug if slug in APP_PATHS else None
    return None


def titles_since(tag: str | None, paths: list[str] | None = None) -> list[tuple[str, str]]:
    """(title, body) of each change on the main line since `tag`: PR titles for merge commits.
    With `paths`, only changes that touched them (a merge counts if it changed them compared with
    the main line before it)."""
    rev = f"{tag}..HEAD" if tag else "HEAD"
    limit = ["--", *(f":(top){p}" for p in paths)] if paths else []   # from the repo's top, wherever we run
    out = git("log", rev, "--first-parent", "--format=%s%x1f%b%x1e", *limit)
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


def releasable(changes: list[tuple[str, str]]) -> list[tuple[str, str]]:
    """Changes players would notice: everything except docs/chore/ci/test/style titles."""
    out = []
    for title, body in changes:
        t = Title.parse(title)
        if t and t.type in QUIET and not breaking(t, body):
            continue
        out.append((title, body))
    return out


def bump(version: str | None, changes: list[tuple[str, str]], for_build: bool = False) -> str:
    if version is None:
        return FIRST_VERSION
    major, minor, patch = (int(x) for x in version.split("."))
    all_changes = changes
    changes = releasable(changes)
    if not changes:
        # A beta must still move past the released version, even if only quiet changes came in.
        return f"{major}.{minor}.{patch + 1}" if for_build and all_changes else version
    parsed = [Title.parse(t) for t, _ in changes]
    if any(breaking(t, body) for t, (_, body) in zip(parsed, changes)):
        return f"{major + 1}.0.0"
    if any(t and t.type == "feat" for t in parsed):
        return f"{major}.{minor + 1}.0"
    return f"{major}.{minor}.{patch + 1}"


def notes(changes: list[tuple[str, str]], limit: int = 3500) -> str:
    """Grouped release notes, newest first, kept under TestFlight's 4,000-character limit."""
    groups: dict[str, list[str]] = {}
    for title, _ in releasable(changes):
        t = Title.parse(title)
        kind = LABELS.get(t.type, "Also") if t else "Also"
        text = t.text if t else title
        groups.setdefault(kind, []).append(text[0].upper() + text[1:])
    order = ["New", "Fixed", "Faster", "Also"]
    text = "\n".join(f"{k}:\n" + "\n".join(f"- {t}" for t in groups[k]) for k in order if k in groups)
    if len(text) > limit:
        text = text[:limit].rsplit("\n", 1)[0] + "\n- …and more"
    return text


def store_notes(changes: list[tuple[str, str]], limit: int = 3800) -> str:
    """The App Store's "What's New": only what players notice (New, Fixed, Faster), under Apple's
    4,000-character limit. Refactors, builds and old free-form titles stay in the GitHub Release."""
    lines = []
    for title, _ in releasable(changes):
        t = Title.parse(title)
        if t and t.type in LABELS:
            lines.append(f"- {t.text[0].upper() + t.text[1:]}")
    text = "\n".join(lines)
    if len(text) > limit:
        text = text[:limit].rsplit("\n", 1)[0] + "\n- …and more"
    return text or "Small fixes and improvements."


def main() -> None:
    tag = last_release()
    app = current_app(sys.argv, os.getcwd())
    changes = titles_since(tag, APP_PATHS[app] if app else None)
    if "--store-notes" in sys.argv:
        print(store_notes(changes))
    elif "--notes" in sys.argv:
        print(notes(changes) or "Small improvements.")
    else:
        print(bump(tag[1:] if tag else None, changes, for_build="--build" in sys.argv))


if __name__ == "__main__":
    main()
