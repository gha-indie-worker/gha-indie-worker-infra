#![forbid(unsafe_code)]

use std::{
    error::Error,
    fs,
    path::{Path, PathBuf},
};

fn read(root: &Path, rel: &str) -> Result<String, Box<dyn Error>> {
    Ok(fs::read_to_string(root.join(rel))?)
}

fn require(haystack: &str, needle: &str, context: &str) -> Result<(), Box<dyn Error>> {
    if !haystack.contains(needle) {
        return Err(format!("{context}: missing {needle:?}").into());
    }
    Ok(())
}

fn main() -> Result<(), Box<dyn Error>> {
    let manifest = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let root = manifest
        .parent()
        .and_then(Path::parent)
        .ok_or("tool must live under tools/<name>")?;

    let required = [
        "cloudflare/pr-gateway/worker.js",
        "cloudflare/pr-gateway/wrangler.toml",
        "k8s/pr-gateway.yaml",
        "modules/neon/projects/ci_control_plane.tf",
        "supabase/ci-control-plane/config.toml",
        "docs/indiebuild-pr-ci.md",
    ];
    for rel in required {
        if !root.join(rel).is_file() {
            return Err(format!("missing required PR-CI contract file: {rel}").into());
        }
    }

    let worker = read(root, "cloudflare/pr-gateway/worker.js")?;
    for needle in [
        "MAX_BODY_BYTES",
        "request.arrayBuffer()",
        "x-ores-edge",
        "redirect: \"manual\"",
        "upstream.protocol !== \"https:\"",
    ] {
        require(&worker, needle, "Cloudflare worker")?;
    }
    if worker.contains("request.json()") {
        return Err("Cloudflare worker must preserve raw webhook bytes".into());
    }

    let wrangler = read(root, "cloudflare/pr-gateway/wrangler.toml")?;
    require(&wrangler, "hooks.indiebuild.dev/*", "wrangler route")?;
    require(&wrangler, "workers_dev = false", "wrangler exposure")?;

    let k8s = read(root, "k8s/pr-gateway.yaml")?;
    for kind in [
        "ConfigMap",
        "Deployment",
        "Service",
        "PodDisruptionBudget",
        "NetworkPolicy",
    ] {
        require(&k8s, &format!("kind: {kind}"), "Kubernetes manifest")?;
    }
    for secret in [
        "INDIEBUILD_GITHUB_WEBHOOK_SECRET",
        "INDIEBUILD_GITHUB_STATUS_TOKEN",
        "INDIEBUILD_BUILD_SERVER_AUTH",
    ] {
        require(&k8s, secret, "Kubernetes secret reference")?;
    }
    if k8s.contains("automountServiceAccountToken: true") || k8s.contains("privileged: true") {
        return Err("PR gateway may not gain ambient service-account or privileged access".into());
    }

    let neon = read(root, "modules/neon/projects/ci_control_plane.tf")?;
    require(&neon, "length(local.projects) == 3", "Neon topology")?;
    require(&neon, "crimson-cell-39815049", "Neon canonical project")?;

    let supabase = read(root, "supabase/ci-control-plane/config.toml")?;
    require(&supabase, "create_project = false", "Supabase boundary")?;
    require(&supabase, "allow_in_supabase = false", "Supabase secret boundary")?;

    for entry in fs::read_dir(root.join("cloudflare/pr-gateway"))? {
        let entry = entry?;
        let file_name = entry.file_name();
        let name = file_name.to_string_lossy().to_ascii_lowercase();
        if name.contains("secret") || name.contains("token") || name.starts_with(".env") {
            return Err(
                format!("credential-shaped file is forbidden in cloudflare/pr-gateway: {name}")
                    .into(),
            );
        }
    }

    println!("indiebuild PR-CI infrastructure contract passed");
    Ok(())
}
