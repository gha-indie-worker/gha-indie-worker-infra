#![forbid(unsafe_code)]

use std::{fs, path::PathBuf};

const ORES_CLI_REV: &str = "d37aa4c1a0b79a292a31e2f16db8622144b0831f";
const ORES_COMPOSE_REV: &str = "9fbbaf4580b91c1445ec91f67ad3b31252094171";
const CODESPACES_CLUSTER_REV: &str = "8c494f4b038a766be06ff29df5a067b6d78c9134";

fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .and_then(std::path::Path::parent)
        .expect("dev-runtime must live under tools/<name>")
        .to_path_buf()
}

fn read(path: &str) -> String {
    fs::read_to_string(repo_root().join(path)).expect("contract file must be readable")
}

#[test]
fn private_auth_is_scoped_to_network_bootstrap_only() {
    let justfile = read("Justfile");

    assert!(justfile.contains("GH_TOKEN=\"$token\" gh repo clone ORESoftware/codespaces-cluster"));
    assert!(justfile.contains("GH_TOKEN=\"$token\" git -C \"$root\" fetch --prune origin main"));
    assert!(justfile.contains("GH_TOKEN=\"$token\" just codespace-edge-bootstrap"));
    assert!(justfile.contains("require_private_read"));

    assert!(!justfile.contains("export GH_TOKEN="));
    assert!(!justfile.contains("GH_TOKEN=\"$token\" ORES_CODESPACES_CLUSTER_"));
    assert!(!justfile.contains("GH_TOKEN=\"$token\" CODESPACES_CLUSTER_CONFIG="));
}

#[test]
fn fresh_codespace_provisions_exact_private_toolchain() {
    let devcontainer = read(".devcontainer/devcontainer.json");

    for required in [
        "ORESoftware/ores-cli",
        "ORESoftware/ores-compose",
        "ORESoftware/codespaces-cluster",
        &format!("--rev {ORES_CLI_REV}"),
        &format!("--rev {ORES_COMPOSE_REV}"),
        "gh repo view ORESoftware/codespaces-cluster --json name",
        r#"GH_TOKEN=\"$ORES_CLI_READ_TOKEN\""#,
        "\"onAutoForward\": \"ignore\"",
    ] {
        assert!(devcontainer.contains(required), "devcontainer contract missing {required:?}");
    }

    for forbidden in [
        "https://x-access-token:",
        "ghp_",
        "github_pat_",
        "CF_TUNNEL_TOKEN",
        ".app.github.dev",
        "c854130ee147e9793a3af8736e90241630a5c934",
    ] {
        assert!(
            !devcontainer.contains(forbidden),
            "devcontainer contains forbidden credential/ingress/stale-pin material {forbidden:?}"
        );
    }
}

#[test]
fn shared_edge_revision_is_reviewed_and_immutable() {
    let revision = read("config/codespaces-cluster.rev");
    let revision = revision.trim();

    assert_eq!(revision, CODESPACES_CLUSTER_REV);
    assert_eq!(revision.len(), 40);
    assert!(revision.bytes().all(|byte| byte.is_ascii_hexdigit()));

    let justfile = read("Justfile");
    assert!(justfile.contains("cat-file -e \"$rev^{commit}\""));
    assert!(justfile.contains("checkout --detach -q \"$rev\""));
    assert!(justfile.contains("rev-parse HEAD"));
}

#[test]
fn docs_describe_the_same_private_repo_boundary() {
    let docs = read("docs/local-development.md");
    for required in [
        "ORESoftware/ores-cli",
        "ORESoftware/ores-compose",
        "ORESoftware/codespaces-cluster",
        "read-only Contents",
        "bootstrap",
        "d37aa4c1a0b79a292a31e2f16db8622144b0831f",
        "8c494f4b038a766be06ff29df5a067b6d78c9134",
    ] {
        assert!(docs.contains(required), "docs missing {required:?}");
    }
}
