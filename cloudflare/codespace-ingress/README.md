# Codespaces ingress contract

Codespaces uses the same infra-owned `.ores-compose.yaml` and the same loopback gateway shape as laptop development, but a distinct hostname and distinct named Cloudflare Tunnel: `codespace.indiebuild.dev`.

Copy `config.example.yml` **outside this repository**, fill in the reviewed tunnel UUID, Access team/AUD and credential-file path, then invoke `scripts/dev/tunnel codespace /absolute/path/to/config.yml`. The Rust wrapper rejects configs stored inside the repository, non-loopback gateway origins, missing fail-closed 404s, embedded tokens and `noTLSVerify: true`.

The public tunnel must not be activated until `scripts/dev/doctor` passes. At the current source pin the doctor intentionally fails because API/web still use print-and-exit server stubs; this prevents a documentation-only contract from being mistaken for a healthy runtime.
