# supabase/migrations

**There are no migration files here, and there should not be.**

## dpm is the only migration tool

The fleet contract is that schema changes are authored once, in
`gha-indie-worker-orm-core/schema.sql`, and applied by **dpm**. Nothing else runs
DDL — not SeaORM, not the Supabase CLI, not a service at boot. `-lib-core` holds
query builders and never migrations; every server is explicitly forbidden from
running DDL at startup.

Two tools that can both alter a schema means the schema has two owners, and the
one that loses is whichever ran second.

## What Supabase mirrors

Supabase's copy is **not** a second schema. It mirrors, from the same
`schema.sql`, only the **auth-adjacent tables** — the ones Supabase Auth and
Realtime need to see in order to enforce RLS on a row:

* the user/identity tables that `auth.uid()` policies join against,
* the organisation/membership tables that decide tenancy,
* the tables published to Realtime for client log streaming.

Everything else — runs, jobs, log chunks, workers, plans, embeddings — lives in
the canonical database and is never mirrored. If a table does not need to be
visible to an RLS policy or a Realtime subscription, it does not belong here.

## How a change reaches Supabase

1. Edit `schema.sql` in `gha-indie-worker-orm-core`. That is the only edit.
2. `dpm` applies it to the canonical and auth databases.
3. If the change touched an auth-adjacent table, update the matching policy note
   in `../policies/` in the same pull request, and re-check the policies against
   the new columns.

If you find yourself wanting to write a `.sql` file in this directory, the change
belongs in `schema.sql` instead — and the fact that it seemed to belong here is
worth saying out loud in the pull request, because it usually means an
auth-adjacent table is growing product responsibilities.
