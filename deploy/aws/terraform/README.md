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

## Run locally with AWS Emulator

Run the real web and collector containers against emulated S3 and local
PostgreSQL. Terraform still exercises the AWS control-plane APIs, but ECS
does not execute containers. Nothing in this workflow needs a real AWS
account. Never enable `aws_emulator` against AWS endpoints.

### Start the emulator

Use a separate terminal and keep the emulator running throughout the test.
For Linux amd64, install the official package:

```sh
curl -fLo "$HOME/aws-emulator.deb" \
  https://downloads.aws.com/aws-emulator/packages/aws-emulator/LTS/latest/aws-emulator_amd64.deb
sudo apt install "$HOME/aws-emulator.deb"
aws-emulator
```

On macOS, enable **host networking** in Docker Desktop 4.34 or later.
The Compose runtime uses host networking on Linux too. Do not publish
ports with `-p`: all services bind only loopback. Ports 9297 (emulator),
15432 (PostgreSQL), 8080 (web), and 8081 (collector API) must be free.
Docker Desktop Enhanced Container Isolation is incompatible with host
networking. Windows is not covered by this workflow.

There is no official prebuilt emulator image. On macOS, build the supplied
Dockerfile (adapted from the
[official Docker instructions](https://docs.aws.amazon.com/emulator/latest/userguide/getting-started-docker.html))
from `deploy/aws`, then run it in a separate terminal:

```sh
docker build --platform linux/amd64 -f Dockerfile.emulator -t aws-emulator-local .
mkdir -p "$HOME/.aws/emulator"
docker run --rm --platform linux/amd64 --network host \
  --mount "type=bind,src=$HOME/.aws/emulator,dst=/home/emulator/.aws/emulator" \
  aws-emulator-local
```

The native Linux install and Compose runtime have been smoke-tested;
the Docker Desktop/macOS instructions have not been executed here.
See the [AWS Emulator guide](https://docs.aws.amazon.com/emulator/latest/userguide/)
for other installation options.

### Apply the local infrastructure

In a new terminal, start in `deploy/aws/terraform`. Unset any real
credentials and profiles before using the generated emulator credentials:

```sh
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_SECURITY_TOKEN
unset AWS_PROFILE AWS_DEFAULT_PROFILE
export AWS_ENDPOINT_URL=https://127.0.0.1:9297
export AWS_SHARED_CREDENTIALS_FILE="$HOME/.aws/emulator/9297/emulator_credentials"
export AWS_CONFIG_FILE="$HOME/.aws/emulator/9297/config"
export AWS_CA_BUNDLE="$HOME/.aws/emulator/9297/ca.pem"
export AWS_EC2_METADATA_DISABLED=true
export AWS_DISABLE_HOST_PREFIX_INJECTION=true
export AWS_REGION=us-east-1
export AWS_DEFAULT_REGION=us-east-1
curl --cacert "$AWS_CA_BUNDLE" "$AWS_ENDPOINT_URL/__admin/health"

terraform init
terraform workspace select emulator || terraform workspace new emulator
terraform apply -var-file=emulator.tfvars.example
cd ..
python3 emulator-env.py
docker compose --env-file .env.emulator up -d --wait
```

Keep local state separate from real deployments. The endpoint is supplied
by `AWS_ENDPOINT_URL`; the variable does not set or verify the endpoint.
Also unset any service-specific `AWS_ENDPOINT_URL_*` overrides from other
environments. The example creates machine `laptop` and uses a five-second
PostgreSQL push floor. Python 3 and Docker Compose v2+ are required.

The generator reads the currently selected Terraform workspace, refuses
non-emulator outputs, and writes `.env.emulator` with mode 0600 plus a copy
of the CA as `.emulator-ca.pem`. Both are ignored by Git. They contain or
grant access to secrets; never publish them or `docker compose config`
output. Regenerate them after every apply or emulator restart, then run
`docker compose --env-file .env.emulator up -d --wait` again.

The collector uses the Terraform-created IAM key and bucket, not the
emulator's bootstrap key. Its S3 client uses `AWS_S3_ENDPOINT`, not
`AWS_ENDPOINT_URL`. The CA is mounted read-only and `SSL_CERT_FILE` tells
Go's Linux certificate verifier to trust it; `AWS_CA_BUNDLE` alone does
not configure this manually constructed S3 client. No TLS verification is
disabled. Host networking preserves `127.0.0.1`, which is in the emulator
certificate's SANs along with `localhost`.

The collector starts before the web service so they cannot race on initial
PostgreSQL schema creation. Its SQLite archive and PostgreSQL data use
separate named Docker volumes. Web configuration is ephemeral, with the
same stable Terraform-generated cursor secret as ECS.

### Upload sessions and open the UI

From `deploy/aws`, with the emulator environment variables still exported:

```sh
BUCKET=$(terraform -chdir=terraform output -raw ingest_bucket)
# Upload only transcripts you intend to ingest; use synthetic files for tests.
aws --endpoint-url "$AWS_ENDPOINT_URL" s3 sync \
  "$HOME/.claude/projects" "s3://$BUCKET/laptop/raw/claude"
# Codex: sync ~/.codex/sessions to laptop/raw/codex.
# Cursor: sync ~/.cursor/projects to laptop/raw/cursor.
docker compose --env-file .env.emulator logs --tail=40 collector
```

The explicit CLI endpoint also supports older AWS CLI versions that ignore
`AWS_ENDPOINT_URL`. Keep the emulator credential environment active for
every AWS CLI call. Allow a collector interval for ingestion and publishing
(five seconds in the example; watcher fallback polling may also log a
two-minute interval). Open <http://localhost:8080> and retrieve the sign-in token:

```sh
aws --endpoint-url "$AWS_ENDPOINT_URL" secretsmanager get-secret-value \
  --secret-id "$(terraform -chdir=terraform output -raw web_token_secret_arn)" \
  --query SecretString --output text
```

This prints a secret; do not include it in logs. API clients use
`Authorization: Bearer TOKEN`; unauthenticated `/api/ping` returns 401.

Stop the app with `docker compose --env-file .env.emulator down`; do not
use `down -v` to handle schema/version changes. Named volumes persist.
Stopping the emulator loses its AWS resources. A later run needs fresh,
isolated Terraform state (for example, a new workspace), another apply,
and regenerated environment/CA files. Never reuse real-AWS state.

### Emulator limits

- RDS control-plane calls return a connectable SQL endpoint, but its engine
  is SQLite-backed, not PostgreSQL-compatible. AgentsView fails there on
  PostgreSQL-specific SQL such as `to_regclass`. Compose therefore runs
  real `postgres:16` on loopback, with the Terraform database password.
  The emulated RDS resource remains for API coverage, not application use.
- ECS APIs do not run task code. Compose runs the real image and commands,
  uses a local archive volume instead of EFS, and uses HTTP on loopback
  instead of the ALB. Cloud control-plane success is not a deployment test.
- IAM policies are not enforced as on AWS. This does not validate security
  isolation, network rules, backups, encryption, or production IAM.
- Emulator state lives in memory and disappears on restart, unlike the
  application's persistent Docker volumes and Terraform state files.
- Only custom security groups/rules, EFS mount targets, and the EFS
  filesystem policy are gated off. The emulator cannot revoke the default
  security-group egress rule, returns 501 for
  `DescribeMountTargetSecurityGroups`, and rejects the EFS policy lockout
  check. Other resources use the VPC default security group locally.
  ALB/HTTPS listener API calls work with the example's dummy certificate,
  but no real ACM certificate or DNS name is required or issued locally.
  Do not set `route53_zone_id` locally.
- With `aws_emulator = false` (the default), the AWS resource configuration
  stays unchanged.
