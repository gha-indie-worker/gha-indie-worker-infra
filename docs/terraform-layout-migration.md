# Terraform root migration runbook

This directory migration is state-preserving, not a reprovisioning event.

## Old to new roots

- `terraform/gcp` -> `environments/production/gcp-platform`
- `gcp/cloudrun` -> `environments/production/gcp-cloudrun`
- `terraform/cloudflare` -> `environments/production/cloudflare-platform`
- `cloudflare/dns` -> `environments/production/cloudflare-dns`
- `neon` -> `environments/production/neon`

## Required operator sequence

For each root independently:

1. Stop applying the old root after this migration branch is merged.
2. Identify the exact state used by the old root. Do not guess a bucket/key or create a new production workspace.
3. Configure the new root to use that SAME state. If the state was local, copy the local state file out-of-band into the new working directory before `init`; never commit it. If a backend was configured out-of-band, configure the identical backend/key on the new root.
4. Run `terraform init -reconfigure` (or the backend-specific migration command required by the existing state setup).
5. Run `terraform plan`. The checked-in `moved.tf` must convert old root addresses to their `module.*` addresses. A destroy/recreate caused only by this directory migration is a blocker.
6. Review outputs and the admin/product isolation invariants before applying the saved plan.
7. Apply only from the new root. Never apply old and new roots concurrently.

The repository intentionally does not hard-code backend bucket credentials or secret values. CI validates configuration with backends disabled where possible and never applies.
