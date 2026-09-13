#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

required=(
  cloudflare/pr-gateway/worker.js
  cloudflare/pr-gateway/wrangler.toml
  neon/main.tf
  neon/ci_control_plane.tf
  neon/versions.tf
  supabase/config.toml
  supabase/ci-control-plane/config.toml
  k8s/pr-gateway.yaml
  docs/indiebuild-pr-ci.md
)

for path in "${required[@]}"; do
  test -f "$path" || { echo "missing required IaC file: $path" >&2; exit 1; }
done

if command -v node >/dev/null 2>&1; then
  node --check cloudflare/pr-gateway/worker.js
fi

if command -v terraform >/dev/null 2>&1; then
  terraform -chdir=neon fmt -check -recursive
elif command -v tofu >/dev/null 2>&1; then
  tofu -chdir=neon fmt -check -recursive
fi

python3 - <<'PY'
from pathlib import Path
import json
import re
import tomllib

with open("cloudflare/pr-gateway/wrangler.toml", "rb") as fh:
    wrangler = tomllib.load(fh)
assert wrangler["workers_dev"] is False
assert any(route["pattern"] == "hooks.indiebuild.dev/*" for route in wrangler["routes"])

with open("supabase/ci-control-plane/config.toml", "rb") as fh:
    supabase = tomllib.load(fh)
assert supabase["ci"]["status_context"] == "indiebuild.dev/ci"
assert supabase["ci"]["create_project"] is False
assert supabase["secrets"]["allow_in_supabase"] is False

text = Path("k8s/pr-gateway.yaml").read_text()
for kind in ("ConfigMap", "Deployment", "Service", "PodDisruptionBudget", "NetworkPolicy"):
    assert f"kind: {kind}" in text, kind
match = re.search(r"repo-profiles\.json:\s*>-\s*\n\s*(\{[^\n]+\})", text)
assert match, "repo-profiles.json ConfigMap payload missing"
profiles = json.loads(match.group(1))
assert len(profiles) >= 10
assert set(profiles.values()) == {"rust-verify"}

neon = Path("neon/ci_control_plane.tf").read_text()
assert "length(local.projects) == 3" in neon
assert "do not create a shadow CI project" in neon

for candidate in Path("cloudflare/pr-gateway").rglob("*"):
    if candidate.is_file():
        lowered = candidate.name.lower()
        assert not any(term in lowered for term in ("secret", "token", ".env")), candidate

print("indiebuild PR CI IaC validation passed")
PY
