# Neon for `gha-indie-worker`

Neon is 1:1 with the GitHub org: Neon org `org-misty-grass-10005930` holds **three** projects, one
per role, exactly as the 2026-09-05 fleet provisioning pass created them for all 39 orgs.

| project | id | role | who may connect |
|---|---|---|---|
| canonical | `crimson-cell-39815049` | product data | web-server, api-server (product NAT address) |
| auth | `fancy-brook-94928157` | shared-auth customer realm | web-server, api-server |
| **admin** | `round-butterfly-64996380` | admin plane | admin-web-server, admin-api-server **only** (admin NAT address) |

## The admin project is provisioned but intentionally unreachable

It was created with **public connections blocked and VPC connections blocked**. That is not a
misconfiguration to "fix" — it is an empty provisioning target that stays closed until its private
endpoint exists. Turning it on is a four-step acceptance, and all four must be evidenced:

1. Create the private endpoint / VPC endpoint and its private DNS.
2. Connect from the **admin** network → must succeed.
3. Connect from the **product** network → must be refused.
4. Connect from the public internet → must be refused.

Neon private networking requires the **Scale** plan (or a provider-enabled trial); every Neon org in
the fleet currently reports **Free**, so step 1 is blocked on a plan decision, not on code. Until
then the admin plane uses the AWS RDS admin database and the Neon admin project stays closed.

## Migrations do not come from here

Neon never ingests schema from git. `dpm` is the only migration tool and the schema authority is
`gha-indie-worker-orm-core`; this directory declares *infrastructure* (project, branches, roles,
databases, endpoints) only. The preview workflow creates a `preview/pr-<n>` branch per PR and runs
`dpm plan` — **plan only**; apply is human-gated, and no service runs DDL at boot.
