#![forbid(unsafe_code)]

use std::env;
use std::io::{self, Read, Write};
use std::net::{Shutdown, SocketAddr, TcpListener, TcpStream};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::Duration;

const MAX_HEADER_BYTES: usize = 64 * 1024;
const CONNECT_TIMEOUT: Duration = Duration::from_secs(3);
const READY_TIMEOUT: Duration = Duration::from_millis(750);
const DEFAULT_MAX_CONNECTIONS: usize = 256;
const MAX_CONNECTIONS_CEILING: usize = 4096;

#[derive(Clone, Copy)]
struct Config {
    bind: SocketAddr,
    api_backend: SocketAddr,
    web_backend: SocketAddr,
    max_connections: usize,
}

struct ActiveConnection(Arc<AtomicUsize>);

impl Drop for ActiveConnection {
    fn drop(&mut self) {
        self.0.fetch_sub(1, Ordering::AcqRel);
    }
}

fn main() {
    if let Err(error) = run() {
        eprintln!("edge load balancer failed: {error}");
        std::process::exit(1);
    }
}

fn run() -> Result<(), String> {
    let config = Config {
        bind: parse_addr("GHA_EDGE_BIND", "0.0.0.0:8080")?,
        api_backend: parse_addr("GHA_EDGE_API_BACKEND", "127.0.0.1:18080")?,
        web_backend: parse_addr("GHA_EDGE_WEB_BACKEND", "127.0.0.1:18081")?,
        max_connections: parse_connection_limit()?,
    };

    let listener = TcpListener::bind(config.bind)
        .map_err(|error| format!("could not bind {}: {error}", config.bind))?;
    eprintln!(
        "gha-indie-worker edge listening on {} api={} web={} max_connections={}",
        config.bind, config.api_backend, config.web_backend, config.max_connections
    );

    let active = Arc::new(AtomicUsize::new(0));
    for accepted in listener.incoming() {
        let mut client = match accepted {
            Ok(client) => client,
            Err(error) => {
                eprintln!("edge accept failed: {error}");
                continue;
            }
        };

        let prior = active.fetch_add(1, Ordering::AcqRel);
        if prior >= config.max_connections {
            active.fetch_sub(1, Ordering::AcqRel);
            let _ = respond(
                &mut client,
                "503 Service Unavailable",
                "text/plain; charset=utf-8",
                b"edge capacity reached\n",
            );
            continue;
        }

        let active = Arc::clone(&active);
        thread::spawn(move || {
            let _active = ActiveConnection(active);
            if let Err(error) = handle_connection(&mut client, config) {
                eprintln!("edge connection failed: {error}");
            }
        });
    }
    Ok(())
}

fn parse_addr(name: &str, default: &str) -> Result<SocketAddr, String> {
    let value = env::var(name).unwrap_or_else(|_| default.to_owned());
    value
        .parse::<SocketAddr>()
        .map_err(|_| format!("{name} must be an IP socket address, got {value:?}"))
}

fn parse_connection_limit() -> Result<usize, String> {
    let value = env::var("GHA_EDGE_MAX_CONNECTIONS")
        .unwrap_or_else(|_| DEFAULT_MAX_CONNECTIONS.to_string());
    let parsed = value
        .parse::<usize>()
        .map_err(|_| "GHA_EDGE_MAX_CONNECTIONS must be an integer".to_string())?;
    if !(1..=MAX_CONNECTIONS_CEILING).contains(&parsed) {
        return Err(format!(
            "GHA_EDGE_MAX_CONNECTIONS must be between 1 and {MAX_CONNECTIONS_CEILING}"
        ));
    }
    Ok(parsed)
}

fn handle_connection(client: &mut TcpStream, config: Config) -> io::Result<()> {
    client.set_nodelay(true)?;
    let request = read_request_head(client)?;
    let (method, path, version) = request_line(&request)?;

    if path == "/healthz" {
        return respond(
            client,
            "200 OK",
            "application/json",
            br#"{"ok":true,"service":"gha-indie-worker-edge-lb"}"#,
        );
    }
    if path == "/readyz" {
        let api_ready = TcpStream::connect_timeout(&config.api_backend, READY_TIMEOUT).is_ok();
        let web_ready = TcpStream::connect_timeout(&config.web_backend, READY_TIMEOUT).is_ok();
        let status = if api_ready && web_ready {
            "200 OK"
        } else {
            "503 Service Unavailable"
        };
        let body = format!(
            "{{\"ok\":{},\"api\":{},\"web\":{}}}",
            api_ready && web_ready,
            api_ready,
            web_ready
        );
        return respond(client, status, "application/json", body.as_bytes());
    }

    let api_path = api_backend_path(path);
    let backend_addr = if api_path.is_some() {
        config.api_backend
    } else {
        config.web_backend
    };
    let mut backend = TcpStream::connect_timeout(&backend_addr, CONNECT_TIMEOUT)?;
    backend.set_nodelay(true)?;

    let forwarded = match api_path {
        Some(path) => rewrite_request_line(&request, method, &path, version)?,
        None => request,
    };
    backend.write_all(&forwarded)?;
    backend.flush()?;

    let mut client_reader = client.try_clone()?;
    let mut backend_writer = backend.try_clone()?;
    let upstream = thread::spawn(move || {
        let result = io::copy(&mut client_reader, &mut backend_writer);
        let _ = backend_writer.shutdown(Shutdown::Write);
        result
    });

    let downstream = io::copy(&mut backend, client);
    let _ = client.shutdown(Shutdown::Write);
    let upstream = upstream
        .join()
        .map_err(|_| io::Error::other("upstream proxy thread panicked"))?;
    upstream?;
    downstream?;
    Ok(())
}

