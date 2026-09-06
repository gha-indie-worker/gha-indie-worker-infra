variable "project_id" {
  description = "GCP project. One org, one project (AGENTS.md 1:1)."
  type        = string
  default     = "gha-indie-worker"
}

variable "region" {
  description = "Region for Cloud Run, the VPC connectors and Artifact Registry."
  type        = string
  default     = "us-central1"
}

variable "github_org" {
  description = "GitHub organisation whose Actions may impersonate the deployer service account."
  type        = string
  default     = "gha-indie-worker"
}

variable "domain" {
  description = "Product domain. Used for the Host header on the web service's health probes, because web-server.rs answers 404 on every path — /healthz included — for a host it does not recognise."
  type        = string
  default     = "indiebuild.dev"
}

# ---- network -----------------------------------------------------------------

variable "vpc_name" {
  description = "Name of the VPC that carries both planes."
  type        = string
  default     = "giw-vpc"
}

variable "product_subnet_cidr" {
  description = "Workload range for the product plane."
  type        = string
  default     = "10.20.0.0/20"
}

variable "admin_subnet_cidr" {
  description = "Workload range for the admin plane. Kept in a separate /20 so a single firewall rule can express product-cannot-reach-admin."
  type        = string
  default     = "10.30.0.0/20"
}

variable "product_connector_cidr" {
  description = "Dedicated /28 for the product Serverless VPC Access connector. A connector attached to a subnet requires that subnet to be a /28 used by nothing else, so it cannot live inside the workload subnet."
  type        = string
  default     = "10.20.240.0/28"
}

variable "admin_connector_cidr" {
  description = "Dedicated /28 for the admin Serverless VPC Access connector."
  type        = string
  default     = "10.30.240.0/28"
}

variable "connector_machine_type" {
  description = "Machine type backing each VPC Access connector."
  type        = string
  default     = "e2-micro"
}

variable "connector_min_instances" {
  description = "Minimum connector instances. GCP requires >= 2."
  type        = number
  default     = 2
}

variable "connector_max_instances" {
  description = "Maximum connector instances. Must be > min_instances."
  type        = number
  default     = 3
}

# ---- Artifact Registry --------------------------------------------------------

variable "artifact_registry_id" {
  description = "Docker repository id. The deploy workflows reference <region>-docker.pkg.dev/<project>/<this-id>/<image>."
  type        = string
  default     = "gha-indie-worker"
}

variable "artifact_registry_keep_versions" {
  description = "How many recent versions of each image to keep. Older untagged versions are deleted so the registry does not grow without bound."
  type        = number
  default     = 20
}

# ---- Cloud Run: shape ----------------------------------------------------------

variable "cloud_run_cpu" {
  description = "CPU limit for every service, overridable per service in `services`."
  type        = string
  default     = "1"
}

variable "cloud_run_memory" {
  description = "Memory limit for every service."
  type        = string
  default     = "512Mi"
}

variable "product_min_instances" {
  description = "Warm instances for the product services. 1 keeps a cold start off the customer path; 0 makes the service free when idle."
  type        = number
  default     = 1
}

variable "product_max_instances" {
  description = "Instance ceiling for the product services — the spend limit as much as the capacity limit."
  type        = number
  default     = 20
}

variable "admin_min_instances" {
  description = "Warm instances for the admin services. 0: an operator can wait for a cold start."
  type        = number
  default     = 0
}

variable "admin_max_instances" {
  description = "Instance ceiling for the admin services."
  type        = number
  default     = 4
}

variable "request_timeout_seconds" {
  description = "Cloud Run request timeout. /v1/ws upgrades ride this timeout, so it is the effective websocket lifetime on the Cloud Run fallback."
  type        = number
  default     = 300
}

variable "container_concurrency" {
  description = "Concurrent requests per instance."
  type        = number
  default     = 80
}

variable "cloud_run_deletion_protection" {
  description = "Refuse `terraform destroy` on a Cloud Run service. Leave true in production."
  type        = bool
  default     = true
}

# ---- Cloud Run: images ---------------------------------------------------------

variable "image_tag" {
  description = "Tag Terraform uses when it CREATES a service. After creation the image is managed by each repository's deploy-cloud-run.yml and Terraform ignores it (see the lifecycle blocks in run_product.tf / run_admin.tf), so this value only matters on day one."
  type        = string
  default     = "latest"
}

# ---- Cloud Run: exposure --------------------------------------------------------

variable "product_services_public" {
  description = <<-EOT
    Whether gha-indie-worker-web and -api accept requests from the public internet
    (ingress = all, plus an allUsers invoker binding).

    This must be TRUE for the edge-router fallback to work at all: the Cloudflare
    Worker fetches the Cloud Run origin directly and cannot mint a Google identity
    token, so a private Cloud Run service is not a fallback, it is a 403.

    Set it FALSE only together with removing those Cloud Run origins from
    cloudflare/edge-router/router.config.json and putting an external HTTPS load
    balancer in front instead. Authentication is application-level either way:
    every route on these services refuses an anonymous caller with 401.
  EOT
  type    = bool
  default = true
}

# ---- application configuration --------------------------------------------------

variable "web_service_env" {
  description = "Extra plaintext environment for the web service, merged over the defaults in run_product.tf. Never put a secret here — this file and the state are not secret stores."
  type        = map(string)
  default     = {}
}

variable "api_service_env" {
  description = "Extra plaintext environment for the api service."
  type        = map(string)
  default     = {}
}

variable "admin_web_service_env" {
  description = "Extra plaintext environment for the admin web service."
  type        = map(string)
  default     = {}
}

variable "admin_api_service_env" {
  description = "Extra plaintext environment for the admin api service."
  type        = map(string)
  default     = {}
}

variable "shared_auth_base" {
  description = "Product shared-auth base URL (SHARED_AUTH_BASE)."
  type        = string
  default     = ""
}

variable "shared_auth_admin_base" {
  description = "Admin-instance shared-auth base URL (SHARED_AUTH_ADMIN_BASE). A different instance from the product one, by contract."
  type        = string
  default     = ""
}

variable "ores_chat_api_base" {
  description = "ores-chat upstream for the API's /v1/chat/* proxy."
  type        = string
  default     = ""
}

variable "nats_url" {
  description = "NATS/JetStream URL reachable over the product connector. Empty disables the async avenue."
  type        = string
  default     = ""
}

variable "admin_nats_url" {
  description = "NATS/JetStream URL reachable over the admin connector."
  type        = string
  default     = ""
}

variable "admin_mcp_url" {
  description = "gha-indie-worker-mcp-server Streamable HTTP endpoint, reachable only from the admin network."
  type        = string
  default     = ""
}

variable "admin_api_base" {
  description = "Internal base URL the admin console calls. Fill this in from the admin API's Cloud Run URL after the first apply."
  type        = string
  default     = ""
}

variable "admin_allowlist" {
  description = "GHA_INDIE_WORKER_ADMIN_ALLOWLIST — the subject ids permitted to act on the admin plane. Not a secret; an identity list."
  type        = string
  default     = ""
}

# ---- secrets -------------------------------------------------------------------

variable "create_placeholder_secret_versions" {
  description = <<-EOT
    Create an initial version holding the literal string "REPLACE_ME" for every
    secret.

    Default false, and that is the fail-closed choice: a Cloud Run revision that
    references a secret with no versions FAILS TO DEPLOY, loudly, at the moment
    someone forgot to populate it. A placeholder version instead lets a service
    start up and authenticate against nothing, or write "REPLACE_ME" into a
    database as if it were a real credential.

    Turn it on only for a throwaway environment.
  EOT
  type    = bool
  default = false
}
