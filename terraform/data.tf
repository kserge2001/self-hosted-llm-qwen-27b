# --- Model bucket: the company's approved copy of the model weights ---------------------------------

resource "aws_s3_bucket" "models" {
  bucket_prefix = "${local.name}-models-"
  force_destroy = true # lab only: lets `terraform destroy` delete the 31 GB of weights
}

resource "aws_s3_bucket_public_access_block" "models" {
  bucket                  = aws_s3_bucket.models.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "models" {
  bucket = aws_s3_bucket.models.id
  versioning_configuration {
    status = "Enabled"
  }
}

# --- Gateway database: teams, keys, budgets and every request's spend -----------------------------

resource "random_password" "db" {
  length  = 32
  special = false
}

resource "aws_db_subnet_group" "gateway" {
  name       = "${local.name}-gateway"
  subnet_ids = module.vpc.private_subnets
}

resource "aws_security_group" "db" {
  name        = "${local.name}-gateway-db"
  description = "PostgreSQL for the LiteLLM gateway, reachable only from the cluster"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "PostgreSQL from EKS nodes and pods"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [module.eks.cluster_primary_security_group_id]
  }
}

resource "aws_db_instance" "gateway" {
  identifier             = "${local.name}-gateway"
  engine                 = "postgres"
  engine_version         = "17"
  instance_class         = var.db_instance_class
  allocated_storage      = 20
  storage_type           = "gp3"
  storage_encrypted      = true
  db_name                = "litellm"
  username               = "litellm"
  password               = random_password.db.result
  db_subnet_group_name   = aws_db_subnet_group.gateway.name
  vpc_security_group_ids = [aws_security_group.db.id]

  backup_retention_period = 7
  # Lab settings. Production: multi_az = true, deletion_protection = true, a final snapshot.
  multi_az            = false
  deletion_protection = false
  skip_final_snapshot = true
}

# --- Secrets: generated here, stored in Secrets Manager, copied into the cluster by a script -------

resource "random_password" "litellm_master" {
  length  = 40
  special = false
}

resource "random_password" "litellm_salt" {
  length  = 40
  special = false
}

resource "random_password" "vllm_api_key" {
  length  = 40
  special = false
}

resource "random_password" "grafana" {
  length  = 24
  special = false
}

resource "aws_secretsmanager_secret" "platform" {
  name_prefix             = "${local.name}/platform-"
  recovery_window_in_days = 0 # lab only: lets you rebuild with the same name right away
}

resource "aws_secretsmanager_secret_version" "platform" {
  secret_id = aws_secretsmanager_secret.platform.id
  secret_string = jsonencode({
    litellm_master_key = "sk-${random_password.litellm_master.result}"
    litellm_salt_key   = random_password.litellm_salt.result
    vllm_api_key       = random_password.vllm_api_key.result
    grafana_password   = random_password.grafana.result
    database_url       = "postgresql://litellm:${random_password.db.result}@${aws_db_instance.gateway.address}:5432/litellm"
  })
}
