# One VPC, two planes.
#
#   giw-product-subnet  10.20.0.0/20   web + api workloads
#   giw-admin-subnet    10.30.0.0/20   admin-web + admin-api workloads
#
# Each plane gets its own Serverless VPC Access connector, so a Cloud Run service
# reaches private ranges with the network identity of its own plane and nothing
# else. The admin connector is what makes admin egress auditable and what the
# admin firewall rules key off.
#
# WHY THERE ARE FOUR SUBNETS AND NOT TWO: a connector attached with `subnet` must
# own a /28 that carries no other workload. So each plane has a workload /20 plus
# a connector /28 carved out of the same plane's address space — the connector is
# still inside its plane's range, which is what the firewall rules care about.

resource "google_compute_network" "vpc" {
  project                         = var.project_id
  name                            = var.vpc_name
  auto_create_subnetworks         = false
  routing_mode                    = "REGIONAL"
  delete_default_routes_on_create = false

  depends_on = [google_project_service.enabled]
}

resource "google_compute_subnetwork" "product" {
  project       = var.project_id
  name          = "giw-product-subnet"
  region        = var.region
  network       = google_compute_network.vpc.id
  ip_cidr_range = var.product_subnet_cidr

  # Reach Google APIs without a public IP.
  private_ip_google_access = true

  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_subnetwork" "admin" {
  project       = var.project_id
  name          = "giw-admin-subnet"
  region        = var.region
  network       = google_compute_network.vpc.id
  ip_cidr_range = var.admin_subnet_cidr

  private_ip_google_access = true

  # The admin plane samples every flow. It is low volume and it is the plane
  # whose traffic anyone would ever have to reconstruct after an incident.
  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 1.0
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_subnetwork" "product_connector" {
  project       = var.project_id
  name          = "giw-product-connector-subnet"
  region        = var.region
  network       = google_compute_network.vpc.id
  ip_cidr_range = var.product_connector_cidr
  purpose       = "PRIVATE"
}

resource "google_compute_subnetwork" "admin_connector" {
  project       = var.project_id
  name          = "giw-admin-connector-subnet"
  region        = var.region
  network       = google_compute_network.vpc.id
  ip_cidr_range = var.admin_connector_cidr
  purpose       = "PRIVATE"
}

resource "google_vpc_access_connector" "product" {
  project = var.project_id
  name    = "gha-indie-worker-connector"
  region  = var.region

  subnet {
    name       = google_compute_subnetwork.product_connector.name
    project_id = var.project_id
  }

  machine_type  = var.connector_machine_type
  min_instances = var.connector_min_instances
  max_instances = var.connector_max_instances

  depends_on = [google_project_service.enabled]
}

resource "google_vpc_access_connector" "admin" {
  project = var.project_id
  name    = "gha-indie-worker-admin-connector"
  region  = var.region

  subnet {
    name       = google_compute_subnetwork.admin_connector.name
    project_id = var.project_id
  }

  machine_type  = var.connector_machine_type
  min_instances = var.connector_min_instances
  max_instances = var.connector_max_instances

  depends_on = [google_project_service.enabled]
}
