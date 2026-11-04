# Every secret of the platform lives in AWS Secrets Manager under astra/.
# External Secrets copies them into the cluster, so no secret is ever written to Git.
#
# Terraform generates most values. One it cannot know, so it creates only the empty secret
# and you set the value with the AWS CLI (see the `fill_hf_token` output):
#   astra/hf-token          a Hugging Face read token, used by the model loader Job
# astra/teams/<team> is not here: gateway/sync_teams.py writes those.

locals {
  rds_host = aws_db_instance.this.address
  rds_port = aws_db_instance.this.port

  # Database users made by the db-init Job. Same names for the database and its user.
  app_databases = toset(["litellm"])
}

# --- Generated values ----------------------------------------------------------------------------

resource "random_password" "db_user" {
  for_each = local.app_databases
  length   = 32
  special  = false
}

resource "random_password" "litellm_master_key" {
  length  = 40
  special = false
}

resource "random_password" "litellm_salt_key" {
  length  = 40
  special = false
}

resource "random_password" "vllm_api_key" {
  length  = 40
  special = false
}

locals {
  generated_secrets = {
    "rds/master" = jsonencode({
      host     = local.rds_host
      port     = local.rds_port
      dbname   = "postgres"
      username = aws_db_instance.this.username
      password = random_password.rds_master.result
    })
    "rds/litellm" = jsonencode({
      host     = local.rds_host
      port     = local.rds_port
      dbname   = "litellm"
      username = "litellm"
      password = random_password.db_user["litellm"].result
    })
    # LiteLLM checks that the master key starts with sk-.
    "litellm/master-key" = "sk-${random_password.litellm_master_key.result}"
    # The salt key encrypts provider credentials in the database. Never change it after the first start.
    "litellm/salt-key" = random_password.litellm_salt_key.result
    "vllm/api-key"     = random_password.vllm_api_key.result
  }

  # Secrets you fill in by hand.
  student_secrets = toset(["hf-token"])
}

resource "aws_secretsmanager_secret" "generated" {
  for_each = local.generated_secrets

  name                    = "${var.name}/${each.key}"
  recovery_window_in_days = 0 # lab only: lets you rebuild with the same name right away
}

resource "aws_secretsmanager_secret_version" "generated" {
  for_each = local.generated_secrets

  secret_id     = aws_secretsmanager_secret.generated[each.key].id
  secret_string = each.value
}

# No secret_version here on purpose: Terraform would overwrite the value the student set.
resource "aws_secretsmanager_secret" "student" {
  for_each = local.student_secrets

  name                    = "${var.name}/${each.key}"
  recovery_window_in_days = 0
}
