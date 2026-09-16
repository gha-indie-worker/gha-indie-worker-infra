#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "terraform-layout: $*" >&2
  exit 1
}

production="environments/production"
roots=(gcp-platform gcp-cloudrun cloudflare-platform cloudflare-dns neon)
modules=(gcp/platform gcp/cloudrun cloudflare/platform cloudflare/dns neon/projects)
module_names=(gcp_platform gcp_cloudrun cloudflare_platform cloudflare_dns neon_projects)

# 1. Preserve the five historical production state boundaries exactly.
mapfile -t actual_roots < <(find "$production" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
mapfile -t expected_roots < <(printf '%s\n' "${roots[@]}" | sort)
[[ "${actual_roots[*]}" == "${expected_roots[*]}" ]] || fail "production roots differ from the five preserved state boundaries"

for i in "${!roots[@]}"; do
  root="${roots[$i]}"
  module_path="${modules[$i]}"
  module_name="${module_names[$i]}"
  dir="$production/$root"

  # 2. Every root maps to exactly one reviewed provider module.
  grep -Fq "source = \"../../../modules/$module_path\"" "$dir/main.tf" || fail "$root does not map to modules/$module_path"

  # 3. Every migrated state root carries main/provider/move declarations.
  for file in main.tf versions.tf moved.tf; do
    [[ -f "$dir/$file" ]] || fail "$root is missing $file"
  done

  # 4. Environment composition stays one-module-thin.
  [[ "$(grep -Ec '^[[:space:]]*module[[:space:]]+"' "$dir/main.tf")" -eq 1 ]] || fail "$root must contain exactly one module block"

  # 5. Provider resources/data live only in modules.
  if grep -R -n -E '^[[:space:]]*(resource|data)[[:space:]]+"' "$dir" --include='*.tf'; then
    fail "$root owns provider resources/data instead of composing its child module"
  fi

  # 6. Provider configuration belongs in the deployable environment root.
  grep -Eq '^[[:space:]]*provider[[:space:]]+"' "$dir/versions.tf" || fail "$root has no provider configuration"

  # 7. State moves point exclusively into this root's child module.
  grep -Eq '^[[:space:]]*from[[:space:]]*=' "$dir/moved.tf" || fail "$root moved.tf has no source addresses"
  grep -Eq '^[[:space:]]*to[[:space:]]*=' "$dir/moved.tf" || fail "$root moved.tf has no destination addresses"
  if grep -E '^[[:space:]]*to[[:space:]]*=' "$dir/moved.tf" | grep -Ev "module\\.${module_name}\\."; then
    fail "$root moved.tf targets a different module namespace"
  fi
done

# 8. Child modules never own Terraform backends.
if grep -R -n -E '^[[:space:]]*backend[[:space:]]+"' modules --include='*.tf'; then
  fail "backend blocks are forbidden in child modules"
fi

# 9. Child modules declare provider requirements, never provider configuration.
if grep -R -n -E '^[[:space:]]*provider[[:space:]]+"' modules --include='*.tf'; then
  fail "provider configuration is forbidden in child modules"
fi

# 10. State, .terraform data and environment values never enter reusable modules.
if find modules -type f \( -name '*.tfvars' -o -name '*.tfstate' -o -name '*.tfstate.*' \) -print -quit | grep -q .; then
  fail "state/tfvars found under modules"
fi
if git ls-files | grep -E '(^|/)\.terraform/|\.tfstate($|\.)' >/dev/null; then
  fail "Terraform working data/state is committed"
fi

# 11. State roots remain independent: no terraform_remote_state coupling.
if grep -R -n 'terraform_remote_state' modules environments --include='*.tf'; then
  fail "cross-state terraform_remote_state coupling is forbidden"
fi

# 12. Production module sources are the exact local provider modules.
for i in "${!roots[@]}"; do
  root="${roots[$i]}"
  module_path="${modules[$i]}"
  sources="$(grep -E '^[[:space:]]*source[[:space:]]*=' "$production/$root/main.tf" || true)"
  [[ "$sources" == *"../../../modules/$module_path"* ]] || fail "$root has an unexpected module source"
done

# 13. No Terraform source crosses into another environment, app checkout or build output.
if grep -R -n -E 'source[[:space:]]*=.*(environments/|_apps/|dist/)' modules environments --include='*.tf'; then
  fail "Terraform source crosses an ownership boundary"
fi

# 14. Legacy Terraform roots are empty while provider-native authorities remain.
if [[ -d terraform ]] && find terraform -type f -name '*.tf' -print -quit | grep -q .; then
  fail "legacy terraform/ root still owns .tf files"
fi
for legacy in gcp/cloudrun cloudflare/dns cloudflare/laptop-tunnel; do
  if [[ -d "$legacy" ]] && find "$legacy" -type f -name '*.tf' -print -quit | grep -q .; then
    fail "legacy Terraform root still owns .tf files: $legacy"
  fi
done
if find neon -maxdepth 1 -type f -name '*.tf' -print -quit | grep -q .; then
  fail "native neon/ root still owns Terraform files"
fi
[[ -f supabase/config.toml ]] || fail "missing native Supabase authority"
[[ -f neon/config.json ]] || fail "missing native Neon authority"
[[ -f cloudflare/edge-router/wrangler.toml ]] || fail "missing native Cloudflare Worker authority"

# 15. The ORES manifest resolves to canonical directories and real native authorities.
grep -Eq '^modules_dir[[:space:]]*=[[:space:]]*"modules"[[:space:]]*$' .ores-infra.toml || fail "manifest modules_dir mismatch"
grep -Eq '^environments_dir[[:space:]]*=[[:space:]]*"environments"[[:space:]]*$' .ores-infra.toml || fail "manifest environments_dir mismatch"
grep -Fq 'native_config = "supabase/config.toml"' .ores-infra.toml || fail "manifest Supabase authority mismatch"
grep -Fq 'native_config = "neon/config.json"' .ores-infra.toml || fail "manifest Neon authority mismatch"
for dir in modules/gcp modules/cloudflare modules/neon modules/supabase environments/preview environments/staging environments/production; do
  [[ -d "$dir" ]] || fail "manifest/layout directory missing: $dir"
done

echo "terraform-layout: 15 invariants passed"
