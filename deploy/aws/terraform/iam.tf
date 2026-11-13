locals {
  ecs_assume = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "ecs-tasks.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}
resource "aws_iam_user" "collector" {
  name = "${var.name}-collector"
}
resource "aws_iam_access_key" "collector" {
  user = aws_iam_user.collector.name
}
resource "aws_iam_user_policy" "collector" {
  user = aws_iam_user.collector.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      { Effect = "Allow", Action = ["s3:ListBucket"], Resource = aws_s3_bucket.ingest.arn },
      { Effect = "Allow", Action = ["s3:GetObject"], Resource = "${aws_s3_bucket.ingest.arn}/*" }
      ], var.ingest_kms_key_arn == null ? [] : [
      { Effect = "Allow", Action = ["kms:Decrypt"], Resource = var.ingest_kms_key_arn }
    ])
  })
}
resource "aws_secretsmanager_secret" "collector" {
  name_prefix = "${var.name}-collector-"
}
resource "aws_secretsmanager_secret_version" "collector" {
  secret_id = aws_secretsmanager_secret.collector.id
  secret_string = jsonencode({
    access_key_id     = aws_iam_access_key.collector.id
    secret_access_key = aws_iam_access_key.collector.secret
  })
}
resource "random_password" "auth" {
  length  = 48
  special = false
}
resource "random_bytes" "cursor" {
  length = 32
}
resource "aws_secretsmanager_secret" "auth" {
  name_prefix = "${var.name}-web-token-"
}
resource "aws_secretsmanager_secret_version" "auth" {
  secret_id     = aws_secretsmanager_secret.auth.id
  secret_string = random_password.auth.result
}
resource "aws_iam_policy" "uploader" {
  for_each    = toset(var.machines)
  name_prefix = "${var.name}-upload-"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Effect    = "Allow", Action = ["s3:ListBucket"], Resource = aws_s3_bucket.ingest.arn
        Condition = { StringLike = { "s3:prefix" = ["${each.key}/raw/*"] } }
      },
      { Effect = "Allow", Action = ["s3:PutObject", "s3:GetObject"], Resource = "${aws_s3_bucket.ingest.arn}/${each.key}/raw/*" }
      ], var.ingest_kms_key_arn == null ? [] : [
      { Effect = "Allow", Action = ["kms:Decrypt", "kms:GenerateDataKey"], Resource = var.ingest_kms_key_arn }
    ])
  })
}
resource "aws_iam_user" "uploader" {
  for_each = var.create_uploader_users ? toset(var.machines) : toset([])
  name     = "${var.name}-upload-${substr(each.key, 0, 24)}-${substr(sha256(each.key), 0, 8)}"
}
resource "aws_iam_access_key" "uploader" {
  for_each = aws_iam_user.uploader
  user     = each.value.name
}
resource "aws_iam_user_policy_attachment" "uploader" {
  for_each   = aws_iam_user.uploader
  user       = each.value.name
  policy_arn = aws_iam_policy.uploader[each.key].arn
}
resource "aws_iam_role" "execution" {
  for_each           = toset(["web", "collector"])
  name_prefix        = "${var.name}-${each.key}-exec-"
  assume_role_policy = local.ecs_assume
}
resource "aws_iam_role_policy_attachment" "execution" {
  for_each   = aws_iam_role.execution
  role       = each.value.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
resource "aws_iam_role_policy" "secrets" {
  for_each = aws_iam_role.execution
  role     = each.value.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["secretsmanager:GetSecretValue"]
      Resource = [
        aws_secretsmanager_secret.database.arn,
        aws_secretsmanager_secret.auth.arn,
        each.key == "web" ? aws_secretsmanager_secret.auth.arn : aws_secretsmanager_secret.collector.arn
      ]
    }]
  })
}
resource "aws_iam_role" "task" {
  for_each           = toset(["web", "collector"])
  name_prefix        = "${var.name}-${each.key}-task-"
  assume_role_policy = local.ecs_assume
}
resource "aws_iam_role_policy" "exec" {
  for_each = var.enable_ecs_exec ? aws_iam_role.task : {}
  role     = each.value.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ssmmessages:CreateControlChannel", "ssmmessages:CreateDataChannel", "ssmmessages:OpenControlChannel", "ssmmessages:OpenDataChannel"]
      Resource = "*"
    }]
  })
}
resource "aws_iam_role_policy" "efs" {
  role = aws_iam_role.task["collector"].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = ["elasticfilesystem:ClientMount", "elasticfilesystem:ClientWrite", "elasticfilesystem:ClientRootAccess"]
      Resource  = aws_efs_file_system.collector.arn
      Condition = { StringEquals = { "elasticfilesystem:AccessPointArn" = aws_efs_access_point.collector.arn } }
    }]
  })
}
resource "aws_efs_file_system_policy" "collector" {
  count          = var.aws_emulator ? 0 : 1
  file_system_id = aws_efs_file_system.collector.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Deny", Principal = "*", Action = "elasticfilesystem:*"
        Resource  = aws_efs_file_system.collector.arn
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
      {
        Effect    = "Allow", Principal = { AWS = aws_iam_role.task["collector"].arn }
        Action    = ["elasticfilesystem:ClientMount", "elasticfilesystem:ClientWrite", "elasticfilesystem:ClientRootAccess"]
        Resource  = aws_efs_file_system.collector.arn
        Condition = { StringEquals = { "elasticfilesystem:AccessPointArn" = aws_efs_access_point.collector.arn } }
      }
    ]
  })
}
resource "aws_iam_role" "backup" {
  name_prefix = "${var.name}-backup-"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "backup.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}
resource "aws_iam_role_policy_attachment" "backup" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}
