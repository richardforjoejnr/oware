#!/bin/bash
# Put an app's public website (privacy, support, What's new) on AWS: S3 + CloudFront, optional
# domain, from your Mac. The whole process and the why: docs/WEBSITE_ON_AWS.md.
#
#   scripts/setup-site.sh --domain leluoware.com --app lelu-oware
#   scripts/setup-site.sh --domain ludogame.com --name ludo-site --source docs-ludo --app ludo --github
#
# Options:
#   --domain D     Domain bought in Route 53 in this AWS account (omit: CloudFront address only)
#   --name N       Stack/site name, one per website (default oware-site)
#   --source DIR   Jekyll source folder (default docs)
#   --app SLUG     App folder on the site, used to check its privacy/support pages (default lelu-oware)
#   --stage S      Stage (default prod)
#   --account ID   Stop unless the AWS credentials belong to this account (e.g. 842822459513)
#   --github       Also store the AWS keys and site variables in this GitHub repo for the Site workflow
#   --skip-build   Deploy the existing _site instead of rebuilding it
#   --yes          Don't ask before deploying
# Safe to re-run: every step checks first and only changes what is missing.
set -euo pipefail

DOMAIN=""; NAME="oware-site"; SOURCE="docs"; APP="lelu-oware"; STAGE="prod"; ACCOUNT=""
GITHUB=false; SKIP_BUILD=false; YES=false
while [ $# -gt 0 ]; do
  case "$1" in
    --domain) DOMAIN="$2"; shift 2 ;;
    --name) NAME="$2"; shift 2 ;;
    --source) SOURCE="$2"; shift 2 ;;
    --app) APP="$2"; shift 2 ;;
    --stage) STAGE="$2"; shift 2 ;;
    --account) ACCOUNT="$2"; shift 2 ;;
    --github) GITHUB=true; shift ;;
    --skip-build) SKIP_BUILD=true; shift ;;
    --yes) YES=true; shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "Unknown option $1 (see --help)"; exit 1 ;;
  esac
done

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'
ok() { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
fail() { echo -e "${RED}✗${NC} $*"; exit 1; }
step() { echo -e "\n${BLUE}== $* ==${NC}"; }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
REGION=us-east-1   # CloudFront certificates must live here

step "1. Tools"
for tool in aws node npm python3 dig curl; do command -v "$tool" >/dev/null || fail "$tool is not installed (brew install awscli node python bind)"; done
ok "aws, node, npm, python3, dig, curl"
if ! $SKIP_BUILD; then
  command -v docker >/dev/null && docker info >/dev/null 2>&1 || fail "Docker must be running to build the site (or use --skip-build)"
  command -v gh >/dev/null && gh auth status >/dev/null 2>&1 || fail "gh must be signed in (gh auth login): the Jekyll build reads repo metadata"
  ok "docker, gh"
fi

step "2. AWS account"
ID_JSON=$(aws sts get-caller-identity --output json 2>/dev/null) || fail "No AWS credentials. Run: aws configure  (keys of an IAM user that can deploy CDK, e.g. cdk-deployer)"
ACCT=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["Account"])' <<<"$ID_JSON")
WHO=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["Arn"].split(":")[-1])' <<<"$ID_JSON")
ok "Account $ACCT as $WHO"
if [ -n "$ACCOUNT" ] && [ "$ACCOUNT" != "$ACCT" ]; then fail "Expected account $ACCOUNT, but these credentials are for $ACCT"; fi
if aws cloudformation describe-stacks --region $REGION --stack-name CDKToolkit >/dev/null 2>&1; then
  ok "CDK is bootstrapped in $REGION"
else
  warn "CDK is not bootstrapped in $REGION; the deploy step will bootstrap it"
fi

if [ -n "$DOMAIN" ]; then
  step "3. Domain $DOMAIN"
  ZONE=$(aws route53 list-hosted-zones-by-name --dns-name "$DOMAIN" \
    --query "HostedZones[?Name=='${DOMAIN}.' && Config.PrivateZone==\`false\`].Id | [0]" --output text 2>/dev/null)
  [ -n "$ZONE" ] && [ "$ZONE" != "None" ] || fail "No public hosted zone for $DOMAIN in account $ACCT.
    Buy it in this account (Route 53 > Registered domains > Register), or, if it is registered elsewhere,
    create a public hosted zone here and copy its four name servers to the registrar."
  ok "Hosted zone ${ZONE##*/}"
  PENDING=$(aws route53domains list-operations --region $REGION \
    --query "Operations[?Type=='REGISTER_DOMAIN' && (Status=='IN_PROGRESS' || Status=='SUBMITTED')] | length(@)" --output text 2>/dev/null || echo 0)
  [ "$PENDING" = "0" ] || fail "A domain registration is still in progress. Wait for Route 53's 'registration successful' email."
  WANT=$(aws route53 get-hosted-zone --id "$ZONE" --query 'DelegationSet.NameServers' --output text | tr '\t' '\n' | sed 's/\.$//' | sort)
  HAVE=$(dig +short NS "$DOMAIN" @8.8.8.8 | sed 's/\.$//' | sort)
  [ "$WANT" = "$HAVE" ] || fail "$DOMAIN's name servers on the internet don't match the hosted zone yet.
    Hosted zone: $(echo $WANT)
    Public DNS:  $(echo ${HAVE:-none})
    The certificate cannot be validated until they match (registrar > name servers)."
  ok "Public DNS delegates to the hosted zone"
