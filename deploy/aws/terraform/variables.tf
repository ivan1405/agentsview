variable "region" {
  type    = string
  default = "us-east-1"
}
variable "name" {
  type    = string
  default = "agentsview"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,19}$", var.name))
    error_message = "Use a lowercase letter followed by up to 19 lowercase letters, digits or hyphens."
  }
}
variable "domain_name" {
  type        = string
  description = "DNS name covered by the ACM certificate."
}
variable "certificate_arn" {
  type        = string
  description = "Issued ACM certificate ARN in the deployment region."
}
variable "route53_zone_id" {
  type    = string
  default = null
}
variable "image" {
  type    = string
  default = "ghcr.io/kenn-io/agentsview:latest"
}
variable "machines" {
  type    = list(string)
  default = []
  validation {
    condition     = alltrue([for m in var.machines : can(regex("^[A-Za-z0-9._-]+$", m)) && !contains([".", ".."], m) && length(m) <= 64]) && length(distinct(var.machines)) == length(var.machines)
    error_message = "Machine names must be unique, 1-64 letters, digits, dots, underscores or hyphens, and not . or ..."
  }
}
variable "agents" {
  type    = set(string)
  default = ["claude", "codex", "cursor", "icodemate"]
  validation {
    condition     = alltrue([for a in var.agents : contains(["claude", "codex", "cursor", "icodemate"], a)])
    error_message = "Supported S3 agents: claude, codex, cursor, icodemate."
  }
}
variable "create_uploader_users" {
  type    = bool
  default = true
}
variable "allowed_cidrs" {
  type    = set(string)
  default = ["0.0.0.0/0"]
  validation {
    condition     = alltrue([for c in var.allowed_cidrs : can(cidrnetmask(c))])
    error_message = "Use IPv4 CIDRs."
  }
}
variable "vpc_cidr" {
  type    = string
  default = "10.42.0.0/16"
}
variable "single_nat_gateway" {
  type    = bool
  default = true
}
variable "web_cpu" {
  type        = number
  default     = 512
  description = "Web Fargate CPU units; choose a supported CPU/memory combination."
}
variable "web_memory" {
  type        = number
  default     = 1024
  description = "Web Fargate memory in MiB."
}
variable "collector_cpu" {
  type        = number
  default     = 1024
  description = "Collector Fargate CPU units; choose a supported CPU/memory combination."
}
variable "collector_memory" {
  type        = number
  default     = 2048
  description = "Collector Fargate memory in MiB."
}
variable "web_desired_count" {
  type    = number
  default = 1
  validation {
    condition     = var.web_desired_count >= 1 && floor(var.web_desired_count) == var.web_desired_count
    error_message = "Web desired count must be a positive integer."
  }
}
variable "collector_interval" {
  type    = string
  default = "5m"
  validation {
    condition     = can(regex("^([0-9]+(\\.[0-9]+)?(ms|s|m|h))+$", var.collector_interval)) && can(regex("[1-9]", var.collector_interval))
    error_message = "Use a positive Go duration, such as 5m."
  }
}
variable "db_instance_class" {
  type    = string
  default = "db.t4g.small"
}
variable "db_multi_az" {
  type    = bool
  default = false
}
variable "deletion_protection" {
  type    = bool
  default = true
}
variable "log_retention_days" {
  type    = number
  default = 30
}
variable "enable_ecs_exec" {
  type    = bool
  default = false
}
variable "ingest_kms_key_arn" {
  type        = string
  default     = null
  description = "Optional customer-managed KMS key; its policy must permit the created IAM principals."
}
variable "noncurrent_version_expiration_days" {
  type    = number
  default = null
  validation {
    condition     = var.noncurrent_version_expiration_days == null ? true : var.noncurrent_version_expiration_days >= 1 && floor(var.noncurrent_version_expiration_days) == var.noncurrent_version_expiration_days
    error_message = "Use null or a positive integer."
  }
}
