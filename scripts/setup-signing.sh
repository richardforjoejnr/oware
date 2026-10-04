#!/usr/bin/env bash
# One-time setup for automatic TestFlight and App Store uploads from GitHub Actions.
#
# Run it yourself in Terminal from the repo root:  ./scripts/setup-signing.sh
# For another app (e.g. Lelu Ludo) once Lelu Oware is set up:  ./scripts/setup-signing.sh --app=lelu-ludo
#   That only creates the app's own App Store profile in the same certificates repo, with the same
#   certificate and passphrase. The GitHub secrets are shared, so they are left as they are.
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
APP="lelu-oware"
for arg in "$@"; do case "$arg" in --app=*) APP="${arg#--app=}" ;; *) echo "Unknown option: $arg"; exit 1 ;; esac; done
[ -f "$ROOT/apps/$APP/fastlane/Fastfile" ] || { echo "No fastlane setup in apps/$APP"; exit 1; }
# Lelu Oware's run sets everything up; any other app only adds its profile.
PROFILE_ONLY=false; [ "$APP" != "lelu-oware" ] && PROFILE_ONLY=true
export PATH="/opt/homebrew/opt/ruby/bin:$PATH"

ruby -e 'exit(RUBY_VERSION >= "3.0" ? 0 : 1)' || { echo "Needs Ruby 3: brew install ruby"; exit 1; }
command -v gh >/dev/null || { echo "Needs the GitHub CLI: brew install gh"; exit 1; }

echo "$APP — signing setup. Values you type after a colon are not shown or saved."
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

# Creating a certificate or a provisioning profile needs a key with Admin access; GitHub's key should be
# App Manager. Apple lets no script create API keys, so this walks through making one by hand (or
# takes an existing one), finds the downloaded .p8, and uses it for this run only.
admin_key_guide() {
  local page="https://appstoreconnect.apple.com/access/integrations/api"
  local before
  before="$(ls "$HOME/Downloads"/AuthKey_*.p8 2>/dev/null | sort)"
  cat <<GUIDE >&2

  Make a key with Admin access (about a minute):
    1. In App Store Connect: Users and Access ▸ Integrations ▸ App Store Connect API ▸ Team Keys.
    2. Click + . Name: match-setup. Access: Admin. Generate.
    3. Click Download next to the new key (Apple allows ONE download), keeping the file in Downloads.
  Opening that page in your browser; this script waits for the file to appear in Downloads…
GUIDE
  open "$page" 2>/dev/null || echo "  Open: $page" >&2
  local found=""
  for _ in $(seq 1 300); do   # up to 10 minutes
    found="$(comm -13 <(printf '%s\n' "$before") <(ls "$HOME/Downloads"/AuthKey_*.p8 2>/dev/null | sort) | head -1)"
    [ -n "$found" ] && break
    sleep 2
  done
  if [ -z "$found" ]; then echo "  No new AuthKey_*.p8 in Downloads. Run the script again when you have it." >&2; exit 1; fi
  echo "  Found $(basename "$found")." >&2
  printf '%s' "$found"
}

echo "Creating the certificate or a profile needs a key with Admin access (GitHub's key should be App Manager)."
echo "  • Press Return if the key above has Admin access."
echo "  • Type the Key ID of an Admin key you already have (e.g. match-setup), if its .p8 is on this Mac."
echo "  • Type n to make one now; this script guides you and picks up the downloaded file."
echo "It is used once here and never saved; you can revoke it afterwards."
read -rp "Admin key [Return / Key ID / n]: " ADMIN_KEY_ID
if [ "$ADMIN_KEY_ID" = "n" ] || [ "$ADMIN_KEY_ID" = "N" ]; then
  ADMIN_P8="$(admin_key_guide)"
  ADMIN_KEY_ID="$(basename "$ADMIN_P8" .p8)"; ADMIN_KEY_ID="${ADMIN_KEY_ID#AuthKey_}"
elif [ -n "$ADMIN_KEY_ID" ]; then
  ADMIN_P8="$(find_p8 "$ADMIN_KEY_ID")"
else
  ADMIN_KEY_ID="$ASC_KEY_ID"; ADMIN_P8="$P8"
fi
echo "GitHub fine-grained token with Contents: read and write on $CERTS_REPO only."
if $PROFILE_ONLY; then echo "(Press Return to use your GitHub CLI login instead.)"; fi
read -rsp "Token: " PAT; echo
if [ -z "$PAT" ] && $PROFILE_ONLY; then PAT="$(gh auth token)"; fi
echo "Passphrase for the certificates. If $CERTS_REPO already has files, it must be the SAME one as before."
read -rsp "Passphrase (keep it in your password manager): " MATCH_PASSWORD; echo

if $PROFILE_ONLY && ! gh repo view "$CERTS_REPO" >/dev/null 2>&1; then
  echo "$CERTS_REPO doesn't exist yet: run ./scripts/setup-signing.sh (Lelu Oware) first."; exit 1
fi
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
LOG="$(mktemp)"
if ! (cd "$ROOT/apps/$APP" && ASC_KEY_ID="$ADMIN_KEY_ID" ASC_KEY_CONTENT="$(base64 -i "$ADMIN_P8" | tr -d '\n')" \
  BUNDLE_GEMFILE="$ROOT/Gemfile" bundle exec fastlane ios setup_signing) 2>&1 | tee "$LOG"; then
  # The two failures people hit, in words (fastlane's own messages are easy to misread).
  if grep -q "forbidden for security reasons\|not allowed to perform this operation" "$LOG"; then
    echo
    echo "✗ Apple refused: key $ADMIN_KEY_ID does not have Admin access (App Manager can't create profiles)."
    echo "  Run this again and type n at the Admin key prompt to make one, or give an Admin key's ID."
  elif grep -q "Couldn't decrypt the repo\|Invalid password" "$LOG"; then
    echo
    echo "✗ Wrong passphrase: it must be the one $CERTS_REPO was set up with (your password manager)."
  fi
  rm -f "$LOG"
  exit 1
fi
rm -f "$LOG"

if $PROFILE_ONLY; then
  [ "$ADMIN_KEY_ID" != "$ASC_KEY_ID" ] && echo "You can now revoke the Admin key $ADMIN_KEY_ID in App Store Connect."
  echo "Done: $APP's App Store profile is in $CERTS_REPO. Re-run its TestFlight workflow (Actions tab) to upload."
  exit 0
fi

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
