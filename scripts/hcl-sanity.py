#!/usr/bin/env python3
"""Offline sanity checks for the Terraform in this repository.

This is **not** a substitute for `terraform validate` — it cannot know a
provider's schema. It is the check that still works with no network and no
provider plugins, and it catches the mistakes that are expensive to find later:

  * unbalanced braces / brackets / parentheses,
  * unterminated quotes,
  * tabs (terraform fmt rejects them),
  * duplicate `resource "type" "name"` / `data` / `variable` / `output` /
    `provider` / `module` addresses within one directory,
  * `var.x` used but never declared, and `variable "x"` declared but never used,
  * `local.x` used but never assigned,
  * a `.tfvars.example` that sets an unknown variable,
  * accidentally committed state, lock or credential files.

Usage:  python3 scripts/hcl-sanity.py [terraform-root ...]      (default: terraform/)
Exit code 0 = clean, 1 = findings.
"""
from __future__ import annotations

import pathlib
import re
import sys

# Characters that open/close a nesting level, tracked outside strings/comments.
PAIRS = {"{": "}", "[": "]", "(": ")"}
CLOSERS = {v: k for k, v in PAIRS.items()}

BLOCK_RE = re.compile(
    r'^\s*(resource|data|variable|output|provider|module|locals|terraform|moved|import|check)\b([^\n{]*)',
    re.M,
)
VAR_USE_RE = re.compile(r'\bvar\.([A-Za-z_][A-Za-z0-9_]*)')
LOCAL_USE_RE = re.compile(r'\blocal\.([A-Za-z_][A-Za-z0-9_]*)')
FORBIDDEN_NAMES = (".terraform", "terraform.tfstate", "terraform.tfstate.backup", ".terraformrc")
# Anything that looks like a real credential rather than a variable reference.
SECRET_RE = re.compile(
    r'(?i)(?:'
    r'ghp_[A-Za-z0-9]{20,}'          # GitHub PAT
    r'|github_pat_[A-Za-z0-9_]{20,}'
    r'|sk-[A-Za-z0-9]{32,}'          # OpenAI-style
    r'|AKIA[0-9A-Z]{16}'             # AWS access key id
    r'|-----BEGIN [A-Z ]*PRIVATE KEY-----'
    r'|eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'  # JWT
    r')'
)


