# An app's website on AWS

How Lelu Oware's public pages moved from GitHub Pages to AWS on 3 October 2026, and how to do the
same for another app. The pages are the ones App Review needs (privacy policy, support) plus What's
new and the test reports. They live on AWS so the code repository can be private.

**Short version** (an AWS account with CLI access, Docker running, `gh` signed in):

```bash
scripts/setup-site.sh --domain leluoware.com --app lelu-oware --account 842822459513 --github
```

The rest of this page is what that script does, what it needs first, and how to adapt it.

## How it fits together

```
docs/ (Jekyll source) ──build──▶ _site/ ──CDK deploy──▶ S3 bucket (private)
                                                          │ Origin Access Control
                         leluoware.com, www ──Route 53──▶ CloudFront (HTTPS, ACM certificate)
```

| Piece | Where | What it does |
|---|---|---|
| CDK app | `infra/site` | One stack per website, `<stage>-<site name>` (e.g. `prod-oware-site`), always in us-east-1 |
| Bucket | stack | Private (all public access blocked, TLS only). Only CloudFront can read it |
| CloudFront | stack | HTTPS redirect, security headers, 404 page, short URLs (`/lelu-oware/privacy` → `…/privacy/index.html`) |
| Domain | stack, when `SITE_DOMAIN` is set | ACM certificate for the domain and `www` (DNS-validated, renews itself) and A/AAAA alias records |
| Short URLs | `scripts/site_pretty_urls.py` | Writes `privacy.html` as `privacy/index.html` too, as GitHub Pages served it |
| Local setup | `scripts/setup-site.sh` | Checks, builds, deploys, verifies; optionally sets the GitHub secrets |
| Automatic deploys | `.github/workflows/pages.yml` ("Site") | On docs changes, releases and finished CI / E2E runs on main; also builds the test reports |

It follows the same conventions as `aws-cdk-boilerplate`: an IAM user's keys in GitHub secrets,
us-east-1, stage-prefixed stacks, a `deploy.sh` that bootstraps, deploys and writes a run summary.

## Before you start (once per AWS account)

1. **AWS CLI credentials** for an IAM user that can deploy CDK (here `cdk-deployer`):
   `aws configure`, then `aws sts get-caller-identity` shows the account. Lelu Oware uses
   **842822459513**.
2. **CDK bootstrapped in us-east-1.** `deploy.sh` does it if missing (`npx cdk bootstrap`).
3. **Tools:** Node 20+, Python 3, Docker (the site is built with the same image as GitHub's
   `jekyll-build-pages`), `gh` signed in, `dig` and `curl`.

## Step by step

### 1. Buy the domain (optional, recommended)

Buy it in Route 53 **in the same AWS account the stack deploys to**: Route 53 creates the hosted zone
there, and the stack looks it up there to make the certificate and DNS records.

- Sign in to the console as yourself (root or an admin), not as `cdk-deployer`: buying needs billing
  permissions. Check the account ID in the top-right menu.
- Route 53 ▸ Registered domains ▸ Register domains. Keep privacy protection and auto-renew on.
- **Click the link in the contact-verification email**, or the domain can be suspended.
- Registration takes minutes to a few hours; wait for the "registration successful" email.

About US$13 a year for a `.com`, plus US$0.50 a month for the hosted zone.

Registered elsewhere? Create a public hosted zone for it in this account and copy its four name
servers to the registrar. The script refuses to deploy until public DNS points at that zone.

Without a domain the site is served at its CloudFront address (`https://d….cloudfront.net`). That
works, but the address changes if the stack is ever recreated, so App Store Connect would need updating.

### 2. Run the setup script

```bash
scripts/setup-site.sh --domain leluoware.com --app lelu-oware --account 842822459513
```

