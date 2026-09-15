# Terraform environment roots

`environments/` contains deployable Terraform root modules and owns provider configuration, state/backends and environment-specific values.

Production intentionally has multiple roots because the repository already had five independent Terraform state histories. The modules migration preserves those boundaries instead of merging state implicitly:

- `production/gcp-platform` -> `modules/gcp/platform`
- `production/gcp-cloudrun` -> `modules/gcp/cloudrun`
- `production/cloudflare-platform` -> `modules/cloudflare/platform`
- `production/cloudflare-dns` -> `modules/cloudflare/dns`
- `production/neon` -> `modules/neon/projects`

Preview and staging are admitted environment namespaces. Add a root there only when that environment actually owns independent managed state. Do not copy production state into them.
