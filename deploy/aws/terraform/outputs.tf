output "url" {
  value = "https://${var.domain_name}"
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
