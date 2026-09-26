#!/usr/bin/env python3
"""Build the test-report pages published on GitHub Pages.

    build-reports.py <artifacts-dir> <out-dir> --app lelu-oware --run-url URL --sha SHA

Reads whatever it finds under <artifacts-dir>:
  * JUnit XML files (Appium/WebdriverIO `junit-*.xml`, Maestro `maestro-report.xml`)
  * `test-summary.json` / `test-tests.json` exported from the xcresult bundle by xcresulttool
  * PNG screenshots (Maestro failure shots, e2e screenshots)
and writes <out-dir>/index.html plus copied screenshots. Plain HTML, no dependencies.
"""
import argparse, datetime, glob, html, json, os, shutil, sys
import xml.etree.ElementTree as ET


def junit_suites(root_dir):
    suites = []
    for path in sorted(glob.glob(os.path.join(root_dir, "**", "*.xml"), recursive=True)):
        try:
            tree = ET.parse(path)
        except ET.ParseError:
            continue
        root = tree.getroot()
        nodes = root.iter("testsuite") if root.tag in ("testsuites", "testsuite") else []
        for suite in nodes:
            cases = []
            for case in suite.findall("testcase"):
                status = "passed"
                detail = ""
                for kind in ("failure", "error"):
                    node = case.find(kind)
                    if node is not None:
                        status = "failed"
                        detail = (node.get("message") or (node.text or "")).strip()
                if case.find("skipped") is not None:
                    status = "skipped"
                cases.append({"name": case.get("name", "?"), "time": float(case.get("time") or 0), "status": status, "detail": detail})
            if cases:
                suites.append({"name": suite.get("name") or os.path.basename(path), "source": os.path.relpath(path, root_dir), "cases": cases})
    return suites


def xcresult_suites(root_dir):
    """xcresulttool `tests` JSON → suites of cases (structure differs between Xcode versions, so walk generically)."""
    suites = []
    for path in glob.glob(os.path.join(root_dir, "**", "test-tests.json"), recursive=True):
        try:
            data = json.load(open(path))
        except (OSError, json.JSONDecodeError):
            continue
        current = {"name": os.path.dirname(os.path.relpath(path, root_dir)) or "App tests", "source": os.path.relpath(path, root_dir), "cases": []}

        def walk(node, suite_name):
            if isinstance(node, dict):
                kind = node.get("nodeType")
                if kind == "Test Case":
                    result = (node.get("result") or "").lower()
                    status = "passed" if result == "passed" else ("skipped" if result == "skipped" else "failed")
                    detail = ""
                    for child in node.get("children", []):
                        if isinstance(child, dict) and child.get("nodeType") == "Failure Message":
                            detail = child.get("name", "")
                    current["cases"].append({"name": f"{suite_name} › {node.get('name', '?')}", "time": 0.0, "status": status, "detail": detail})
                    return
                if kind in ("Test Suite", "Unit test bundle", "UI test bundle"):
                    suite_name = node.get("name", suite_name)
                for child in node.get("children", []) + node.get("testNodes", []):
                    walk(child, suite_name)
            elif isinstance(node, list):
                for child in node:
                    walk(child, suite_name)

        walk(data, "")
        if current["cases"]:
            suites.append(current)
    return suites


def summary_text(root_dir):
    for path in glob.glob(os.path.join(root_dir, "**", "test-summary.json"), recursive=True):
        try:
            data = json.load(open(path))
        except (OSError, json.JSONDecodeError):
            continue
        parts = []
        for key in ("totalTestCount", "passedTests", "failedTests", "skippedTests"):
            if key in data:
                parts.append(f"{key.replace('Tests', '').replace('totalTestCount', 'total')}: {data[key]}")
        devices = data.get("devicesAndConfigurations") or []
        if devices:
            dev = devices[0].get("device", {})
            parts.append(f"{dev.get('deviceName', '')} · {dev.get('osVersion', '')}".strip(" ·"))
        return " · ".join(parts)
    return ""


def copy_screenshots(root_dir, out_dir):
    shots_dir = os.path.join(out_dir, "screenshots")
    os.makedirs(shots_dir, exist_ok=True)
    copied = []
    for path in sorted(glob.glob(os.path.join(root_dir, "**", "*.png"), recursive=True))[:60]:
        name = os.path.relpath(path, root_dir).replace(os.sep, "_")
        shutil.copy(path, os.path.join(shots_dir, name))
        copied.append(name)
    return copied


