#!/usr/bin/env bash
# One-time setup for automatic TestFlight and App Store uploads from GitHub Actions.
#
# Run it yourself in Terminal from the repo root:  ./scripts/setup-signing.sh
# It asks for each value privately, creates the private certificates repo if needed, stores the
# App Store certificate there with fastlane match, adds every secret to GitHub, and finally turns
# SIGNING_READY on. Nothing is written to disk in this repo and nothing is printed back.
set -euo pipefail

REPO="richardforjoejnr/oware"
CERTS_REPO="richardforjoejnr/oware-certificates"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="/opt/homebrew/opt/ruby/bin:$PATH"

ruby -e 'exit(RUBY_VERSION >= "3.0" ? 0 : 1)' || { echo "Needs Ruby 3: brew install ruby"; exit 1; }
command -v gh >/dev/null || { echo "Needs the GitHub CLI: brew install gh"; exit 1; }

echo "Lelu Oware — signing setup. Values you type after a colon are not shown or saved."
read -rp "Apple Team ID [${DEVELOPMENT_TEAM:-}]: " TEAM; TEAM="${TEAM:-${DEVELOPMENT_TEAM:-}}"
read -rp "App Store Connect API Key ID: " ASC_KEY_ID
read -rp "App Store Connect Issuer ID: " ASC_ISSUER_ID
# Find the key by its ID in the usual places; otherwise ask (dragging the file in works).
P8="$(find "$HOME/Downloads" "$HOME/Desktop" "$HOME/Documents" -maxdepth 3 -name "AuthKey_${ASC_KEY_ID}.p8" 2>/dev/null | head -1)"
if [ -n "$P8" ]; then
  read -rp "Found $P8 — use it? [Y/n]: " OK
  case "$OK" in [nN]*) P8="" ;; esac
fi
while [ ! -f "$P8" ]; do
  read -r -p "Path to the AuthKey_….p8 file (or drag it here): " P8
  P8="$(printf '%s' "$P8" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e "s/^['\"]//" -e "s/['\"]$//" -e 's/\\\(.\)/\1/g')"
  P8="${P8/#\~/$HOME}"
  [ -f "$P8" ] || echo "No file at: '$P8'. Try again."
done
echo "GitHub fine-grained token with Contents: read and write on $CERTS_REPO only."
read -rsp "Token: " PAT; echo
read -rsp "Choose a passphrase that encrypts the certificates (keep it in your password manager): " MATCH_PASSWORD; echo

if ! gh repo view "$CERTS_REPO" >/dev/null 2>&1; then
  echo "Creating the private repo $CERTS_REPO…"
  gh repo create "$CERTS_REPO" --private --description "Encrypted signing certificates (fastlane match)"
fi

export DEVELOPMENT_TEAM="$TEAM" ASC_KEY_ID ASC_ISSUER_ID MATCH_PASSWORD
export ASC_KEY_CONTENT="$(base64 -i "$P8" | tr -d '\n')"
export MATCH_GIT_URL="https://github.com/$CERTS_REPO"
export MATCH_GIT_BASIC_AUTHORIZATION="$(printf '%s' "richardforjoejnr:$PAT" | base64 | tr -d '\n')"

echo "Creating and storing the App Store certificate and profile…"
(cd "$ROOT" && bundle config set --local path vendor/bundle >/dev/null && bundle install --quiet)
(cd "$ROOT/apps/lelu-oware" && BUNDLE_GEMFILE="$ROOT/Gemfile" bundle exec fastlane ios setup_signing)

echo "Adding the secrets to GitHub…"
gh secret set DEVELOPMENT_TEAM -R "$REPO" --body "$DEVELOPMENT_TEAM"
gh secret set ASC_KEY_ID -R "$REPO" --body "$ASC_KEY_ID"
gh secret set ASC_ISSUER_ID -R "$REPO" --body "$ASC_ISSUER_ID"
gh secret set ASC_KEY_CONTENT -R "$REPO" --body "$ASC_KEY_CONTENT"
gh secret set MATCH_GIT_URL -R "$REPO" --body "$MATCH_GIT_URL"
gh secret set MATCH_GIT_BASIC_AUTHORIZATION -R "$REPO" --body "$MATCH_GIT_BASIC_AUTHORIZATION"
gh secret set MATCH_PASSWORD -R "$REPO" --body "$MATCH_PASSWORD"

gh variable set SIGNING_READY -R "$REPO" --body true
echo "Done. Every merge to main now uploads a TestFlight build; a GitHub Release (tag vX.Y) uploads for the App Store."
