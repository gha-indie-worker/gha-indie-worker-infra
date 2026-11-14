#!/usr/bin/env node
// Real broker control flow, with command stubs instead of GitHub, Lima or CI
// workloads. The copied broker changes only PATH for hermetic test injection.
import test from 'node:test';
import assert from 'node:assert/strict';
import {
  chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync,
} from 'node:fs';
import { spawn, spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const source = fileURLToPath(new URL('./run-local-runner.sh', import.meta.url));
const repo = 'ores-truffle-oreslang/oreslang-format';
const digest = 'indiebuild-runner@sha256:6c241aa7944a536aaf0117ea7ecfb6e1973177330bd8976f11a819bc5f46b3cd';

function mock(bin, name, body) {
  const path = join(bin, name);
  writeFileSync(path, '#!/usr/bin/env bash\nset -Eeuo pipefail\n' + body + '\n');
  chmodSync(path, 0o700);
}
function fixture() {
  const dir = mkdtempSync(join(tmpdir(), 'giw-lifecycle-'));
  const bin = join(dir, 'bin');
  const project = join(dir, 'project');
  const scriptDir = join(project, 'scripts', 'ci');
  const home = join(dir, 'home');
  const log = join(dir, 'events.log');
  mkdirSync(bin); mkdirSync(scriptDir, { recursive: true }); mkdirSync(home);
  mkdirSync(join(project, 'config'));
  writeFileSync(join(project, 'config', 'macbook-ci-repositories.json'), JSON.stringify([repo]));
  const src = readFileSync(source, 'utf8');
  const originalPath = 'export PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin';
  assert.ok(src.includes(originalPath), 'broker must retain its reviewed production PATH');
  const runner = join(scriptDir, 'run-local-runner.sh');
  writeFileSync(runner, src.replace(originalPath, `export PATH="${bin}:/usr/bin:/bin:/usr/sbin:/sbin"`));
  mock(bin, 'jq', 'exit 0');
  mock(bin, 'uname', 'echo Darwin');
  mock(bin, 'id', 'echo 501');
  mock(bin, 'stat', 'echo 700');
  mock(bin, 'uuidgen', 'echo 11111111-2222-3333-4444-555555555555');
  mock(bin, 'gh', `echo token >> "$MOCK_LOG"; echo abcdefghijklmnopqrstuv0123456789`);
  mock(bin, 'limactl', `
echo "limactl $*" >> "$MOCK_LOG"
case "$*" in
  "shell atto-ci -- id -u") echo 501 ;;
  "shell atto-ci -- nerdctl image inspect "*) echo "\${MOCK_IMAGE_DIGEST:-${digest}}" ;;
  "shell atto-ci -- nerdctl run "*) exec /bin/sleep 30 ;;
  "shell atto-ci -- nerdctl rm -f "*) echo cleanup >> "$MOCK_LOG"; if [[ "\${MOCK_REMOVE_FAIL:-0}" == 1 ]]; then exit 9; fi ;;
  *) echo "unsupported mock operation: $*" >&2; exit 3 ;;
esac
`);
  const env = { ...process.env, HOME: home, MOCK_LOG: log };
  return { dir, runner, log, home, env, lock: join(home, '.cache/indiebuild-runner/active.lock') };
}
async function until(predicate, timeoutMs = 5000) {
  const end = Date.now() + timeoutMs;
  while (Date.now() < end) {
    if (predicate()) return;
    await new Promise(resolve => setTimeout(resolve, 40));
  }
  throw new Error('mock runner failed to reach expected lifecycle state');
}
test('one-login concurrent admission is blocked and TERM cleans the VM runner', { timeout: 12000 }, async () => {
  const f = fixture();
  const child = spawn('bash', [f.runner, repo], { env: f.env, stdio: ['ignore', 'pipe', 'pipe'] });
  let stderr = '';
  child.stderr.on('data', chunk => { stderr += String(chunk); });
  try {
    await until(() => existsSync(f.log) && readFileSync(f.log, 'utf8').includes('nerdctl run'));
    assert.ok(existsSync(f.lock), 'first runner holds an exclusive lock');
    const second = spawnSync('bash', [f.runner, repo], {
      env: f.env, encoding: 'utf8', timeout: 3000,
    });
    assert.equal(second.status, 2, second.stderr);
    assert.match(second.stderr, /busy or a stale lock/);
    const events = readFileSync(f.log, 'utf8');
    assert.equal(events.split('token').length - 1, 1, 'second broker must not fetch a token');
    const done = new Promise(resolve => child.once('exit', (code, signal) => resolve({ code, signal })));
    child.kill('SIGTERM');
    const result = await done;
    assert.deepEqual(result, { code: 143, signal: null }, stderr);
    assert.match(readFileSync(f.log, 'utf8'), /nerdctl rm -f indiebuild-/);
    assert.ok(!existsSync(f.lock), 'clean shutdown releases the lock');
  } finally {
    child.kill('SIGKILL');
    rmSync(f.dir, { recursive: true, force: true });
  }
});
test('a stale lock rejects before registration-token acquisition', () => {
  const f = fixture();
  try {
    mkdirSync(f.lock, { recursive: true, mode: 0o700 });
    const result = spawnSync('bash', [f.runner, repo], { env: f.env, encoding: 'utf8', timeout: 3000 });
    assert.equal(result.status, 2, result.stderr);
    assert.match(result.stderr, /busy or a stale lock/);
    assert.ok(!existsSync(f.log), 'no token or VM operation is allowed with stale lock');
  } finally {
    rmSync(f.dir, { recursive: true, force: true });
  }
});

test('wrong guest image digest rejects before acquiring a GitHub registration token', () => {
  const f = fixture();
  try {
    const result = spawnSync('bash', [f.runner, repo], {
      env: { ...f.env, MOCK_IMAGE_DIGEST: 'attacker/runner@sha256:bad' },
      encoding: 'utf8', timeout: 3000,
    });
    assert.equal(result.status, 2, result.stderr);
    assert.match(result.stderr, /Runner image digest differs/);
    assert.doesNotMatch(readFileSync(f.log, 'utf8'), /token/);
    assert.ok(!existsSync(f.lock), 'preflight failure releases the lock');
  } finally { rmSync(f.dir, { recursive: true, force: true }); }
});
test('failed guest cleanup retains a stale lock and blocks new broker admission', {timeout:12000}, async () => {
  const f = fixture();
  const child = spawn('bash', [f.runner, repo], {
    env: {...f.env, MOCK_REMOVE_FAIL:'1'}, stdio:['ignore','pipe','pipe'],
  });
  let stderr='';
  child.stderr.on('data', chunk => { stderr += String(chunk); });
  try {
    await until(() => existsSync(f.log) && readFileSync(f.log,'utf8').includes('nerdctl run'));
    const done = new Promise(resolve => child.once('exit',(code,signal)=>resolve({code,signal})));
    child.kill('SIGTERM');
    const result = await done;
    assert.deepEqual(result,{code:1,signal:null},stderr);
    assert.match(stderr,/CRITICAL: could not remove VM runner/);
    assert.ok(existsSync(f.lock),'unsafe cleanup retains the lock');
    const another=spawnSync('bash',[f.runner,repo],{env:f.env,encoding:'utf8',timeout:3000});
    assert.equal(another.status,2,another.stderr);
    assert.match(another.stderr,/busy or a stale lock/);
    assert.equal(readFileSync(f.log,'utf8').split('token').length-1,1);
  } finally {
    child.kill('SIGKILL');
    rmSync(f.dir, {recursive:true,force:true});
  }
});
