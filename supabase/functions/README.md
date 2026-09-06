# supabase/functions

**Edge functions are not used, and this directory is empty on purpose.**

## Why

**There is already an edge.** `cloudflare/edge-router/` is the Worker that fronts
every host, with health-based failover, Access enforcement on the admin hosts and
one origin decision per request. A Supabase Edge Function would be a second,
differently-configured edge with its own deploy path, its own logging and its own
opinion about which origin is healthy.

**There is already a server.** The four interaction avenues — SeaORM reads,
HTTP/WebSocket, TCP, NATS — all terminate in `api-server.rs`, which holds the
state machines, the typed errors, the rate limiter and the audit trail. Logic in
a Deno function is logic outside all of that: it cannot use the domain types, it
is not covered by `cargo test`, and it does not appear in the feature-containment
build that proves what the crate depends on.

**It would be a third language on the critical path.** The fleet's runtimes are
Rust, TypeScript and Dart, and the server tier is Rust. An edge function is
TypeScript-on-Deno with a different standard library and a different deployment
lifetime from the TS clients.

**It reintroduces the surface we are trying to close.** Functions are one of the
six Supabase surfaces that PrivateLink does not cover (see `../README.md`).
Deploying one means a new public endpoint on a project whose network controls are
already blocked on entitlements.

## If this ever changes

The bar is: something that must run in the same transaction or the same
authentication context as Supabase itself, and cannot be done from
`api-server.rs`. A database trigger's side effect is the usual honest example.

If that day comes, add the function here, add its endpoint to
`projects/<role>/project.json` under `surfaces.functions`, set `used: true`, and
say in the pull request what makes it impossible to do in the API server.