fn read_request_head(client: &mut TcpStream) -> io::Result<Vec<u8>> {
    let mut request = Vec::with_capacity(4096);
    let mut chunk = [0_u8; 4096];
    loop {
        let read = client.read(&mut chunk)?;
        if read == 0 {
            return Err(io::Error::new(
                io::ErrorKind::UnexpectedEof,
                "client closed before request headers completed",
            ));
        }
        request.extend_from_slice(&chunk[..read]);
        if request.windows(4).any(|window| window == b"\r\n\r\n") {
            return Ok(request);
        }
        if request.len() > MAX_HEADER_BYTES {
            let _ = respond(
                client,
                "431 Request Header Fields Too Large",
                "text/plain; charset=utf-8",
                b"request headers too large\n",
            );
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "request headers exceed bounded edge limit",
            ));
        }
    }
}

fn request_line(request: &[u8]) -> io::Result<(&str, &str, &str)> {
    let header_end = request
        .windows(4)
        .position(|window| window == b"\r\n\r\n")
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidData, "missing header terminator"))?;
    let header = std::str::from_utf8(&request[..header_end])
        .map_err(|_| io::Error::new(io::ErrorKind::InvalidData, "headers must be UTF-8/ASCII"))?;
    let line = header.lines().next().unwrap_or_default();
    let mut parts = line.split_whitespace();
    let method = parts.next().unwrap_or_default();
    let path = parts.next().unwrap_or_default();
    let version = parts.next().unwrap_or_default();
    if method.is_empty() || path.is_empty() || !version.starts_with("HTTP/") || parts.next().is_some() {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "malformed HTTP request line",
        ));
    }
    Ok((method, path, version))
}

fn api_backend_path(path: &str) -> Option<String> {
    if path == "/api" {
        return Some("/".to_owned());
    }
    if let Some(query) = path.strip_prefix("/api?") {
        return Some(format!("/?{query}"));
    }
    path.strip_prefix("/api/")
        .map(|rest| format!("/{rest}"))
}

fn rewrite_request_line(
    request: &[u8],
    method: &str,
    path: &str,
    version: &str,
) -> io::Result<Vec<u8>> {
    let line_end = request
        .windows(2)
        .position(|window| window == b"\r\n")
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidData, "missing request-line terminator"))?;
    let mut output = format!("{method} {path} {version}").into_bytes();
    output.extend_from_slice(&request[line_end..]);
    Ok(output)
}

fn respond(
    stream: &mut TcpStream,
    status: &str,
    content_type: &str,
    body: &[u8],
) -> io::Result<()> {
    let headers = format!(
        "HTTP/1.1 {status}\r\nContent-Type: {content_type}\r\nContent-Length: {}\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n",
        body.len()
    );
    stream.write_all(headers.as_bytes())?;
    stream.write_all(body)?;
    stream.flush()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn api_prefix_routes_and_is_stripped_for_backend() {
        assert_eq!(api_backend_path("/api"), Some("/".to_owned()));
        assert_eq!(
            api_backend_path("/api/jobs?limit=3"),
            Some("/jobs?limit=3".to_owned())
        );
        assert_eq!(api_backend_path("/apix"), None);
    }

    #[test]
    fn request_line_rewrite_preserves_headers_and_body() {
        let input = b"POST /api/jobs HTTP/1.1\r\nHost: example\r\nContent-Length: 2\r\n\r\n{}";
        let rewritten = rewrite_request_line(input, "POST", "/jobs", "HTTP/1.1").expect("rewrite");
        assert_eq!(
            rewritten,
            b"POST /jobs HTTP/1.1\r\nHost: example\r\nContent-Length: 2\r\n\r\n{}"
        );
    }

    #[test]
    fn request_line_parser_rejects_malformed_lines() {
        assert!(request_line(b"GET /\r\n\r\n").is_err());
    }
}
