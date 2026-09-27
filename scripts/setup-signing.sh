#!/usr/bin/env bash
# One-time setup for automatic TestFlight and App Store uploads from GitHub Actions.
#
# Run it yourself in Terminal from the repo root:  ./scripts/setup-signing.sh
# It asks for each value privately, creates the private certificates repo if needed, stores the
# App Store certificate there with fastlane match, adds every secret to GitHub, and finally turns
# SIGNING_READY on. No secret is written to this repo or printed back.
#
# Creating the distribution certificate needs an App Store Connect key with Admin access; GitHub
# only needs App Manager. Give the Admin key at its own prompt; it is used once and not stored.
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
# Finds AuthKey_<id>.p8 in the usual places, or asks (dragging the file in works). Prints the path.
find_p8() {
  local id="$1" path=""
  path="$(find "$HOME/Downloads" "$HOME/Desktop" "$HOME/Documents" -maxdepth 3 -name "AuthKey_${id}.p8" 2>/dev/null | head -1)"
  if [ -n "$path" ]; then
    read -rp "Found $path — use it? [Y/n]: " OK </dev/tty
    case "$OK" in [nN]*) path="" ;; esac
  fi
  while [ ! -f "$path" ]; do
    read -r -p "Path to AuthKey_${id}.p8 (or drag it here): " path </dev/tty
    path="$(printf '%s' "$path" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e "s/^['\"]//" -e "s/['\"]$//" -e 's/\\\(.\)/\1/g')"
    path="${path/#\~/$HOME}"
    [ -f "$path" ] || echo "No file at: '$path'. Try again." >&2
  done
  printf '%s' "$path"
}
P8="$(find_p8 "$ASC_KEY_ID")"

echo "Creating the distribution certificate needs a key with Admin access. If the key above is"
echo "App Manager (recommended for GitHub), create a second key with Admin access for this one step."
echo "It is used once here and never saved; you can revoke it afterwards."
read -rp "Admin Key ID for the certificate step (press Return to use the same key): " ADMIN_KEY_ID
if [ -n "$ADMIN_KEY_ID" ]; then ADMIN_P8="$(find_p8 "$ADMIN_KEY_ID")"; else ADMIN_KEY_ID="$ASC_KEY_ID"; ADMIN_P8="$P8"; fi
echo "GitHub fine-grained token with Contents: read and write on $CERTS_REPO only."
read -rsp "Token: " PAT; echo
echo "Passphrase for the certificates. If $CERTS_REPO already has files, it must be the SAME one as before."
read -rsp "Passphrase (keep it in your password manager): " MATCH_PASSWORD; echo

if ! gh repo view "$CERTS_REPO" >/dev/null 2>&1; then
  echo "Creating the private repo $CERTS_REPO…"
  gh repo create "$CERTS_REPO" --private --description "Encrypted signing certificates (fastlane match)"
fi

export DEVELOPMENT_TEAM="$TEAM" ASC_KEY_ID ASC_ISSUER_ID MATCH_PASSWORD
export ASC_KEY_CONTENT="$(base64 -i "$P8" | tr -d '\n')"
export MATCH_GIT_URL="https://github.com/$CERTS_REPO"
export MATCH_GIT_BASIC_AUTHORIZATION="$(printf '%s' "richardforjoejnr:$PAT" | base64 | tr -d '\n')"

echo "Creating and storing the App Store certificate and profile, using key $ADMIN_KEY_ID (must have Admin access)…"
(cd "$ROOT" && bundle config set --local path vendor/bundle >/dev/null && bundle install --quiet)
(cd "$ROOT/apps/lelu-oware" && ASC_KEY_ID="$ADMIN_KEY_ID" ASC_KEY_CONTENT="$(base64 -i "$ADMIN_P8" | tr -d '\n')" \
  BUNDLE_GEMFILE="$ROOT/Gemfile" bundle exec fastlane ios setup_signing)

echo "Adding the secrets to GitHub…"
gh secret set DEVELOPMENT_TEAM -R "$REPO" --body "$DEVELOPMENT_TEAM"
gh secret set ASC_KEY_ID -R "$REPO" --body "$ASC_KEY_ID"
gh secret set ASC_ISSUER_ID -R "$REPO" --body "$ASC_ISSUER_ID"
gh secret set ASC_KEY_CONTENT -R "$REPO" --body "$ASC_KEY_CONTENT"
gh secret set MATCH_GIT_URL -R "$REPO" --body "$MATCH_GIT_URL"
gh secret set MATCH_GIT_BASIC_AUTHORIZATION -R "$REPO" --body "$MATCH_GIT_BASIC_AUTHORIZATION"
gh secret set MATCH_PASSWORD -R "$REPO" --body "$MATCH_PASSWORD"

gh variable set SIGNING_READY -R "$REPO" --body true
[ "$ADMIN_KEY_ID" != "$ASC_KEY_ID" ] && echo "You can now revoke the Admin key $ADMIN_KEY_ID in App Store Connect (GitHub uses $ASC_KEY_ID)."
echo "Done. Every merge to main that changes the app now uploads a TestFlight build; a GitHub Release (tag vX.Y.Z) uploads for the App Store."
