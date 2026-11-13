# AgentsView on AWS

Deploy a read-only web UI and an S3 collector backed by PostgreSQL.

```text
Laptops / AWS agents -> S3 ingest -> collector (one Fargate task)
                                     | SQLite archive on EFS
                                     v
Browser -> HTTPS ALB -> web tasks -> RDS PostgreSQL 16
```

The stack creates a two-AZ VPC, public ALB, private Fargate tasks and RDS,
an S3 gateway endpoint, and one NAT gateway by default. Set
`single_nat_gateway = false` for one NAT per AZ. The collector has no
inbound security group rules. Its archive is encrypted on EFS with daily
AWS Backup recovery points retained for 30 days; RDS retains seven days
of backups. The web tasks use ephemeral storage.

## Prerequisites

- Terraform >= 1.6 and AWS CLI credentials with permission to provision
  VPC, ECS, EFS, Backup, RDS, S3, IAM, Secrets Manager, CloudWatch, and ALB.
- An issued ACM certificate in the chosen region covering `domain_name`.
- DNS control: supply `route53_zone_id` for an alias, or point your DNS
  provider's alias at the `alb_dns_name` output.
- Capacity in two availability zones and outbound access to the public GHCR
  image. Pin `image` to a release digest for repeatable deployments.

NAT, ALB, Fargate, EFS/Backup and RDS have ongoing charges even when idle.
This example creates its own VPC; existing-VPC deployment is not supported.

For offline configuration tests, use Terraform >= 1.7 and run
`terraform test`. AWS and random providers are mocked; these tests do not
create cloud resources.

## Deploy

Run from this directory:

```sh
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: domain, certificate, region, machines, CIDRs.
terraform init
terraform plan -out=deployment.tfplan
terraform apply deployment.tfplan
terraform output url
```

Use an encrypted, access-controlled remote Terraform backend with locking
for shared use. No backend is configured here. Passwords, access keys,
the web token and cursor secret end up in Terraform state and saved plans.
Sensitive outputs hide values in routine terminal output, not in state.
Do not commit state, plans, credentials, or your terraform.tfvars.

Retrieve the web bearer token (requires Secrets Manager read permission):

```sh
aws secretsmanager get-secret-value \
  --secret-id "$(terraform output -raw web_token_secret_arn)" \
  --query SecretString --output text
```

Use that token to sign in at the HTTPS URL. Terraform generates a URL-safe
database password and stores it in a Secrets Manager secret as JSON with a
`password` field. Both services receive it via ECS secret injection; no
database password is placed in the task definition. Automatic rotation is
not enabled. Coordinate any password rotation through Terraform so RDS and
the secret remain in sync, then force a new deployment of both services.
Likewise redeploy after rotating the web token or collector credentials.

Set `web_cpu` and `web_memory` to size the web tasks (defaults: 512 CPU
units and 1024 MiB). Set `collector_cpu` and `collector_memory` for the
collector (defaults: 1024 CPU units and 2048 MiB). Choose CPU/memory
combinations supported by AWS Fargate.

## Add a machine

1. Add its unique name to `machines` (letters, digits, dots, underscores and
   hyphens; not `.` or `..`; at most 64 characters).
2. Run `terraform plan`, then `terraform apply`.
3. The changed roots produce a new collector task definition and restart the
   collector. Deployment stops the old task before starting the replacement,
   preserving a single SQLite writer. Expect a short ingest interruption.
4. For laptops, retrieve only that machine's credentials into a secure AWS CLI
   profile. This command prints secrets; do not log or share its output:

   ```sh
   terraform output -json uploader_keys | jq '.["laptop"]'
   aws configure --profile agentsview-upload
   ```

For AWS agents, attach the machine's policy from `uploader_policy_arns` to
the existing host/task role instead. Set `create_uploader_users = false`
to avoid creating any laptop IAM users. Managed uploader policies are
always created. Each policy allows only uploads, reads and prefix-scoped
listing under `MACHINE/raw/*`, not deletion.

The collector currently requires a dedicated static access key: its S3
reader does not use the ECS task role. Terraform stores that key in Secrets
Manager and ECS injects it. If you supply `ingest_kms_key_arn`, its key
policy must allow these IAM principals; their IAM policies already grant
the necessary encrypt/decrypt operations. AES256 encryption is the default.

## Upload laptop transcripts

Set these values and use the matching machine's profile:

```sh
export AWS_PROFILE=agentsview-upload
export AWS_DEFAULT_REGION=us-east-1
BUCKET=your-ingest-bucket
MACHINE=laptop

while true; do
  aws s3 sync "$HOME/.claude/projects" "s3://$BUCKET/$MACHINE/raw/claude"
  aws s3 sync "$HOME/.codex/sessions" "s3://$BUCKET/$MACHINE/raw/codex"
  aws s3 sync "$HOME/.cursor/projects" "s3://$BUCKET/$MACHINE/raw/cursor"
  sleep 300
done
```

Alternatively, put the three sync commands and environment settings in a
script and run it from cron (`*/5 * * * *`) or a launchd job with
`StartInterval` set to 300. Use absolute paths to the AWS CLI in scheduled
jobs. Do not run the loop inside a scheduled job. Do not add `--delete`;
the uploader policy intentionally does not permit object deletion.

For iCodeMate CLI, sync `~/.icodemate/cli/projects` to
`s3://BUCKET/MACHINE/raw/icodemate`. Upload only data you intend to
centralize: transcripts can contain source code, prompts and secrets.

## Limits and operations

- Only Claude, Codex, Cursor and iCodeMate are configured for S3 ingestion.
  Cursor means transcript files under projects, not Cursor IDE SQLite stores.
  Explicit directory arrays replace local defaults for these providers.
  Other providers have no local session directories in the container, so
  no hardcoded provider-disable list is needed.
- New objects are found on the interval scan (default `5m`), not instantly.
  Empty `machines` creates no S3 roots. Adding a machine enables every
  selected agent for that machine; `agents` can narrow that list.
- Keep the collector at exactly one task. Never launch a second collector
  against the same EFS archive, including manual tasks and blue/green
  deployments. Task shutdown allows 40 seconds for the final push.
- The web config contains one generated, stable 32-byte base64 cursor secret
  shared across tasks. It is a task environment value, so restrict ECS
  task-definition read permissions as well as state access.
- The web uses PostgreSQL replica serving. The collector also runs replica
  serving with `--push-watch`, but is unreachable from inbound networks.
- ECS Exec is off by default. Enabling it grants SSM message-channel
  permissions; operators also need ECS Exec client permissions.
- Logs are under `/ecs/NAME/web` and `/ecs/NAME/collector`. A 401 from
  `/api/ping` is healthy because authentication is required.
- RDS deletion protection is on by default. Disable it deliberately before
  teardown. A final snapshot is retained; S3 objects and Backup recovery
  points must be handled explicitly before destroying nonempty resources.
  Never delete the persistent SQLite archive to resolve a version change.
- This configuration is validated statically; an AWS apply and live
  application smoke test are still required in your account.
