# PR webhook edge gateway

`hooks.indiebuild.dev` is the public GitHub webhook front door for external PR CI. This Worker is intentionally thin: it bounds request size, preserves GitHub's raw request body and signature headers, and proxies only `POST /webhooks/github` to the Rust `indiebuild-pr-gateway` origin.

The Worker does **not** verify the GitHub HMAC itself, hold a GitHub status token, know the build-server auth secret, or execute repository code. Those responsibilities stay at the Rust origin and the gha-indie-worker build server. This keeps Cloudflare compromise from becoming a code-execution credential path.

## Deployment contract

Set `PR_GATEWAY_ORIGIN` outside git to the private/restricted origin serving the `pr-gateway` Docker target from `gha-indie-worker/gha-clone-server.rs`. Keep the origin inaccessible to ordinary internet clients where possible; Cloudflare is the public edge, while the Rust gateway remains the HMAC enforcement point.

Required GitHub webhook configuration:

- URL: `https://hooks.indiebuild.dev/webhooks/github`
- content type: `application/json`
- event: **Pull requests**
- secret: same sealed secret exposed to the Rust gateway as `INDIEBUILD_GITHUB_WEBHOOK_SECRET`

The edge health endpoint is `GET /healthz`. The webhook path rejects other methods and payloads larger than 1 MiB. Never parse and reserialize the GitHub JSON in this Worker: the origin verifies `X-Hub-Signature-256` over the exact bytes GitHub sent.

`wrangler.toml` contains no secret material. CI may run syntax/config validation and `wrangler deploy --dry-run`; production deployment remains an explicit operator action under the repository's no-apply-from-PR policy.
