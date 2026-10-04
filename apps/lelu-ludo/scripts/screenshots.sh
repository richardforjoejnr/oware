#!/usr/bin/env bash
# App Store screenshots for Lelu Ludo (`make screenshots`), shot by LeluLudoUITests/ScreenshotUITests
# on the sizes App Store Connect asks for: iPhone 6.9" (1320×2868) and iPad 13" (2064×2752), portrait.
#
# Creates its own simulators (so it never disturbs one you or another run is using), gives them a
# clean status bar (9:41, full battery and signal), shoots, and deletes them again. PNGs land in
# fastlane/screenshots/en-GB/ as iPhone-NN-name.png and iPad-NN-name.png (git-ignored).
#
#   ONLY=iphone|ipad   shoot one device only
#   IPHONE_TYPE / IPAD_TYPE   simulator device types (defaults below)
#   IPHONE_UDID / IPAD_UDID   use this existing simulator instead (left in place afterwards)
set -euo pipefail
cd "$(dirname "$0")/.."

IPHONE_TYPE=${IPHONE_TYPE:-"iPhone 18 Pro Max"}
IPAD_TYPE=${IPAD_TYPE:-"com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB"}
OUT="$PWD/fastlane/screenshots/en-GB"
LOGS="$PWD/build/screenshots"
mkdir -p "$OUT" "$LOGS"

created=()
cleanup() {
  for udid in "${created[@]:-}"; do
    [ -n "$udid" ] || continue
    xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
    xcrun simctl delete "$udid" >/dev/null 2>&1 || true
  done
}
trap cleanup EXIT

# One device: create, boot, clean status bar, run the screenshot tests with a watchdog.
shoot() {
  local label=$1 type=$2 udid=${3:-}
  if [ -z "$udid" ]; then
    udid=$(xcrun simctl create "Lelu Ludo shots $label" "$type")
    created+=("$udid")
  fi
  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" -b >/dev/null
  xcrun simctl status_bar "$udid" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
  rm -f "$OUT/$label"-*.png
  rm -rf "$LOGS/$label.xcresult"

  echo "Shooting $label ($type, $udid)…"
  TEST_RUNNER_SCREENSHOT_DIR="$OUT" xcodebuild test -project LeluLudo.xcodeproj -scheme LeluLudo \
    -destination "id=$udid" -only-testing:LeluLudoUITests/ScreenshotUITests \
    -resultBundlePath "$LOGS/$label.xcresult" -collect-test-diagnostics never \
    CODE_SIGNING_ALLOWED=NO >"$LOGS/$label.log" 2>&1 &
  local pid=$! waited=0
  # Watchdog: xcodebuild can hang in `simctl diagnose` after a failure. Once it has printed its
  # verdict, give it a minute to exit, then stop the diagnose and xcodebuild.
  while kill -0 "$pid" 2>/dev/null; do
    sleep 5
    if grep -q -E '\*\* TEST (SUCCEEDED|FAILED|EXECUTE FAILED) \*\*' "$LOGS/$label.log"; then
      waited=$((waited + 5))
      if [ "$waited" -ge 60 ]; then
        pkill -f "simctl diagnose" || true
        kill "$pid" 2>/dev/null || true
      fi
    fi
  done
  wait "$pid" || true
  grep -E '\*\* TEST|Test Case .*(passed|failed|skipped)' "$LOGS/$label.log" | sed 's/^/  /' || true
  grep -q '\*\* TEST SUCCEEDED \*\*' "$LOGS/$label.log" || { echo "  $label failed: see $LOGS/$label.log"; return 1; }
}

xcodegen generate >/dev/null
status=0
[ "${ONLY:-}" = ipad ] || shoot iPhone "$IPHONE_TYPE" "${IPHONE_UDID:-}" || status=1
[ "${ONLY:-}" = iphone ] || shoot iPad "$IPAD_TYPE" "${IPAD_UDID:-}" || status=1

# The 6.5" iPhone slot in App Store Connect takes only 1284×2778 (or 1242×2688), not 6.9"'s 1320×2868:
# copies scaled to that width and trimmed top and bottom (the shapes differ by under 1%).
mkdir -p "$OUT/iPhone-6.5"
for f in "$OUT"/iPhone-*.png; do
  [ -e "$f" ] || continue
  out="$OUT/iPhone-6.5/$(basename "$f" | sed 's/^iPhone-/iPhone65-/')"
  sips --resampleWidth 1284 "$f" --out "$out" >/dev/null && sips --cropToHeightWidth 2778 1284 "$out" >/dev/null
done

echo
for f in "$OUT"/*.png "$OUT"/iPhone-6.5/*.png; do
  [ -e "$f" ] || continue
  printf '%s  %s×%s\n' "$(basename "$f")" \
    "$(sips -g pixelWidth "$f" | awk '/pixelWidth/ {print $2}')" "$(sips -g pixelHeight "$f" | awk '/pixelHeight/ {print $2}')"
done
exit $status