def strip_code(text: str) -> str:
    """Blank out string literals, heredocs and comments so structure can be counted."""
    out: list[str] = []
    i, n = 0, len(text)
    heredoc: str | None = None
    while i < n:
        ch = text[i]
        if heredoc is not None:
            line_end = text.find("\n", i)
            if line_end == -1:
                line_end = n
            line = text[i:line_end]
            if line.strip() == heredoc:
                heredoc = None
            out.append(" " * (line_end - i))
            out.append("\n" if line_end < n else "")
            i = line_end + 1
            continue
        if ch == "#" or (ch == "/" and i + 1 < n and text[i + 1] == "/"):
            line_end = text.find("\n", i)
            line_end = n if line_end == -1 else line_end
            out.append(" " * (line_end - i))
            i = line_end
            continue
        if ch == "/" and i + 1 < n and text[i + 1] == "*":
            end = text.find("*/", i + 2)
            end = n if end == -1 else end + 2
            out.append("".join(c if c == "\n" else " " for c in text[i:end]))
            i = end
            continue
        if ch == "<" and text.startswith("<<", i):
            m = re.match(r'<<[-~]?([A-Za-z_][A-Za-z0-9_]*)', text[i:])
            if m:
                heredoc = m.group(1)
                out.append(" " * m.end())
                i += m.end()
                continue
        if ch == '"':
            j = i + 1
            while j < n:
                if text[j] == "\\":
                    j += 2
                    continue
                if text[j] == '"':
                    break
                if text[j] == "\n":
                    break
                j += 1
            if j >= n or text[j] != '"':
                out.append("\x00")  # marker: unterminated string
                i += 1
                continue
            out.append("".join(c if c == "\n" else " " for c in text[i:j + 1]))
            i = j + 1
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def check_file(path: pathlib.Path, findings: list[str]) -> dict:
    raw = path.read_text()
    if "\t" in raw:
        findings.append(f"{path}: contains a tab (terraform fmt rejects tabs)")
    for marker in ("<<<<<<<", ">>>>>>>", "======="):
        if any(line.startswith(marker) for line in raw.splitlines()):
            findings.append(f"{path}: git conflict marker {marker!r}")
    if SECRET_RE.search(raw):
        findings.append(f"{path}: something secret-shaped is committed here")
    code = strip_code(raw)
    if "\x00" in code:
        line = code[:code.index("\x00")].count("\n") + 1
        findings.append(f"{path}:{line}: unterminated string literal")
    stack: list[tuple[str, int]] = []
    line = 1
    for ch in code:
        if ch == "\n":
            line += 1
        elif ch in PAIRS:
            stack.append((ch, line))
        elif ch in CLOSERS:
            if not stack:
                findings.append(f"{path}:{line}: stray {ch!r}")
            elif stack[-1][0] != CLOSERS[ch]:
                findings.append(f"{path}:{line}: {ch!r} closes {stack[-1][0]!r} opened on line {stack[-1][1]}")
                stack.pop()
            else:
                stack.pop()
    for ch, ln in stack:
        findings.append(f"{path}:{ln}: {ch!r} is never closed")

    addresses: list[str] = []
    declared_vars: set[str] = set()
    declared_outputs: set[str] = set()
    for m in BLOCK_RE.finditer(code):
        kind, rest = m.group(1), m.group(2)
        labels = re.findall(r'"([^"]*)"', raw[m.start(2):m.start(2) + len(rest)])
        if kind in ("resource", "data") and len(labels) == 2:
            addresses.append(f"{kind}.{labels[0]}.{labels[1]}")
        elif kind in ("variable", "output", "module", "provider") and labels:
            addresses.append(f"{kind}.{labels[0]}")
            if kind == "variable":
                declared_vars.add(labels[0])
            if kind == "output":
                declared_outputs.add(labels[0])
    # References also live inside string interpolations, which strip_code blanks
    # out. Scan the interpolation bodies separately so `"${var.x}"` counts as a
    # use of var.x.
    interpolated = " ".join(re.findall(r'\$\{[^}]*\}', raw))
    return {
        "addresses": addresses,
        "declared_vars": declared_vars,
        "declared_outputs": declared_outputs,
        "used_vars": set(VAR_USE_RE.findall(code)) | set(VAR_USE_RE.findall(interpolated)),
        "used_locals": set(LOCAL_USE_RE.findall(code)) | set(LOCAL_USE_RE.findall(interpolated)),
        "assigned_locals": set(re.findall(r'^\s{2,}([A-Za-z_][A-Za-z0-9_]*)\s*=', code, re.M)),
        "raw": raw,
    }


def check_root(root: pathlib.Path, findings: list[str]) -> None:
    files = sorted(p for p in root.rglob("*.tf"))
    if not files:
        findings.append(f"{root}: no .tf files")
        return
    seen: dict[str, pathlib.Path] = {}
    declared_vars: set[str] = set()
    used_vars: set[str] = set()
    used_locals: set[str] = set()
    assigned_locals: set[str] = set()
    for f in files:
        info = check_file(f, findings)
        for addr in info["addresses"]:
            if addr in seen:
                findings.append(f"{f}: duplicate block {addr} (also in {seen[addr].name})")
            else:
                seen[addr] = f
        declared_vars |= info["declared_vars"]
        used_vars |= info["used_vars"]
        used_locals |= info["used_locals"]
        assigned_locals |= info["assigned_locals"]

    for name in sorted(used_vars - declared_vars):
        findings.append(f"{root}: var.{name} is used but no `variable \"{name}\"` block declares it")
    for name in sorted(declared_vars - used_vars):
        findings.append(f"{root}: variable \"{name}\" is declared but never used")
    for name in sorted(used_locals - assigned_locals):
        findings.append(f"{root}: local.{name} is used but never assigned")

    example = root / "terraform.tfvars.example"
    if example.exists():
        for m in re.finditer(r'^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=', strip_code(example.read_text()), re.M):
            if m.group(1) not in declared_vars:
                findings.append(f"{example}: sets unknown variable {m.group(1)!r}")

    for p in root.rglob("*"):
        if p.name in FORBIDDEN_NAMES or p.name.endswith(".tfstate"):
            findings.append(f"{p}: state/plugin artifacts must never be committed")


def main(argv: list[str]) -> int:
    roots = [pathlib.Path(a) for a in argv[1:]] or [pathlib.Path("terraform")]
    findings: list[str] = []
    checked = 0
    for base in roots:
        if not base.exists():
            findings.append(f"{base}: does not exist")
            continue
        for root in sorted({p.parent for p in base.rglob("*.tf")}):
            check_root(root, findings)
            checked += 1
    for f in findings:
        print(f"[hcl-sanity] {f}")
    print(f"[hcl-sanity] {checked} terraform root(s) checked, {len(findings)} finding(s)")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
