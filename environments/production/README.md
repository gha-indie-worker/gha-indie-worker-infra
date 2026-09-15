# Production environment

Terraform/OpenTofu root configuration lives here; provider-dependent resources live under `modules/`.

Apply order remains: `gcp` -> `cloudflare` -> edge-router Worker -> `neon`/`supabase`. Each provider has an independent root/state boundary so credentials and blast radius stay isolated.

The historical `terraform/{gcp,cloudflare}` and top-level Neon Terraform roots are retained temporarily as migration references. Do not add new resources there. New changes belong in `modules/*` and `environments/production/*`.
