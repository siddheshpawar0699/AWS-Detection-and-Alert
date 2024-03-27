variable "source_s3_bucket" {}
variable "frame_s3_bucket_name" {}
variable "cognito_username" {
  description = "Email address of user to create a Cognito account"
}
variable "cognito_password" {
  description = "Password of user to create a Cognito account"
}
variable "sns_subscription_email" {
  description = "Enter email to receive email alerts into"
}

provider "aws" {
  region = "us-east-1"  # Replace with your desired region
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# Create the sns topic
resource "aws_sns_topic" "alert_topic" {
  name = "alert-sns-topic"
}

resource "aws_cognito_user_pool" "my_user_pool" {
  name = "swen-614-user-pool"
#   alias_attributes = ["email"]
  username_attributes = ["email"]

    password_policy {
        temporary_password_validity_days = 0
        minimum_length                  =  8
        require_lowercase              = false
        require_numbers                = false
        require_symbols                = false
        require_uppercase              = false
    }

  schema {
    name = "email"
    attribute_data_type = "String"
    required = true
  }

}

resource "aws_cognito_user_pool_client" "my_user_pool_client" {
  name                     = "swen-614-user-pool-client"
  user_pool_id             = aws_cognito_user_pool.my_user_pool.id
  generate_secret          = false  # Set to true if you want a client secret
  explicit_auth_flows      = ["ALLOW_ADMIN_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH", "ALLOW_USER_PASSWORD_AUTH"]
  enable_token_revocation  = true
  prevent_user_existence_errors = "ENABLED"
}

resource "aws_cognito_user" "swen-614-user" {
  user_pool_id = aws_cognito_user_pool.my_user_pool.id
  username     = var.cognito_username
  password     = var.cognito_password
  attributes   = {
    email          = var.cognito_username
    email_verified = true
  }
}


resource "aws_s3_bucket" "eb_bucket" {
  bucket = "swen-sp-614-eb-bucket" 
}


resource "aws_s3_object" "eb_bucket_obj" {
  bucket = aws_s3_bucket.eb_bucket.id
  key    = "beanstalk/app.zip" 
  source = "../app.zip"  

  depends_on = [aws_s3_bucket.eb_bucket]        
}


resource "aws_elastic_beanstalk_application" "eb_app" {
  name        = "enes-eb-tf-app"   
  description = "simple flask app"
  depends_on = [aws_s3_bucket.eb_bucket, aws_s3_object.eb_bucket_obj]         
}


resource "aws_elastic_beanstalk_application_version" "eb_app_ver" {
  bucket      = aws_s3_bucket.eb_bucket.id                   
  key         = aws_s3_object.eb_bucket_obj.id         
  application = aws_elastic_beanstalk_application.eb_app.name 
  name        = "enes-eb-tf-app-version-label"

  depends_on = [aws_s3_bucket.eb_bucket, aws_s3_object.eb_bucket_obj]                
}

resource "aws_elastic_beanstalk_environment" "tfenv" {
  name                = "enes-eb-tf-env"
  application         = aws_elastic_beanstalk_application.eb_app.name             
  solution_stack_name = "64bit Amazon Linux 2 v3.5.9 running Python 3.8"        
  description         = "environment for flask app"                              
  version_label       = aws_elastic_beanstalk_application_version.eb_app_ver.name 

  setting {
    namespace = "aws:autoscaling:launchconfiguration" 
    name      = "IamInstanceProfile"                  
    value     = "${aws_iam_instance_profile.beanstalk_ec2.name}"      
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "USER_POOL_ID"
    value     = "${aws_cognito_user_pool.my_user_pool.id}"  
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "APP_CLIENT_ID"
    value     = "${aws_cognito_user_pool_client.my_user_pool_client.id}" 
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "EC2KeyName"
    value     = "test1"
  }

  depends_on = [ aws_cognito_user_pool.my_user_pool, 
    aws_cognito_user_pool_client.my_user_pool_client, 
    aws_elastic_beanstalk_application.eb_app, 
    aws_elastic_beanstalk_application_version.eb_app_ver,
    aws_iam_instance_profile.beanstalk_ec2,
    aws_s3_bucket.eb_bucket,
    aws_s3_object.eb_bucket_obj
  ]
}

resource "aws_iam_instance_profile" "beanstalk_ec2" {
    name = "beanstalk-ec2-user"
    role = "${aws_iam_role.beanstalk_ec2.name}"
}

resource "aws_iam_role" "beanstalk_ec2" {
    name = "beanstalk-ec2-role"

    managed_policy_arns = [
      "arn:aws:iam::aws:policy/AmazonCognitoPowerUser",
      "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess",
      "arn:aws:iam::aws:policy/AmazonRekognitionFullAccess",
      "arn:aws:iam::aws:policy/AmazonS3FullAccess",
      "arn:aws:iam::aws:policy/AWSElasticBeanstalkMulticontainerDocker",
      "arn:aws:iam::aws:policy/AWSElasticBeanstalkWebTier",
      "arn:aws:iam::aws:policy/AWSElasticBeanstalkWorkerTier"
    ]

    assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

# Create subscriptions for each email address
resource "aws_sns_topic_subscription" "email_subscriptions" {
  topic_arn = aws_sns_topic.alert_topic.arn
  protocol  = "email"
  endpoint  = "${var.sns_subscription_email}"
}

resource "aws_s3_bucket" "frame_s3_bucket" {
  bucket = var.frame_s3_bucket_name
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "frame_s3_bucket_public_access_block" {
  bucket = aws_s3_bucket.frame_s3_bucket.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "frame_s3_bucket_policy" {
  bucket = aws_s3_bucket.frame_s3_bucket.id
  policy = data.aws_iam_policy_document.frame_s3_bucket_iam_policy_document.json
  depends_on = [ aws_s3_bucket_public_access_block.frame_s3_bucket_public_access_block ]
}

data "aws_iam_policy_document" "frame_s3_bucket_iam_policy_document" {
  statement {
    sid = "AllowPublicRead"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    } 

    actions = [
      "s3:GetObject"
    ]

    resources = [
      "${aws_s3_bucket.frame_s3_bucket.arn}/*",
    ]
  }
}

resource "aws_iam_policy" "image_processor_policy" {
  name        = "ImageProcessorPolicy"
  description = "IAM policy for the Image Processor Lambda function"
  
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
        ],
        Resource = "*",
      },
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ],
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*",
      },
      {
        Effect = "Allow",
        Action = "logs:CreateLogGroup",
        Resource = "*",
      },
      {
        Effect = "Allow",
        Action = ["sns:publish"],
        Resource = "*",
      },
      {
        Effect = "Allow",
        Action = [
          "kinesis:GetRecords",
          "kinesis:GetShardIterator",
          "kinesis:ListStreams",
          "kinesis:DescribeStream",
          "kinesis:ListShards",
        ],
        Resource = "*",
      },
      {
        Effect = "Allow",
        Action = ["rekognition:*"],
        Resource = "*",
      },
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:DeleteObject",
        ],
        Resource = [
          "arn:aws:s3:::${var.frame_s3_bucket_name}",
          "arn:aws:s3:::${var.frame_s3_bucket_name}/*",
        ],
      },
    ],
  })
}

