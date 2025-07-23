resource "aws_s3_bucket" "artifact_bucket"{
  bucket="my-bucket-awsproject-tanujasai"
}

resource "aws_iam_role" "codepipeline_role"{
  name="codepipeline-role"

  assume_role_policy=jsonencode({
    Version="2012-10-17",
    Statement=[{
      Effect="Allow",
      Principal={
        Service="codepipeline.amazonaws.com"
      },
      Action="sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "codepipeline_s3_policy" {
  name = "codepipeline-s3-access"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:GetBucketVersioning"
        ],
        Resource = [
          "arn:aws:s3:::my-bucket-awsproject-tanujasai",
          "arn:aws:s3:::my-bucket-awsproject-tanujasai/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_s3_policy" {
  role       = aws_iam_role.codepipeline_role.name
  policy_arn = aws_iam_policy.codepipeline_s3_policy.arn
}


resource "aws_iam_role_policy_attachment" "codepipeline_policy_attach"{
  role=aws_iam_role.codepipeline_role.name
  policy_arn="arn:aws:iam::aws:policy/AWSCodePipeline_FullAccess"
}

resource "aws_iam_role" "codebuild_role"{
  name="codebuild-role"

  assume_role_policy=jsonencode({
    Version="2012-10-17",
    Statement=[{
      Effect="Allow",
      Principal={
        Service="codebuild.amazonaws.com"
      },
      Action="sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "codebuild_policy_attach" {
  role=aws_iam_role.codebuild_role.name
  policy_arn="arn:aws:iam::aws:policy/AWSCodeBuildDeveloperAccess"
}

resource "aws_iam_role" "codedeploy_role"{
  name="codedeploy-role"

  assume_role_policy=jsonencode({
    Version="2012-10-17",
    Statement=[{
      Effect="Allow",
      Principal={
        Service="codedeploy.amazonaws.com"
      },
      Action="sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "codedeploy_policy_attach"{
  role=aws_iam_role.codedeploy_role.name
  policy_arn="arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole"
}


#Policy to allow CodePipeline to use CodeStar connection
resource "aws_iam_policy" "codestar_use_connection_policy" {
  name="CodePipelineUseConnectionPolicy"

  policy=jsonencode({
    Version="2012-10-17",
    Statement=[
      {
        Effect="Allow",
        Action="codestar-connections:UseConnection",
        Resource="arn:aws:codeconnections:ap-south-1:030998640438:connection/d1a78ae9-e88f-4712-9b78-4ede3f038bbc"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_codestar_policy" {
  role       = aws_iam_role.codepipeline_role.name
  policy_arn = aws_iam_policy.codestar_use_connection_policy.arn
}

resource "aws_codebuild_project" "codebuild"{
  name="aws-codebuild"
  description="CodeBuild for demo pipeline"
  build_timeout=5

  source{
    type="GITHUB"
    location="https://github.com/TanujaGajavelli/devops-project"
    buildspec="buildspec.yml"
  }

  artifacts{
    type="NO_ARTIFACTS"
  }

  environment {
    compute_type="BUILD_GENERAL1_SMALL"
    image="aws/codebuild/standard:5.0"
    type="LINUX_CONTAINER"
    privileged_mode=true
  }

  service_role=aws_iam_role.codebuild_role.arn
}


#CodeDeploy Application
resource "aws_codedeploy_app" "my_app"{
  name="aws-project-app"
  compute_platform="Server"
}

#CodeDeploy Deployment Group
resource "aws_codedeploy_deployment_group" "my_deployment_group"{
  app_name=aws_codedeploy_app.my_app.name
  deployment_group_name="aws-project-deploy-group"
  service_role_arn=aws_iam_role.codedeploy_role.arn

  deployment_style{
    deployment_type="IN_PLACE"
    deployment_option="WITHOUT_TRAFFIC_CONTROL"
  }

  ec2_tag_set{
    ec2_tag_filter{
      key="Name"
      type="KEY_AND_VALUE"
      value="aws-project-instance"
    }
  }

  auto_rollback_configuration{
    enabled=true
    events=["DEPLOYMENT_FAILURE"]
  }
}

#Code Pipeline
resource "aws_codepipeline" "codepipeline"{
  name="aws-project-pipeline"
  role_arn=aws_iam_role.codepipeline_role.arn

  artifact_store{
    location=aws_s3_bucket.artifact_bucket.bucket
    type="S3"
  }

  stage{
  name="Source"

  action{
    name="Source"
    category="Source"
    owner="AWS"
    provider="CodeStarSourceConnection"
    version="1"
    output_artifacts=["source_output"]

    configuration={
      ConnectionArn="arn:aws:codeconnections:ap-south-1:030998640438:connection/d1a78ae9-e88f-4712-9b78-4ede3f038bbc"
      FullRepositoryId = "TanujaGajavelli/devops-project"
      BranchName="main"
      DetectChanges= "true"
    }
  }
}


  stage{
    name="Build"

    action{
      name="Build"
      category="Build"
      owner="AWS"
      provider="CodeBuild"
      input_artifacts=["source_output"]
      output_artifacts=["build_output"]
      version="1"

      configuration={
        ProjectName=aws_codebuild_project.codebuild.name
      }
    }
  }

  stage{
    name="Deploy"

    action{
      name="Deploy"
      category="Deploy"
      owner="AWS"
      provider="CodeDeploy"
      input_artifacts=["build_output"]
      version="1"

      configuration={
        ApplicationName=aws_codedeploy_app.my_app.name
        DeploymentGroupName=aws_codedeploy_deployment_group.my_deployment_group.deployment_group_name
      }
    }
  }
}


resource "aws_iam_policy" "codepipeline_codebuild_policy" {
  name = "codepipeline-start-codebuild"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "codebuild:StartBuild",
          "codebuild:BatchGetBuilds"
        ],
        Resource = aws_codebuild_project.codebuild.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_codebuild_policy" {
  role       = aws_iam_role.codepipeline_role.name
  policy_arn = aws_iam_policy.codepipeline_codebuild_policy.arn
}


resource "aws_iam_policy" "codebuild_logging_policy" {
  name = "codebuild-cloudwatch-logging"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_logging_policy_to_codebuild" {
  role       = aws_iam_role.codebuild_role.name
  policy_arn = aws_iam_policy.codebuild_logging_policy.arn
}

#Codebuild s3 policy
resource "aws_iam_policy" "codebuild_s3_policy" {
  name = "codebuild-s3-access"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:GetBucketVersioning",
          "s3:PutObject"
        ],
        Resource = [
          "arn:aws:s3:::my-bucket-awsproject-tanujasai",
          "arn:aws:s3:::my-bucket-awsproject-tanujasai/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_s3_policy_to_codebuild" {
  role       = aws_iam_role.codebuild_role.name
  policy_arn = aws_iam_policy.codebuild_s3_policy.arn
}

#CodeDeploy policy
resource "aws_iam_policy" "codepipeline_codedeploy_policy"{
  name ="codepipeline-codedeploy-access"

  policy=jsonencode({
    Version="2012-10-17",
    Statement=[
      {
        Effect="Allow",
        Action = [
          "codedeploy:CreateDeployment",
          "codedeploy:GetDeployment",
          "codedeploy:GetDeploymentConfig"
        ],
        Resource="*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_codedeploy_policy_to_codepipeline" {
  role= aws_iam_role.codepipeline_role.name
  policy_arn= aws_iam_policy.codepipeline_codedeploy_policy.arn
}


resource "aws_iam_policy" "codepipeline_codedeploy_register_policy" {
  name = "codepipeline-codedeploy-register-revision"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "codedeploy:RegisterApplicationRevision"
        ],
        Resource = aws_codedeploy_app.my_app.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_register_revision_policy" {
  role       = aws_iam_role.codepipeline_role.name
  policy_arn = aws_iam_policy.codepipeline_codedeploy_register_policy.arn
}


resource "aws_iam_policy" "codepipeline_codedeploy_extra_policy" {
  name = "codepipeline-codedeploy-get-revision"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "codedeploy:GetApplicationRevision"
        ],
        Resource = aws_codedeploy_app.my_app.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_get_revision_policy" {
  role       = aws_iam_role.codepipeline_role.name
  policy_arn = aws_iam_policy.codepipeline_codedeploy_extra_policy.arn
}
