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

After apply, obtain the **runtime tunnel token** for `indiebuild-laptop-ci` and put it in the local encrypted environment used to launch the worker. Do not commit the token. A remotely managed tunnel needs only that token on the laptop; the ingress rule and DNS hostname remain managed in Cloudflare/Terraform.

Run the connector with:

```sh
cloudflared tunnel --no-autoupdate run --token "$CLOUDFLARE_TUNNEL_TOKEN"
```

`gha-indie-worker` itself listens on `127.0.0.1:8100` in the laptop profile. GitHub webhook requests go to `/webhooks/github` and are authenticated by the worker's GitHub webhook HMAC secret. Operator/build endpoints retain the worker's normal application authentication.

## Why webhooks, not a GitHub Actions dispatcher

The primary path is:

```text
GitHub push / PR webhook
        -> ci-laptop.indiebuild.dev/webhooks/github
        -> Cloudflare Tunnel
        -> laptop gha-indie-worker
```

This consumes zero GitHub-hosted Actions minutes and continues to work when the Actions budget is exhausted. A tiny Actions dispatcher can still be kept as a compatibility path, but it must not be required for the worker to receive jobs.

## Availability

A laptop is an opportunistic worker. When it is offline, the tunnel is unavailable and GitHub webhook delivery can be redelivered later. Do not point production traffic at this hostname. Long-term workers can run the same service on dedicated machines and use additional `cloudflared` replicas or separate tunnel hostnames.
