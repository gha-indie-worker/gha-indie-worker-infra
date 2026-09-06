# The two values every repository's deploy workflow needs as GitHub secrets.
# Copy them verbatim; they are identifiers, not credentials.

output "GCP_WORKLOAD_IDENTITY_PROVIDER" {
  description = "Set as the GCP_WORKLOAD_IDENTITY_PROVIDER secret in every deploying repository (or once at org level)."
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "GCP_SERVICE_ACCOUNT" {
  description = "Set as the GCP_SERVICE_ACCOUNT secret. The identity GitHub Actions impersonates; it has no key."
  value       = google_service_account.deployer.email
}

output "GCP_RUN_SERVICE_ACCOUNT" {
  description = "Runtime service accounts, by service. The admin workflows pass one of these as --service-account (their GCP_RUN_SERVICE_ACCOUNT secret); web-server.rs calls the same thing GCP_RUNTIME_SERVICE_ACCOUNT."
  value       = { for k, sa in google_service_account.runtime : k => sa.email }
}

output "cloud_run_hosts" {
  description = "Cloud Run hostnames, without the scheme. These are the values cloudflare/edge-router/router.config.json needs as fallback origins and hostHeaders, and the values terraform/cloudflare wants as cloud_run_*_host."

  value = {
    web       = trimprefix(google_cloud_run_v2_service.web.uri, "https://")
    api       = trimprefix(google_cloud_run_v2_service.api.uri, "https://")
    admin-web = trimprefix(google_cloud_run_v2_service.admin_web.uri, "https://")
    admin-api = trimprefix(google_cloud_run_v2_service.admin_api.uri, "https://")
  }
}

output "cloud_run_urls" {
  description = "Full service URLs."

  value = {
    web       = google_cloud_run_v2_service.web.uri
    api       = google_cloud_run_v2_service.api.uri
    admin-web = google_cloud_run_v2_service.admin_web.uri
    admin-api = google_cloud_run_v2_service.admin_api.uri
  }
}

output "ingress_posture" {
  description = "What is actually reachable, as Terraform sees it. Read this after every apply: `admin-web` and `admin-api` must always be INGRESS_TRAFFIC_INTERNAL_ONLY."

  value = {
    web       = google_cloud_run_v2_service.web.ingress
    api       = google_cloud_run_v2_service.api.ingress
    admin-web = google_cloud_run_v2_service.admin_web.ingress
    admin-api = google_cloud_run_v2_service.admin_api.ingress

    public_invoker_bindings = compact([
      var.product_services_public ? "gha-indie-worker-web:allUsers" : "",
      var.product_services_public ? "gha-indie-worker-api:allUsers" : "",
    ])
  }
}

output "artifact_registry" {
  description = "Where images live. Deploy workflows must use exactly this prefix."
  value       = local.registry_base
}

output "vpc_connectors" {
  description = "Serverless VPC Access connector names, as the deploy workflows pass them to --vpc-connector."

  value = {
    product = google_vpc_access_connector.product.name
    admin   = google_vpc_access_connector.admin.name
  }
}

output "secret_ids" {
  description = "Every Secret Manager container this root created. A secret with no version is not an error here — it is the fail-closed default. Populate with `gcloud secrets versions add`."
  value       = sort(keys(local.secrets))
}

output "unpopulated_secrets_are_expected" {
  description = "A reminder that a Cloud Run deploy will fail until each secret listed in secret_ids has at least one version, and that this is deliberate."
  value       = var.create_placeholder_secret_versions ? "placeholder versions ARE being created — do not use this setting in production" : "no versions created by terraform; populate each secret before the first deploy"
}
