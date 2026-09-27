#!/usr/bin/env python3
"""App Store readiness checks for an app in this repo. Fast, no Xcode needed (runs on Linux CI).

    python3 scripts/release_readiness.py apps/lelu-oware

Catches the things that get builds rejected or pulled: a missing or incomplete privacy manifest,
debug switches in release builds, an icon with transparency, placeholder text on the public
support and privacy pages, and so on. Exit code 1 lists every failure.
"""
import pathlib
import plistlib
import re
import struct
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
failures: list[str] = []
passes: list[str] = []


def check(ok: bool, message: str) -> None:
    (passes if ok else failures).append(message)


def main(app_dir: str) -> int:
    app = ROOT / app_dir
    slug = app.name
    sources = list((app / "Oware" / "Sources").rglob("*.swift")) + [
        p for pkg in (ROOT / "packages").iterdir() if (pkg / "Sources").exists() for p in (pkg / "Sources").rglob("*.swift")
    ]
    code = "\n".join(p.read_text() for p in sources)
    project = (app / "project.yml").read_text()

    # 1. Privacy manifest: present, valid, no tracking, and a reason for every required-reason API used.
    manifest_path = app / "Oware" / "Resources" / "PrivacyInfo.xcprivacy"
    check(manifest_path.exists(), "App privacy manifest (PrivacyInfo.xcprivacy) exists")
    if manifest_path.exists():
        manifest = plistlib.loads(manifest_path.read_bytes())
        check(manifest.get("NSPrivacyTracking") is False, "Privacy manifest declares no tracking")
        declared = {d.get("NSPrivacyAccessedAPIType") for d in manifest.get("NSPrivacyAccessedAPITypes", [])}
        required = {
            "NSPrivacyAccessedAPICategoryUserDefaults": r"\bUserDefaults\b|@AppStorage",
            "NSPrivacyAccessedAPICategoryFileTimestamp": r"creationDate|modificationDate|attributesOfItem",
            "NSPrivacyAccessedAPICategorySystemBootTime": r"systemUptime|mach_absolute_time",
            "NSPrivacyAccessedAPICategoryDiskSpace": r"volumeAvailableCapacity|systemFreeSize",
            "NSPrivacyAccessedAPICategoryActiveKeyboards": r"activeInputModes",
        }
        for category, pattern in required.items():
            if re.search(pattern, code):
                check(category in declared, f"Privacy manifest gives a reason for {category.split('Category')[-1]}")
        uses_analytics = "TelemetryDeck" in project
        collected = {d.get("NSPrivacyCollectedDataType") for d in manifest.get("NSPrivacyCollectedDataTypes", [])}
        if uses_analytics:
            check("NSPrivacyCollectedDataTypeProductInteraction" in collected,
                  "Privacy manifest declares the analytics data collected")
            if re.search(r"tipPurchased|tipJar\.purchased", code):
                check("NSPrivacyCollectedDataTypePurchaseHistory" in collected,
                      "Privacy manifest declares purchase history (tip events are sent to analytics)")
    check('excludes: ["Tips.storekit"]' in project or ".storekit" not in project,
          "StoreKit test configuration is not shipped in the app")

    # 2. Info.plist and entitlements.
    info = plistlib.loads((app / "Oware" / "Info.plist").read_bytes())
    check(info.get("ITSAppUsesNonExemptEncryption") is False, "Export compliance answered (ITSAppUsesNonExemptEncryption = NO)")
    usage_keys = [k for k in info if k.endswith("UsageDescription")]
    check(all(str(info[k]).strip() for k in usage_keys), "Every permission prompt has a description")
    ent_path = app / "Oware" / "Oware.entitlements"
    if ent_path.exists():
        ents = set(plistlib.loads(ent_path.read_bytes()))
        allowed = {"com.apple.developer.game-center"}
        check(ents <= allowed, f"Entitlements are only the expected ones ({', '.join(sorted(ents)) or 'none'})")

    # 3. Version and icon.
    m = re.search(r'MARKETING_VERSION:\s*"([^"]+)"', project)
    check(bool(m and re.fullmatch(r"\d+(\.\d+){1,2}", m.group(1))), f"Version number is valid ({m.group(1) if m else 'missing'})")
    icons = list((app / "Oware" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset").glob("*.png"))
    for icon in icons:
        head = icon.read_bytes()[:33]
        width, height, _, color_type = struct.unpack(">IIBB", head[16:26])
        check(width == height == 1024, f"App icon {icon.name} is 1024×1024")
        check(color_type not in (4, 6), f"App icon {icon.name} has no transparency")

    # 4. Release builds carry no test switches, no plain-http links.
    launch = re.search(r"enum LaunchOptions \{.*?#if DEBUG\s*private static let enabled = true\s*#else\s*private static let enabled = false", code, re.S)
    check(bool(launch), "Test launch options are compiled out of release builds")
    check(not re.search(r'"http://(?!www\.apple\.com/DTDs)', code), "No plain-http links in the app")

    # 5. Public pages App Review reads.
    for page in ("privacy", "support"):
        path = ROOT / "docs" / slug / f"{page}.md"
        text = path.read_text() if path.exists() else ""
        check(bool(text), f"Public {page} page exists")
        check(not re.search(r"owner to fill|TODO|TBD|lorem", text, re.I), f"Public {page} page has no placeholders")
        check(bool(re.search(r"[\w.+-]+@[\w-]+\.[\w.]+", text)), f"Public {page} page shows a contact email")
    privacy = (ROOT / "docs" / slug / "privacy.md").read_text() if (ROOT / "docs" / slug / "privacy.md").exists() else ""
    if "TelemetryDeck" in project:
        check("TelemetryDeck" in privacy, "Privacy policy names the analytics service")
    if "game-center" in project:
        check("Game Center" in privacy, "Privacy policy covers Game Center")

    for p in passes:
        print(f"  ✓ {p}")
    for f in failures:
        print(f"  ✗ {f}")
    print(f"\n{len(passes)} passed, {len(failures)} failed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "apps/lelu-oware"))
