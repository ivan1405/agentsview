output "url" {
  value = var.aws_emulator ? "http://localhost:8080" : "https://${var.domain_name}"
}
output "alb_dns_name" {
  value = aws_lb.web.dns_name
}
output "ingest_bucket" {
  value = aws_s3_bucket.ingest.id
}
output "web_token_secret_arn" {
  value = aws_secretsmanager_secret.auth.arn
}
output "uploader_policy_arns" {
  value = { for machine, policy in aws_iam_policy.uploader : machine => policy.arn }
}
output "uploader_keys" {
  sensitive = true
  value = { for machine, key in aws_iam_access_key.uploader : machine => {
    access_key_id     = key.id
    secret_access_key = key.secret
  } }
}
output "ecs_cluster" {
  value = aws_ecs_cluster.main.name
}

output "emulator_runtime" {
  description = "Local Compose configuration; contains emulator-only credentials. Never publish."
  sensitive   = true
  value = var.aws_emulator ? {
    AGENTSVIEW_IMAGE                 = var.image
    AGENTSVIEW_AUTH_TOKEN            = random_password.auth.result
    AGENTSVIEW_WEB_CONFIG_TOML       = local.web_config
    AGENTSVIEW_COLLECTOR_CONFIG_TOML = local.collector_config
    COLLECTOR_INTERVAL               = var.collector_interval
    POSTGRES_USER                    = aws_db_instance.main.username
    POSTGRES_DB                      = aws_db_instance.main.db_name
    PG_PASSWORD                      = random_password.database.result
    AWS_ACCESS_KEY_ID                = aws_iam_access_key.collector.id
    AWS_SECRET_ACCESS_KEY            = aws_iam_access_key.collector.secret
    AWS_REGION                       = var.region
    INGEST_BUCKET                    = aws_s3_bucket.ingest.id
  } : null
}
