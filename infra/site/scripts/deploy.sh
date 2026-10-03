#!/bin/bash
# Deploy the website to a stage. Usage: SITE_DIR=../../_site ./scripts/deploy.sh [dev|prod]
# Optional: SITE_DOMAIN=leluoware.com once the domain is bought in Route 53.
# SITE_NAME (default oware-site) names the stack: <stage>-<SITE_NAME>. Another website, another name.
# Self-contained: only ever touches that one stack.
set -e
STAGE=${1:-dev}
GREEN='\033[0;32m'; BLUE='\033[0;34m'; RED='\033[0;31m'; NC='\033[0m'
cd "$(dirname "$0")/.."
SITE_NAME=${SITE_NAME:-oware-site}; export SITE_NAME
STACK="${STAGE}-${SITE_NAME}"
SITE_DIR=${SITE_DIR:-../../_site}
if [ ! -f "$SITE_DIR/index.html" ]; then
  echo -e "${RED}No built site at $SITE_DIR (the Site workflow builds it).${NC}"; exit 1
fi
export SITE_DIR="$(cd "$SITE_DIR" && pwd)"

echo -e "${BLUE}Installing deps...${NC}"; npm ci --no-audit --no-fund
echo -e "${BLUE}Building + testing...${NC}"; npm run build && npm test
echo -e "${BLUE}Bootstrapping CDK (idempotent)...${NC}"
npx cdk bootstrap "aws://$(aws sts get-caller-identity --query Account --output text)/us-east-1" 2>/dev/null || true
echo -e "${BLUE}Deploying stage: ${STAGE}${SITE_DOMAIN:+ (domain $SITE_DOMAIN)}...${NC}"
STAGE=${STAGE} npx cdk deploy "$STACK" --require-approval never

get_output() {
  aws cloudformation describe-stacks --region us-east-1 --stack-name "$STACK" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text 2>/dev/null
}
SITE_URL=$(get_output SiteUrl); PRIVACY_URL=$(get_output PrivacyUrl); SUPPORT_URL=$(get_output SupportUrl)
echo -e "${GREEN}✓ Site deployed to ${STAGE}${NC}"
echo -e "Site:    ${GREEN}${SITE_URL}${NC}"
echo -e "Privacy: ${PRIVACY_URL}"
echo -e "Support: ${SUPPORT_URL}"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  { echo "site_url=${SITE_URL}"; echo "privacy_url=${PRIVACY_URL}"; echo "support_url=${SUPPORT_URL}"; } >> "$GITHUB_OUTPUT"
fi
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "## 🌍 Site deployed to ${STAGE}"
    echo ""
    echo "| What | URL |"; echo "| --- | --- |"
    echo "| Site | ${SITE_URL} |"
    echo "| Privacy policy (App Store Connect) | ${PRIVACY_URL} |"
    echo "| Support (App Store Connect) | ${SUPPORT_URL} |"
    echo "| What's new | ${SITE_URL}/lelu-oware/whats-new |"
    echo "| Test report | ${SITE_URL}/reports/lelu-oware/ |"
  } >> "$GITHUB_STEP_SUMMARY"
fi