resource "aws_iam_role" "image_processor_lambda_execution_role" {
    name = "ImageProcessorLambdaExecutionRole"
    managed_policy_arns = [
        aws_iam_policy.image_processor_policy.arn
    ] 
    path = "/"
    assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
        {
            Effect = "Allow",
            Principal = {
                Service = "lambda.amazonaws.com",
            },
            Action = "sts:AssumeRole",
        },
    ],
    })
    depends_on = [ 
        aws_s3_bucket.frame_s3_bucket,
        aws_dynamodb_table.enriched_frame
    ]
}

resource "aws_iam_policy" "frame_fetcher_policy" {
  name        = "FrameFetcherPolicy"
  description = "IAM policy for the Frame Fetcher Lambda function"
  
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
        ],
        Resource = [
          aws_dynamodb_table.enriched_frame.arn,
          "${aws_dynamodb_table.enriched_frame.arn}/index/${var.ddb_global_secondary_index_name}"
        ],
      },
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ],
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow",
        Action = "logs:CreateLogGroup",
        Resource = "*",
      },
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:DeleteObject",
        ],
        Resource = [
          aws_s3_bucket.frame_s3_bucket.arn,
          "${aws_s3_bucket.frame_s3_bucket.arn}/*",
        ],
      },
    ],
  })
}

