# Terraform root/child module contract

Use `modules/*` for reusable, parameterized child modules and `environments/<environment>/*` for independent root modules/state boundaries.

Child modules are environment-agnostic, own no backend/state, and should not contain environment-specific `*.tfvars`. Provider authentication/configuration belongs in the calling root module.

Each environment root may call local modules and may also define direct resources that genuinely exist only in that environment. If the same resource graph is needed by two or more environments, promote it into `modules/`. When moving existing managed resources into a module, use Terraform `moved` blocks where needed to preserve resource addresses/state.

Run Terraform from the environment root, for example `terraform -chdir=environments/staging plan` or `terraform -chdir=environments/production plan`.

`.ores-infra.toml` is the repository discovery contract: `modules_dir = "modules"` and `environments_dir = "environments"` define the Terraform convention, while provider sections identify native Supabase, Cloudflare, and Neon locations. Native provider repository integrations are separate from Terraform root-module selection.

Invariants: no backend blocks in `modules/*`; no committed Terraform state or `.terraform/`; environment-only resources may coexist with module calls in root modules; shared resource graphs belong in child modules.
