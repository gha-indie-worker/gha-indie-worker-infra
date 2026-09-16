#![forbid(unsafe_code)]

use std::{
    env,
    error::Error,
    fs,
    path::{Path, PathBuf},
    process::{Command, ExitStatus},
};

const MONOREPO_PATH: &str = "_apps/gha-monorepo";
const EXPECTED_MONOREPO: &str = "f5f481bec20774bc6cc2d8a2092c5c212cff1a03";
const EXPECTED_API_PIN: &str = "040ebfb6b33eb67ef6e7272a5cc849378bda2e7c";
const EXPECTED_WEB_PIN: &str = "4b4f98de3cac12a3f59b4d7201b32ff09e5cd631";
const ORES_CLI_REV: &str = "c854130ee147e9793a3af8736e90241630a5c934";

fn root() -> Result<PathBuf, Box<dyn Error>> {
    let manifest = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    Ok(manifest
        .parent()
        .and_then(Path::parent)
        .ok_or("dev-runtime must live under tools/<name>")?
        .to_path_buf())
}

fn read(root: &Path, rel: &str) -> Result<String, Box<dyn Error>> {
    Ok(fs::read_to_string(root.join(rel))?)
}

fn run(root: &Path, program: &str, args: &[&str]) -> Result<ExitStatus, Box<dyn Error>> {
    Ok(Command::new(program).current_dir(root).args(args).status()?)
}

fn output(root: &Path, program: &str, args: &[&str]) -> Result<String, Box<dyn Error>> {
    let out = Command::new(program).current_dir(root).args(args).output()?;
    if !out.status.success() {
        return Err(format!("{program} {:?} failed", args).into());
    }
    Ok(String::from_utf8(out.stdout)?.trim().to_string())
}

fn validate_devcontainer(root: &Path) -> Result<(), Box<dyn Error>> {
    let devcontainer = read(root, ".devcontainer/devcontainer.json")?;
    let revision = format!("--rev {ORES_CLI_REV}");
    for required in [
        "ghcr.io/devcontainers/features/github-cli:1",
        "ghcr.io/jsburckhardt/devcontainer-features/just:1.0.0",
        "ghcr.io/devcontainers-extra/features/cloudflared:1.0.8",
        "ORES_CLI_READ_TOKEN",
        "TUNNEL_TOKEN",
        "CARGO_NET_GIT_FETCH_WITH_CLI=true",
        "https://github.com/ORESoftware/ores-cli.git",
        revision.as_str(),
        "just codespace-edge-check",
        "\"8080\"",
        "\"onAutoForward\": \"ignore\"",
    ] {
        if !devcontainer.contains(required) {
            return Err(format!("devcontainer edge contract missing {required:?}").into());
        }
    }

    for forbidden in [
        "https://x-access-token:",
        "ghp_",
        "github_pat_",
        "*.app.github.dev",
        "CF_TUNNEL_TOKEN",
    ] {
        if devcontainer.contains(forbidden) {
            return Err(format!(
                "devcontainer contains credential-shaped or legacy ingress material: {forbidden}"
            )
            .into());
        }
    }

    Ok(())
}

