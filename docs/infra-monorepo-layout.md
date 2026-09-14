# Infrastructure monorepo layout

Reusable infrastructure may live under `modules/`, but provider Git sync must always terminate at a provider-native entrypoint. Providers are never expected to discover the ORESoftware `modules/` convention by themselves.

- **Supabase:** configure a Working directory that contains a child `supabase/` directory. Prefer `.` with root `supabase/`.
- **Cloudflare:** configure each Worker/Pages Root directory to the directory containing its Wrangler/project config; include consumed `modules/cloudflare/` paths in build watch paths.
- **Neon:** keep a `neon.ts` config-as-code entrypoint in the linked project root; it may import reusable policy from `modules/neon/`.

Recommended reusable roots are `modules/{cloudflare,supabase,neon}` plus `environments/{dev,staging,production}`. Keep state isolated per deploy/environment root. Path-filtered CI tests affected roots, while shared-module changes fan out to all consuming sync roots.

A module is not deployable until a committed provider-native sync root can see it. Mirrors and sibling application monorepos are not provider deploy sources. This rollout does not connect providers or apply live infrastructure.
