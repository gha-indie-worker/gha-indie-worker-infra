#!/usr/bin/env python3
from pathlib import Path

PATH = Path("crates/ores-stack-core/src/rpc_spec_validation.rs")
text = PATH.read_text()


def replace_once(old: str, new: str, label: str) -> None:
    global text
    if new in text:
        return
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{PATH}: {label} drifted; expected one anchor, found {count}")
    text = text.replace(old, new, 1)


replace_once(
    "collect_operations(&handlers_file, &handlers_display)?",
    "collect_operations(&handlers_file, &handlers_display, &specs)?",
    "collect_operations call",
)

replace_once(
    """fn collect_operations(
    file: &syn::File,
    path: &str,
) -> Result<BTreeMap<String, OperationDecl>, RpcSourceError> {""",
    """fn collect_operations(
    file: &syn::File,
    path: &str,
    specs: &BTreeMap<String, SpecDecl>,
) -> Result<BTreeMap<String, OperationDecl>, RpcSourceError> {""",
    "collect_operations signature",
)

parse_line = "        let (spec, key) = parse_operation_meta(attr, path, function)?;"
stream_line = parse_line + "\n        let stream = operation_stream_mode(attr, path, function)?;"
replace_once(parse_line, stream_line, "operation metadata")

if "let (response, error) = operation_result_types(" not in text:
    start = text.find("        let (response, error) = result_types(&function.sig.output)")
    end = text.find("        let name = function.sig.ident.to_string();", start)
    if start < 0 or end < 0:
        raise SystemExit(f"{PATH}: return-shape block anchors drifted")
    replacement = """        let (response, error) = operation_result_types(
            &function.sig.output,
            &spec,
            &stream,
            specs,
            path,
            function,
        )?;
"""
    text = text[:start] + replacement + text[end:]

if "fn operation_result_types(" not in text:
    anchor = "fn parse_operation_meta(\n"
    index = text.find(anchor)
    if index < 0:
        raise SystemExit(f"{PATH}: helper insertion anchor drifted")
    helper = r'''fn operation_result_types(
    output: &ReturnType,
    spec_name: &str,
    stream: &str,
    specs: &BTreeMap<String, SpecDecl>,
    path: &str,
    function: &ItemFn,
) -> Result<(String, String), RpcSourceError> {
    match stream {
        "unary" => result_types(output).ok_or_else(|| {
            RpcSourceError::Contract(format!(
                "{path}: {} is unary and must return Result<Success, Error>",
                function.sig.ident
            ))
        }),
        "server_stream" => {
            let return_spec = single_generic_return(output, "ServerStreamResult").ok_or_else(|| {
                RpcSourceError::Contract(format!(
                    "{path}: {} uses server_stream metadata and must return ServerStreamResult<OperationSpec>",
                    function.sig.ident
                ))
            })?;
            if normalize_type(&return_spec) != normalize_type(spec_name) {
                return Err(RpcSourceError::Contract(format!(
                    "{path}: {} returns ServerStreamResult<{return_spec}> but #[ores_operation] declares spec {spec_name}",
                    function.sig.ident
                )));
            }
            let local = specs.get(&normalize_type(spec_name));
            let response = local
                .and_then(|decl| decl.associated.get("ResponseBody"))
                .cloned()
                .unwrap_or_else(|| {
                    format!("<{spec_name} as ::ores_api_docs::OperationSpec>::ResponseBody")
                });
            let error = local
                .and_then(|decl| decl.associated.get("Error"))
                .cloned()
                .unwrap_or_else(|| format!("<{spec_name} as ::ores_api_docs::OperationSpec>::Error"));
            Ok((response, error))
        }
        "client_stream" | "bidi" => Err(RpcSourceError::Contract(format!(
            "{path}: {} uses unsupported Rust handler stream mode {stream:?}; ores-stack currently admits unary and server_stream only",
            function.sig.ident
        ))),
        other => Err(RpcSourceError::Contract(format!(
            "{path}: {} uses unknown stream mode {other:?}",
            function.sig.ident
        ))),
    }
}

fn single_generic_return(output: &ReturnType, expected: &str) -> Option<String> {
    let ReturnType::Type(_, ty) = output else {
        return None;
    };
    let Type::Path(path) = ty.as_ref() else {
        return None;
    };
    let segment = path.path.segments.last()?;
    if segment.ident != expected {
        return None;
    }
    let PathArguments::AngleBracketed(arguments) = &segment.arguments else {
        return None;
    };
    let mut types = arguments.args.iter().filter_map(|argument| match argument {
        GenericArgument::Type(value) => Some(tokens(value)),
        _ => None,
    });
    let first = types.next()?;
    types.next().is_none().then_some(first)
}

fn operation_stream_mode(
    attr: &Attribute,
    path: &str,
    function: &ItemFn,
) -> Result<String, RpcSourceError> {
    let args = attr
        .parse_args_with(Punctuated::<Meta, Token![,]>::parse_terminated)
        .map_err(|error| {
            RpcSourceError::Contract(format!(
                "{path}: invalid #[ores_operation] on {}: {error}",
                function.sig.ident
            ))
        })?;
    let mut stream = None;
    for meta in args {
        let Meta::NameValue(value) = meta else {
            continue;
        };
        if !value.path.is_ident("stream") {
            continue;
        }
        if stream.is_some() {
            return Err(RpcSourceError::Contract(format!(
                "{path}: {} declares stream metadata more than once",
                function.sig.ident
            )));
        }
        let Expr::Lit(value) = value.value else {
            return Err(RpcSourceError::Contract(format!(
                "{path}: {} stream must be a string literal",
                function.sig.ident
            )));
        };
        let Lit::Str(value) = value.lit else {
            return Err(RpcSourceError::Contract(format!(
                "{path}: {} stream must be a string literal",
                function.sig.ident
            )));
        };
        stream = Some(value.value());
    }
    let stream = stream.unwrap_or_else(|| "unary".to_owned());
    if !matches!(
        stream.as_str(),
        "unary" | "server_stream" | "client_stream" | "bidi"
    ) {
        return Err(RpcSourceError::Contract(format!(
            "{path}: {} uses unsupported stream mode {stream:?}",
            function.sig.ident
        )));
    }
    Ok(stream)
}

'''
    text = text[:index] + helper + text[index:]

PATH.write_text(text)