fn validate(root: &Path) -> Result<(), Box<dyn Error>> {
    let manifest = read(root, ".ores-compose.yaml")?;
    for required in [
        "schema_version: ores.compose.v1",
        "project: gha-indie-worker",
        "working_dir: _apps/gha-monorepo/apps/gha-indie-worker-api-server.rs",
        "working_dir: _apps/gha-monorepo/apps/gha-indie-worker-web-server.rs",
        "GHA_INDIE_WORKER_API_BIND=127.0.0.1:18080",
        "GHA_INDIE_WORKER_WEB_BIND=127.0.0.1:18081",
        "tools/edge-lb/Cargo.toml",
        "http://127.0.0.1:8080/readyz",
        "depends_on: [api, web]",
    ] {
        if !manifest.contains(required) {
            return Err(format!("compose contract missing {required:?}").into());
        }
    }
    if manifest.contains("token:") || manifest.contains("credentials:") || manifest.contains("../") {
        return Err("compose manifest contains a credential-shaped or traversal field".into());
    }
    if manifest.contains("repository:") || manifest.contains("checkout_dir:") {
        return Err(
            "compose manifest must execute from the verified _apps gitlink, not a floating source checkout"
                .into(),
        );
    }

    let tree = output(root, "git", &["ls-tree", "HEAD", MONOREPO_PATH])?;
    let fields = tree.split_whitespace().collect::<Vec<_>>();
    if fields.len() < 4 || fields[0] != "160000" || fields[1] != "commit" {
        return Err("_apps/gha-monorepo must be a tracked mode-160000 gitlink".into());
    }
    if fields[2] != EXPECTED_MONOREPO {
        return Err(format!(
            "tracked monorepo gitlink {} != expected {EXPECTED_MONOREPO}",
            fields[2]
        )
        .into());
    }

    for required_file in [
        "tools/edge-lb/Cargo.toml",
        "tools/edge-lb/Cargo.lock",
        "tools/edge-lb/src/main.rs",
    ] {
        if !root.join(required_file).is_file() {
            return Err(format!("required edge load-balancer file is missing: {required_file}").into());
        }
    }

    validate_devcontainer(root)?;
    println!("local compose and Codespace edge contracts passed at {EXPECTED_MONOREPO}");
    Ok(())
}

fn command_available(name: &str) -> bool {
    Command::new(name)
        .arg("--version")
        .output()
        .map(|output| output.status.success())
        .unwrap_or(false)
}

fn verify_edge_cli(root: &Path) -> Result<(), Box<dyn Error>> {
    let status = Command::new("oresc")
        .current_dir(root)
        .args(["--no-json", "codespace", "edge", "status"])
        .status()
        .map_err(|error| format!("required command is unavailable: oresc ({error})"))?;

    match status.code() {
        Some(0 | 2) => Ok(()),
        Some(code) => Err(format!("oresc codespace edge status failed with exit code {code}").into()),
        None => Err("oresc codespace edge status terminated without an exit code".into()),
    }
}

fn nested_pin(root: &Path, path: &str) -> Result<String, Box<dyn Error>> {
    output(
        &root.join(MONOREPO_PATH),
        "git",
        &["ls-tree", "HEAD", path],
    )
    .and_then(|line| {
        line.split_whitespace()
            .nth(2)
            .map(str::to_string)
            .ok_or_else(|| format!("missing monorepo gitlink {path}").into())
    })
}

fn doctor(root: &Path) -> Result<(), Box<dyn Error>> {
    validate(root)?;

    for command in ["git", "cargo", "ores-compose", "curl", "just"] {
        if !command_available(command) {
            return Err(format!("required command is unavailable: {command}").into());
        }
    }
    verify_edge_cli(root)?;

    let monorepo = root.join(MONOREPO_PATH);
    if !monorepo.join(".git").exists() && !monorepo.join(".gitmodules").exists() {
        return Err("monorepo submodule is not initialized; run scripts/dev/bootstrap".into());
    }
    let checked_out = output(&monorepo, "git", &["rev-parse", "HEAD"])?;
    if checked_out != EXPECTED_MONOREPO {
        return Err(format!(
            "initialized monorepo is {checked_out}; expected {EXPECTED_MONOREPO}"
        )
        .into());
    }

    let api_pin = nested_pin(root, "apps/gha-indie-worker-api-server.rs")?;
    let web_pin = nested_pin(root, "apps/gha-indie-worker-web-server.rs")?;
    if api_pin != EXPECTED_API_PIN {
        return Err(format!(
            "API gitlink {api_pin} != compose-runnable pin {EXPECTED_API_PIN}"
        )
        .into());
    }
    if web_pin != EXPECTED_WEB_PIN {
        return Err(format!(
            "web gitlink {web_pin} != compose-runnable pin {EXPECTED_WEB_PIN}"
        )
        .into());
    }

    println!("local runtime doctor passed");
    Ok(())
}