resource "aws_iam_role" "frame_fetcher_lambda_execution_role" {
  name = "FrameFetcherLambdaExecutionRole"

  managed_policy_arns = [
    aws_iam_policy.frame_fetcher_policy.arn
  ]

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com",
        },
        Action = "sts:AssumeRole",
      },
    ],
  })
  depends_on = [ 
    aws_s3_bucket.frame_s3_bucket,
    aws_dynamodb_table.enriched_frame 
  ]
}

resource "aws_kinesis_stream" "frame_stream" {
  name        = var.kinesis_stream_name
  shard_count = 1
}

resource "aws_lambda_function" "image_processor_lambda" {
  function_name = "imageprocessor"
  description  = "Function processes frame images fetched from a Kinesis stream."
  handler      = "imageprocessor.handler"
  role         = aws_iam_role.image_processor_lambda_execution_role.arn

  s3_bucket = "${var.source_s3_bucket}"

  s3_key = "${var.image_processor_source_s3_key}"
  
  runtime     = "python3.7"
  timeout     = 40
  memory_size = 128
  depends_on = [ 
    aws_kinesis_stream.frame_stream,
    aws_iam_role.image_processor_lambda_execution_role 
  ]

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.alert_topic.arn
    }
  }
}

resource "aws_lambda_event_source_mapping" "event_source_mapping" {
  event_source_arn = aws_kinesis_stream.frame_stream.arn
  function_name    = aws_lambda_function.image_processor_lambda.arn
  starting_position = "TRIM_HORIZON"
  depends_on = [ 
    aws_kinesis_stream.frame_stream,
    aws_lambda_function.image_processor_lambda,
    aws_iam_policy.image_processor_policy
  ]
}

resource "aws_lambda_function" "frame_fetcher_lambda" {
  function_name = "framefetcher"
  description  = "Function responds to a GET request by returning a list of frames up to a certain fetch horizon."
  handler      = "framefetcher.handler"
  role         = aws_iam_role.frame_fetcher_lambda_execution_role.arn

  s3_bucket = "${var.source_s3_bucket}"

  s3_key = "${var.frame_fetcher_source_s3_key}"
  
  runtime     = "python3.7"
  timeout     = 10
  memory_size = 128
  depends_on = [ aws_iam_role.frame_fetcher_lambda_execution_role ]
}

resource "aws_dynamodb_table" "enriched_frame" {
  name           = var.ddb_table_name
  read_capacity  = 10
  write_capacity = 10
  
  hash_key = "frame_id"
  
  attribute {
    name = "frame_id"
    type = "S"
  }

  attribute {
    name = "processed_timestamp"
    type = "N"
  }

  attribute {
    name = "processed_year_month"
    type = "S"
  }

  global_secondary_index {
    name               = var.ddb_global_secondary_index_name
    projection_type    = "ALL"
    read_capacity      = 10
    write_capacity     = 10

    hash_key = "processed_year_month"
    range_key = "processed_timestamp"
  }
}

resource "aws_dynamodb_table" "felon_images_metadata"{
    name = "felon_images_metadata"
    billing_mode = "PAY_PER_REQUEST"

    hash_key = "ID"

    attribute {
      name = "ID"
      type = "N"
    }

}

