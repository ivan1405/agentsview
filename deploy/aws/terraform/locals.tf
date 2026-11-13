locals {
  s3_agents = ["claude", "codex", "cursor", "icodemate"]
  agent_roots = {
    for agent in local.s3_agents : agent => [
      for machine in sort(var.machines) : "s3://${aws_s3_bucket.ingest.id}/${machine}/raw/${agent}"
    ] if contains(var.agents, agent)
  }
  collector_sources = join("\n", [
    for agent in local.s3_agents : "[agents.${agent}]\ndirs = ${jsonencode(lookup(local.agent_roots, agent, []))}\n"
  ])
  pg_config        = <<-TOML
    [pg]
    url = "postgres://${aws_db_instance.main.username}:$${PG_PASSWORD}@${aws_db_instance.main.address}:5432/${aws_db_instance.main.db_name}?sslmode=require"
  TOML
  collector_config = <<-TOML
    ${local.pg_config}
    ${local.collector_sources}
  TOML
  web_config       = <<-TOML
    cursor_secret = "${random_bytes.cursor.base64}"
    ${local.pg_config}
  TOML
}
