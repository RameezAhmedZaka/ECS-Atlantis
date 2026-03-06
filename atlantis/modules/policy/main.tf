################################################################################
# Terraform role
################################################################################

data "aws_caller_identity" "current" {}

resource "aws_iam_policy" "policy" {
  name        = "terraform-managed-${var.policy_name}-${var.environment}"
  path        = var.path
  description = var.description

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        "Effect" : "Allow",
        "Action" : [
          "eks:*",
          "ssm:*",
          "glue:*",
          "athena:*",
          "iam:CreateInstanceProfile",
          "iam:GetPolicyVersion",
          "iam:ListPolicyVersion",
          "iam:GetInstanceProfile",
          "iam:GetPolicy",
          "iam:GetRole",
          "iam:GetRolePolicy",
          "iam:PassRole",
          "iam:ListRoles",
          "iam:ListInstanceProfilesForRole",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:AttachRolePolicy",
          "iam:PutRolePolicy",
          "iam:ListPolicies",
          "iam:ListPolicyVersions",
          "iam:UpdateAssumeRolePolicy",
          "iam:AddRoleToInstanceProfile",
          "ec2:*",
          "elasticloadbalancing:*",
          "cloudwatch:*",
          "autoscaling:*",
          "logs:*",
          "route53:*",
          "kms:*",
          "sns:*",
          "sqs:*",
          "s3:*",
          "cloudfront:*",
          "rds:*",
          "ecr:*",
          "kafka:*",
          "lambda:*",
          "waf:*",
          "secretsmanager:*",
          "dynamodb:*",
          "application-autoscaling:*",
          "sso:DescribeAccountAssignmentCreationStatus",
          "sso:DescribeAccountAssignmentDeletionStatus",
          "sso:DescribePermissionSet",
          "sso:DescribePermissionSetProvisioningStatus",
          "sso:DescribePermissionsPolicies",
          "sso:DescribeRegisteredRegions",
          "sso:GetApplicationInstance",
          "sso:GetApplicationTemplate",
          "sso:GetInlinePolicyForPermissionSet",
          "sso:GetManagedApplicationInstance",
          "sso:GetMfaDeviceManagementForDirectory",
          "sso:GetPermissionSet",
          "sso:GetPermissionsPolicy",
          "sso:GetProfile",
          "sso:GetSharedSsoConfiguration",
          "sso:GetSsoConfiguration",
          "sso:GetSSOStatus",
          "sso:GetTrust",
          "sso:ListAccountAssignmentCreationStatus",
          "sso:ListAccountAssignmentDeletionStatus",
          "sso:ListAccountAssignments",
          "sso:ListAccountsForProvisionedPermissionSet",
          "sso:ListApplicationInstanceCertificates",
          "sso:ListApplicationInstances",
          "sso:ListApplications",
          "sso:ListApplicationTemplates",
          "sso:ListDirectoryAssociations",
          "sso:ListInstances",
          "sso:ListManagedPoliciesInPermissionSet",
          "sso:ListPermissionSetProvisioningStatus",
          "sso:ListPermissionSets",
          "sso:ListPermissionSetsProvisionedToAccount",
          "sso:ListProfileAssociations",
          "sso:ListProfiles",
          "sso:ListTagsForResource",
          "sso-directory:DescribeDirectory",
          "sso-directory:DescribeGroups",
          "sso-directory:DescribeUsers",
          "sso-directory:ListGroupsForUser",
          "sso-directory:ListMembersInGroup",
          "sso-directory:SearchGroups",
          "sso-directory:SearchUsers",
          "sso:CreateManagedApplicationInstance",
          "grafana:*",
          "aps:*",
          "sso:DeleteManagedApplicationInstance",
          "acm:*",
          "wafv2:*",
          "events:*",
          "scheduler:*"
        ],
        "Resource" : "*"
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "iam:CreatePolicy",
          "iam:CreatePolicyVersion",
          "iam:DeletePolicy",
        ]
        "Resource" : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/terraform-managed*",
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:PutRolePolicy",
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:UpdateRole",
          "iam:DetachRolePolicy",
        ]
        "Resource" : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/terraform-managed*",
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "iam:PutGroupPolicy",
        ]
        "Resource" : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:group/terraform-managed*",
      },
      { "Effect" : "Allow",
        "Action" : "iam:CreateServiceLinkedRole",
        "Resource" : "*",
        "Condition" : {
          "StringEquals" : {
            "iam:AWSServiceName" : [
              "autoscaling.amazonaws.com",
              "ec2scheduled.amazonaws.com",
              "elasticloadbalancing.amazonaws.com",
              "spot.amazonaws.com",
              "spotfleet.amazonaws.com",
              "transitgateway.amazonaws.com",
              "redshift.amazonaws.com"
            ]
          }
        }
      },
      {
        "Sid" : "DenySpecifics",
        "Action" : [
          "iam:*User*",
          "iam:*Login*",
          "iam:*Group*",
          "aws-portal:*",
          "budgets:*",
          "config:*",
          "directconnect:*",
          "aws-marketplace:*",
          "aws-marketplace-management:*",
          "ec2:*ReservedInstances*"
        ],
        "Effect" : "Deny",
        "Resource" : "*"
      }
    ]
  })
}