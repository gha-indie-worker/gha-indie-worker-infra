# IndieBuild local + Cloudflare quickstart

This is the operator path for running the GIW application on a laptop while
Cloudflare serves `indiebuild.dev`.

## Checkout

```sh
mkdir -p ~/src/indiebuild && cd ~/src/indiebuild

git clone https://github.com/gha-indie-worker/gha-indie-worker-infra.git
git clone https://github.com/gha-indie-worker/giw-desktop-infra.git
git clone https://github.com/gha-indie-worker/giw-desktop-daemon.git
git clone https://github.com/scintilla-run/scintilla-desktop-infra.git
git clone https://github.com/ORESoftware/ores-compose.git

for d in gha-indie-worker-infra giw-desktop-infra giw-desktop-daemon scintilla-desktop-infra ores-compose; do
  git -C "$d" pull --ff-only
done
```

The application source itself is materialized at an exact reviewed commit by
`gha-indie-worker-infra/.ores-compose.yaml`; do not separately run a moving
`main` checkout.

## Install the reviewed local tooling

```sh
cd ~/src/indiebuild/gha-indie-worker-infra
export PATH="${CARGO_HOME:-$HOME/.cargo}/bin:$PATH"
./scripts/dev/bootstrap
./scripts/dev/doctor
```

## Start the application stack

The canonical application compose file starts the API on `127.0.0.1:18090`
and web on `127.0.0.1:18091`.

```sh
cd ~/src/indiebuild/gha-indie-worker-infra
ores-compose check ./.ores-compose.yaml
ores-compose plan ./.ores-compose.yaml
ores-compose up ./.ores-compose.yaml
```

For the shared local edge on `127.0.0.1:8080`:

```sh
just codespace-origin-up
curl --fail http://127.0.0.1:8080/readyz
```

## Start Scintilla + GIW desktop control plane

```sh
cd ~/src/indiebuild/scintilla-desktop-infra
ores-compose check ./.ores-compose.yaml
ores-compose plan ./.ores-compose.yaml
ores-compose up ./.ores-compose.yaml
curl --fail http://127.0.0.1:8765/healthz

cd ~/src/indiebuild/giw-desktop-infra
SCINTILLA_DIR="$(cd ../scintilla-desktop-infra && pwd)"
SCINTILLA_STATE="${SCINTILLA_DESKTOP_STATE:-$SCINTILLA_DIR/.desktop}"
test -s "$SCINTILLA_STATE/runtime/token"
export GIW_SCINTILLA_TOKEN_FILE="$SCINTILLA_STATE/runtime/token"
ores-compose check ./.ores-compose.yaml
ores-compose plan ./.ores-compose.yaml
ores-compose up ./.ores-compose.yaml
curl --fail http://127.0.0.1:8770/healthz
```

Neither `:8765` nor `:8770` is a tunnel origin.

## Cloudflare Tunnel for indiebuild.dev

Install and authenticate Cloudflare:

```sh
brew install cloudflared
cloudflared tunnel login
cloudflared tunnel create indiebuild-local
cloudflared tunnel route dns indiebuild-local local.indiebuild.dev
```

Create `~/.cloudflared/indiebuild-local.yml` using the tunnel id and credential
file printed by Cloudflare:

```yaml
tunnel: YOUR_TUNNEL_UUID
credentials-file: /Users/YOU/.cloudflared/YOUR_TUNNEL_UUID.json
ingress:
  - hostname: local.indiebuild.dev
    service: http://127.0.0.1:8080
  - service: http_status:404
```

Then:

```sh
cd ~/src/indiebuild/gha-indie-worker-infra
./scripts/dev/tunnel laptop "$HOME/.cloudflared/indiebuild-local.yml"
```

For the production hostnames (`app.indiebuild.dev`, `api.indiebuild.dev`,
`auth.indiebuild.dev`) keep the Cloudflare Worker/router in front. Point its
local origin to a dedicated tunnel hostname that terminates at the shared edge
on `:8080`; never tunnel the GIW/Scintilla daemon ports directly.

## Auth worker

```sh
cd ~/src/indiebuild/gha-indie-worker-infra/cloudflare/auth-racer
npm install
npx wrangler login
npx wrangler secret put SUPABASE_ANON_KEY
npx wrangler secret put NEON_AUTH_SHARED_SECRET
npm run check
npm run deploy
```

`GET https://auth.indiebuild.dev/v1/auth/verify` races Supabase session
verification with the Neon-backed `/v1/auth/verify` endpoint and returns the
first successful identity.

## Stop

```sh
cd ~/src/indiebuild/gha-indie-worker-infra
just codespace-edge-down || true
ores-compose down ./.ores-compose.yaml || true

cd ~/src/indiebuild/giw-desktop-infra
ores-compose down ./.ores-compose.yaml || true

cd ~/src/indiebuild/scintilla-desktop-infra
ores-compose down ./.ores-compose.yaml || true
```