fn bootstrap(root: &Path) -> Result<(), Box<dyn Error>> {
    for args in [
        vec!["submodule", "sync", "--", MONOREPO_PATH],
        vec!["submodule", "update", "--init", "--checkout", "--", MONOREPO_PATH],
    ] {
        if !run(root, "git", &args)?.success() {
            return Err(format!("git {:?} failed", args).into());
        }
    }
    for args in [
        vec!["submodule", "sync", "--recursive"],
        vec!["submodule", "update", "--init", "--recursive", "--checkout"],
    ] {
        if !run(&root.join(MONOREPO_PATH), "git", &args)?.success() {
            return Err(format!("nested git {:?} failed", args).into());
        }
    }
    validate(root)?;
    println!("exact application source initialized; run scripts/dev/doctor next");
    Ok(())
}

fn compose_check(root: &Path) -> Result<(), Box<dyn Error>> {
    doctor(root)?;
    if !run(root, "ores-compose", &["check", ".ores-compose.yaml"])?.success() {
        return Err("ores-compose check failed".into());
    }
    if !run(
        root,
        "cargo",
        &[
            "test",
            "--locked",
            "--manifest-path",
            "tools/edge-lb/Cargo.toml",
        ],
    )?
    .success()
    {
        return Err("edge load-balancer tests failed".into());
    }
    println!("compose and edge load-balancer checks passed");
    Ok(())
}

fn up(root: &Path) -> Result<(), Box<dyn Error>> {
    doctor(root)?;
    let status = Command::new("ores-compose")
        .current_dir(root)
        .arg("up")
        .arg(".ores-compose.yaml")
        .status()?;
    if !status.success() {
        return Err("ores-compose up exited unsuccessfully".into());
    }
    Ok(())
}

fn tunnel(root: &Path, mode: &str, config: &Path) -> Result<(), Box<dyn Error>> {
    doctor(root)?;
    if !command_available("cloudflared") {
        return Err("required command is unavailable for tunnel mode: cloudflared".into());
    }
    let config = config.canonicalize()?;
    let repo = root.canonicalize()?;
    if config.starts_with(&repo) {
        return Err("real cloudflared config/credentials must live outside the repository".into());
    }
    let text = fs::read_to_string(&config)?;
    let expected_host = match mode {
        "laptop" => "hostname: local.indiebuild.dev",
        "codespace" => "hostname: codespace.indiebuild.dev",
        _ => return Err("tunnel mode must be laptop or codespace".into()),
    };
    for required in [
        expected_host,
        "service: http://127.0.0.1:8080",
        "service: http_status:404",
        "credentials-file:",
    ] {
        if !text.contains(required) {
            return Err(format!("tunnel config missing fail-closed field {required:?}").into());
        }
    }
    if text.contains("noTLSVerify: true") || text.contains("token:") {
        return Err("tunnel config weakens TLS or embeds a token".into());
    }
    let status = Command::new("cloudflared")
        .arg("tunnel")
        .arg("--config")
        .arg(&config)
        .arg("run")
        .status()?;
    if !status.success() {
        return Err("cloudflared exited unsuccessfully".into());
    }
    Ok(())
}

fn usage() -> ! {
    eprintln!(
        "usage: gha-indie-worker-dev-runtime <validate|bootstrap|doctor|check|up|tunnel> [laptop|codespace] [config-path]"
    );
    std::process::exit(2);
}

fn main() -> Result<(), Box<dyn Error>> {
    let root = root()?;
    let args = env::args().skip(1).collect::<Vec<_>>();
    match args.first().map(String::as_str) {
        Some("validate") if args.len() == 1 => validate(&root),
        Some("bootstrap") if args.len() == 1 => bootstrap(&root),
        Some("doctor") if args.len() == 1 => doctor(&root),
        Some("check") if args.len() == 1 => compose_check(&root),
        Some("up") if args.len() == 1 => up(&root),
        Some("tunnel") if args.len() == 3 => tunnel(&root, &args[1], Path::new(&args[2])),
        _ => usage(),
    }
}
