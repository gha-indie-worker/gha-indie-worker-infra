# Firewall posture.
#
# READ THIS BEFORE TRUSTING THESE RULES.
#
# VPC firewall rules govern traffic that actually traverses the VPC: traffic a
# Cloud Run service sends THROUGH its Serverless VPC Access connector, and
# traffic between VM/GKE workloads in these subnets.
#
# They do NOT govern a request from the internet to a Cloud Run service's
# *.run.app URL. That request never enters the VPC — it arrives at Google's
# front end. The control for that is the service's ingress setting and its IAM
# invoker binding, which is why the admin services carry
# INGRESS_TRAFFIC_INTERNAL_ONLY and have no allUsers binding (run_admin.tf).
# What follows is defence in depth for the path that does traverse the VPC. It
# is not the admin plane's front door.
#
# Two more mechanics worth knowing, because they decide how these rules are
# written:
#   * An EGRESS rule may only filter by destination_ranges and target_*; an
#     INGRESS rule only by source_ranges and target_*. There is no
#     "ingress to this range" selector — the destination is expressed by tagging
#     the workloads that sit there.
#   * A Serverless VPC Access connector's instances carry the network tags
#     `vpc-connector` and `vpc-connector-<region>-<connector-name>`. The second
#     one is how a single plane's connector is targeted.
#
# The intent is one sentence: the product plane must not reach the admin plane.
# It is stated from both ends so that deleting either rule still leaves it said.

locals {
  product_connector_tag = "vpc-connector-${var.region}-${google_vpc_access_connector.product.name}"
  admin_connector_tag   = "vpc-connector-${var.region}-${google_vpc_access_connector.admin.name}"

  # Tags any future VM/GKE workload in these subnets must carry. Cloud Run does
  # not use them; the connector tags above cover the serverless path.
  product_workload_tag = "giw-product"
  admin_workload_tag   = "giw-admin"

  product_ranges = [var.product_subnet_cidr, var.product_connector_cidr]
  admin_ranges   = [var.admin_subnet_cidr, var.admin_connector_cidr]
}

# 1. Nothing leaving the product plane may be addressed to the admin plane.
resource "google_compute_firewall" "deny_product_egress_to_admin" {
  project     = var.project_id
  name        = "giw-deny-product-egress-to-admin"
  network     = google_compute_network.vpc.name
  description = "The product plane must not initiate traffic into the admin plane."
  direction   = "EGRESS"
  priority    = 900

  target_tags        = [local.product_connector_tag, local.product_workload_tag]
  destination_ranges = local.admin_ranges

  deny {
    protocol = "all"
  }

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# 2. And nothing in the admin plane accepts traffic from the product ranges,
#    whatever the sender believes it is allowed to do.
resource "google_compute_firewall" "deny_admin_ingress_from_product" {
  project     = var.project_id
  name        = "giw-deny-admin-ingress-from-product"
  network     = google_compute_network.vpc.name
  description = "Nothing from the product plane may reach the admin plane."
  direction   = "INGRESS"
  priority    = 900

  source_ranges = local.product_ranges
  target_tags   = [local.admin_connector_tag, local.admin_workload_tag]

  deny {
    protocol = "all"
  }

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# 3. Google's health-check and front-end probe ranges, scoped to the ports these
#    services actually listen on (api 8080, web 8081, admin-api 8787,
#    admin-web 8788, plus 8080 on Cloud Run where $PORT is 8080).
resource "google_compute_firewall" "allow_health_checks" {
  project     = var.project_id
  name        = "giw-allow-google-health-checks"
  network     = google_compute_network.vpc.name
  description = "Google load-balancer and health-check probe ranges."
  direction   = "INGRESS"
  priority    = 1000

  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
  target_tags   = [local.product_workload_tag, local.admin_workload_tag]

  allow {
    protocol = "tcp"
    ports    = ["8080", "8081", "8787", "8788"]
  }
}

# 4. Each plane may talk to itself. Stated explicitly so that the plane-to-plane
#    denies above are the only thing distinguishing the two.
resource "google_compute_firewall" "allow_intra_product" {
  project     = var.project_id
  name        = "giw-allow-intra-product"
  network     = google_compute_network.vpc.name
  description = "Product plane internal traffic."
  direction   = "INGRESS"
  priority    = 1100

  source_ranges = local.product_ranges
  target_tags   = [local.product_workload_tag]

  allow {
    protocol = "tcp"
  }
}

resource "google_compute_firewall" "allow_intra_admin" {
  project     = var.project_id
  name        = "giw-allow-intra-admin"
  network     = google_compute_network.vpc.name
  description = "Admin plane internal traffic."
  direction   = "INGRESS"
  priority    = 1100

  source_ranges = local.admin_ranges
  target_tags   = [local.admin_workload_tag]

  allow {
    protocol = "tcp"
  }
}

# There is deliberately NO catch-all deny rule here. GCP already applies an
# implied deny-all-ingress at the lowest priority; adding an explicit one above
# it, in a network whose allow rules are this narrow, blocks the first workload
# somebody adds without changing what is actually reachable.
