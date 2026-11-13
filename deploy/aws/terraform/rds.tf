resource "random_password" "database" {
  length  = 48
  special = false
}
resource "aws_secretsmanager_secret" "database" {
  name_prefix = "${var.name}-database-"
}
resource "aws_secretsmanager_secret_version" "database" {
  secret_id     = aws_secretsmanager_secret.database.id
  secret_string = jsonencode({ password = random_password.database.result })
}
resource "aws_db_subnet_group" "main" {
  name_prefix = "${var.name}-"
  subnet_ids  = aws_subnet.private[*].id
}
resource "aws_db_instance" "main" {
  identifier                 = var.name
  engine                     = "postgres"
  engine_version             = "16"
  instance_class             = var.db_instance_class
  allocated_storage          = 20
  max_allocated_storage      = 100
  storage_type               = "gp3"
  storage_encrypted          = true
  db_name                    = "agentsview"
  username                   = "agentsview"
  password                   = random_password.database.result
  publicly_accessible        = false
  db_subnet_group_name       = aws_db_subnet_group.main.name
  vpc_security_group_ids     = [aws_security_group.service["db"].id]
  multi_az                   = var.db_multi_az
  backup_retention_period    = 7
  deletion_protection        = var.deletion_protection
  skip_final_snapshot        = false
  final_snapshot_identifier  = "${var.name}-final-${random_id.suffix.hex}"
  auto_minor_version_upgrade = true
}