else
  step "3. Domain"
  warn "No --domain: the site will be served at its CloudFront address only"
fi

step "4. Build the site"
SITE="$ROOT/_site"
if $SKIP_BUILD; then
  [ -f "$SITE/index.html" ] || fail "No built site at $SITE"
  ok "Using the existing $SITE"
else
  [ -f "$SOURCE/_config.yml" ] || fail "$SOURCE/_config.yml not found (Jekyll source)"
  REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
  WHATS_NEW="$SOURCE/$APP/whats-new.md"
  if [ -f "$WHATS_NEW" ] && gh api "repos/$REPO/releases?per_page=100" > /tmp/site-releases.$$.json 2>/dev/null; then
    # Written for the build only; the committed file is put back afterwards.
    cp "$WHATS_NEW" /tmp/site-whats-new.$$.md
    trap 'cp /tmp/site-whats-new.$$.md "$WHATS_NEW" 2>/dev/null; rm -f /tmp/site-whats-new.$$.md' EXIT
    python3 scripts/build_release_notes.py /tmp/site-releases.$$.json "$WHATS_NEW" --app "$(echo "$APP" | sed 's/-/ /g')" --slug "$APP" >/dev/null && ok "What's new from the GitHub Releases"
  fi
  rm -f /tmp/site-releases.$$.json
  rm -rf "$SITE"; mkdir -p "$SITE"
  # The same image GitHub's jekyll-build-pages action runs, so local and CI builds match.
  docker run --rm -e INPUT_SOURCE="$SOURCE" -e INPUT_DESTINATION=_site -e INPUT_FUTURE=false \
    -e INPUT_BUILD_REVISION="$(git rev-parse --short HEAD)" -e INPUT_VERBOSE=false -e INPUT_TOKEN="$(gh auth token)" \
    -e GITHUB_WORKSPACE=/github/workspace -e GITHUB_REPOSITORY="$REPO" \
    -v "$ROOT":/github/workspace -w /github/workspace ghcr.io/actions/jekyll-build-pages:v1.0.13 >/dev/null 2>&1 \
    || fail "Jekyll build failed. Re-run the docker command above without >/dev/null to see why."
  python3 scripts/site_pretty_urls.py "$SITE" >/dev/null
  ok "Built $(find "$SITE" -name '*.html' | wc -l | tr -d ' ') pages into _site (test reports are added by the Site workflow)"
fi

step "5. Deploy $STAGE-$NAME"
if ! $YES; then
  read -r -p "Deploy $STAGE-$NAME${DOMAIN:+ for $DOMAIN} to account $ACCT? [y/N] " ANSWER
  [[ "$ANSWER" =~ ^[Yy]$ ]] || { echo "Stopped before deploying."; exit 0; }
fi
SITE_NAME="$NAME" SITE_DOMAIN="$DOMAIN" SITE_DIR="$SITE" infra/site/scripts/deploy.sh "$STAGE"
URL=$(aws cloudformation describe-stacks --region $REGION --stack-name "$STAGE-$NAME" \
  --query "Stacks[0].Outputs[?OutputKey=='SiteUrl'].OutputValue" --output text)
CF=$(aws cloudformation describe-stacks --region $REGION --stack-name "$STAGE-$NAME" \
  --query "Stacks[0].Outputs[?OutputKey=='CloudFrontUrl'].OutputValue" --output text)

step "6. Check it is live"
check_url() {   # Resolves through public DNS (8.8.8.8), so a stale cache on this Mac can't hide a working site.
  local url="$1" host ip code
  host=$(echo "$url" | sed -E 's|https://([^/]+).*|\1|')
  ip=$(dig +short A "$host" @8.8.8.8 | grep -E '^[0-9.]+$' | head -1)
  code=$(curl -s -o /dev/null -w '%{http_code}' ${ip:+--resolve "$host:443:$ip"} "$url")
  if [ "$code" = "200" ]; then ok "$url"; else warn "$url answered $code"; fi
}
for base in "$URL" ${DOMAIN:+"https://www.$DOMAIN"} "$CF"; do
  check_url "$base/$APP/privacy"; check_url "$base/$APP/support"
done

if $GITHUB; then
  step "7. GitHub (for the Site workflow)"
  command -v gh >/dev/null || fail "gh is not installed"
  REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
  # Read straight from the AWS CLI config into GitHub; never printed.
  gh secret set AWS_ACCESS_KEY_ID -R "$REPO" --body "$(aws configure get aws_access_key_id)"
  gh secret set AWS_SECRET_ACCESS_KEY -R "$REPO" --body "$(aws configure get aws_secret_access_key)"
  gh variable set SITE_ON_AWS -R "$REPO" --body true
  [ -n "$DOMAIN" ] && gh variable set SITE_DOMAIN -R "$REPO" --body "$DOMAIN"
  ok "Secrets AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY and variables SITE_ON_AWS${DOMAIN:+, SITE_DOMAIN} set on $REPO"
fi

echo -e "\n${GREEN}Done.${NC} Next:"
echo "  - App Store Connect: privacy policy URL $URL/$APP/privacy (App Information),"
echo "    support URL $URL/$APP/support (the version page)."
echo "  - The app's Links.swift: point privacy/support at the same URLs."
$GITHUB || echo "  - For automatic deploys on merge: re-run with --github (or see docs/WEBSITE_ON_AWS.md)."
