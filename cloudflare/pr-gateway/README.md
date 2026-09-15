# PR webhook edge gateway

`hooks.indiebuild.dev` is the public GitHub webhook edge for external PR CI. The Worker is deliberately thin: it bounds request size, preserves the exact GitHub request body and signature headers, and proxies only `POST /webhooks/github` to the Rust PR gateway origin.

It does **not** verify HMACs, hold GitHub/build-server credentials, or execute repository code. HMAC verification, allowlist selection, build dispatch and status writes remain Rust-origin responsibilities.

`PR_GATEWAY_ORIGIN` is runtime configuration and is never committed. Production activation remains human-gated.
