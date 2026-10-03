#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import * as path from 'path';
import { fileURLToPath } from 'url';
import { SiteStack } from '../lib/site-stack.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const app = new cdk.App();

// Same conventions as aws-cdk-boilerplate: stage from env and a stage-prefixed stack. Always
// us-east-1: CloudFront only accepts certificates from there.
const stage = process.env.STAGE ?? 'dev';
// The built site (Jekyll output plus test reports). The workflow builds it before deploying.
const siteDir = process.env.SITE_DIR ?? path.join(__dirname, '../../../_site');
// e.g. leluoware.com once bought in Route 53 (its hosted zone is created with it). Empty: the
// site is served at its CloudFront address only.
const domainName = process.env.SITE_DOMAIN || undefined;

new SiteStack(app, `${stage}-oware-site`, {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: 'us-east-1',
  },
  stackName: `${stage}-oware-site`,
  description: `Lelu Oware website: privacy, support, What's new and test reports (${stage})`,
  stage,
  siteDir,
  domainName,
});

cdk.Tags.of(app).add('App', 'oware-site');
cdk.Tags.of(app).add('Environment', stage);
cdk.Tags.of(app).add('ManagedBy', 'CDK');

app.synth();