resource "aws_api_gateway_rest_api" "vid_analyzer_rest_api" {
  name        = var.api_gateway_rest_api_name
  description = "The amazon rekognition video analyzer public API"
  depends_on = [ aws_lambda_function.frame_fetcher_lambda ]
}

resource "aws_api_gateway_resource" "enriched_frame_resource" {
  rest_api_id = aws_api_gateway_rest_api.vid_analyzer_rest_api.id
  parent_id   = aws_api_gateway_rest_api.vid_analyzer_rest_api.root_resource_id
  path_part   = var.frame_fetcher_api_resource_path_part
  depends_on = [ aws_api_gateway_rest_api.vid_analyzer_rest_api ]

}

resource "aws_api_gateway_method" "enriched_frame_resource_get" {
  rest_api_id   = aws_api_gateway_rest_api.vid_analyzer_rest_api.id
  resource_id   = aws_api_gateway_resource.enriched_frame_resource.id
  http_method   = "GET"
  authorization = "NONE"
  depends_on = [ aws_api_gateway_resource.enriched_frame_resource ]
}

resource "aws_api_gateway_integration" "enriched_frame_resource_get_integration" {
    rest_api_id   = aws_api_gateway_rest_api.vid_analyzer_rest_api.id
    resource_id   = aws_api_gateway_resource.enriched_frame_resource.id
    integration_http_method =  "POST"

    type              = "AWS_PROXY"
    http_method       = "GET"
    uri               = aws_lambda_function.frame_fetcher_lambda.invoke_arn
    depends_on = [ aws_api_gateway_method.enriched_frame_resource_get ]
}

resource "aws_api_gateway_method_response" "enriched_frame_resource_get_method_response" {
    rest_api_id   = aws_api_gateway_rest_api.vid_analyzer_rest_api.id
    resource_id   = aws_api_gateway_resource.enriched_frame_resource.id
    http_method = "GET"
    status_code = 200
    response_models = {
        "application/json" = "Empty"
    }

    response_parameters = {
      "method.response.header.Access-Control-Allow-Origin" = true
      "method.response.header.Access-Control-Allow-Methods" = true
      "method.response.header.Access-Control-Allow-Headers" = true
    }
    depends_on = [ aws_api_gateway_method.enriched_frame_resource_get ]
}

resource "aws_api_gateway_method" "enriched_frame_resource_options" {
    rest_api_id   = aws_api_gateway_rest_api.vid_analyzer_rest_api.id
    resource_id   = aws_api_gateway_resource.enriched_frame_resource.id
    http_method   = "OPTIONS"
    authorization = "NONE"
    depends_on = [ aws_api_gateway_resource.enriched_frame_resource ]
}

resource "aws_api_gateway_integration" "enriched_frame_resource_options_integration" {
    rest_api_id   = aws_api_gateway_rest_api.vid_analyzer_rest_api.id
    resource_id   = aws_api_gateway_resource.enriched_frame_resource.id

    type              = "MOCK"
    http_method       = "OPTIONS"
    passthrough_behavior = "WHEN_NO_MATCH"
    request_templates = {
      "application/json" = jsonencode({"statusCode": 200})
    }

    depends_on = [ 
        aws_api_gateway_method.enriched_frame_resource_options
    ]

}

