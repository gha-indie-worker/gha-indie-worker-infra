#!/usr/bin/env node
// Live GitHub API readback. Not a physical-host or network-isolation attestation.
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';

const ROOT = fileURLToPath(new URL('../../', import.meta.url));
const SHA40 = /^[a-f0-9]{40}$/;
const REQUIRED = new Map([
  ['Produce immutable evidence', ['Pin and validate checkout', 'Assert native Linux guest and exact commit', 'Write immutable SHA receipt', 'Upload receipt']],
  ['Consume and verify artifact', ['Download receipt', 'Verify receipt integrity']],
]);
function assert(value, message) { if (!value) throw new Error(message); }
const good = x => x?.status === 'completed' && x?.conclusion === 'success';
const pos = n => Number.isSafeInteger(n) && n > 0;
export function validateNativeAcceptance({run, jobs, artifacts}, {repository, runId, expectedSha}) {
  assert(/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repository), 'Invalid repository');
  assert(pos(runId) && SHA40.test(expectedSha), 'Exact run ID and 40-hex head SHA required');
  assert(run?.id === runId && run?.repository?.full_name === repository, 'Run ID/repository mismatch');
  assert(run?.event === 'workflow_dispatch', 'Expected explicitly dispatched workflow');
  assert(run?.path === '.github/workflows/indiebuild-native-acceptance.yml', 'Unexpected workflow path');
  assert(run?.head_sha === expectedSha && good(run), 'Wrong commit or incomplete/failed workflow');
  assert(pos(run?.run_attempt), 'Missing run attempt');
  assert(run?.html_url === `https://github.com/${repository}/actions/runs/${runId}`, 'Run URL mismatch');
  assert(jobs?.total_count === 2 && jobs?.jobs?.length === 2, 'Expected exactly two non-paginated jobs');
  const found = new Map();
  for (const job of jobs.jobs) {
    assert(!found.has(job.name) && REQUIRED.has(job.name), 'Duplicate or unexpected job');
    found.set(job.name, job);
    assert(good(job) && pos(job.id) && pos(job.runner_id), `Job failed or lacks native IDs: ${job.name}`);
    // A run can be re-run at the same head. Refuse old-attempt or cross-run
    // jobs even if the name and reported conclusion happen to match.
    assert(job.run_id === runId && job.run_attempt === run.run_attempt &&
      job.head_sha === expectedSha, `Job run/attempt/head mismatch: ${job.name}`);
    assert(job.run_url === `https://api.github.com/repos/${repository}/actions/runs/${runId}` &&
      job.html_url === `${run.html_url}/job/${job.id}`, `Job URL mismatch: ${job.name}`);
    assert(job.runner_name?.startsWith('indiebuild-'), `Wrong runner name: ${job.name}`);
    assert(job.labels?.includes('indiebuild-linux-arm64'), `Wrong runner label: ${job.name}`);
    assert(Array.isArray(job.steps), 'Missing job step details');
    let prior = -1;
    for (const name of REQUIRED.get(job.name)) {
      const matches = job.steps.map((step, idx) => ({step, idx})).filter(x => x.step?.name === name);
      assert(matches.length === 1, `Missing or duplicate step: ${job.name} / ${name}`);
      const {idx, step} = matches[0];
      assert(idx > prior && good(step), `Out-of-order/failed step: ${job.name} / ${name}`);
      prior = idx;
    }
  }
  const producer = found.get('Produce immutable evidence');
  const consumer = found.get('Consume and verify artifact');
  assert(producer && consumer, 'Producer/consumer job missing');
  assert(producer.runner_id !== consumer.runner_id &&
    producer.runner_name !== consumer.runner_name, 'Two jobs reused one non-ephemeral runner');
  const ended = Date.parse(producer.completed_at);
  const started = Date.parse(consumer.started_at);
  assert(Number.isFinite(ended) && Number.isFinite(started) && started >= ended, 'Job dependency ordering violated');
  assert(artifacts?.total_count === 1 && artifacts?.artifacts?.length === 1, 'Exactly one artifact required');
  const artifact = artifacts.artifacts[0];
  assert(artifact.name === `indiebuild-native-acceptance-${runId}-${run.run_attempt}`, 'Artifact name or attempt mismatch');
  assert(artifact.expired === false && pos(artifact.size_in_bytes) && pos(artifact.id), 'Missing/expired/empty artifact');
  assert(artifact.workflow_run?.id === runId &&
    artifact.workflow_run?.head_sha === expectedSha &&
    artifact.workflow_run?.repository_id === run.repository.id,
  'Artifact run/head/repository identity mismatch');
  return {repository, runId, headSha: expectedSha, runAttempt: run.run_attempt,
    jobs: jobs.jobs.map(j => ({id:j.id, name:j.name, runnerId:j.runner_id, runnerName:j.runner_name})),
    artifactId:artifact.id};
}
function github(path) {
  const output = execFileSync('gh', ['api', '-H', 'Accept: application/vnd.github+json', path], {
    encoding:'utf8', maxBuffer:8*1024*1024, timeout:30000, stdio:['ignore','pipe','pipe'],
  });
  return JSON.parse(output);
}
export function runCli(argv = process.argv.slice(2)) {
  assert(argv.length === 3, 'Usage: verify-native-acceptance.mjs OWNER/REPO RUN_ID EXACT_40_HEX_HEAD_SHA');
  const [repository, runText, expectedSha] = argv;
  assert(/^[1-9][0-9]*$/.test(runText) && Number.isSafeInteger(Number(runText)) && SHA40.test(expectedSha), 'Invalid run ID or exact SHA');
  const allowed = JSON.parse(readFileSync(resolve(ROOT, 'config/macbook-ci-repositories.json'), 'utf8'));
  assert(Array.isArray(allowed) && allowed.includes(repository), 'Repository not admitted for laptop CI');
  const base = `repos/${repository}/actions/runs/${runText}`;
  const result = validateNativeAcceptance({
    run: github(base), jobs: github(`${base}/jobs?per_page=100`), artifacts: github(`${base}/artifacts?per_page=100`),
  }, {repository, runId:Number(runText), expectedSha});
  process.stdout.write(JSON.stringify(result,null,2)+'\n');
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { runCli(); } catch(error) { console.error(error.message); process.exitCode=1; }
}
