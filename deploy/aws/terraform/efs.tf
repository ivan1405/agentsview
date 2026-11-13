resource "aws_efs_file_system" "collector" {
  encrypted = true
  tags      = { Name = "${var.name}-collector" }
}
resource "aws_efs_access_point" "collector" {
  file_system_id = aws_efs_file_system.collector.id
  posix_user {
    uid = 0
    gid = 0
  }
  root_directory {
    path = "/archive"
    creation_info {
      owner_uid   = 0
      owner_gid   = 0
      permissions = "0700"
    }
  }
}
resource "aws_efs_mount_target" "collector" {
  count           = 2
  file_system_id  = aws_efs_file_system.collector.id
  subnet_id       = aws_subnet.private[count.index].id
  security_groups = [aws_security_group.service["efs"].id]
}
resource "aws_backup_vault" "collector" {
  name = "${var.name}-collector"
}
resource "aws_backup_plan" "collector" {
  name = "${var.name}-collector"
  rule {
    rule_name         = "daily"
    target_vault_name = aws_backup_vault.collector.name
    schedule          = "cron(0 5 * * ? *)"
    lifecycle { delete_after = 30 }
  }
}
resource "aws_backup_selection" "collector" {
  name         = "collector"
  plan_id      = aws_backup_plan.collector.id
  iam_role_arn = aws_iam_role.backup.arn
  resources    = [aws_efs_file_system.collector.arn]
}
