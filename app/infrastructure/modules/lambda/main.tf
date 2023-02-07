resource "aws_iam_role" "test_service_lambda_role" {
  name = "${var.environment}-test_service_lambda_role"

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}


resource "aws_lambda_permission" "apigw_lambda" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.test_service_lambda_function.function_name
  principal     = "apigateway.amazonaws.com"
}


# Error: error creating Lambda Function (1): InvalidParameterValueException: Source image 801295807338.dkr.ecr.eu-west-1.amazonaws.com/dev-test_service_ecr_repo:latest does not exist. Provide a valid source image.
# solution : https://stackoverflow.com/questions/74257294/aws-error-describing-ecr-images-when-deploying-lambda-in-terraform

data "aws_caller_identity" "current" {}

locals {
  # prefix              = "mycompany"
  account_id          = data.aws_caller_identity.current.account_id
  ecr_repository_name = "${var.environment}-test_service_ecr_repo"
  ecr_image_tag       = "latest"
}

resource "aws_lambda_function" "test_service_lambda_function" {
  function_name = "${var.environment}-test_service_lambda"
  role          = aws_iam_role.test_service_lambda_role.arn
  # image_uri = "${aws_ecr_repository.test_service_ecr_repo.repository_url}:latest"
  image_uri = "${aws_ecr_repository.test_service_ecr_repo.repository_url}:${local.ecr_image_tag}"
  package_type = "Image"
  timeout = 60
}


resource "null_resource" "ecr_image" {
  triggers = {
    python_file = md5(file("../../../src/app.py"))
    docker_file = md5(file("../../../src/Dockerfile"))
  }

  resource "aws_ecr_repository" "test_service_ecr_repo" {
  #name                 = "${var.environment}-test_service_ecr_repo"
  name = local.ecr_repository_name
  image_tag_mutability = "MUTABLE"
}


  provisioner "local-exec" {
    command = <<EOF
           aws ecr get-login-password --region eu-west-1 | docker login --username AWS --password-stdin ${local.account_id}.dkr.ecr.eu-west-1.amazonaws.com
           docker build -t ${local.ecr_repository_name} .
           docker tag ${local.ecr_repository_name}:${local.ecr_image_tag} ${aws_ecr_repository.test_service_ecr_repo.repository_url}:${local.ecr_image_tag} 
           docker push ${aws_ecr_repository.test_service_ecr_repo.repository_url}:${local.ecr_image_tag}
       EOF
    # interpreter = ["pwsh", "-Command"] # For Windows 
    interpreter = ["bash", "-c"] # For Linux/MacOS
    working_dir = "../../../src/"
  }
}

data "aws_ecr_image" "lambda_image" {
  depends_on = [
    null_resource.ecr_image
  ]
  repository_name = local.ecr_repository_name
  image_tag       = local.ecr_image_tag
}
