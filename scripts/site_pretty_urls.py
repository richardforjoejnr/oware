#!/usr/bin/env python3
"""Give every page a short URL on S3 + CloudFront, as GitHub Pages did.

    python3 scripts/site_pretty_urls.py _site

Jekyll writes docs/lelu-oware/privacy.md as _site/lelu-oware/privacy.html. GitHub Pages served it
at /lelu-oware/privacy; CloudFront's viewer function maps /lelu-oware/privacy to
/lelu-oware/privacy/index.html, so this copies each page there too. index.html and 404.html stay.
"""
import pathlib
import shutil
import sys


def prettify(site: pathlib.Path) -> list[pathlib.Path]:
    made = []
    for page in sorted(site.rglob("*.html")):
        if page.name in ("index.html", "404.html"):
            continue
        target = page.with_suffix("") / "index.html"
        if target.exists():
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(page, target)
        made.append(target)
    return made


if __name__ == "__main__":
    site = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "_site")
    for path in prettify(site):
        print(path.relative_to(site))
