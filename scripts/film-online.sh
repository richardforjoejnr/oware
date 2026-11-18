#!/usr/bin/env bash
# Films a game of Lelu Oware online between two simulators, through the dev relay, and joins the
# two recordings side by side:  ./scripts/film-online.sh [output.mp4]
# The video App Review is sent with each release is apps/lelu-oware/fastlane/review/online-play.mp4:
# film again, then copy the new one over it.
# The larger phone (Ama) starts a game; the other (Kofi) joins with the invitation link; they
# play, Kofi resigns, and they have a rematch. Needs xcodegen, ffmpeg and the two simulators below.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/build/oware-online.mp4}"
HOST="iPhone 18 Pro Max"
GUEST="iPhone 18 Pro"
WORK="$(mktemp -d)"
trap 'kill -INT ${REC_A:-} ${REC_B:-} 2>/dev/null || true' EXIT

udid() { xcrun simctl list devices available | grep -F "    $1 (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/'; }
A="$(udid "$HOST")"; B="$(udid "$GUEST")"
[ -n "$A" ] && [ -n "$B" ] || { echo "Needs the simulators '$HOST' and '$GUEST'."; exit 1; }
xcrun simctl boot "$A" 2>/dev/null || true
xcrun simctl boot "$B" 2>/dev/null || true
xcrun simctl bootstatus "$A" >/dev/null; xcrun simctl bootstatus "$B" >/dev/null

cd "$ROOT/apps/lelu-oware"
xcodegen generate >/dev/null
xcodebuild build-for-testing -project Oware.xcodeproj -scheme Oware \
  -destination "platform=iOS Simulator,id=$A" -destination "platform=iOS Simulator,id=$B" \
  CODE_SIGNING_ALLOWED=NO -quiet

xcrun simctl io "$A" recordVideo --codec h264 --force "$WORK/host.mov" & REC_A=$!
xcrun simctl io "$B" recordVideo --codec h264 --force "$WORK/guest.mov" & REC_B=$!
sleep 2
# One run per simulator: with both in a single run the second app froze at launch.
film() {
  TEST_RUNNER_OWARE_FILM_DIR="$WORK" xcodebuild test-without-building -project Oware.xcodeproj -scheme Oware \
    -destination "platform=iOS Simulator,id=$1" -resultBundlePath "$WORK/$2.xcresult" \
    CODE_SIGNING_ALLOWED=NO -only-testing:OwareUITests/OnlineFilmUITests > "$WORK/$2.log" 2>&1 || true
}
film "$A" host & RUN_A=$!
film "$B" guest & RUN_B=$!
wait "$RUN_A" "$RUN_B"
cat "$WORK/host.log" "$WORK/guest.log" > "$WORK/test.log"
grep -E "error: -|Executed [0-9]+ test|TEST (SUCCEEDED|FAILED)" "$WORK/test.log" | sort -u || true
kill -INT "$REC_A" "$REC_B"; wait "$REC_A" "$REC_B" 2>/dev/null || true

mkdir -p "$(dirname "$OUT")"
# Both at the same height, side by side on the app's dark background.
# Without the simulators' own home screens at the start, or one app closing before the other at the end.
LENGTH="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$WORK/guest.mov" | cut -d. -f1)"
ffmpeg -y -loglevel error -ss 18 -t "$((LENGTH - 18))" -i "$WORK/host.mov" -ss 18 -t "$((LENGTH - 18))" -i "$WORK/guest.mov" -filter_complex \
  "[0:v]scale=-2:1080[a];[1:v]scale=-2:1080[b];[a][b]hstack=inputs=2:shortest=1,pad=iw+80:ih+80:40:40:color=0x14100c[v]" \
  -map "[v]" -r 30 -c:v libx264 -pix_fmt yuv420p -movflags +faststart "$OUT"
echo "Wrote $OUT"
