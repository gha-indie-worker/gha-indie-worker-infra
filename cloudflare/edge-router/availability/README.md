# Always-available server status

This dedicated Worker handles only `indiebuild.dev/*`,
`builds.indiebuild.dev/*` and `bretelle.multiapp.fyi/*`. It leaves the existing
edge-router Worker and admin-plane configuration unchanged. `config.json` is
the source of truth; `render.mjs` generates this Worker's `wrangler.json`.

Origins are dedicated tunnel hostnames outside these Worker routes, preventing
recursive proxying:

- IndieBuild: `origin-status.indiebuild.dev` -> loopback `:18091`.
- Bretelle: `origin-bretelle.multiapp.fyi` -> the local application gateway
  `:8081`, with its Host header explicitly set to `bretelle.multiapp.fyi`.

`/__server-status` is a Cloudflare-served status page. `/healthz` returns a
fresh health result with `live`, expected service identity, origin HTTP status
and a check timestamp. Only a successful JSON response with the expected
service identity counts as live. Missing/failed/mismatched origins report
unavailable; a generic HTTP 200 page is not accepted as health evidence.

Live HTML responses get Server status and healthz links. If the origin cannot
respond or returns a server error, Cloudflare serves its own outage page with
HTTP 503 and periodic rechecks. This remains available when the laptop process,
connector or laptop is unavailable. No GitHub, tunnel or management credential
is a Worker binding. The Worker cannot run commands on the laptop.

Launchd owns local startup/restart. Seven public-serving components are installed
in `/Library/LaunchDaemons`, with RunAtLoad/KeepAlive and the normal user as
UserName. The boot installer disables their corresponding login agents to avoid
duplicates. GitHub runners and evidence refresh remain login agents because the
GitHub CLI uses the login Keychain. FileVault unlock is still a precondition for
macOS to boot.

## Deploy

Run `node deploy.mjs` from this directory. It renders the configuration, runs
the availability tests and deploys with pinned Wrangler 4.160.0. Wrangler uses
the operator's OAuth credentials in the OS Keychain, with Worker script/route
permissions. Tunnel-login certificates alone lack Worker-route permissions.

The original `cloudflare/edge-router/wrangler.toml` is not edited or deployed
by this separate availability Worker.

## Executed acceptance

- Five unit tests cover expected-service health, failed health, unavailable
  origins unknown hosts and network-path upstream confinement.
- Actual IndieBuild process was paused: public `/healthz` returned HTTP 503 /
  `live:false`, and Cloudflare served its independent outage HTML.
- Bretelle remained independently healthy during the IndieBuild outage.
- The IndieBuild process was resumed and both health endpoints recovered.
- Actual Bretelle app process was terminated: its system supervisor started a
  new PID automatically.
- Both live HTML pages contain working server-status and healthz controls.

Worker deployment version: `f2a5f983-6315-4df7-a18a-0f8630a3f878`.