CSS = """
:root{--bg:#1a120c;--panel:#26180f;--text:#ede3d2;--dim:#b9a58a;--ok:#7c9a3c;--bad:#b8452d;--skip:#8a7a62;--brass:#c49627}
body{margin:0;font:15px/1.5 -apple-system,system-ui,sans-serif;background:var(--bg);color:var(--text)}
main{max-width:960px;margin:0 auto;padding:32px 20px}
h1{font-family:Georgia,serif;font-weight:500;font-size:34px;margin:0 0 4px}
h2{font-family:Georgia,serif;font-weight:500;font-size:22px;margin:32px 0 10px}
.meta{color:var(--dim);margin-bottom:24px}.meta a{color:var(--brass)}
.totals{display:flex;gap:12px;flex-wrap:wrap;margin:16px 0}
.pill{padding:6px 14px;border-radius:999px;background:var(--panel);border:1px solid #3a2a1c}
.pill b{font-size:18px}
table{width:100%;border-collapse:collapse;background:var(--panel);border-radius:12px;overflow:hidden}
th,td{padding:8px 12px;text-align:left;border-bottom:1px solid #3a2a1c;vertical-align:top}
th{color:var(--dim);font-weight:500}
.s{display:inline-block;width:10px;height:10px;border-radius:50%;margin-right:8px;vertical-align:middle}
.passed .s{background:var(--ok)}.failed .s{background:var(--bad)}.skipped .s{background:var(--skip)}
.failed td.n{color:#ffb5a0}.detail{color:var(--dim);font-size:13px;white-space:pre-wrap}
.shots{display:grid;grid-template-columns:repeat(auto-fill,minmax(160px,1fr));gap:12px}
.shots img{width:100%;border-radius:8px;border:1px solid #3a2a1c}
footer{color:var(--dim);margin-top:40px;font-size:13px}
"""


def render(app, suites, summary, shots, run_url, sha, out_dir):
    all_cases = [c for s in suites for c in s["cases"]]
    counts = {k: sum(1 for c in all_cases if c["status"] == k) for k in ("passed", "failed", "skipped")}
    overall = "failed" if counts["failed"] else "passed"
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    parts = [f"<!doctype html><html lang='en'><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'>",
             f"<title>{html.escape(app)} — test report</title><style>{CSS}</style></head><body><main>",
             f"<h1>{html.escape(app)} — test report</h1>",
             f"<div class='meta'>Built {now}" + (f" · commit <a href='{html.escape(run_url)}'>{html.escape(sha[:7])}</a>" if run_url else "") +
             (f"<br>{html.escape(summary)}" if summary else "") + "</div>",
             "<div class='totals'>",
             f"<span class='pill {overall}'><span class='s'></span><b>{'All passing' if overall == 'passed' else str(counts['failed']) + ' failing'}</b></span>",
             f"<span class='pill'><b>{counts['passed']}</b> passed</span>",
             f"<span class='pill'><b>{counts['failed']}</b> failed</span>",
             f"<span class='pill'><b>{counts['skipped']}</b> skipped</span>",
             f"<span class='pill'><b>{len(suites)}</b> suites</span></div>"]
    if not suites:
        parts.append("<p class='meta'>No test results were found in the downloaded artifacts.</p>")
    for suite in suites:
        parts.append(f"<h2>{html.escape(suite['name'])}</h2><div class='meta'>{html.escape(suite['source'])}</div>")
        parts.append("<table><tr><th>Result</th><th>Test</th><th>Time</th></tr>")
        for c in sorted(suite["cases"], key=lambda c: (c["status"] != "failed", c["name"])):
            detail = f"<div class='detail'>{html.escape(c['detail'][:600])}</div>" if c["detail"] else ""
            time = f"{c['time']:.1f}s" if c["time"] else ""
            parts.append(f"<tr class='{c['status']}'><td><span class='s'></span>{c['status']}</td><td class='n'>{html.escape(c['name'])}{detail}</td><td>{time}</td></tr>")
        parts.append("</table>")
    if shots:
        parts.append("<h2>Screenshots</h2><div class='shots'>")
        for name in shots:
            parts.append(f"<a href='screenshots/{html.escape(name)}'><img src='screenshots/{html.escape(name)}' alt='{html.escape(name)}' loading='lazy'></a>")
        parts.append("</div>")
    parts.append("<footer><a href='../../' style='color:var(--brass)'>All apps</a></footer></main></body></html>")
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, "index.html"), "w") as f:
        f.write("\n".join(parts))
    return counts


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("artifacts")
    ap.add_argument("out")
    ap.add_argument("--app", default="lelu-oware")
    ap.add_argument("--run-url", default="")
    ap.add_argument("--sha", default="")
    args = ap.parse_args()
    suites = xcresult_suites(args.artifacts) + junit_suites(args.artifacts)
    shots = copy_screenshots(args.artifacts, args.out)
    counts = render(args.app, suites, summary_text(args.artifacts), shots, args.run_url, args.sha, args.out)
    print(f"{args.app}: {len(suites)} suites, {counts}, {len(shots)} screenshots → {args.out}/index.html")


if __name__ == "__main__":
    sys.exit(main())
