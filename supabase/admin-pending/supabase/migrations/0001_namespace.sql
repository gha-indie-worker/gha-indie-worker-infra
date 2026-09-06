-- gha-indie-worker / admin: isolated namespace inside the shared oresoftware Supabase org.
-- Every object this org owns in this project lives in this schema and nowhere else.
create schema if not exists gha_indie_worker;

-- Nothing is readable by default. Grants are explicit, per-role, below.
revoke all on schema gha_indie_worker from public;

-- Roles Supabase creates: anon (unauthenticated), authenticated (a logged-in end user),
-- service_role (server-side, bypasses RLS). The admin project grants NONE of them to anon.
do $$
begin
  if 'admin' = 'admin' then
    -- Admin plane: no anonymous access at all, ever.
    execute 'revoke all on schema gha_indie_worker from anon';
    execute 'revoke all on schema gha_indie_worker from authenticated';
    execute 'grant usage on schema gha_indie_worker to service_role';
  else
    execute 'grant usage on schema gha_indie_worker to authenticated, service_role';
  end if;
end
$$;

-- Default-deny RLS for anything created later in this schema.
alter default privileges in schema gha_indie_worker revoke all on tables from public, anon;
