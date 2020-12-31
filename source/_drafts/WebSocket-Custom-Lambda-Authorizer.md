---
title: Troubleshooting Pesky API ApiGatewayV2 Authorizer permissions
tags:
---

Lately I've been building a Web application for [crosscut.io](https://crosscut.io). The frontend is built with Vue/Vuetify, the backend is a mix of TypeScript and R (for GIS Processing). Most of the compute is handled with lambdas, and to provide bi-directional communication I'm using a WebSockets API Gateway. I had a devil of a time getting the permissions to work for the Authorizer. I kept getting errors like this in the API Gateway logs:


2020-07-02T11:34:31.881-04:00 (PDS1PEC4oAMFpyA=) Execution failed due to configuration error: Invalid permissions on Lambda function

2020-07-02T11:34:31.882-04:00 (PDS1PEC4oAMFpyA=) Execution failed due to configuration error: Authorizer error

2020-07-02T11:34:31.882-04:00 (PDS1PEC4oAMFpyA=) Gateway response type: AUTHORIZER_CONFIGURATION_ERROR with status code: 500


After creating an Authorizer through the console instead of through CloudFormation, I realized that the authorizer source arn is different than the other methods (it doesn't run from a stage). I changed my `SourceArn` in the template to this, and then the Authorizer Lambda started working:


{% codeblock Code lang:yaml  %}

AuthPermission:
    Type: AWS::Lambda::Permission
    Properties:
      Action: lambda:InvokeFunction
      FunctionName: !Ref CCAuthorizerLambda
      Principal: apigateway.amazonaws.com
      SourceArn: !Sub "arn:aws:execute-api:${AWS::Region}:${AWS::AccountId}:${CCApi}/*"
{% endcodeblock %}


For reference, the API Gateway and Authorizer are declared like this:

{% codeblock Code lang:js  %}
CCApi:
    Type: "AWS::ApiGatewayV2::Api"
    Properties:
      Name: cc-api
      ProtocolType: WEBSOCKET
      RouteSelectionExpression: $request.body.action
      ApiKeySelectionExpression: $request.header.x-api-key
CCApiAuthorizer:
    Type: AWS::ApiGatewayV2::Authorizer
    Properties:
      ApiId: !Ref CCApi
      # AuthorizerCredentialsArn: !GetAtt CCApiAuthorizerRole.Arn
      AuthorizerType: REQUEST
      AuthorizerUri: !Sub "arn:aws:apigateway:${AWS::Region}:lambda:path/2015-03-31/functions/${CCAuthorizerLambda.Arn}/invocations"
      IdentitySource: 
        - "route.request.header.Authorization"
      Name: ConnectAuthorizer      
{% endcodeblock %}