resource "aws_cloudwatch_log_group" "service" {
  for_each          = toset(["web", "collector"])
  name              = "/ecs/${var.name}/${each.key}"
  retention_in_days = var.log_retention_days
}
resource "aws_ecs_cluster" "main" {
  name = var.name
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}
resource "aws_ecs_task_definition" "service" {
  for_each                 = toset(["web", "collector"])
  family                   = "${var.name}-${each.key}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = each.key == "web" ? var.web_cpu : var.collector_cpu
  memory                   = each.key == "web" ? var.web_memory : var.collector_memory
  execution_role_arn       = aws_iam_role.execution[each.key].arn
  task_role_arn            = aws_iam_role.task[each.key].arn
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }
  dynamic "volume" {
    for_each = each.key == "collector" ? [1] : []
    content {
      name = "archive"
      efs_volume_configuration {
        file_system_id     = aws_efs_file_system.collector.id
        transit_encryption = "ENABLED"
        authorization_config {
          access_point_id = aws_efs_access_point.collector.id
          iam             = "ENABLED"
        }
      }
    }
  }
  container_definitions = jsonencode([{
    name            = each.key
    image           = var.image
    essential       = true
    entryPoint      = ["/bin/sh", "-c"]
    command         = [each.key == "collector" ? "umask 077; printf '%s' \"$AGENTSVIEW_CONFIG_TOML\" > /data/config.toml && exec /usr/local/bin/agentsview replica pg serve --push-watch --interval ${var.collector_interval}" : "umask 077; printf '%s' \"$AGENTSVIEW_CONFIG_TOML\" > /data/config.toml && exec /usr/local/bin/agentsview replica pg serve --public-url \"$PUBLIC_URL\""]
    stopTimeout     = 40
    linuxParameters = { initProcessEnabled = true }
    environment = [
      { name = "AGENTSVIEW_CONFIG_TOML", value = each.key == "web" ? local.web_config : local.collector_config },
      { name = "AGENTSVIEW_MODE", value = "pg-serve" },
      { name = "AGENTSVIEW_DATA_DIR", value = "/data" },
      { name = "AGENTSVIEW_HOST", value = "0.0.0.0" },
      { name = "AGENTSVIEW_REQUIRE_AUTH", value = "true" },
      { name = "AGENTSVIEW_NO_BROWSER", value = "true" },
      { name = "AWS_REGION", value = var.region },
      { name = "PUBLIC_URL", value = "https://${var.domain_name}" }
    ]
    secrets = concat([
      { name = "PG_PASSWORD", valueFrom = "${aws_secretsmanager_secret.database.arn}:password::" }
      ], each.key == "web" ? [
      { name = "AGENTSVIEW_AUTH_TOKEN", valueFrom = aws_secretsmanager_secret.auth.arn }
      ] : [
      { name = "AWS_ACCESS_KEY_ID", valueFrom = "${aws_secretsmanager_secret.collector.arn}:access_key_id::" },
      { name = "AWS_SECRET_ACCESS_KEY", valueFrom = "${aws_secretsmanager_secret.collector.arn}:secret_access_key::" },
      { name = "AGENTSVIEW_AUTH_TOKEN", valueFrom = aws_secretsmanager_secret.auth.arn }
    ])
    portMappings = each.key == "web" ? [{ containerPort = 8080, protocol = "tcp" }] : []
    mountPoints  = each.key == "collector" ? [{ sourceVolume = "archive", containerPath = "/data", readOnly = false }] : []
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.service[each.key].name
        awslogs-region        = var.region
        awslogs-stream-prefix = each.key
      }
    }
  }])
}
resource "aws_ecs_service" "web" {
  name                              = "web"
  cluster                           = aws_ecs_cluster.main.id
  task_definition                   = aws_ecs_task_definition.service["web"].arn
  desired_count                     = var.web_desired_count
  launch_type                       = "FARGATE"
  platform_version                  = "1.4.0"
  enable_execute_command            = var.enable_ecs_exec
  health_check_grace_period_seconds = 120
  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [local.service_security_group_ids["web"]]
    assign_public_ip = false
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.web.arn
    container_name   = "web"
    container_port   = 8080
  }
  depends_on = [aws_lb_listener.https, aws_route.nat, aws_iam_role_policy.secrets, aws_iam_role_policy_attachment.execution, aws_secretsmanager_secret_version.auth, aws_secretsmanager_secret_version.database]
}
resource "aws_ecs_service" "collector" {
  name                               = "collector"
  cluster                            = aws_ecs_cluster.main.id
  task_definition                    = aws_ecs_task_definition.service["collector"].arn
  desired_count                      = 1
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100
  launch_type                        = "FARGATE"
  platform_version                   = "1.4.0"
  enable_execute_command             = var.enable_ecs_exec
  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [local.service_security_group_ids["collector"]]
    assign_public_ip = false
  }
  depends_on = [aws_efs_mount_target.collector, aws_efs_file_system_policy.collector, aws_iam_role_policy.efs, aws_route.nat, aws_iam_role_policy.secrets, aws_iam_role_policy_attachment.execution, aws_secretsmanager_secret_version.collector, aws_secretsmanager_secret_version.auth, aws_secretsmanager_secret_version.database]
}
