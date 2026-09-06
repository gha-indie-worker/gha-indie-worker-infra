# Admin Supabase project — not provisioned

Rename this directory to the real 20-character project ref once the admin project exists, and set
`supabase.projects[] .ref` + `state: "active"` in `../../.db-providers.json`.

**Blocked on two owner decisions** (both recorded in the rollout report, neither an engineering task):

1. ~$10/month for one additional project in the shared `oresoftware` org.
2. PrivateLink entitlement — Supabase places it under Enterprise; Team starts at $599/month/org.

Until then, the admin plane's system of record is the **Neon admin project**
(`round-butterfly-64996380`) plus the AWS RDS admin database, both reachable only from the admin
NAT address. Nothing in the admin plane depends on Supabase to function.

Before flipping this on, the acceptance checks in `../../infra-isolation/` must pass against the
real project: connect from the admin network (succeeds), connect from the product network (must be
refused), connect from the public internet (must be refused), and the REST/Auth/Storage/Realtime
endpoints must refuse the anon key.
