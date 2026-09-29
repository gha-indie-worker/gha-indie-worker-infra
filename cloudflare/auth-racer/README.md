# IndieBuild auth racer

Cloudflare Worker for `auth.indiebuild.dev`.

## Contract

- `GET /v1/auth/verify` races two **read-only** credential verification paths:
  - Supabase Auth: `SUPABASE_URL/auth/v1/user`
  - Neon-backed GIW backend: `NEON_AUTH_ORIGIN/v1/auth/verify`
- The first successful verifier wins; the loser is aborted.
- Signup/login/refresh requests under `/auth/*` go to Supabase only.
- Writes are never raced. The GIW backend is responsible for idempotently projecting
  identity/session data into Neon.
- Responses are `no-store`; redirects are disabled for verifier calls; verifier
  response bodies are bounded.

## Secrets

```sh
npx wrangler secret put SUPABASE_ANON_KEY
npx wrangler secret put NEON_AUTH_SHARED_SECRET
```

The Neon verifier origin must authenticate the Worker-to-origin request when exposed
outside loopback. For local development, point `NEON_AUTH_ORIGIN` at the
Cloudflare Tunnel hostname that routes to the standalone GIW API edge, never at the
GIW or Scintilla desktop control daemons.
