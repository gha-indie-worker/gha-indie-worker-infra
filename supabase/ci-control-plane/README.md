# Supabase boundary for external PR CI

The `indiebuild.dev/ci` dispatcher does not get its own Supabase project. Durable build/job state remains owned by the existing build system.

Rules: `create_project` remains false; GitHub webhook/status and build-server credentials stay in sealed secrets; portable application schema remains outside provider overlays; any future Supabase-owned CI data requires a separate design review.
