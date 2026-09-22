#!/usr/bin/env python3
from pathlib import Path

PATH = Path("crates/ores-stack-cli/src/process_per_request.rs")
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
    "const CHILD_LIFETIME_TIMEOUT: Duration = Duration::from_secs(90);\nconst STREAM_RELAY_POLL: Duration = Duration::from_millis(5);",
    "const CHILD_LIFETIME_TIMEOUT: Duration = Duration::from_secs(90);\nconst MIDDLEWARE_FINALIZATION_RESERVE: Duration = Duration::from_secs(2);\nconst STREAM_RELAY_POLL: Duration = Duration::from_millis(5);",
    "deadline constants",
)

replace_once(
    ") -> Result<(), String> {\n    client\n        .set_read_timeout(Some(REQUEST_HEAD_TIMEOUT))",
    ") -> Result<(), String> {\n    let hard_deadline = Instant::now() + CHILD_LIFETIME_TIMEOUT;\n    let work_deadline = hard_deadline\n        .checked_sub(MIDDLEWARE_FINALIZATION_RESERVE)\n        .ok_or(\"invalid PPR finalization reserve\")?;\n\n    client\n        .set_read_timeout(Some(REQUEST_HEAD_TIMEOUT))",
    "handle_connection deadline start",
)

replace_once(
    "    let active_request = match runtime.block_on(stack.begin(metadata)) {\n        Ok(active) => active,\n        Err(error) => {\n            write_middleware_error(client, &error)?;\n            return Ok(());\n        }\n    };",
    "    let active_request = match runtime.block_on(tokio::time::timeout_at(\n        tokio::time::Instant::from_std(work_deadline),\n        stack.begin(metadata),\n    )) {\n        Ok(Ok(active)) => active,\n        Ok(Err(error)) => {\n            write_middleware_error(client, &error)?;\n            return Ok(());\n        }\n        Err(_) => {\n            write_proxy_error(client, \"504 Gateway Timeout\", \"middleware begin exceeded the PPR hard deadline\\n\");\n            return Err(\"PPR middleware begin exceeded the hard request deadline\".to_owned());\n        }\n    };",
    "deadline-bound middleware begin",
)

replace_once(
    "    if let Err(error) = run_prepare(spec.prepare, prepare_lock) {\n        let middleware_headers = runtime.block_on(stack.finish(active_request, 503, None));\n        write_proxy_error_with_headers(\n            client,\n            \"503 Service Unavailable\",\n            \"dev generation failed\\n\",\n            &middleware_headers,\n        );\n        return Err(error);\n    }\n\n    let child_deadline = Instant::now() + CHILD_LIFETIME_TIMEOUT;",
    "    if let Err(error) = run_prepare(spec.prepare, prepare_lock, work_deadline) {\n        let middleware_headers = runtime\n            .block_on(tokio::time::timeout_at(\n                tokio::time::Instant::from_std(hard_deadline),\n                stack.finish(active_request, 503, None),\n            ))\n            .map_err(|_| {\n                \"PPR middleware finalization exceeded the hard request deadline after generation failure\"\n                    .to_owned()\n            })?;\n        write_proxy_error_with_headers(\n            client,\n            \"503 Service Unavailable\",\n            \"dev generation failed\\n\",\n            &middleware_headers,\n        );\n        return Err(error);\n    }\n\n    if Instant::now() >= work_deadline {\n        let middleware_headers = runtime\n            .block_on(tokio::time::timeout_at(\n                tokio::time::Instant::from_std(hard_deadline),\n                stack.finish(active_request, 504, None),\n            ))\n            .map_err(|_| {\n                \"PPR middleware finalization exceeded the hard request deadline before Lambda launch\"\n                    .to_owned()\n            })?;\n        write_proxy_error_with_headers(\n            client,\n            \"504 Gateway Timeout\",\n            \"request budget exhausted before Lambda launch\\n\",\n            &middleware_headers,\n        );\n        return Err(\"PPR request budget exhausted before Lambda launch\".to_owned());\n    }\n\n    let child_deadline = work_deadline;",
    "prepare and child work deadline",
)

replace_once(
    "    let finalized_headers = runtime.block_on(stack.finish(active_request, finish_status, None));",
    "    let finalized_headers = runtime\n        .block_on(tokio::time::timeout_at(\n            tokio::time::Instant::from_std(hard_deadline),\n            stack.finish(active_request, finish_status, None),\n        ))\n        .map_err(|_| {\n            \"PPR middleware finalization exceeded the hard 90-second request deadline\".to_owned()\n        })?;",
    "deadline-bound middleware finalization",
)

old_prepare_start = "fn run_prepare(mode: PrepareMode, prepare_lock: &Mutex<()>) -> Result<(), String> {"
new_prepare_start = "fn run_prepare(\n    mode: PrepareMode,\n    prepare_lock: &Mutex<()>,\n    deadline: Instant,\n) -> Result<(), String> {"
replace_once(old_prepare_start, new_prepare_start, "run_prepare signature")

old_prepare_body = '''    let _guard = prepare_lock
        .lock()
        .map_err(|_| "process-per-request generation lock was poisoned".to_owned())?;
    let executable = env::current_exe().map_err(|error| {
        format!("could not resolve ores-stack executable for PPR generation: {error}")
    })?;
    let status = Command::new(executable)
        .args(["generate", "all", "--root=."])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::inherit())
        .status()
        .map_err(|error| format!("could not run PPR source generation: {error}"))?;
    if status.success() {
        Ok(())
    } else {
        Err(format!("PPR source generation exited with status {status}"))
    }
'''
new_prepare_body = '''    let _guard = loop {
        match prepare_lock.try_lock() {
            Ok(guard) => break guard,
            Err(std::sync::TryLockError::Poisoned(_)) => {
                return Err("process-per-request generation lock was poisoned".to_owned());
            }
            Err(std::sync::TryLockError::WouldBlock) => {
                if Instant::now() >= deadline {
                    return Err(
                        "PPR source generation waited past the hard request work deadline"
                            .to_owned(),
                    );
                }
                thread::sleep(STREAM_RELAY_POLL);
            }
        }
    };
    if Instant::now() >= deadline {
        return Err("PPR source generation started after the hard request work deadline".to_owned());
    }
    let executable = env::current_exe().map_err(|error| {
        format!("could not resolve ores-stack executable for PPR generation: {error}")
    })?;
    let mut child = Command::new(executable)
        .args(["generate", "all", "--root=."])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::inherit())
        .spawn()
        .map_err(|error| format!("could not run PPR source generation: {error}"))?;
    loop {
        if let Some(status) = child
            .try_wait()
            .map_err(|error| format!("could not poll PPR source generation: {error}"))?
        {
            return if status.success() {
                Ok(())
            } else {
                Err(format!("PPR source generation exited with status {status}"))
            };
        }
        if Instant::now() >= deadline {
            let kill_error = child.kill().err();
            let reap = child.wait();
            if let Some(kill_error) = kill_error {
                return Err(format!(
                    "PPR source generation exceeded the hard request work deadline; kill failed: {kill_error}"
                ));
            }
            reap.map_err(|error| {
                format!(
                    "PPR source generation exceeded the hard request work deadline and could not be reaped: {error}"
                )
            })?;
            return Err(
                "PPR source generation exceeded the hard request work deadline and was killed/reaped"
                    .to_owned(),
            );
        }
        thread::sleep(STREAM_RELAY_POLL);
    }
'''
replace_once(old_prepare_body, new_prepare_body, "deadline-bound generation process")

PATH.write_text(text)
