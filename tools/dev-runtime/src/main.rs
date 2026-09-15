#![forbid(unsafe_code)]

use std::{
    env,
    error::Error,
    fs,
    path::{Path, PathBuf},
    process::{Command, ExitStatus},
};

const MONOREPO_PATH: &str = "_apps/gha-monorepo";
const EXPECTED_MONOREPO: &str = "ed76301ff9db6ba359570f58a00cc29ca90b6840";
const STUB_API_PIN: &str = "90cfc8a86660d36683fc96d629af843c347e6667";
const STUB_WEB_PIN: &str = "d99dbb64f3cb4434d023e7f7943a016b7c8c3bd4";

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

fn manifest_commit(text: &str) -> Option<&str> {
    text.lines()
        .map(str::trim)
        .find_map(|line| line.strip_prefix("commit:").map(str::trim))
}

fn validate(root: &Path) -> Result<(), Box<dyn Error>> {
    let manifest = read(root, ".ores-compose.yaml")?;
    for required in [
        "schema_version: ores.compose.v1",
        "repository: https://github.com/gha-indie-worker/gha-indie-worker-monorepo.git",
        "checkout_dir: .ores/sources/gha-indie-worker-monorepo",
        "load_balancer:",
        "strategy: round-robin",
        "max_attempts: 2",
        "failover_on_missing_backend: true",
        "failover_on_invalid_backend: true",
        "working_dir: apps/gha-indie-worker-api-server.rs",
        "working_dir: apps/gha-indie-worker-web-server.rs",
        "http://127.0.0.1:8080/readyz",
        "http://127.0.0.1:8081/readyz",
    ] {
        if !manifest.contains(required) {
            return Err(format!("compose contract missing {required:?}").into());
        }
    }
    if manifest.contains("token:") || manifest.contains("credentials:") || manifest.contains("../") {
        return Err("compose manifest contains a credential-shaped or traversal field".into());
    }

    let compose_pin = manifest_commit(&manifest).ok_or("compose source commit is missing")?;
    if compose_pin != EXPECTED_MONOREPO {
        return Err(format!("compose source pin {compose_pin} != expected {EXPECTED_MONOREPO}").into());
    }

    let tree = output(root, "git", &["ls-tree", "HEAD", MONOREPO_PATH])?;
    let fields = tree.split_whitespace().collect::<Vec<_>>();
    if fields.len() < 4 || fields[0] != "160000" || fields[1] != "commit" {
        return Err("_apps/gha-monorepo must be a tracked mode-160000 gitlink".into());
    }
    if fields[2] != compose_pin {
        return Err(format!("tracked monorepo gitlink {} != compose source pin {compose_pin}", fields[2]).into());
    }

    println!("local compose static contract passed at {compose_pin}");
    Ok(())
}

fn command_available(name: &str) -> bool {
    Command::new(name).arg("--version").output().map(|o| o.status.success()).unwrap_or(false)
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

    for command in ["git", "cargo", "curl", "ores-compose", "cloudflared"] {
        if !command_available(command) {
            return Err(format!("required command is unavailable: {command}").into());
        }
    }

    let monorepo = root.join(MONOREPO_PATH);
    if !monorepo.join(".git").exists() && !monorepo.join(".gitmodules").exists() {
        return Err("monorepo submodule is not initialized; run scripts/dev/bootstrap".into());
    }
    let checked_out = output(&monorepo, "git", &["rev-parse", "HEAD"])?;
    if checked_out != EXPECTED_MONOREPO {
        return Err(format!("initialized monorepo is {checked_out}; expected {EXPECTED_MONOREPO}").into());
    }

    let api_pin = nested_pin(root, "apps/gha-indie-worker-api-server.rs")?;
    let web_pin = nested_pin(root, "apps/gha-indie-worker-web-server.rs")?;
    if api_pin == STUB_API_PIN || web_pin == STUB_WEB_PIN {
        return Err(format!(
            "runtime intentionally blocked: API/web pins still reference print-and-exit server stubs (api={api_pin}, web={web_pin})"
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

fn tunnel(root: &Path, mode: &str, config: &Path) -> Result<(), Box<dyn Error>> {
    doctor(root)?;
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
    for required in [expected_host, "service: http://127.0.0.1:8080", "service: http_status:404", "credentials-file:"] {
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
    eprintln!("usage: gha-indie-worker-dev-runtime <validate|bootstrap|doctor|tunnel> [laptop|codespace] [config-path]");
    std::process::exit(2)
}

fn main() -> Result<(), Box<dyn Error>> {
    let root = root()?;
    let args = env::args().skip(1).collect::<Vec<_>>();
    match args.first().map(String::as_str) {
        Some("validate") if args.len() == 1 => validate(&root),
        Some("bootstrap") if args.len() == 1 => bootstrap(&root),
        Some("doctor") if args.len() == 1 => doctor(&root),
        Some("tunnel") if args.len() == 3 => tunnel(&root, &args[1], Path::new(&args[2])),
        _ => usage(),
    }
}
