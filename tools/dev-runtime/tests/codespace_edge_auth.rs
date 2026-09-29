#![forbid(unsafe_code)]

use std::{fs, path::PathBuf};

const EXPECTED_ORES_CLI_REV: &str = "d37aa4c1a0b79a292a31e2f16db8622144b0831f";
const CODESPACES_CLUSTER_REV: &str = "fe61abec77af464dd31944f6bf1fdd6ddfd0a65c";
const STALE_ORES_CLI_REV: &str = "c854130ee147e9793a3af8736e90241630a5c934";
const STALE_ORES_COMPOSE_REV: &str = "c52d08c875e73892acb88897c3b4a8969ad37ff2";

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

fn revision(path: &str) -> String {
    let value = read(path).trim().to_string();
    assert_eq!(value.len(), 40, "{path} must contain one full commit SHA");
    assert!(
        value.bytes().all(|byte| byte.is_ascii_hexdigit()),
        "{path} must contain hex only"
    );
    value
}

#[test]
fn private_auth_is_scoped_to_network_bootstrap_only() {
    let justfile = read("Justfile");
    let origin_up = read("scripts/dev/codespace-origin-up");

    assert!(justfile.contains("bash scripts/dev/codespace-origin-up"));
    assert!(origin_up.contains("GH_TOKEN=\"$token\" gh repo clone ORESoftware/codespaces-cluster"));
    assert!(origin_up.contains(r#"env "${git_auth_env[@]}" GH_TOKEN="$token""#));
    assert!(origin_up.contains("git -C \"$cluster_root\" fetch --no-tags origin \"$revision\""));
    assert!(origin_up.contains("GIT_CONFIG_VALUE_1=!gh auth git-credential"));
    assert!(!origin_up.contains("gh auth setup-git"));
    assert!(origin_up.contains("ORES_CLI_READ_TOKEN=\"$token\" just codespace-edge-bootstrap"));
    assert!(origin_up.contains("require_private_read"));
    assert!(origin_up.contains("gh auth token"));

    assert!(!origin_up.contains("export GH_TOKEN="));
    assert!(!origin_up.contains("GH_TOKEN=\"$token\" ORES_CODESPACES_CLUSTER_"));
    assert!(!origin_up.contains("GH_TOKEN=\"$token\" CODESPACES_CLUSTER_CONFIG="));
}

#[test]
fn bootstrap_git_auth_is_command_scoped() {
    let bootstrap = read("scripts/dev/bootstrap");

    assert!(!bootstrap.contains("gh auth setup-git"));
    assert!(bootstrap.contains("GIT_CONFIG_COUNT=2"));
    assert!(bootstrap.contains("GIT_CONFIG_KEY_0=credential.https://github.com.helper"));
    assert!(bootstrap.contains("GIT_CONFIG_VALUE_0="));
    assert!(bootstrap.contains("GIT_CONFIG_KEY_1=credential.https://github.com.helper"));
    assert!(bootstrap.contains("GIT_CONFIG_VALUE_1=!gh auth git-credential"));
    assert!(bootstrap.contains(r#"env "${git_auth_env[@]}" GH_TOKEN="$token""#));
    assert!(!bootstrap.contains("git config --global"));
}

#[test]
fn reviewed_tool_revisions_are_immutable_and_match_devcontainer() {
    let ores_cli = revision("config/ores-cli.rev");
    let ores_compose = revision("config/ores-compose.rev");
    let devcontainer = read(".devcontainer/devcontainer.json");

    assert_eq!(ores_cli, EXPECTED_ORES_CLI_REV);
    assert_ne!(ores_compose, STALE_ORES_COMPOSE_REV);
    assert!(devcontainer.contains(&format!("--rev {ores_cli}")));
    assert!(devcontainer.contains(&format!("--rev {ores_compose}")));
    assert!(!devcontainer.contains(STALE_ORES_CLI_REV));
    assert!(!devcontainer.contains(STALE_ORES_COMPOSE_REV));
}

#[test]
fn fresh_codespace_provisions_exact_private_toolchain() {
    let devcontainer = read(".devcontainer/devcontainer.json");
    let ores_cli = revision("config/ores-cli.rev");
    let ores_compose = revision("config/ores-compose.rev");

    for required in [
        "ORESoftware/ores-cli",
        "ORESoftware/ores-compose",
        "ORESoftware/codespaces-cluster",
        &format!("--rev {ores_cli}"),
        &format!("--rev {ores_compose}"),
        "gh repo view ORESoftware/codespaces-cluster --json name",
        r#"GH_TOKEN=\"$ORES_CLI_READ_TOKEN\""#,
        "\"onAutoForward\": \"ignore\"",
    ] {
        assert!(
            devcontainer.contains(required),
            "devcontainer contract missing {required:?}"
        );
    }

    for forbidden in [
        "https://x-access-token:",
        "ghp_",
        "github_pat_",
        "CF_TUNNEL_TOKEN",
        ".app.github.dev",
        STALE_ORES_CLI_REV,
        STALE_ORES_COMPOSE_REV,
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

    let origin_up = read("scripts/dev/codespace-origin-up");
    assert!(origin_up.contains("cat-file -e \"$revision^{commit}\""));
    assert!(origin_up.contains("checkout --detach -q \"$revision\""));
    assert!(origin_up.contains("rev-parse HEAD"));
}

#[test]
fn docs_describe_the_same_private_repo_boundary() {
    let docs = read("docs/local-development.md");
    let ores_cli = revision("config/ores-cli.rev");
    let ores_compose = revision("config/ores-compose.rev");

    for required in [
        "ORESoftware/ores-cli",
        "ORESoftware/ores-compose",
        "ORESoftware/codespaces-cluster",
        "read-only Contents",
        CODESPACES_CLUSTER_REV,
        "codespace-origin-up",
    ] {
        assert!(docs.contains(required), "docs missing {required:?}");
    }
    assert!(docs.contains(&ores_cli), "docs missing reviewed ores-cli revision");
    assert!(
        docs.contains(&ores_compose),
        "docs missing reviewed ores-compose revision"
    );
    assert!(!docs.contains(STALE_ORES_COMPOSE_REV));
}
