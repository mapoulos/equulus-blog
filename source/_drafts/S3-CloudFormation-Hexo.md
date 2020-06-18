---
title: S3-CloudFormation-Hexo
date: 2020-06-18 15:56:53
tags:
---

I took the chance to learn a few things as I put together this site. I knew I wanted a lightweight static site, but I wanted most of the flexibility I've had for years while from my [personal wordpress blog](https://alexpoulos.com). [Hexo](https://hexo.io/) seemed like a decent choice: it's built on top of Node (which I prefer to python) and has relatively sane documentation. But there are plenty of other choices out there (see this [post](https://www.sitepoint.com/6-static-blog-generators-arent-jekyll/) for a few). Hosting wise, I knew I'd use S3/CloudFront. I spend loads of time working with Amazon's cloud, so this was a decent opportunity to put together a static site in CloudFormation (before I'd just used AWS Amplify).  

Broadly speaking, there were a few steps:

- configure DNS
- deploy the S3/CloudFormation stack
- generate and upload the files to S3

## Configuring DNS

DNS is, well, always a pain. I came across a haiku last year that sums it up quite nicely:

> It's not DNS
> Surely, it's not DNS.
> It was DNS.


I use hover.com as my registrar for both [equul.us](equul.us) and [alexpoulos.com](alexpoulos.com). I began by deploying the following CloudFormation stack:

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Description: Creates an Amazon Route 53 hosted zone
Parameters:
  DomainName:
    Type: String
    Description: The DNS name of an Amazon Route 53 hosted zone e.g. jevsejev.io
    AllowedPattern: (?!-)[a-zA-Z0-9-.]{1,63}(?<!-)
    ConstraintDescription: must be a valid DNS zone name.
Resources:
  DNS:
    Type: AWS::Route53::HostedZone
    Properties:
      HostedZoneConfig:
        Comment: !Join ['', ['Hosted zone for ', !Ref 'DomainName']]
      Name: !Ref 'DomainName'
      HostedZoneTags:
      - Key: Application
        Value: Blog
  Certificate:
    Type: AWS::CertificateManager::Certificate
    Properties: 
      DomainName: !Ref DomainName
      SubjectAlternativeNames: # in case I want to set these up later
        - alex.equul.us
        - www.equul.us
      ValidationMethod: "DNS"
Outputs:
  Certificate:
    Description: Certificate
    Value: !Ref Certificate
    Export:
      Name: EquulusCertificate
```

Now this will spin forever, at least until you add the verification manually in Route 53. There are ways around this, but I didn't want to go the [Custom Resource route](https://binx.io/blog/2018/10/05/automated-provisioning-of-acm-certificates-using-route53-in-cloudformation/) for a single domain. So I let it create the hosted zone, and then I pointed my nameservers in hover.com at the nameservers listed in Route53 for the hostedzone.

TODO: screenshot

After this, I went into the Route 53 console and added the verification records that had been spit out as CloudFormation events (if I were to do this over, I think I would have gone the custom resource route...):

TODO: screenshots

After this, I waited for a while (well, came back the next day). The stack and SSL certificate had finally been generated. I was ready to move on to building the S3 bucket and the CloudFront Distribution.

## S3/CloudFront Distribution

- walk through the template
- Custom Origin vs S3 Origin
- 

## Hexo build and deploy

- the https://github.com/Wouter33/hexo-deployer-s3-cloudfront doesn't work
- funniness with trailing slashes and /index.html
- 


