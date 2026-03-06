base = {
  project          = "github-assume-role"
  environment      = "production"
  owner_team       = "sre"
  stage_account_id = "<ACCOUNT-ID>"       #account id for stage
  svc_account_id   = "<ACCOUNT-ID>"       #account id for svc
  prod_account_id  = "<ACCOUNT-ID>"       #account id for prod
  svc_role_name    = "svc-role"
}

role = {
  terraform_role_name = "atlantis-role"
}

policy = {
  policy_name = "terraform_policy_assumerole_policy"
  path        = "/"
  description = "policy for terraform to provision resources"
}