# One VPC, two subnets, two Serverless VPC Access connectors. The product connector has no route
# to the admin subnet, so a product service cannot reach the admin database even with valid creds.

resource "google_compute_network" "vpc" {
  name                    = "giw-vpc"
  auto_create_subnetworks = false
  description             = "gha-indie-worker: product and admin planes, no route between them"
}

resource "google_compute_subnetwork" "product" {
  name                     = "giw-product"
  ip_cidr_range            = "10.20.0.0/20"
  region                   = var.region
  network                  = google_compute_network.vpc.id
  private_ip_google_access = true
}

resource "google_compute_subnetwork" "admin" {
  name                     = "giw-admin"
  ip_cidr_range            = "10.20.16.0/20"
  region                   = var.region
  network                  = google_compute_network.vpc.id
  private_ip_google_access = true
}

resource "google_vpc_access_connector" "product" {
  name   = "giw-product"
  region = var.region
  subnet {
    name = google_compute_subnetwork.product.name
  }
  min_instances = 2
  max_instances = 4
  machine_type  = "e2-micro"
}

resource "google_vpc_access_connector" "admin" {
  name   = "giw-admin"
  region = var.region
  subnet {
    name = google_compute_subnetwork.admin.name
  }
  min_instances = 2
  max_instances = 3
  machine_type  = "e2-micro"
}

# Egress: NAT so the services reach Neon/Supabase/GitHub over stable addresses that the
# providers' IP allow-lists can name. Product and admin get SEPARATE addresses so the admin
# projects' allow-lists can name only the admin address.
resource "google_compute_router" "router" {
  name    = "giw-router"
  region  = var.region
  network = google_compute_network.vpc.id
}

resource "google_compute_address" "nat_product" {
  name   = "giw-nat-product"
  region = var.region
}

resource "google_compute_address" "nat_admin" {
  name   = "giw-nat-admin"
  region = var.region
}

resource "google_compute_router_nat" "product" {
  name                               = "giw-nat-product"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "MANUAL_ONLY"
  nat_ips                            = [google_compute_address.nat_product.self_link]
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"
  subnetwork {
    name                    = google_compute_subnetwork.product.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

resource "google_compute_router_nat" "admin" {
  name                               = "giw-nat-admin"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "MANUAL_ONLY"
  nat_ips                            = [google_compute_address.nat_admin.self_link]
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"
  subnetwork {
    name                    = google_compute_subnetwork.admin.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Default-deny east-west, then the two allow rules we actually want.
resource "google_compute_firewall" "deny_cross_plane" {
  name        = "giw-deny-product-to-admin"
  network     = google_compute_network.vpc.name
  direction   = "INGRESS"
  priority    = 900
  description = "The product plane must never open a connection into the admin plane."

  source_ranges      = [google_compute_subnetwork.product.ip_cidr_range]
  destination_ranges = [google_compute_subnetwork.admin.ip_cidr_range]

  deny {
    protocol = "all"
  }

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_firewall" "admin_internal" {
  name        = "giw-admin-internal"
  network     = google_compute_network.vpc.name
  direction   = "INGRESS"
  priority    = 1000
  description = "Admin services (and the MCP server) may talk to each other inside the admin subnet."

  source_ranges      = [google_compute_subnetwork.admin.ip_cidr_range]
  destination_ranges = [google_compute_subnetwork.admin.ip_cidr_range]

  allow {
    protocol = "tcp"
    ports    = ["443", "8080", "8787", "8788", "8790"]
  }
}
