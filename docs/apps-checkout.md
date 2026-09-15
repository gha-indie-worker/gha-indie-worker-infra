# Application checkout inside infra

`_apps/gha-monorepo` is a tracked Git submodule pointing at `gha-indie-worker/gha-indie-worker-monorepo`. It gives infrastructure tooling a reproducible, exact-revision view of the application monorepo without copying application source into this repository.

## Clone / initialize

A fresh clone may use `git clone --recurse-submodules ...`. For an existing checkout run:

```sh
scripts/sync-apps.sh
```

That command initializes the submodule at the exact gitlink recorded by the infra commit. It deliberately does **not** follow remote `main` automatically.

## Advance the pin

Run `scripts/update-app-pin.sh` only when intentionally reviewing a newer monorepo revision. The helper fetches `origin/main` inside the submodule and leaves the parent repository with a reviewable gitlink change; it does not commit, merge, rebase, reset, or force-push anything.

## Local output

`dist/` is local/generated output and is never a source-of-truth directory. `_apps/*` is ignored by default except for the tracked `_apps/gha-monorepo` gitlink. Terraform under `modules/` and `environments/` must not use either `_apps/` or `dist/` as a module source: deploy/state reproducibility must not depend on whether an optional application checkout exists locally.
