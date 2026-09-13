# Supabase boundary for external PR CI

The `indiebuild.dev/ci` gateway does not need its own Supabase project. It is a stateless dispatcher: GitHub supplies the PR event, the Rust gateway submits a fixed gha-indie-worker profile, the build server owns durable job state, and the gateway writes the final commit status back to GitHub.

`config.toml` makes that negative infrastructure decision machine-readable so a future provisioning pass cannot quietly add a paid shadow project or move webhook credentials into Supabase.

Rules:

1. `create_project` remains `false` unless a separately reviewed design introduces Supabase-owned CI data.
2. Portable application schema remains outside provider overlays; provider-specific RLS/Auth/Storage/Realtime changes stay under the existing project-ref directories.
3. GitHub webhook secrets, GitHub status tokens, and build-server auth stay in sealed secrets and are never committed or stored as Supabase Edge Function environment for this gateway.
4. If CI eventually needs product data, use the existing `gha_indie_worker` namespace in the canonical project with least-privilege roles. Do not reuse the auth or admin project for convenience.
5. The admin project remains a separate, intentionally isolated decision; external PR CI is not a reason to relax its network boundary.
