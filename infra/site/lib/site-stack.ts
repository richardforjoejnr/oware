import * as cdk from 'aws-cdk-lib';
import * as acm from 'aws-cdk-lib/aws-certificatemanager';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import * as origins from 'aws-cdk-lib/aws-cloudfront-origins';
import * as route53 from 'aws-cdk-lib/aws-route53';
import * as targets from 'aws-cdk-lib/aws-route53-targets';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as s3deploy from 'aws-cdk-lib/aws-s3-deployment';
import { Construct } from 'constructs';

export interface SiteStackProps extends cdk.StackProps {
  stage: string;
  /** Names the stack's resources, e.g. oware-site. One per website. */
  siteName: string;
  /** The built site to upload (Jekyll output plus test reports). */
  siteDir: string;
  /** A domain bought in Route 53 (its hosted zone exists); the site is also served at www. */
  domainName?: string;
}

/**
 * The public website from a private S3 bucket behind CloudFront (same pattern as
 * aws-cdk-boilerplate's web stack): privacy and support pages App Review links to, What's new,
 * and the test reports. The bucket is never public; CloudFront reads it through Origin Access
 * Control. Everything in it is rebuilt by the workflow, so the bucket is not retained.
 */
export class SiteStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: SiteStackProps) {
    super(scope, id, props);
    const { stage, siteName, siteDir, domainName } = props;

    const bucket = new s3.Bucket(this, 'SiteBucket', {
      bucketName: `${stage}-${siteName}-${this.account}`,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      enforceSSL: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Short URLs, as GitHub Pages served them: /lelu-oware/privacy and /lelu-oware/ resolve to
    // their index.html (the workflow writes privacy.html as privacy/index.html too).
    const prettyUrls = new cloudfront.Function(this, 'PrettyUrlsFn', {
      functionName: `${stage}-${siteName}-pretty-urls`,
      code: cloudfront.FunctionCode.fromInline(`
function handler(event) {
  var req = event.request;
  var uri = req.uri;
  var last = uri.substring(uri.lastIndexOf('/') + 1);
  if (uri.endsWith('/')) { req.uri = uri + 'index.html'; }
  else if (last.indexOf('.') === -1) { req.uri = uri + '/index.html'; }
  return req;
}`),
    });

    let certificate: acm.ICertificate | undefined;
    let zone: route53.IHostedZone | undefined;
    if (domainName) {
      zone = route53.HostedZone.fromLookup(this, 'Zone', { domainName });
      // CloudFront only takes certificates from us-east-1, which is where this stack lives.
      certificate = new acm.Certificate(this, 'Certificate', {
        domainName,
        subjectAlternativeNames: [`www.${domainName}`],
        validation: acm.CertificateValidation.fromDns(zone),
      });
    }

    const distribution = new cloudfront.Distribution(this, 'SiteDistribution', {
      comment: `${stage} ${siteName.replace(/-/g, ' ')}`,
      defaultRootObject: 'index.html',
      domainNames: domainName ? [domainName, `www.${domainName}`] : undefined,
      certificate,
      minimumProtocolVersion: cloudfront.SecurityPolicyProtocol.TLS_V1_2_2021,
      defaultBehavior: {
        origin: origins.S3BucketOrigin.withOriginAccessControl(bucket),
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
        cachePolicy: cloudfront.CachePolicy.CACHING_OPTIMIZED,
        responseHeadersPolicy: cloudfront.ResponseHeadersPolicy.SECURITY_HEADERS,
        functionAssociations: [{ function: prettyUrls, eventType: cloudfront.FunctionEventType.VIEWER_REQUEST }],
      },
      // Without public access S3 answers 403 for a missing key; show the 404 page instead.
      errorResponses: [403, 404].map((httpStatus) => ({
        httpStatus,
        responseHttpStatus: 404,
        responsePagePath: '/404.html',
        ttl: cdk.Duration.minutes(5),
      })),
    });

    if (domainName && zone) {
      for (const recordName of [domainName, `www.${domainName}`]) {
        const target = route53.RecordTarget.fromAlias(new targets.CloudFrontTarget(distribution));
        new route53.ARecord(this, `Alias-${recordName}`, { zone, recordName, target });
        new route53.AaaaRecord(this, `AliasV6-${recordName}`, { zone, recordName, target });
      }
    }

    new s3deploy.BucketDeployment(this, 'SiteDeployment', {
      sources: [s3deploy.Source.asset(siteDir)],
      destinationBucket: bucket,
      distribution,
      distributionPaths: ['/*'],
      memoryLimit: 1024,   // test reports carry screenshots
    });

    const url = `https://${domainName ?? distribution.distributionDomainName}`;
    new cdk.CfnOutput(this, 'SiteUrl', { value: url, exportName: `${stage}-${siteName}-url` });
    new cdk.CfnOutput(this, 'CloudFrontUrl', { value: `https://${distribution.distributionDomainName}` });
    new cdk.CfnOutput(this, 'PrivacyUrl', { value: `${url}/lelu-oware/privacy` });
    new cdk.CfnOutput(this, 'SupportUrl', { value: `${url}/lelu-oware/support` });
  }
}
