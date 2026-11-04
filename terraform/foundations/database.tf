# One private PostgreSQL instance for LiteLLM (keys, teams, spend).
# Terraform creates the instance and the secrets. The `db-init` Job in platform/db-init reads
# astra/rds/master and creates the litellm database and user from astra/rds/litellm.

resource "random_password" "rds_master" {
  length  = 32
  special = false # avoids characters that break connection URLs
}

resource "aws_db_subnet_group" "this" {
  name       = local.name
  subnet_ids = module.vpc.private_subnets
}

resource "aws_security_group" "rds" {
  name        = "${local.name}-rds"
  description = "PostgreSQL, reachable only from the cluster"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "PostgreSQL from the node security group (system and Karpenter nodes) and the cluster security group"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    security_groups = [
      module.eks.node_security_group_id,
      module.eks.cluster_primary_security_group_id,
    ]
  }
}

resource "aws_db_instance" "this" {
  identifier             = local.name
  engine                 = "postgres"
  engine_version         = "18" # major only: RDS picks the newest 18.x minor (18.6 on 2026-10-28)
  instance_class         = var.db_instance_class
  allocated_storage      = 20 # the gp3 minimum; LiteLLM's keys, teams and spend use a few MB
  storage_type           = "gp3"
  storage_encrypted      = true
  username               = "postgres"
  password               = random_password.rds_master.result
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  auto_minor_version_upgrade = true
  # Lab settings. Production: multi_az = true, deletion_protection = true, backups kept 7-35 days,
  # storage autoscaling (max_allocated_storage) and a final snapshot.
  backup_retention_period = 0 # no automated backups: the lab is deleted after each session
  multi_az                = false
  deletion_protection     = false
  skip_final_snapshot     = true
}