It is safe to re-run. It:
1. checks the tools;
2. checks the AWS identity (and stops if `--account` doesn't match) and the CDK bootstrap;
3. checks the domain: hosted zone in this account, no registration still in progress, and public
   DNS delegating to the zone (the certificate cannot validate otherwise);
4. builds `docs/` with Jekyll in Docker, writes What's new from the GitHub Releases, and adds the
   short-URL copies;
5. asks, then deploys with `infra/site/scripts/deploy.sh` (installs, type-checks and tests the stack,
   bootstraps, `cdk deploy`). The first deploy with a domain takes about 7 minutes (certificate
   validation and CloudFront);
6. checks the privacy and support pages on the domain, `www` and the CloudFront address, resolving
   through public DNS.

### 3. Let GitHub deploy from now on

Add `--github` to the script, or by hand:

```bash
gh secret set AWS_ACCESS_KEY_ID --body "$(aws configure get aws_access_key_id)"
gh secret set AWS_SECRET_ACCESS_KEY --body "$(aws configure get aws_secret_access_key)"
gh variable set SITE_ON_AWS --body true
gh variable set SITE_DOMAIN --body leluoware.com
```

The values go straight from the AWS CLI config into GitHub and are never printed. `AWS_REGION` is not
needed: the workflow always uses us-east-1. The Site workflow is skipped until `SITE_ON_AWS` is
`true`.

### 4. Point App Store Connect and the app at the new pages

- **App Store Connect:** privacy policy URL in App Information; support URL on the version page.
- **The app:** `apps/<app>/Oware/Sources/Support/Links.swift` (App Review 5.1.1(i) wants the policy
  inside the app too). `scripts/release_readiness.py` checks both links are there.

Do this before turning the old pages off: a reviewer who opens a dead privacy link can reject the build.

### 5. Make the code repository private

Settings ▸ General ▸ Danger Zone ▸ Change visibility. This also turns GitHub Pages off. With a free
GitHub account, private repositories get 2,000 Actions minutes a month and macOS minutes count ten
times, so watch the CI usage (Settings ▸ Billing).

## Another app

**Same domain, new folder** (simplest): add `docs/<app>/privacy.md`, `support.md`, `whats-new.md`.
The next Site run publishes `https://leluoware.com/<app>/privacy`. No AWS changes.

**Its own domain:** give it its own site name and source folder, so it gets its own stack and never
touches Lelu Oware's:

```bash
scripts/setup-site.sh --name ludo-site --source docs-ludo --domain ludogame.com --app ludo --account 842822459513
```

For automatic deploys, copy `.github/workflows/pages.yml` to a new workflow, set `SITE_NAME: ludo-site`
and the Jekyll `source:` to `./docs-ludo`, and use its own domain variable.

## Costs

| Item | Cost |
|---|---|
| S3 and requests | a few cents a month |
| CloudFront | within the free allowance (1 TB and 10 million requests a month) |
| ACM certificate | free |
| Route 53 hosted zone | US$0.50 a month |
| Domain | about US$13 a year (.com) |

## When something goes wrong

| Symptom | Cause and fix |
|---|---|
| `curl` or the browser can't find the new domain, but `dig @8.8.8.8` can | This Mac cached "no such domain" from before registration finished. Wait (up to the zone's SOA TTL, 15 min to an hour) or `sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder` |
| Deploy waits a long time on the certificate | Public DNS doesn't point at the hosted zone yet (registration unfinished, or name servers at another registrar not updated). The script checks this before deploying |
| `No public hosted zone for …` | The domain is in another AWS account, or not bought yet |
| Pages load without styling | Jekyll's `baseurl` must be `""` (`docs/_config.yml`): the site lives at the root of its domain |
| A page says "View the Project on GitHub" | `docs/_config.yml` must keep `github.is_project_page: false` |
| Site workflow skipped | Variable `SITE_ON_AWS` is not `true` |
| 404 at `/<app>/` itself | There is no `docs/<app>/index.md`; add one if you want a landing page |

## Removing a site

`cd infra/site && SITE_NAME=<name> STAGE=prod SITE_DIR=<any built site> npx cdk destroy prod-<name>`
deletes the bucket, CloudFront, certificate and records. The domain and its hosted zone stay (delete
or let them lapse in Route 53).
