mock_provider "aws" {
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/example" }
  }
  mock_resource "aws_iam_policy" {
    defaults = { arn = "arn:aws:iam::123456789012:policy/example" }
  }
  mock_resource "aws_lb" {
    defaults = { arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/example/0000000000000000" }
  }
  mock_resource "aws_lb_target_group" {
    defaults = { arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/example/0000000000000000" }
  }
  mock_resource "aws_secretsmanager_secret" {
    defaults = { arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:example-abcdef" }
  }
  mock_data "aws_availability_zones" {
    defaults = { names = ["us-east-1a", "us-east-1b"] }
  }
}
mock_provider "random" {}

override_resource {
  target = aws_s3_bucket.ingest
  values = {
    id  = "example-ingest"
    arn = "arn:aws:s3:::example-ingest"
  }
}
override_resource {
  target = aws_db_instance.main
  values = {
    address  = "database.example.com"
    username = "agentsview"
    db_name  = "agentsview"
  }
}
variables {
  domain_name     = "sessions.example.com"
  certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/00000000-0000-0000-0000-000000000000"
}

run "two_machines" {
  command = apply
  variables {
    machines = ["laptop", "ci-runner"]
  }
  assert {
    condition     = aws_db_instance.main.password == jsondecode(aws_secretsmanager_secret_version.database.secret_string).password
    error_message = "RDS and the injected secret must use the same password."
  }
  assert {
    condition     = alltrue([for task in aws_ecs_task_definition.service : contains(jsondecode(task.container_definitions)[0].secrets, { name = "PG_PASSWORD", valueFrom = "${aws_secretsmanager_secret.database.arn}:password::" })])
    error_message = "Both services must inject the password field from the database secret."
  }
  assert {
    condition     = aws_ecs_task_definition.service["web"].cpu == "512" && aws_ecs_task_definition.service["web"].memory == "1024" && aws_ecs_task_definition.service["collector"].cpu == "1024" && aws_ecs_task_definition.service["collector"].memory == "2048"
    error_message = "Default task sizes must match each service's requirements."
  }
  assert {
    condition     = strcontains(local.collector_config, "postgres://agentsview:$${PG_PASSWORD}@database.example.com:5432/agentsview?sslmode=require")
    error_message = "The database password reference must stay literal."
  }
  assert {
    condition     = strcontains(local.collector_config, "[agents.claude]\ndirs = [\"s3://example-ingest/ci-runner/raw/claude\",\"s3://example-ingest/laptop/raw/claude\"]")
    error_message = "Each machine needs its own Claude root."
  }
  assert {
    condition     = strcontains(local.collector_config, "[agents.codex]\ndirs = [\"s3://example-ingest/ci-runner/raw/codex\",\"s3://example-ingest/laptop/raw/codex\"]") && strcontains(local.collector_config, "[agents.cursor]\ndirs = [\"s3://example-ingest/ci-runner/raw/cursor\",\"s3://example-ingest/laptop/raw/cursor\"]") && strcontains(local.collector_config, "[agents.icodemate]\ndirs = [\"s3://example-ingest/ci-runner/raw/icodemate\",\"s3://example-ingest/laptop/raw/icodemate\"]")
    error_message = "All selected agents need separate machine roots."
  }
}
run "empty_machines" {
  command = plan
  variables { machines = [] }
  assert {
    condition     = local.collector_sources == "[agents.claude]\ndirs = []\n\n[agents.codex]\ndirs = []\n\n[agents.cursor]\ndirs = []\n\n[agents.icodemate]\ndirs = []\n"
    error_message = "Empty machines must explicitly clear local directories."
  }
}
run "custom_task_sizes" {
  command = plan
  variables {
    web_cpu          = 1024
    web_memory       = 2048
    collector_cpu    = 2048
    collector_memory = 4096
  }
  assert {
    condition     = aws_ecs_task_definition.service["web"].cpu == "1024" && aws_ecs_task_definition.service["web"].memory == "2048" && aws_ecs_task_definition.service["collector"].cpu == "2048" && aws_ecs_task_definition.service["collector"].memory == "4096"
    error_message = "Service-specific task size overrides must reach the task definitions."
  }
}
run "invalid_machine" {
  command = plan
  variables { machines = ["bad/prefix"] }
  expect_failures = [var.machines]
}
run "unsupported_agent" {
  command = plan
  variables { agents = ["unsupported"] }
  expect_failures = [var.agents]
}
