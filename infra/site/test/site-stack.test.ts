import * as cdk from 'aws-cdk-lib';
import { Match, Template } from 'aws-cdk-lib/assertions';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { SiteStack } from '../lib/site-stack.js';

const env = { account: '123456789012', region: 'us-east-1' };

function synth(domainName?: string): Template {
  const siteDir = fs.mkdtempSync(path.join(os.tmpdir(), 'site-'));
  fs.writeFileSync(path.join(siteDir, 'index.html'), '<h1>ok</h1>');
  const app = new cdk.App();
  const stack = new SiteStack(app, 'test-oware-site', { env, stage: 'test', siteDir, domainName });
  return Template.fromStack(stack);
}

describe('SiteStack', () => {
  test('the bucket is never public and requires TLS', () => {
    const t = synth();
    t.hasResourceProperties('AWS::S3::Bucket', {
      PublicAccessBlockConfiguration: {
        BlockPublicAcls: true, BlockPublicPolicy: true, IgnorePublicAcls: true, RestrictPublicBuckets: true,
      },
    });
    t.hasResourceProperties('AWS::S3::BucketPolicy', {
      PolicyDocument: { Statement: Match.arrayWith([Match.objectLike({ Effect: 'Deny', Condition: { Bool: { 'aws:SecureTransport': 'false' } } })]) },
    });
  });

  test('CloudFront reads the bucket through Origin Access Control and forces HTTPS', () => {
    const t = synth();
    t.resourceCountIs('AWS::CloudFront::OriginAccessControl', 1);
    t.hasResourceProperties('AWS::CloudFront::Distribution', {
      DistributionConfig: Match.objectLike({
        DefaultRootObject: 'index.html',
        DefaultCacheBehavior: Match.objectLike({ ViewerProtocolPolicy: 'redirect-to-https' }),
        CustomErrorResponses: Match.arrayWith([Match.objectLike({ ErrorCode: 404, ResponsePagePath: '/404.html' })]),
      }),
    });
  });

  test('short URLs resolve to index.html', () => {
    const t = synth();
    const fns = t.findResources('AWS::CloudFront::Function');
    const code: string = Object.values(fns)[0].Properties.FunctionCode;
    // Run the viewer function the way CloudFront does.
    const handler = new Function(`${code}; return handler;`)() as (e: { request: { uri: string } }) => { uri: string };
    const route = (uri: string) => handler({ request: { uri } }).uri;
    expect(route('/lelu-oware/privacy')).toBe('/lelu-oware/privacy/index.html');
    expect(route('/lelu-oware/')).toBe('/lelu-oware/index.html');
    expect(route('/')).toBe('/index.html');
    expect(route('/assets/css/style.css')).toBe('/assets/css/style.css');
  });

  test('without a domain there is no certificate or DNS', () => {
    const t = synth();
    t.resourceCountIs('AWS::CertificateManager::Certificate', 0);
    t.resourceCountIs('AWS::Route53::RecordSet', 0);
  });

  test('with a domain: certificate for it and www, and alias records', () => {
    const t = synth('example.com');
    t.hasResourceProperties('AWS::CertificateManager::Certificate', {
      DomainName: 'example.com',
      SubjectAlternativeNames: ['www.example.com'],
    });
    t.hasResourceProperties('AWS::CloudFront::Distribution', {
      DistributionConfig: Match.objectLike({ Aliases: ['example.com', 'www.example.com'] }),
    });
    t.resourceCountIs('AWS::Route53::RecordSet', 4);   // A and AAAA for the apex and www
  });
});
