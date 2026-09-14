# Laptop CI Cloudflare Tunnel

This Terraform root creates a remotely managed Cloudflare Tunnel for the local `gha-indie-worker` service running on a developer laptop.

Public route:

```text
https://ci-laptop.indiebuild.dev
        |
        v
Cloudflare Tunnel
        |
        v
http://127.0.0.1:8100
```

The tunnel is intentionally outbound-only from the laptop; no router/firewall port-forward is required.

## Apply

Run this root with the normal Cloudflare provider environment used by the rest of this repository:

```sh
terraform -chdir=cloudflare/laptop-tunnel init
terraform -chdir=cloudflare/laptop-tunnel plan \
  -var='cloudflare_account_id=<account-id>'
terraform -chdir=cloudflare/laptop-tunnel apply \
  -var='cloudflare_account_id=<account-id>'
```

The repository policy still applies: CI plans only; an operator performs the apply.

After apply, obtain the **runtime tunnel token** for `indiebuild-laptop-ci` and put it in the local encrypted environment used to launch the worker session. Do not commit the token. A remotely managed tunnel needs only that token on the laptop; the ingress rule and DNS hostname remain managed in Cloudflare/Terraform.

Run the connector with:

```sh
cloudflared tunnel --no-autoupdate run --token "$CLOUDFLARE_TUNNEL_TOKEN"
```

`gha-indie-worker` itself listens on `127.0.0.1:8100` in the laptop profile. GitHub webhook requests go to `/webhooks/github` and are authenticated by the worker's GitHub webhook HMAC secret. Operator/build endpoints retain the worker's normal application authentication.

## Secret boundary

`CLOUDFLARE_TUNNEL_TOKEN` is a connector credential, not a worker credential. The canonical `.ores-compose.yaml` maps it only to the `cloudflare-tunnel` service as `TUNNEL_TOKEN`; it is deliberately not injected into `gha-indie-worker`, API servers, tested profile containers, or nested PR sessions.

This matters even though all of the services are supervised by one `ores-compose` session: session membership must not imply secret sharing. Each child receives only the environment explicitly declared for that service.

## Why webhooks, not a GitHub Actions dispatcher

The bootstrap zero-minute path is:

```text
GitHub push / PR webhook
        -> ci-laptop.indiebuild.dev/webhooks/github
        -> Cloudflare Tunnel
        -> laptop gha-indie-worker
```

This consumes zero GitHub-hosted Actions minutes and continues to work when the Actions budget is exhausted. A tiny Actions dispatcher can still be kept as a compatibility path, but it must not be required for the worker to receive jobs.

## Tunnel is ingress, not the scheduling authority

The long-term continuity lane must not require an intermittently-online laptop to be directly reachable at dispatch time. The durable queue tracked by `gha-indie-worker/gha-indie-worker.rs#57` is the scheduling authority:

```text
GitHub webhook / API admission
        -> durable exact-SHA job record
        -> worker pull + lease + fencing
        -> ores-compose session
        -> exact-SHA result/check publication
```

Cloudflare Tunnel remains useful for signed webhook ingress, operator/API access, health/status, log streaming, and direct compatibility dispatch. A worker may also run with no public tunnel at all and only make outbound requests to claim queued work. That split lets a laptop sleep or change networks without losing admitted CI work.

A zero-step GitHub Actions runner-admission failure (for example exhausted hosted-runner budget) should therefore promote or prioritize the already admitted independent job; it must not be the only trigger, because no workflow step can execute when runner admission itself fails.

## Availability

A laptop is an opportunistic worker. When it is offline, the direct tunnel path is unavailable. GitHub webhook delivery can be redelivered, but durable queue admission is preferred because it lets eligible workers drain work after reconnecting without depending on webhook redelivery timing.

Do not point production application traffic at this hostname. Long-term workers can run the same execution service on dedicated machines and either pull from the same durable queue or use additional `cloudflared` replicas / separate tunnel hostnames for ingress and operations.