resource "aws_api_gateway_integration_response" "enriched_frame_resource_options_integration_response" {
    rest_api_id   = aws_api_gateway_rest_api.vid_analyzer_rest_api.id
    resource_id   = aws_api_gateway_resource.enriched_frame_resource.id
    http_method = "OPTIONS"
    status_code = 200

    response_parameters = {
        "method.response.header.Access-Control-Allow-Origin" = "'*'"
        "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS'"
        "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    }
    response_templates = {
      "application/json" = ""
    }
    depends_on = [ 
        aws_api_gateway_integration.enriched_frame_resource_options_integration,
        aws_api_gateway_method_response.enriched_frame_resource_options_method_response
    ]
}

resource "aws_api_gateway_method_response" "enriched_frame_resource_options_method_response" {
    rest_api_id   = aws_api_gateway_rest_api.vid_analyzer_rest_api.id
    resource_id   = aws_api_gateway_resource.enriched_frame_resource.id
    http_method = "OPTIONS"
    status_code = 200

    response_parameters = {
      "method.response.header.Access-Control-Allow-Origin" = true
      "method.response.header.Access-Control-Allow-Methods" = true
      "method.response.header.Access-Control-Allow-Headers" = true
    }
    response_models = {
      "application/json" = "Empty"
    }
    depends_on = [ 
        aws_api_gateway_method.enriched_frame_resource_options
    ]
}

resource "aws_api_gateway_deployment" "vid_analyzer_api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.vid_analyzer_rest_api.id
  depends_on = [
    aws_api_gateway_method.enriched_frame_resource_get,
    aws_api_gateway_method.enriched_frame_resource_options,
    aws_api_gateway_rest_api.vid_analyzer_rest_api,
    aws_api_gateway_resource.enriched_frame_resource,
    aws_api_gateway_method_response.enriched_frame_resource_get_method_response,
    aws_api_gateway_method_response.enriched_frame_resource_options_method_response,
    aws_api_gateway_integration.enriched_frame_resource_options_integration,
    aws_api_gateway_integration.enriched_frame_resource_get_integration,
    aws_api_gateway_integration_response.enriched_frame_resource_options_integration_response
  ]
}

resource "aws_api_gateway_stage" "dev_stage" {
  deployment_id = aws_api_gateway_deployment.vid_analyzer_api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.vid_analyzer_rest_api.id
  stage_name    = var.api_gateway_stage_name
}

resource "aws_api_gateway_usage_plan" "dev_usage_plan" {
  name = var.api_gateway_usage_plan_name

  api_stages {
    api_id = aws_api_gateway_rest_api.vid_analyzer_rest_api.id
    stage  = aws_api_gateway_stage.dev_stage.stage_name
  }

  description = "Development usage plan"
}

resource "aws_api_gateway_api_key" "vid_analyzer_api_key" {
  name        = "DevApiKey"
  description = "Video Analyzer Dev API Key"
  enabled = true
  
  depends_on = [ 
    aws_api_gateway_deployment.vid_analyzer_api_deployment,
    aws_api_gateway_stage.dev_stage
  ]
}

resource "aws_api_gateway_usage_plan_key" "dev_usage_plan_key" {
  key_id        = aws_api_gateway_api_key.vid_analyzer_api_key.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.dev_usage_plan.id
}

resource "aws_lambda_permission" "lambda_invoke_permission_star" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.frame_fetcher_lambda.arn
  principal     = "apigateway.amazonaws.com"

  source_arn = "arn:aws:execute-api:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:${aws_api_gateway_rest_api.vid_analyzer_rest_api.id}/*/*/${var.frame_fetcher_lambda_function_name}"
  depends_on = [ aws_api_gateway_deployment.vid_analyzer_api_deployment ]
}

resource "aws_lambda_permission" "lambda_invoke_permission_get" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.frame_fetcher_lambda.arn
  principal     = "apigateway.amazonaws.com"

  source_arn = "arn:aws:execute-api:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:${aws_api_gateway_rest_api.vid_analyzer_rest_api.id}/*/GET/${var.frame_fetcher_lambda_function_name}"
  depends_on = [ aws_api_gateway_deployment.vid_analyzer_api_deployment ]
}

output "vid_analyzer_api_endpoint" {
  description = "Endpoint for invoking video analyzer API."
  value       = aws_api_gateway_deployment.vid_analyzer_api_deployment.invoke_url
}

output "vid_analyzer_api_key" {
  sensitive = true
  description = "Key for invoking video analyzer API."
  value       = aws_api_gateway_api_key.vid_analyzer_api_key.value
}

output "beanstalk_url" {
  description = "URL to visit the Web UI"
  value = aws_elastic_beanstalk_environment.tfenv.endpoint_url
}
