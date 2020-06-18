#!/bin/bash

AWS_PROFILE="default"
hexo generate
aws s3 sync public/ s3://equulus-blog-blogs3-187syz9kmeg2b/
aws cloudfront create-invalidation --distribution-id E26V8V7GUAP7JY --paths '/*'
