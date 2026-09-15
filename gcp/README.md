# GCP for `gha-indie-worker`

GCP Terraform is now modules-first. Provider implementation lives under `modules/gcp/`; deployable production roots live under `environments/production/`.

Two independent GCP state histories are intentionally preserved:

- `environments/production/gcp-platform` -> `modules/gcp/platform` (formerly `terraform/gcp`)
- `environments/production/gcp-cloudrun` -> `modules/gcp/cloudrun` (formerly `gcp/cloudrun`)

Do not combine them during this layout migration. They overlap conceptually and require a separate state/authority reconciliation before one can replace the other safely.

The product/admin isolation contract is unchanged: separate network identities and secrets, admin Cloud Run internal ingress, no public admin fallback, and independent database planes. Images for the `gcp-cloudrun` root remain digest-pinned.

See `TERRAFORM_LAYOUT.md` and `docs/terraform-layout-migration.md` before planning or applying.
