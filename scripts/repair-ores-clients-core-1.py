#!/usr/bin/env python3
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: repair-ores-clients-core-1.py <repo-root>")

root = Path(sys.argv[1])
render = root / "src/render.rs"
text = render.read_text()
old = "s.split(|c: char| c == '_' || c == '-')"
if text.count(old) != 1:
    raise SystemExit(f"expected one manual char comparison, found {text.count(old)}")
render.write_text(text.replace(old, "s.split(['_', '-'])"))

lib = root / "src/lib.rs"
text = lib.read_text()

old_call = '''        if run_conformance {
            run_language_conformance(
                root,
                &loaded,
                target,
                renderer,
                language,
                &canonical,
                &package_root,
                &mut failures,
            )?;
        }
'''
new_call = '''        if run_conformance {
            let context = ConformanceContext {
                root,
                config: root.join(CONFIG_FILE),
                contract: clean_join(root, &loaded.cfg.contract.surface)?,
                header: &canonical,
                package_root: &package_root,
                target,
                renderer,
            };
            run_language_conformance(&loaded, language, &context, &mut failures)?;
        }
'''
if text.count(old_call) != 1:
    raise SystemExit("run_language_conformance call shape changed")
text = text.replace(old_call, new_call)

marker = "fn run_language_conformance(\n"
if text.count(marker) != 1:
    raise SystemExit("run_language_conformance definition shape changed")
context_def = '''struct ConformanceContext<'a> {
    root: &'a Path,
    config: PathBuf,
    contract: PathBuf,
    header: &'a Path,
    package_root: &'a Path,
    target: &'a str,
    renderer: &'a str,
}

'''
text = text.replace(marker, context_def + marker, 1)

old_sig = '''fn run_language_conformance(
    root: &Path,
    loaded: &Loaded,
    target: &str,
    renderer: &str,
    language: &LanguageConfig,
    header: &Path,
    package_root: &Path,
    failures: &mut Vec<String>,
) -> Result<()> {
'''
new_sig = '''fn run_language_conformance(
    loaded: &Loaded,
    language: &LanguageConfig,
    context: &ConformanceContext<'_>,
    failures: &mut Vec<String>,
) -> Result<()> {
    let target = context.target;
'''
if text.count(old_sig) != 1:
    raise SystemExit("run_language_conformance signature changed")
text = text.replace(old_sig, new_sig)

old_shell_call = '''            let status = shell(
                command,
                root,
                &root.join(CONFIG_FILE),
                &clean_join(root, &loaded.cfg.contract.surface)?,
                header,
                package_root,
                target,
                renderer,
            )?;
'''
if text.count(old_shell_call) != 1:
    raise SystemExit("shell call shape changed")
text = text.replace(old_shell_call, "            let status = shell(command, context)?;\n")

old_shell = '''fn shell(
    command: &str,
    root: &Path,
    config: &Path,
    contract: &Path,
    header: &Path,
    package_root: &Path,
    language: &str,
    renderer: &str,
) -> Result<std::process::ExitStatus> {
'''
new_shell = '''fn shell(command: &str, context: &ConformanceContext<'_>) -> Result<std::process::ExitStatus> {
'''
if text.count(old_shell) != 1:
    raise SystemExit("shell signature changed")
text = text.replace(old_shell, new_shell)

old_env = '''    cmd.current_dir(root)
        .env("ORES_CLIENTS_CONFIG", config)
        .env("ORES_CLIENTS_CONTRACT", contract)
        .env("ORES_CLIENTS_HEADER", header)
        .env("ORES_CLIENTS_PACKAGE_ROOT", package_root)
        .env("ORES_CLIENTS_LANGUAGE", language)
        .env("ORES_CLIENTS_RENDERER", renderer)
'''
new_env = '''    cmd.current_dir(context.root)
        .env("ORES_CLIENTS_CONFIG", &context.config)
        .env("ORES_CLIENTS_CONTRACT", &context.contract)
        .env("ORES_CLIENTS_HEADER", context.header)
        .env("ORES_CLIENTS_PACKAGE_ROOT", context.package_root)
        .env("ORES_CLIENTS_LANGUAGE", context.target)
        .env("ORES_CLIENTS_RENDERER", context.renderer)
'''
if text.count(old_env) != 1:
    raise SystemExit("shell environment block changed")
lib.write_text(text.replace(old_env, new_env))
