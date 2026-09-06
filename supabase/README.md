# Supabase overlays for `gha-indie-worker`

Per the fleet ADR (`k8s-libs-and-shared-defs` → `docs/db-providers-in-infra-adr.md`): provider
overlays live in `*-infra`, one directory per Supabase **project ref**, each connected to the
Supabase GitHub App with working directory `supabase/<ref>` and "Supabase changes only" on.

| directory | role | ref | plane | reached by |
|---|---|---|---|---|
| `mktabbhmldkewllyfizc/` | canonical (product data) | `mktabbhmldkewllyfizc` | product | web-server, api-server |
| `qelemqszswrasjtgwfag/` | auth (shared-auth customer realm) | `qelemqszswrasjtgwfag` | product | web-server, api-server |
| `admin-pending/` | **admin** | not created yet | admin | admin-web-server, admin-api-server **only** |

## Portable SQL does not live here

Schema authority is `gha-indie-worker-orm-core` (SeaORM code-first + Diesel db-first cross-check,
applied with `dpm`). Only Supabase-*specific* overlays belong under `<ref>/supabase/`: RLS policies,
grants, Auth/Storage/Realtime configuration, and Edge Functions. Services never run DDL at boot.

## Near-term shared-org model

Projects live in the shared `oresoftware` Supabase org (org ref `agcymjepsfsztukakrrl`) because a
dedicated project is ~$25/month each. Isolation is by Postgres **schema namespace**
`gha_indie_worker`; every migration here starts with `create schema if not exists gha_indie_worker;`
and is scoped to it. `migrationTarget: own-org-later` in `.db-providers.json` marks the planned move
to a per-org Supabase org, at which point `pg_dump --schema=gha_indie_worker` carries the namespace
across.

## The admin project is deliberately not created yet

The ChatGPT provisioning pass (DEN-3146 / draft PR #85) created the **Neon** admin projects for 39
orgs but stopped before Supabase: the connector quotes $10/month for an additional project and
wanted an explicit cost confirmation, and **Supabase PrivateLink requires Team/Enterprise**
(Team starts at $599/month/org). Two consequences worth writing down before anyone provisions it:

1. **PrivateLink covers Postgres/PgBouncer only.** The admin project's REST (PostgREST), Auth,
   Storage and Realtime endpoints stay on the public internet and need their own controls — JWT
   audience pinning, disabled anon key, IP allow-list on the admin NAT address
   (`gcp/cloudrun` output `nat_addresses.admin`), and RLS that denies by default.
2. Until PrivateLink exists, the admin Supabase project must be reachable **only** from the admin
   NAT address and the k8s admin namespace's egress address, and the admin binaries must fail
   closed when that is not true.

`admin-pending/` holds the migrations that will run the moment the project exists, so the decision
is a billing decision and not an engineering one.
