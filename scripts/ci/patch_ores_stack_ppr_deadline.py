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

replace_once(
    "fn run_prepare(mode: PrepareMode, prepare_lock: &Mutex<()>) -> Result<(), String> {",
    "fn run_prepare(\n    mode: PrepareMode,\n    prepare_lock: &Mutex<()>,\n    deadline: Instant,\n) -> Result<(), String> {",
    "run_prepare signature",
)

replace_once(
    '''    let _guard = prepare_lock
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
''',
    '''    let _guard = loop {
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
''',
    "deadline-bound generation process",
)

# Lock the lifecycle ordering and direct-child reap behavior into tests.
test_anchor = '''    #[test]
    fn reason_phrases_cover_timeout_and_gateway_errors() {'''
if "fn hard_deadline_covers_middleware_prepare_child_and_finalize()" not in text:
    test = r'''    #[test]
    fn hard_deadline_covers_middleware_prepare_child_and_finalize() {
        let source = include_str!("process_per_request.rs");
        let start = source
            .find("let hard_deadline = Instant::now() + CHILD_LIFETIME_TIMEOUT")
            .expect("absolute hard deadline");
        let begin = source
            .find("stack.begin(metadata)")
            .expect("middleware begin");
        let prepare = source
            .find("run_prepare(spec.prepare, prepare_lock, work_deadline)")
            .expect("deadline-bound generation");
        let relay = source
            .find("let child_deadline = work_deadline")
            .expect("child work deadline");
        let finish = source
            .rfind("stack.finish(active_request")
            .expect("deadline-bound finalization");
        assert!(start < begin && begin < prepare && prepare < relay && relay < finish);
        assert!(source.contains("MIDDLEWARE_FINALIZATION_RESERVE"));
        assert!(source.contains("tokio::time::Instant::from_std(hard_deadline)"));
        assert!(source.matches("stack.finish(active_request").count() >= 3);
    }

    #[cfg(unix)]
    #[test]
    fn child_guard_kill_and_reap_reaps_the_actual_child() {
        let child = Command::new("sh")
            .args(["-c", "sleep 30"])
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .expect("spawn sleeping child");
        let mut guard = ChildGuard(child);
        let status = guard.kill_and_reap().expect("kill and reap child");
        assert!(!status.success());
        assert!(guard.0.try_wait().expect("poll reaped child").is_some());
    }

'''
    index = text.find(test_anchor)
    if index < 0:
        raise SystemExit(f"{PATH}: lifecycle test insertion anchor drifted")
    text = text[:index] + test + text[index:]

PATH.write_text(text)
