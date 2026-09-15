# The one Docker repository for this org's images.
#
# LOCATION MATTERS AND IS CURRENTLY INCONSISTENT ACROSS THE REPOS.
# This repository is created in var.region (us-central1), so images live at
#   us-central1-docker.pkg.dev/gha-indie-worker/gha-indie-worker/<image>
# which is what gha-indie-worker-api-server.rs and -web-server.rs already push
# to and deploy from. The two admin repositories' deploy-cloud-run.yml currently
# reference `us-docker.pkg.dev` — the "us" MULTI-REGION, which is a different
# repository that this root does not create. See README.md; either fix those two
# workflows or add a second repository here deliberately.

resource "google_artifact_registry_repository" "docker" {
  project       = var.project_id
  location      = var.region
  repository_id = var.artifact_registry_id
  format        = "DOCKER"
  description   = "Container images for github.com/gha-indie-worker"

  docker_config {
    # A tag must mean one set of bytes forever. Deploys pin the digest anyway;
    # this makes the tag itself honest.
    immutable_tags = true
  }

  cleanup_policy_dry_run = false

  cleanup_policies {
    id     = "keep-recent-versions"
    action = "KEEP"
    most_recent_versions {
      keep_count = var.artifact_registry_keep_versions
    }
  }

  cleanup_policies {
    id     = "delete-old-untagged"
    action = "DELETE"
    condition {
      tag_state  = "UNTAGGED"
      older_than = "2592000s" # 30 days
    }
  }

  depends_on = [google_project_service.enabled]
}
