# Laptop CI tunnel module

This child module is the state-safe successor to the standalone `cloudflare/laptop-tunnel` root proposed in infra PR #13. It creates a remotely managed Cloudflare Tunnel plus the single proxied DNS record for the laptop CI webhook listener.

It deliberately does **not** read, create, or output the runtime tunnel token/credential. The connector credential remains runtime-only secret material. The origin host is hard-coded to loopback and only the port is configurable, so Terraform cannot be repurposed into an arbitrary proxy target.

`ci-laptop.indiebuild.dev` is a signed webhook surface whose independent application gate is the GitHub webhook HMAC check. It is distinct from the Access-protected `local.indiebuild.dev` developer UI/API ingress managed by the platform module.

## Fail-closed webhook path ingress

The dedicated remotely-managed `cloudflared` config now routes only paths
matching the anchored expression `^/webhooks/github$` to the loopback listener.
Every other path and hostname falls through to `http_status:404`.
This is a **second independent fail-closed route boundary** in addition to the
Cloudflare zone WAF and the worker's GitHub HMAC verifier. A valid path alone
does **not** authorize a request: Cloudflare WAF must allow only `POST` to
this exact hostname/path; the origin must reject invalid/missing
`X-Hub-Signature-256` signatures, non-POST methods, duplicate deliveries and
oversized bodies.

Cloudflare Tunnel ingress rules do not enforce HTTP methods. Do not turn off
the separate WAF to make webhooks work, do not add wildcard ingress or a
non-404 catch-all, and never point the tunnel at the GIW/Scintilla desktop
control APIs on ports 8770/8765. These rules do not register a native GitHub
Actions runner and do not constitute successful laptop job execution.

### Required provider-level acceptance (not proven by Terraform validate)

Before applying to production, read back the actual tunnel ID/config,
proxied DNS hostname, live connector version and WAF deployment from the
Cloudflare account. Test an authentic GitHub-signed POST, unsigned/bad-HMAC
POST, GET/PUT to the valid path, and POSTs to `/healthz`, `/builds`,
`/v1/jobs/dispatch`, a nested path, a double slash, and an encoded path.
Confirm the invalid cases cannot reach the origin and the valid case is
deduplicated. Include proof that the catch-all 404 works and that
`cloudflared` and origin processes do not share control-plane secrets.
Only then consider the route deployment-ready.
