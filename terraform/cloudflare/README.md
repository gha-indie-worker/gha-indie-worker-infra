# terraform/cloudflare

Everything Cloudflare owns for **indiebuild.dev** except Worker routes: DNS
records, Zero Trust Access applications and policies, the WAF / rate-limit /
cache rulesets, and the zone's TLS posture.

## The split, and why it matters

| object | owned by | applied with |
|---|---|---|
| DNS records | this root | `terraform apply` |
| Access applications and policies | this root | `terraform apply` |
| Rulesets (rate limit, firewall, cache) | this root | `terraform apply` |
| Zone settings (SSL, TLS floor, HSTS) | this root | `terraform apply` |
| **Worker routes** | `cloudflare/edge-router/wrangler.toml` | `wrangler deploy` |
| **Worker script and its config** | `cloudflare/edge-router/router.config.json` | `wrangler deploy` |

This is the same split `ores-edge-router` documents: *"DNS records for the
subdomains are proxied CNAMEs/A records managed in Terraform; Worker routes are
owned by this `wrangler.toml`."*

It is not a style preference. A route and a record for the same hostname are two
independent API objects. If Terraform also declared routes, every `wrangler
deploy` would show up as drift in the next plan, and every `terraform apply`
would delete routes wrangler had just created — each tool silently reverting the
other, with production flapping in between. One object, one owner.

## Apply order

Cloudflare comes **second**, after `terraform/gcp`, because the Cloud Run
hostnames the edge router falls back to do not exist until GCP has been applied.

```console
# 0. from terraform/gcp, once it has been applied:
terraform -chdir=../gcp output -json cloud_run_hosts

# 1. inputs
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars           # k8s_origin_ip, admin_access_emails, the Cloud Run hosts

# 2. credentials — environment only, never a file
export CLOUDFLARE_API_TOKEN=...    # scopes below

# 3. plan, read it, then apply
terraform init
terraform plan -out=tfplan
terraform show tfplan | less
terraform apply tfplan
```

Then, and only then, deploy the Worker (`cloudflare/edge-router/`) so the routes
attach to records that already exist.

## The API token

Create a **custom token** scoped to this one zone plus the account-level Zero
Trust permissions. Anything broader is a token that can edit zones this
repository knows nothing about.

| permission | level | why |
|---|---|---|
| Zone → Zone → Read | this zone | look the zone up, read settings |
| Zone → DNS → Edit | this zone | the records in `dns.tf` |
| Zone → Zone Settings → Edit | this zone | SSL, min TLS, HSTS in `settings.tf` |
| Zone → Zone WAF → Edit | this zone | the rulesets in `rulesets.tf` |
| Account → Access: Apps and Policies → Edit | this account | `access.tf` |
| Account → Account Settings → Read | this account | resolve the account |

Zone Resources: *Include → Specific zone → indiebuild.dev*.
Account Resources: *Include → the account in `cloudflare_account_id`*.

`CLOUDFLARE_API_TOKEN` is read from the environment by the provider. There is no
variable for it, deliberately: a token in a `.tfvars` file ends up in a shell
history, a backup, or a commit.

## What this root creates

**DNS.** Proxied CNAMEs for `app`, `user`, `org`, `m`, `api`, `admin`,
`admin-api`, all pointing at `origin-hetzner.indiebuild.dev`; unproxied A
records for `origin-hetzner` and `origin-aws` (the addresses the Worker itself
connects to — proxying them would send Cloudflare through Cloudflare). `auth` is
**not** created by default: shared-auth is a separate system with its own
infrastructure repository, and `manage_auth_record` exists for the day this zone
becomes the single owner of that record.

**Email posture.** `manage_email_posture` publishes a null MX (RFC 7505), an SPF
record authorising nobody (`v=spf1 -all`) and a `p=reject` DMARC record. The
domain sends no mail today; a domain with no SPF or DMARC is free to spoof. When
the product starts sending mail, these three records are the first thing to
change — before the first message goes out, not after.

**Access.** Applications for `admin.indiebuild.dev`, `admin-api.indiebuild.dev`
and `api.indiebuild.dev/__ores/router/status`, each with the same two policies:
an allow for the operator email list (plus an optional IdP-backed group),
requiring an MFA authentication method, with a 24-hour session; and a terminal
deny for everyone else. The deny is redundant — Access denies by default — but it
survives someone adding a looser allow policy later, and it makes the intent
visible in the Zero Trust UI.

Access is one of **three** independent gates on the admin plane. The other two
are in `terraform/gcp` (internal-only ingress, no `allUsers` binding) and in the
Worker (`access: "cloudflare-access"` refuses a request with no assertion). No
single one of them may be treated as sufficient.

**Rate limiting.** A per-IP budget on `api.indiebuild.dev`
(`api_rate_limit_requests` per `api_rate_limit_period`), answering 429 with a
JSON body. WebSocket upgrades on `/v1/ws` are excluded from counting: they are
one long-lived request, and counting them alongside REST calls would throttle a
client for staying connected. The application's own limiter — opaque HMAC
principals, identity ahead of network location — remains the accurate one; this
exists so a flood never reaches it.

**Bot challenge.** A managed challenge for `cf.client.bot` on `app`, `org`,
`user` and `m`.

> ⚠️ `cf.client.bot` is Cloudflare's **known-bot** signal, which includes
> catalogued crawlers such as Googlebot. Challenging them is usually not what
> you want on marketing pages. `bot_challenge_exempt_expression` keeps
> `/robots.txt`, `/sitemap.xml` and `/.well-known/` answerable by default; widen
> it to cover the marketing paths you need indexed, rather than turning the rule
> off wholesale. Verify with Search Console after the first apply — this is the
> one rule here whose effect is invisible until traffic arrives.

**Cache.** `/assets/releases/*` is content-addressed by release id, so it is
cached for a year at the edge and in the browser. Everything else on the zone is
bypassed: a per-session HTML render, an authenticated JSON response or an admin
surface cached at the edge is how one tenant is served another tenant's page.

**TLS.** `ssl = strict` (Cloudflare verifies the origin certificate; `full`
would accept a self-signed origin, which means anything between Cloudflare and
the origin can impersonate it), a TLS 1.2 floor, TLS 1.3 on, always-use-HTTPS,
and HSTS.

> ⚠️ HSTS is close to irreversible. A browser that has seen `max-age=31536000`
> refuses plaintext for a year no matter what the zone says afterwards, and
> `include_subdomains` commits every future subdomain to HTTPS.
> `terraform.tfvars.example` therefore starts at **86400**. Raise it only once
> every host under the zone is verified HTTPS-only. `hsts_preload` stays false
> until someone deliberately submits the domain to the browser preload list.

## Verified how far

`terraform validate` needs provider plugins and therefore network; it has not
been run against this code. What has been checked offline:

* `scripts/hcl-sanity.py` — balanced delimiters, no tabs, unique resource
  addresses, every `var.` declared and used, no orphan `local.`, and a
  `.tfvars.example` that sets only real variables.
* Alignment is unambiguous under `terraform fmt` (no comment or multi-line
  attribute sits inside an alignment group).

The provider schema itself is **not** verified. Cloudflare's v5 provider is
generated from the API and renamed or reshaped much of v4, so the first
`terraform validate` on a machine with network is the real gate. The most likely
places to need a small fix, in order: the `filter` shape on the
`cloudflare_zone` data source, the `include`/`require` object forms on
`cloudflare_zero_trust_access_policy`, the optional cookie attributes on
`cloudflare_zero_trust_access_application`, and the `value` shape of the
`security_header` zone setting.
