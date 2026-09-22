#!/usr/bin/env python3
from pathlib import Path

PATH = Path("crates/ores-stack-cli/src/ppr_api_direct_child.rs")
text = PATH.read_text()

old_import = "use ores_stack_core::{sync_api_lambda_sources, sync_api_rpc_route_map, sync_api_rpc_sources};"
new_import = "use ores_stack_core::{\n    sync_api_lambda_sources, sync_api_rpc_route_map, sync_api_rpc_sources, LambdaOperation,\n    LambdaSections,\n};"
if new_import not in text:
    if text.count(old_import) != 1:
        raise SystemExit(f"{PATH}: ores_stack_core import anchor drifted")
    text = text.replace(old_import, new_import, 1)

old_sections = '''#[derive(Debug)]
struct ApiSections {
    path: bool,
    query: bool,
    headers: bool,
    body: bool,
}

'''
if old_sections in text:
    text = text.replace(old_sections, "", 1)

text = text.replace("    sections: ApiSections,", "    sections: LambdaSections,")

start = text.find("#[derive(Debug)]\nstruct ApiHttpRoute {")
if start >= 0:
    end = text.find("\n}\n\npub(crate) fn try_run", start)
    if end < 0:
        raise SystemExit(f"{PATH}: ApiHttpRoute end anchor drifted")
    text = text[:start] + text[end + 3 :]

select_start = text.find("fn select_api_tmp(")
parser_start = text.find("fn collect_generated_api_lambdas(", select_start)
render_start = text.find("fn render_api_main(", parser_start)
if min(select_start, parser_start, render_start) < 0:
    raise SystemExit(f"{PATH}: selection/parser/render anchors drifted")

replacement = r'''fn select_api_tmp(
    root: &Path,
    request: &RequestView<'_>,
) -> Result<(PathBuf, ApiSelection), String> {
    if request.path == "/v1/rpc" {
        if request.method != "POST" {
            return Err("/v1/rpc PPR invocation requires POST".to_owned());
        }
        let value: Value = serde_json::from_slice(request.body)
            .map_err(|error| format!("invalid RPC v1 request JSON: {error}"))?;
        let key = value
            .get("key")
            .and_then(Value::as_str)
            .ok_or("RPC v1 request is missing string key")?;
        let operation = LambdaOperation::select_ppr_rpc(root, key)
            .map_err(|error| format!("RPC PPR selection failed: {error}"))?;
        let tmp = tmp_for_operation(root, &operation)?;
        return Ok((
            tmp,
            ApiSelection {
                operation_key: operation.operation_key,
                route_params: BTreeMap::new(),
                sections: operation.sections,
                rpc: true,
                stream_mode: operation.stream_mode,
            },
        ));
    }

    let (operation, route_params) =
        LambdaOperation::select_ppr_http(root, request.method, request.path)
            .map_err(|error| format!("HTTP PPR selection failed: {error}"))?;
    let tmp = tmp_for_operation(root, &operation)?;
    Ok((
        tmp,
        ApiSelection {
            operation_key: operation.operation_key,
            route_params,
            sections: operation.sections,
            rpc: false,
            stream_mode: operation.stream_mode,
        },
    ))
}

fn tmp_for_operation(root: &Path, operation: &LambdaOperation) -> Result<PathBuf, String> {
    let relative = Path::new(&operation.handlers_source);
    if relative.is_absolute()
        || relative.components().any(|component| {
            matches!(
                component,
                Component::ParentDir | Component::RootDir | Component::Prefix(_)
            )
        })
    {
        return Err(format!(
            "typed Lambda operation {:?} has non-confined handlers source {:?}",
            operation.operation_key, operation.handlers_source
        ));
    }
    let handlers = root.join(relative);
    let metadata = fs::symlink_metadata(&handlers).map_err(|error| {
        format!(
            "could not inspect typed Lambda handlers source {}: {error}",
            handlers.display()
        )
    })?;
    if metadata.file_type().is_symlink() || !metadata.is_file() {
        return Err(format!(
            "typed Lambda handlers source {} must be a regular non-symlink file",
            handlers.display()
        ));
    }
    let handlers = handlers.canonicalize().map_err(|error| {
        format!(
            "could not canonicalize typed Lambda handlers source {}: {error}",
            handlers.display()
        )
    })?;
    if !handlers.starts_with(root) {
        return Err(format!(
            "typed Lambda handlers source {} escapes repository root {}",
            handlers.display(),
            root.display()
        ));
    }
    let route_dir = handlers
        .parent()
        .ok_or("typed Lambda handlers source has no route directory")?;
    let lambda = route_dir.join("lambda.rs");
    let metadata = fs::symlink_metadata(&lambda).map_err(|error| {
        format!(
            "could not inspect generated API Lambda {}: {error}",
            lambda.display()
        )
    })?;
    if metadata.file_type().is_symlink() || !metadata.is_file() {
        return Err(format!(
            "generated API Lambda {} must be a regular non-symlink file",
            lambda.display()
        ));
    }
    let source = fs::read_to_string(&lambda).map_err(|error| {
        format!(
            "could not read generated API Lambda {}: {error}",
            lambda.display()
        )
    })?;
    if source.lines().next() != Some(GENERATED_API_LAMBDA_MARKER) {
        return Err(format!(
            "{} is not an ores-stack generated API Lambda",
            lambda.display()
        ));
    }
    Ok(route_dir.join("tmp"))
}

'''
text = text[:select_start] + replacement + text[render_start:]

# The old generated-source parser is gone; so are its route-matching helpers.
match_start = text.find("fn match_route(")
json_start = text.find("fn rust_json_object(", match_start)
if match_start >= 0:
    if json_start < 0:
        raise SystemExit(f"{PATH}: route helper end anchor drifted")
    text = text[:match_start] + text[json_start:]

text = text.replace("sections: ApiSections {", "sections: LambdaSections {")

# Delete tests that deliberately exercised the retired line-oriented generated-source parser.
for test_name in [
    "fully_qualified_http_route_metadata_is_parsed",
    "stream_key_sets_are_disjoint_authority",
]:
    marker = f"    #[test]\n    fn {test_name}()"
    start = text.find(marker)
    if start >= 0:
        next_test = text.find("\n    #[test]", start + len(marker))
        module_end = text.rfind("\n}")
        end = next_test if next_test >= 0 else module_end
        if end < 0:
            raise SystemExit(f"{PATH}: could not remove test {test_name}")
        text = text[:start] + text[end:]

PATH.write_text(text)
