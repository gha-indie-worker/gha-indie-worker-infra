# Laptop CI tunnel module

This child module is the state-safe successor to the standalone `cloudflare/laptop-tunnel` root proposed in infra PR #13. It creates a remotely managed Cloudflare Tunnel plus the single proxied DNS record for the laptop CI webhook listener.

It deliberately does **not** read, create, or output the runtime tunnel token/credential. The connector credential remains runtime-only secret material. The origin host is hard-coded to loopback and only the port is configurable, so Terraform cannot be repurposed into an arbitrary proxy target.

`ci-laptop.indiebuild.dev` is a signed webhook surface whose independent application gate is the GitHub webhook HMAC check. It is distinct from the Access-protected `local.indiebuild.dev` developer UI/API ingress managed by the platform module.
