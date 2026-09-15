# Infrastructure monorepo layout

The canonical Terraform topology is:

```text
modules/
  cloudflare/{platform,dns}/
  gcp/{platform,cloudrun}/
  neon/projects/
  supabase/
environments/
  preview/
  staging/
  production/{cloudflare-platform,cloudflare-dns,gcp-platform,gcp-cloudrun,neon}/
```

`modules/` owns shared provider implementation. `environments/` owns stateful composition, provider configuration and environment values. Production keeps one root per pre-existing state boundary; module organization is NOT permission to merge states.

Provider-native sources stay outside Terraform modules where their provider tools discover them: Supabase config/migrations/functions under `supabase/`, Neon inventory/schema verification under `neon/`, Cloudflare Worker routes under `cloudflare/edge-router/`, Kubernetes manifests under `k8s/`.

The Supabase Terraform module is intentionally empty today: no reviewed Terraform-owned Supabase resources existed before this migration, so native Supabase desired state remains the authority instead of being duplicated.
