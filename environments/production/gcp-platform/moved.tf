moved {
  from = google_project_service.enabled
  to   = module.gcp_platform.google_project_service.enabled
}

moved {
  from = google_artifact_registry_repository.docker
  to   = module.gcp_platform.google_artifact_registry_repository.docker
}

moved {
  from = google_compute_network.vpc
  to   = module.gcp_platform.google_compute_network.vpc
}

moved {
  from = google_compute_subnetwork.product
  to   = module.gcp_platform.google_compute_subnetwork.product
}

moved {
  from = google_compute_subnetwork.admin
  to   = module.gcp_platform.google_compute_subnetwork.admin
}

moved {
  from = google_compute_subnetwork.product_connector
  to   = module.gcp_platform.google_compute_subnetwork.product_connector
}

moved {
  from = google_compute_subnetwork.admin_connector
  to   = module.gcp_platform.google_compute_subnetwork.admin_connector
}

moved {
  from = google_vpc_access_connector.product
  to   = module.gcp_platform.google_vpc_access_connector.product
}

moved {
  from = google_vpc_access_connector.admin
  to   = module.gcp_platform.google_vpc_access_connector.admin
}

moved {
  from = google_compute_firewall.deny_product_egress_to_admin
  to   = module.gcp_platform.google_compute_firewall.deny_product_egress_to_admin
}

moved {
  from = google_compute_firewall.deny_admin_ingress_from_product
  to   = module.gcp_platform.google_compute_firewall.deny_admin_ingress_from_product
}

moved {
  from = google_compute_firewall.allow_health_checks
  to   = module.gcp_platform.google_compute_firewall.allow_health_checks
}

moved {
  from = google_compute_firewall.allow_intra_product
  to   = module.gcp_platform.google_compute_firewall.allow_intra_product
}

moved {
  from = google_compute_firewall.allow_intra_admin
  to   = module.gcp_platform.google_compute_firewall.allow_intra_admin
}

moved {
  from = google_cloud_run_v2_service.web
  to   = module.gcp_platform.google_cloud_run_v2_service.web
}

moved {
  from = google_cloud_run_v2_service.api
  to   = module.gcp_platform.google_cloud_run_v2_service.api
}

moved {
  from = google_cloud_run_v2_service.admin_api
  to   = module.gcp_platform.google_cloud_run_v2_service.admin_api
}

moved {
  from = google_cloud_run_v2_service.admin_web
  to   = module.gcp_platform.google_cloud_run_v2_service.admin_web
}

moved {
  from = google_cloud_run_v2_service_iam_member.web_public
  to   = module.gcp_platform.google_cloud_run_v2_service_iam_member.web_public
}

moved {
  from = google_cloud_run_v2_service_iam_member.api_public
  to   = module.gcp_platform.google_cloud_run_v2_service_iam_member.api_public
}

moved {
  from = google_service_account.runtime
  to   = module.gcp_platform.google_service_account.runtime
}

moved {
  from = google_service_account.deployer
  to   = module.gcp_platform.google_service_account.deployer
}

moved {
  from = google_project_iam_member.deployer
  to   = module.gcp_platform.google_project_iam_member.deployer
}

moved {
  from = google_service_account_iam_member.deployer_acts_as_runtime
  to   = module.gcp_platform.google_service_account_iam_member.deployer_acts_as_runtime
}

moved {
  from = google_secret_manager_secret.this
  to   = module.gcp_platform.google_secret_manager_secret.this
}

moved {
  from = google_secret_manager_secret_version.placeholder
  to   = module.gcp_platform.google_secret_manager_secret_version.placeholder
}

moved {
  from = google_secret_manager_secret_iam_member.accessor
  to   = module.gcp_platform.google_secret_manager_secret_iam_member.accessor
}

moved {
  from = google_iam_workload_identity_pool.github
  to   = module.gcp_platform.google_iam_workload_identity_pool.github
}

moved {
  from = google_iam_workload_identity_pool_provider.github
  to   = module.gcp_platform.google_iam_workload_identity_pool_provider.github
}

moved {
  from = google_service_account_iam_member.github_impersonates_deployer
  to   = module.gcp_platform.google_service_account_iam_member.github_impersonates_deployer
}
