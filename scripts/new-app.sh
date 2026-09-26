#!/usr/bin/env bash
# Scaffold a new iOS app from templates/ios-app.
#   scripts/new-app.sh my-app "My App"
set -euo pipefail
cd "$(dirname "$0")/.."
slug="${1:?usage: new-app.sh <slug> [\"Display Name\"]}"
display="${2:-$slug}"
name="$(echo "$slug" | awk -F- '{ for (i = 1; i <= NF; i++) printf "%s%s", toupper(substr($i, 1, 1)), substr($i, 2) }')"   # my-app -> MyApp
bundle="com.richardforjoe.$(echo "$slug" | tr -d '-')"
dest="apps/$slug"
[ -e "$dest" ] && { echo "$dest already exists"; exit 1; }
cp -R templates/ios-app "$dest"
# Rename folders, then substitute placeholders in every text file.
for d in "$dest/__NAME__" "$dest/__NAME__Tests" "$dest/__NAME__UITests"; do
  mv "$d" "${d//__NAME__/$name}"
done
find "$dest" -type f \( -name "*.swift" -o -name "*.yml" -o -name "*.md" -o -name "Makefile" -o -name "*.plist" \) -print0 \
  | xargs -0 sed -i '' -e "s/__NAME__/$name/g" -e "s/__DISPLAY__/$display/g" -e "s/__BUNDLE__/$bundle/g" -e "s/__SLUG__/$slug/g"
(cd "$dest" && xcodegen generate >/dev/null)
echo "Created $dest  (target $name, bundle $bundle)."
echo "Next: copy .github/workflows/ci.yml with APP_DIR=$dest and new job names; then \`make open APP=$slug\`."
