# terraform/gcp

Project `gha-indie-worker`, region `us-central1`: APIs, Artifact Registry, the
VPC and its two planes, the four Cloud Run services, Secret Manager containers,
service accounts, and Workload Identity Federation for GitHub Actions.

This root goes **first**. Cloudflare and the edge router both need values that
only exist after it has been applied.

## Bootstrap, once

State lives in a GCS bucket that Terraform cannot create for itself — the bucket
has to exist before `terraform init` can use it. Do this once, by hand:

```console
gcloud auth login
gcloud config set project gha-indie-worker

gcloud storage buckets create gs://gha-indie-worker-tfstate \
  --project=gha-indie-worker --location=us-central1 \
  --uniform-bucket-level-access --public-access-prevention
gcloud storage buckets update gs://gha-indie-worker-tfstate --versioning
```

Then uncomment the `backend "gcs"` block in `versions.tf` and run
`terraform init -migrate-state`. Until that is done, state is a local file and
must not be committed — `.gitignore` already refuses `*.tfstate*`.

Terraform state contains resource attributes that are credential-adjacent. It
does **not** contain the secret payloads: this root creates Secret Manager
containers, never versions.

## First apply

```console
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars

terraform init
terraform plan -out=tfplan          # or ../../scripts/apply-terraform.sh gcp
terraform show tfplan | less
terraform apply tfplan
```

The first plan is large: enabling twelve APIs, a VPC with four subnets, two
serverless connectors, five service accounts, seventeen secrets and four Cloud
Run services. Read it. In particular check that `admin-web` and `admin-api` show
`ingress = "INGRESS_TRAFFIC_INTERNAL_ONLY"` and that the only `allUsers`
bindings are the two on `web` and `api`.

**The first apply will fail at the Cloud Run services, and that is correct.** A
revision cannot start until every secret it references has a version, and this
root deliberately creates none. Populate them, then re-apply:

```console
terraform output -json secret_ids | jq -r '.[]'

printf %s "$VALUE" | gcloud secrets versions add gha-indie-worker-web-session-secret \
  --project=gha-indie-worker --data-file=-
# ... and so on for each id
```

A value added this way is never read back into state, and `apply` will not
revert it. See the header comment in `secrets.tf` for why a placeholder version
would be worse than no version at all.

## After the apply: what to copy where

```console
terraform output GCP_WORKLOAD_IDENTITY_PROVIDER   # -> repo secret in all four service repos
terraform output GCP_SERVICE_ACCOUNT              # -> repo secret in all four service repos
terraform output -json GCP_RUN_SERVICE_ACCOUNT    # -> GCP_RUN_SERVICE_ACCOUNT / GCP_RUNTIME_SERVICE_ACCOUNT
terraform output -json cloud_run_hosts            # -> terraform/cloudflare tfvars + router.config.json
terraform output -json ingress_posture            # read this every time
```

`ingress_posture` exists to be read, not just to exist. `admin-web` and
`admin-api` must always be `INGRESS_TRAFFIC_INTERNAL_ONLY`, and
`public_invoker_bindings` must contain exactly the two product services.

## Design notes worth knowing before you change something

**Four subnets, not two.** `giw-product-subnet` (10.20.0.0/20) and
`giw-admin-subnet` (10.30.0.0/20) carry workloads. A Serverless VPC Access
connector attached with `subnet` requires a **/28 that carries nothing else**, so
each plane also has a dedicated connector /28 carved out of its own range
(`10.20.240.0/28`, `10.30.240.0/28`). The connectors are still inside their
plane's address space, which is what the firewall rules key off.

**Firewall rules are defence in depth, not the admin front door.** They govern
traffic that traverses the VPC — what a Cloud Run service sends through its
connector, and VM/GKE traffic in these subnets. A request from the internet to a
`*.run.app` URL never enters the VPC; it stops at Google's front end. That is why
the admin services carry internal-only ingress and no `allUsers` binding, and
why `firewall.tf` opens with a paragraph saying exactly this. Read it before
concluding that a firewall rule protects the admin plane.

**Egress differs by plane on purpose.** The product services use
`PRIVATE_RANGES_ONLY`: only RFC1918 destinations go through the connector, so
calls to Neon and Supabase over the public internet do not funnel through a
connector sized for internal traffic. The admin services use `ALL_TRAFFIC`,
because the admin database's IP allow-list can only name the admin network if
every outbound packet leaves through it.

**The admin bind address is load-bearing.** Both admin binaries default to
`127.0.0.1:8787` / `:8788`, refuse a non-loopback bind unless
`GHA_INDIE_WORKER_ADMIN_ALLOW_PUBLIC_BIND=1`, and **do not read Cloud Run's
`$PORT`**. Without `GHA_INDIE_WORKER_ADMIN_BIND=0.0.0.0:8080` the container
listens on loopback while Cloud Run waits on 8080, and the revision never
becomes ready. Both variables are set in `run_admin.tf`, next to the ingress
setting that makes them safe — never in the image, which stays loopback-only.

**The web service's probes carry a `Host` header.** `web-server.rs` routes by
`Host` and answers 404 on *every* path — `/healthz` included — for a host it does
not recognise. A probe without `Host: app.indiebuild.dev` marks every revision
unhealthy.

**Terraform does not own the images.** Each service's `lifecycle` block ignores
`template[0].containers[0].image`. The repositories' `deploy-cloud-run.yml`
workflows own it and pin a digest; if this root managed it too, every apply would
roll production back to whatever tag Terraform last saw.

**Runtime service accounts have no project-level role.** Every permission a
service has is a binding on the one secret it needs. A compromised service reads
the four strings it was given and nothing else.

**No Cloud SQL.** `sqladmin.googleapis.com` is deliberately absent from
`apis.tf`. This fleet's Postgres is Neon and Supabase; enabling Cloud SQL would
put a second, unmanaged database plane one API call away.

## Known inconsistency to resolve

`artifact_registry.tf` creates the repository in **us-central1**, so images live
at `us-central1-docker.pkg.dev/gha-indie-worker/gha-indie-worker/<image>`. That
matches what `gha-indie-worker-api-server.rs` and `-web-server.rs` push to and
deploy from.

The two admin repositories' `deploy-cloud-run.yml` currently reference
**`us-docker.pkg.dev`** — the `us` multi-region, which is a *different*
repository that this root does not create. Either change those two workflows to
`us-central1-docker.pkg.dev`, or add a second `google_artifact_registry_repository`
here on purpose. Leaving it as-is means the admin deploys fail on first push,
loudly, which is at least not silent.

## Verified how far

`terraform validate` needs provider plugins and therefore network; it has not
been run. `scripts/hcl-sanity.py` passes (delimiters, tabs, duplicate addresses,
undeclared/unused variables, orphan locals, tfvars keys). Alignment is
unambiguous under `terraform fmt`.

The `google` provider's schema is not verified offline. The most likely places
to need a small fix are the `cleanup_policies` block shape on
`google_artifact_registry_repository`, `startup_cpu_boost` / `cpu_idle` inside
`resources`, and the exact `ignore_changes` address for a nested Cloud Run v2
container image.
