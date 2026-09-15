# Reusable infrastructure modules

`modules/` contains provider-dependent, environment-agnostic Terraform child modules.
Provider configuration, backend/state ownership and environment-specific values belong in `environments/`.

- `gcp/platform`: existing project/VPC/Artifact Registry/WIF/Cloud Run platform state.
- `gcp/cloudrun`: the independent Cloud Run fallback state retained from `gcp/cloudrun`.
- `cloudflare/platform`: DNS/Access/WAF/cache/zone/laptop-ingress state retained from `terraform/cloudflare`.
- `cloudflare/dns`: the independent DNS state retained from `cloudflare/dns`.
- `neon/projects`: Neon project/database/role state.
- `supabase`: reserved Terraform boundary; native Supabase desired state remains under `/supabase` and is not duplicated here.

Child modules MUST NOT contain backend blocks, committed state, `.tfvars`, or provider credentials.
