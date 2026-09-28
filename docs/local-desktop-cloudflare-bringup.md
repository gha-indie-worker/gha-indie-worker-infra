# Local desktop + Cloudflare bring-up

This is the reproducible developer path for running the GHA Indie Worker product stack locally while keeping the machine control plane loopback-only.

There are three deliberately separate lifecycles:

1. **GIW product API/web** — `gha-indie-worker-infra/.ores-compose.yaml` (`127.0.0.1:18090` / `:18091`).
2. **GIW desktop execution adapter** — `giw-desktop-infra/.ores-compose.yaml` (`127.0.0.1:8770`) -> Scintilla desktop daemon (`127.0.0.1:8765`).
3. **Public ingress** — the shared Rust edge (`127.0.0.1:8080`) plus `cloudflared`.

`ores-compose up` is intentionally foreground-attached. Cloudflare Tunnel remains a separate supervisor/process; do not put tunnel credentials into an ORES Compose manifest or repository environment.

## 1. Clone/update the reviewed GIW graph

```sh
mkdir -p "$HOME/src"
cd "$HOME/src"

if [ ! -d gha-infra/.git ]; then
  git clone --recurse-submodules \
    https://github.com/gha-indie-worker/gha-indie-worker-infra.git \
    gha-infra
fi

cd "$HOME/src/gha-infra"
git fetch origin
git switch main
git pull --ff-only
git submodule sync --recursive
git submodule update --init --recursive
```

Do not independently pull nested submodules during ordinary bring-up: the gitlinks are reviewed revision pins.

## 2. Install/check local tooling

```sh
cargo install --git https://github.com/ORESoftware/ores-compose.git --locked ores-compose
brew install just cloudflared gh || true

cd "$HOME/src/gha-infra"
just codespace-edge-check
scripts/dev/bootstrap
scripts/dev/doctor
```

A private bootstrap fetch can require a narrowly scoped `ORES_CLI_READ_TOKEN`; do not persist it in repo config.

## 3. Run only the product API/web with ORES Compose

```sh
cd "$HOME/src/gha-infra"
ores-compose check .ores-compose.yaml
ores-compose plan .ores-compose.yaml
ores-compose up .ores-compose.yaml
```

In another terminal:

```sh
curl -fsS http://127.0.0.1:18090/readyz
curl -fsS http://127.0.0.1:18091/readyz
```

Port `8080` is not owned by this compose manifest; the shared edge owns it.

## 4. Run the shared edge

The reviewed wrapper starts the pinned `codespaces-cluster` controller, uses ORES Compose for the product app, and then starts the shared Rust edge/connector lifecycle:

```sh
cd "$HOME/src/gha-infra"
just codespace-edge-up
just codespace-edge-status
curl -fsS http://127.0.0.1:8080/api/readyz
```

Stop it with:

```sh
just codespace-edge-down
```

This path uses the shared edge contract and can require `TUNNEL_TOKEN`/private bootstrap access according to the pinned `codespaces-cluster` configuration.

## 5. Explicit laptop Cloudflare Tunnel

For a developer laptop, keep the tunnel config and credential JSON outside Git:

```sh
mkdir -p "$HOME/.config/gha-indie-worker"
cp cloudflare/laptop-ingress/config.example.yml \
  "$HOME/.config/gha-indie-worker/cloudflared.yml"
${EDITOR:-vi} "$HOME/.config/gha-indie-worker/cloudflared.yml"
```

Fill in the actual tunnel UUID, credentials-file path, Cloudflare Access team name, and Access audience. The ingress contract is:

```yaml
ingress:
  - hostname: local.indiebuild.dev
    service: http://127.0.0.1:8080
  - service: http_status:404
```

Then run:

```sh
cd "$HOME/src/gha-infra"
scripts/dev/tunnel laptop "$HOME/.config/gha-indie-worker/cloudflared.yml"
```

The laptop hostname is **`local.indiebuild.dev`**. Do not repoint the production `indiebuild.dev` apex at a developer laptop; production stays behind the normal Cloudflare edge Worker.

## 6. GIW desktop daemon through ORES Compose

```sh
cd "$HOME/src"
if [ ! -d giw-desktop-infra/.git ]; then
  git clone https://github.com/gha-indie-worker/giw-desktop-infra.git
fi
cd giw-desktop-infra
git fetch origin
git switch main
git pull --ff-only

ores-compose check .ores-compose.yaml
ores-compose plan .ores-compose.yaml
ores-compose up .ores-compose.yaml
```

The pinned manifest builds the exact `giw-desktop-daemon` revision and binds it to `127.0.0.1:8770`.

Direct Cargo installation is also supported when an operator wants the binary outside ORES Compose:

```sh
cargo install \
  --git https://github.com/gha-indie-worker/giw-desktop-daemon.git \
  --rev e9f51d021a8b0051556fd5dd0cab70c2ac179667 \
  --locked \
  giw-desktop-daemon

giw-desktop-daemon
```

## 7. Scintilla desktop substrate

GIW delegates machine/process/container lifecycle to Scintilla. Use the exact Scintilla revision recorded by `giw-desktop-infra/appliance.json`:

```sh
cd "$HOME/src"
if [ ! -d scintilla-desktop-infra/.git ]; then
  git clone https://github.com/scintilla-run/scintilla-desktop-infra.git
fi
cd scintilla-desktop-infra
git fetch origin
SCINTILLA_REV="$(jq -r '.substrate.rev' ../giw-desktop-infra/appliance.json)"
git checkout --detach "$SCINTILLA_REV"

ores-compose check .ores-compose.yaml
ores-compose plan .ores-compose.yaml
ores-compose up .ores-compose.yaml
```

That starts the machine-local Scintilla daemon at `127.0.0.1:8765`. For the complete standalone Scintilla appliance (BEAM ingress, workers, persistent OS service, optional substrate-managed tunnel), use its audited bootstrap/install scripts rather than exposing the control API.

## 8. Health checks

```sh
curl -fsS http://127.0.0.1:8765/healthz
curl -fsS http://127.0.0.1:8770/healthz
curl -fsS http://127.0.0.1:18090/readyz
curl -fsS http://127.0.0.1:18091/readyz
curl -fsS http://127.0.0.1:8080/api/readyz
```

A request to `https://local.indiebuild.dev/` is expected to encounter Cloudflare Access unless the caller has a valid browser session or reviewed service credential.

## Database race invariant

The Cloudflare edge may race equivalent Supabase and Neon **safe reads** (`GET`/`HEAD`/`OPTIONS`) after both PostgREST-compatible provider surfaces are converged. It must never duplicate mutations across providers. Writes remain single-authority and replication/synchronization is handled separately.
