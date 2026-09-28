# GHA Indie Worker provider race

Cloudflare Worker for the provider-independent **read** surface at `db.indiebuild.dev`.

The Worker sends the same idempotent GET/HEAD request to two application adapters:

- `SUPABASE_ORIGIN` — an HTTPS adapter backed by the GIW Supabase project.
- `NEON_ORIGIN` — an HTTPS adapter backed by the GIW Neon project.

The first successful 2xx/3xx response wins. A fast 5xx does not beat a slower success.
The losing request is aborted. Responses identify the winner with
`x-giw-db-origin: supabase|neon`.

Writes are intentionally **not** raced. POST/PUT/PATCH/DELETE return 405 here.
Signup, login, token refresh, job dispatch, and all other mutations keep one
authoritative execution path through the GIW/Shared Auth backend. This avoids the
classic failure mode where the "losing" side of a race still commits a mutation.

## Configure

The two origins are runtime configuration; no provider credential belongs in Git.

```sh
cd cloudflare/provider-race
npm install
npx wrangler secret put SUPABASE_ORIGIN
npx wrangler secret put NEON_ORIGIN
npx wrangler deploy
```

Each adapter must expose the same read contract and a `/healthz` endpoint. The
Worker route is `db.indiebuild.dev/*`.

Optional deadline:

```sh
npx wrangler secret put GIW_PROVIDER_RACE_DEADLINE_MS
```

The accepted range is 100–10000 ms; default is 2500 ms.

## Test

```sh
npm test
```
