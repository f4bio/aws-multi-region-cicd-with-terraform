data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  name             = "idleague"
  namespace        = "idleague-tf-state" # This is the tf_backend_config_prefix. Pick a namespace that's globally unique in S3.  See https://github.com/cloudposse/terraform-aws-tfstate-backend#input_namespace
  environment_list = ["dev", "qa", "staging", "prod"]
}

module "terraform_state_backend" {
  for_each            = toset(local.environment_list)
  source              = "github.com/cloudposse/terraform-aws-tfstate-backend?ref=0.38.1"
  namespace           = local.namespace
  stage               = each.key
  dynamodb_table_name = "${local.namespace}-lock-${each.key}"

  terraform_backend_config_file_path = "."
  terraform_backend_config_file_name = "backend.tf"
  force_destroy                      = false
}

# Regional CI/CD Resources such as CodeBuild, CodePipeline, CodeCommit resources
module "regional" {
  source                             = "./modules/regional"
  env                                = var.env
  tag_prefix_list                    = var.tag_prefix_list
  name                               = local.name
  number_of_azs                      = var.number_of_azs
  global_resource_deploy_from_region = var.global_resource_deploy_from_region
  codebuild_artifacts_prefix         = var.codebuild_artifacts_prefix
  source_repo_bucket_prefix          = var.source_repo_bucket_prefix
  codepipeline_artifacts_prefix      = var.codepipeline_artifacts_prefix
  tf_backend_config_prefix           = var.tf_backend_config_prefix
}

# Provider to deploy global resources from the region set in var.global_resource_deploy_from_region
provider "aws" {
  alias  = "global_resource_deploy_from_region"
  region = var.global_resource_deploy_from_region
  assume_role {
    role_arn     = "arn:aws:iam::${var.account}:role/InfraBuildRole"
    session_name = "INFRA_BUILD"
  }
}

# Global CI/CD resources such as IAM roles
module "global" {
  source          = "./modules/global"
  env             = var.env
  target_accounts = var.target_accounts
  tag_prefix_list = var.tag_prefix_list
  name            = local.name

  providers = {
    aws = aws.global_resource_deploy_from_region
  }
}
