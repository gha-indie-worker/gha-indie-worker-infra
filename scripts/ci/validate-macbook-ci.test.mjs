import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { execFileSync, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import {
  validateRepoList, validateEvidence, validateTunnel, validateRunnerScript,
} from './validate-macbook-ci.mjs';

const origin = fileURLToPath(new URL('../../cloudflare/local-ci-status/config.example.yml', import.meta.url));
const runner = fileURLToPath(new URL('./run-local-runner.sh', import.meta.url));
const config = fileURLToPath(new URL('../../config/macbook-ci-repositories.json', import.meta.url));
const SHA = '1234567890abcdef1234567890abcdef12345678';
const IMAGE = 'indiebuild-runner@sha256:6c241aa7944a536aaf0117ea7ecfb6e1973177330bd8976f11a819bc5f46b3cd';
const repo = 'ores-truffle-oreslang/oreslang-format';
const runId = 123456789;
function sample() {
  const url = `https://github.com/${repo}/actions/runs/${runId}`;
  return {
    runnerImage: IMAGE, runs: [{
      repository: repo, headSha: SHA, sourceTreeSha: SHA, workflowBlobSha: SHA,
      databaseId: runId, url, status: 'completed', conclusion: 'success',
      jobs: [{
        id: 987654321, runnerId: 12, runnerName: 'indiebuild-oreslang-format-1',
        status: 'completed', conclusion: 'success', labels: ['indiebuild-linux-arm64'],
        url: `${url}/job/987654321`,
        executedSteps: [{name:'Set up job',conclusion:'success'}, {name:'Run cargo test --locked',conclusion:'success'}],
      }],
    }],
  };
}
const accepted = () => new Set([repo]);
test('existing admitted repository manifest has unique canonical slugs', () => {
  const list = JSON.parse(readFileSync(config,'utf8'));
  assert.equal(validateRepoList(list).size,3);
});
test('reject duplicate, empty and path-injection repository allowlists', () => {
  for (const list of [[],[repo,repo],['oops'],['../repo'],['a/../b'],['a/b?x'],[42]]) {
    assert.throws(() => validateRepoList(list));
  }
});
test('positive native runner receipt contains a substantive step', () => {
  assert.deepEqual(validateEvidence(sample(),accepted(),'fixture'),{runs:1,jobs:1,substantive:1});
});
for (const [name, mutate] of [
  ['different image digest', e => e.runnerImage = 'other'],
  ['unadmitted repository', e => e.runs[0].repository = 'attacker/repo'],
  ['invalid head SHA', e => e.runs[0].headSha = 'HEAD'],
  ['invalid tree SHA', e => e.runs[0].sourceTreeSha = 'short'],
  ['invalid workflow SHA', e => e.runs[0].workflowBlobSha = 'short'],
  ['zero-step hosted fake', e => e.runs[0].jobs[0].executedSteps = []],
  ['only setup steps', e => e.runs[0].jobs[0].executedSteps = [{name:'Set up job',conclusion:'success'}]],
  ['no GitHub runner identity', e => delete e.runs[0].jobs[0].runnerId],
  ['wrong runner label', e => e.runs[0].jobs[0].labels = ['ubuntu-latest']],
  ['pending run', e => e.runs[0].status = 'queued'],
  ['failed job', e => e.runs[0].jobs[0].conclusion = 'failure'],
  ['forged run URL', e => e.runs[0].url = 'https://example.com/other'],
  ['forged job URL', e => e.runs[0].jobs[0].url = 'https://example.com/other'],
  ['duplicated native job', e => e.runs[0].jobs.push(structuredClone(e.runs[0].jobs[0]))],
]) test(`evidence fails closed: ${name}`, () => {
  const fixture=sample(); mutate(fixture);
  assert.throws(() => validateEvidence(fixture,accepted(),'fixture'));
});
test('dedicated Cloudflare origin only', () => {
  validateTunnel(readFileSync(origin,'utf8'));
});
for (const [name, change] of [
  ['extra apex route', s => s.replace('  - service: http_status:404','  - hostname: indiebuild.dev\n    service: http://127.0.0.1:18091\n  - service: http_status:404')],
  ['control API origin', s => s.replace(':18091', ':8770')],
  ['management metrics origin', s => s.replace(':18091', ':20392')],
  ['unsafe catchall', s => s.replace('http_status:404', 'http://127.0.0.1:18091')],
  ['missing credentials file', s => s.replace(/^credentials-file:.*\n/m,'')],
]) test(`tunnel fails closed: ${name}`, () => {
  assert.throws(() => validateTunnel(change(readFileSync(origin,'utf8'))));
});
test('runner uses ephemeral unprivileged bounded container and passes shell syntax', () => {
  validateRunnerScript(readFileSync(runner, 'utf8'));
  execFileSync('bash', ['-n', runner]);
});
for (const flag of ['--cap-drop=ALL', '--security-opt no-new-privileges', '--ephemeral']) {
  test(`missing ${flag} is a rejected runner contract`, () => {
    assert.throws(() => validateRunnerScript(readFileSync(runner,'utf8').replace(flag,'')));
  });
}
test('allowlist rejects unknown repo before contacting GitHub or Lima', () => {
  const p = spawnSync('bash',[runner,'untrusted/repo'],{encoding:'utf8'});
  assert.equal(p.status,2);
  assert.match(p.stderr,/not admitted/);
});
test('invalid concurrency rejects before GitHub or Lima', () => {
  const p = spawnSync('bash',[runner,repo,'99'],{encoding:'utf8'});
  assert.equal(p.status,2);
  assert.match(p.stderr,/jobs must be 1\.\.4/);
});

test('real jq admission rejects malformed policy and substring confusion', () => {
  const policy='type == "array" and all(.[]; type == "string") and any(.[]; . == $repo)';
  assert.ok(readFileSync(runner,'utf8').includes(policy), 'broker must use the reviewed type-checked policy');
  for (const [document, accepted] of [
    [[repo],true],
    [[repo+'-attacker'],false],
    [repo,false],
    [{repos:[repo]},false],
    [[repo,42],false],
    [['other/other'],false],
    [[],false],
  ]) {
    const result=spawnSync('jq',['-e','--arg','repo',repo,policy],{
      encoding:'utf8', input:JSON.stringify(document), timeout:2000,
    });
    assert.equal(result.status,accepted?0:1,JSON.stringify({document,stderr:result.stderr}));
  }
});
