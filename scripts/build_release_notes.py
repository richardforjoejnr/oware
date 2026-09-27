#!/usr/bin/env python3
"""Write an app's public "What's new" page from its GitHub Releases (used by the Pages workflow).

    build_release_notes.py <releases.json> <out.md> --app "Lelu Oware" --slug lelu-oware

<releases.json> is `gh api repos/OWNER/REPO/releases`. Only releases named "<app> X.Y.Z" are used
(the App Store workflow names them that way), newest first. The notes come from
scripts/next_version.py --notes ("New:", "Fixed:", ... followed by "- " lines).
"""
import argparse
import datetime
import json
import re

GROUP = re.compile(r"^(New|Fixed|Faster|Also):\s*$")


def render(releases: list[dict], app: str, slug: str) -> str:
    lines = ["---", f"title: {app} — What's new", "---", "", f"# What's new in {app}", ""]
    ours = [r for r in releases if (r.get("name") or "").startswith(app) and not r.get("draft") and not r.get("prerelease")]
    ours.sort(key=lambda r: r.get("published_at") or "", reverse=True)
    if not ours:
        lines += ["The first release is on its way. Sign up for [news by email](newsletter) to hear when it lands.", ""]
    for r in ours:
        version = r["name"][len(app):].strip() or r.get("tag_name", "")
        date = (r.get("published_at") or "")[:10]
        pretty = datetime.date.fromisoformat(date).strftime("%-d %B %Y") if date else ""
        lines += [f"## {version}", f"_{pretty}_" if pretty else "", ""]
        for raw in (r.get("body") or "").splitlines():
            m = GROUP.match(raw.strip())
            if m:
                lines += ["", f"**{ {'New': 'New', 'Fixed': 'Fixed', 'Faster': 'Faster', 'Also': 'Also improved'}[m.group(1)] }**", ""]
            elif raw.strip():
                lines.append(raw.rstrip())
        lines.append("")
    lines += ["[Support](support) · [Privacy](privacy) · [News by email](newsletter) · [All apps](../)", ""]
    return "\n".join(lines)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("releases"); ap.add_argument("out")
    ap.add_argument("--app", required=True); ap.add_argument("--slug", required=True)
    a = ap.parse_args()
    with open(a.releases) as f:
        releases = json.load(f)
    with open(a.out, "w") as f:
        f.write(render(releases, a.app, a.slug))
