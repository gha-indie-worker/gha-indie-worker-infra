#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "terraform-state-safety: $*" >&2
  exit 1
}

production="environments/production"
roots=(gcp-platform gcp-cloudrun cloudflare-platform cloudflare-dns neon)
modules=(gcp/platform gcp/cloudrun cloudflare/platform cloudflare/dns neon/projects)
module_names=(gcp_platform gcp_cloudrun cloudflare_platform cloudflare_dns neon_projects)
providers=(google google cloudflare cloudflare neon)

all_move_sources=()
all_move_destinations=()

for i in "${!roots[@]}"; do
  root="${roots[$i]}"
  module_path="${modules[$i]}"
  module_name="${module_names[$i]}"
  provider="${providers[$i]}"
  dir="$production/$root"
  module_dir="modules/$module_path"

  [[ -d "$dir" ]] || fail "missing production root: $dir"
  [[ -d "$module_dir" ]] || fail "missing provider module: $module_dir"

  # 16. Module block labels are part of state-address identity and must be exact.
  grep -Eq "^[[:space:]]*module[[:space:]]+\"${module_name}\"[[:space:]]*\{" "$dir/main.tf" \
    || fail "$root module label must be ${module_name}"

  # 17. A production root may reference exactly one module source expression.
  [[ "$(grep -Ec '^[[:space:]]*source[[:space:]]*=' "$dir/main.tf")" -eq 1 ]] \
    || fail "$root must contain exactly one module source"

  # 18. The root provider and child required-provider identity must agree.
  grep -Eq "^[[:space:]]*provider[[:space:]]+\"${provider}\"" "$dir/versions.tf" \
    || fail "$root must configure provider ${provider}"
  grep -Eq "^[[:space:]]*${provider}[[:space:]]*=[[:space:]]*\{" "$module_dir/versions.tf" \
    || fail "$module_path must declare required provider ${provider}"

  # 19. Every real provider module must own at least one resource or data object.
  if ! grep -R -q -E '^[[:space:]]*(resource|data)[[:space:]]+"' "$module_dir" --include='*.tf'; then
    fail "$module_path contains no provider resource/data declarations"
  fi

  # 20. Production roots may not introduce remote/registry module sources.
  if grep -E '^[[:space:]]*source[[:space:]]*=' "$dir/main.tf" \
      | grep -E '(git::|https?://|github\.com|registry\.terraform\.io|app\.terraform\.io)'; then
    fail "$root uses a remote module source"
  fi

  mapfile -t move_sources < <(sed -n -E 's/^[[:space:]]*from[[:space:]]*=[[:space:]]*(.+)[[:space:]]*$/\1/p' "$dir/moved.tf")
  mapfile -t move_destinations < <(sed -n -E 's/^[[:space:]]*to[[:space:]]*=[[:space:]]*(.+)[[:space:]]*$/\1/p' "$dir/moved.tf")

  # 21. State-move blocks must be structurally paired.
  [[ "${#move_sources[@]}" -gt 0 ]] || fail "$root has no move sources"
  [[ "${#move_sources[@]}" -eq "${#move_destinations[@]}" ]] \
    || fail "$root move source/destination counts differ"

  # 22. A legacy address may be moved only once in a root.
  if printf '%s\n' "${move_sources[@]}" | sort | uniq -d | grep -q .; then
    fail "$root contains duplicate move source addresses"
  fi

  # 23. A destination address may be targeted only once in a root.
  if printf '%s\n' "${move_destinations[@]}" | sort | uniq -d | grep -q .; then
    fail "$root contains duplicate move destination addresses"
  fi

  # 24. Each migration is a pure namespace move: module.<name>.<old-address>.
  for j in "${!move_sources[@]}"; do
    expected="module.${module_name}.${move_sources[$j]}"
    [[ "${move_destinations[$j]}" == "$expected" ]] \
      || fail "$root move ${move_sources[$j]} must target $expected (got ${move_destinations[$j]})"
  done

  # 25. Every move destination must correspond to a resource/data declared by the child module.
  mapfile -t declared_addresses < <(
    grep -R -h -E '^[[:space:]]*(resource|data)[[:space:]]+"[^\"]+"[[:space:]]+"[^\"]+"' "$module_dir" --include='*.tf' \
      | sed -E \
          -e 's/^[[:space:]]*resource[[:space:]]+"([^\"]+)"[[:space:]]+"([^\"]+)".*/\1.\2/' \
          -e 's/^[[:space:]]*data[[:space:]]+"([^\"]+)"[[:space:]]+"([^\"]+)".*/data.\1.\2/' \
      | sort -u
  )
  for source in "${move_sources[@]}"; do
    base_address="${source%%[*}"
    if ! printf '%s\n' "${declared_addresses[@]}" | grep -Fxq "$base_address"; then
      fail "$root move source $source has no matching declaration in $module_path"
    fi
  done

  all_move_sources+=("${move_sources[@]}")
  all_move_destinations+=("${move_destinations[@]}")
done

# 26. No destination address can be claimed by two preserved state roots.
if printf '%s\n' "${all_move_destinations[@]}" | sort | uniq -d | grep -q .; then
  fail "a migration destination is claimed by more than one production state root"
fi

# 27. Reusable modules may not depend on remote/registry modules implicitly.
if grep -R -n -E '^[[:space:]]*source[[:space:]]*=.*(git::|https?://|github\.com|registry\.terraform\.io|app\.terraform\.io)' modules --include='*.tf'; then
  fail "remote module source found below modules/"
fi

# 28. Provider credentials must come from runtime identity/environment, never literal HCL values.
if grep -R -n -E '^[[:space:]]*(api_key|api_token|access_token|client_secret|private_key|password|credentials)[[:space:]]*=[[:space:]]*"[^\"]+"' modules environments --include='*.tf' --include='*.tfvars' --include='*.tfvars.example'; then
  fail "literal provider credential found in Terraform source/example values"
fi

# 29. Preview/staging are admitted namespaces, not accidental long-lived state roots yet.
for env in preview staging; do
  if find "environments/$env" -type f \( -name '*.tf' -o -name '*.tfvars' -o -name '*.tfstate' -o -name '*.tfstate.*' \) -print -quit | grep -q .; then
    fail "$env unexpectedly owns Terraform state/configuration; admit it through a reviewed root first"
  fi
done

# 30. Supabase remains provider-native until a reviewed Terraform authority is deliberately introduced.
if grep -R -q -E '^[[:space:]]*(resource|data)[[:space:]]+"' modules/supabase --include='*.tf'; then
  fail "modules/supabase unexpectedly owns provider resources"
fi
if find supabase -type f -name '*.tf' -print -quit | grep -q .; then
  fail "native supabase/ authority must not also own Terraform resources"
fi
[[ -f supabase/config.toml ]] || fail "missing canonical Supabase native config"

echo "terraform-state-safety: 15 second-wave invariants passed"
