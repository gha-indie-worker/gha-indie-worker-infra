# supabase/policies

Row-level security notes for the auth-adjacent tables Supabase can see. These
are **notes, not applied policy** — the SQL that creates them travels with
`schema.sql` through dpm (see `../migrations/README.md`). This directory exists
so the intent is reviewable next to the rest of the infrastructure, and so a
reviewer can tell whether a new column widened someone's access.

## The rules these follow

**RLS is on for every table Supabase can reach.** A table published to
PostgREST or Realtime with RLS disabled is readable by anyone holding the anon
key, which is a public value. There is no "internal" table on a surface that has
a public API in front of it.

**Deny by default, then add.** Every table starts with no policy — which denies
everything — and gains one policy per operation that is genuinely needed.
`USING (true)` never appears.

**Tenancy comes from the token, not the row.** A policy compares the caller's
organisation claim to the row's organisation column. It never trusts an
organisation id supplied in the request body, and it never derives tenancy by
joining through a table the caller can also write.

**A missing row and a forbidden row look the same.** RLS filtering makes a
forbidden row simply absent, which matches how the API answers: another tenant's
run id is *not found*, never *forbidden*, so the API does not confirm that the id
exists.

**Service-role keys never reach a browser.** The anon key is public by design and
gets only what RLS allows. Anything needing more runs server-side in
`api-server.rs` with a database role, not with a service-role key handed to a
client.

## Table-by-table intent

| table | select | insert | update | delete |
|---|---|---|---|---|
| users / identities | own row only (`auth.uid() = id`) | none (created by Auth) | own row, non-privileged columns only | none |
| organizations | rows the caller is a member of | none (server-side) | none (server-side) | none |
| organization_members | rows in the caller's own organisations | none | none | none |
| runs (published to Realtime) | rows in the caller's organisation | none | none | none |
| job_events / log_chunks (Realtime) | rows whose run is in the caller's organisation | none | none | none |

Every write is `none` on purpose: writes go through `api-server.rs`, which has
the state machines, the idempotency ledger and the audit trail. A client that can
insert a row directly can insert one those machines would have refused.

## Reviewing a change

When a column is added to a table in this list, answer both questions in the pull
request:

1. Does the existing `SELECT` policy now expose something it did not before?
   (Policies filter rows, not columns — a new column is visible to everyone the
   row is visible to.)
2. If it is sensitive, does it belong on a table Supabase can reach at all?

## Cross-check with orm-core

These policies must match the tenancy columns in
`gha-indie-worker-orm-core/schema.sql`. If a table's organisation column is
renamed there and not here, the policy silently stops matching and — because a
non-matching policy denies rather than allows — the symptom is an empty result
set, not an error. That failure direction is the safe one, but it is still a
failure: check both files in the same change.
