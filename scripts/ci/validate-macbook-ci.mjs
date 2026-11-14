#!/usr/bin/env node
// Offline, fail-closed *structural* check. Authoritative evidence still
// requires a fresh GitHub API readback at the exact workflow/run/job IDs.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';

const ROOT = fileURLToPath(new URL('../../', import.meta.url));
const IMAGE = 'indiebuild-runner@sha256:6c241aa7944a536aaf0117ea7ecfb6e1973177330bd8976f11a819bc5f46b3cd';
const SHA40 = /^[a-f0-9]{40}$/;
const REPO = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
function requireValue(value, message) {
  if (!value) throw new Error(message);
}
export function validateRepoList(list) {
  requireValue(Array.isArray(list) && list.length > 0, 'Repository list must be nonempty');
  const repos = new Set();
  for (const repo of list) {
    requireValue(typeof repo === 'string' && REPO.test(repo) && !repo.includes('..'), `Invalid admitted repository: ${repo}`);
    requireValue(!repos.has(repo), `Duplicate admitted repository: ${repo}`);
    repos.add(repo);
  }
  return repos;
}
export function validateEvidence(evidence, allowed, filename) {
  requireValue(evidence?.runnerImage === IMAGE, `${filename}: runner digest mismatch`);
  requireValue(Array.isArray(evidence?.runs) && evidence.runs.length > 0, `${filename}: no runs`);
  const seenJobs = new Set();
  const seenRuns = new Set();
  let substantive = 0;
  for (const run of evidence.runs) {
    requireValue(allowed.has(run.repository), `${filename}: unadmitted repository ${run.repository}`);
    requireValue(SHA40.test(run.headSha) && SHA40.test(run.sourceTreeSha) && SHA40.test(run.workflowBlobSha), `${filename}: malformed source/workflow SHA`);
    requireValue(Number.isSafeInteger(run.databaseId) && run.databaseId > 0, `${filename}: invalid run ID`);
    requireValue(run.status === 'completed' && run.conclusion === 'success', `${filename}: run was not successful`);
    requireValue(run.url === `https://github.com/${run.repository}/actions/runs/${run.databaseId}`, `${filename}: run URL mismatch`);
    const key = `${run.repository}/${run.databaseId}`;
    requireValue(!seenRuns.has(key), `${filename}: duplicate run ${key}`);
    seenRuns.add(key);
    requireValue(Array.isArray(run.jobs) && run.jobs.length > 0, `${filename}: empty job list`);
    for (const job of run.jobs) {
      requireValue(Number.isSafeInteger(job.id) && job.id > 0 && Number.isSafeInteger(job.runnerId) && job.runnerId > 0, `${filename}: missing native runner/job ID`);
      const jobKey = `${run.repository}/${job.id}`;
      requireValue(!seenJobs.has(jobKey), `${filename}: duplicate job ${jobKey}`);
      seenJobs.add(jobKey);
      requireValue(typeof job.runnerName === 'string' && job.runnerName.startsWith('indiebuild-'), `${filename}: unknown runner`);
      requireValue(Array.isArray(job.labels) && job.labels.includes('indiebuild-linux-arm64'), `${filename}: missing admitted runner label`);
      requireValue(job.status === 'completed' && job.conclusion === 'success', `${filename}: job failed or is pending`);
      requireValue(job.url === `${run.url}/job/${job.id}`, `${filename}: job URL mismatch`);
      requireValue(Array.isArray(job.executedSteps), `${filename}: missing job steps`);
      const executed = job.executedSteps.filter(step => typeof step?.name === 'string' && step.name.startsWith('Run ') && step.conclusion === 'success');
      requireValue(executed.length >= 1, `${filename}: no successful substantive steps`);
      substantive += executed.length;
    }
  }
  return {runs: seenRuns.size, jobs: seenJobs.size, substantive};
}
export function validateTunnel(config) {
  const lines = config.split(/\r?\n/).map(line => line.replace(/\s+#.*$/, '').trim()).filter(line => line && !line.startsWith('#'));
  // This is a deliberately tiny example profile, not a general YAML parser:
  // reject unknown keys/routes rather than trying to interpret YAML aliases.
  requireValue(lines.length === 6 &&
    /^tunnel: [A-Za-z0-9_-]+$/.test(lines[0]) &&
    /^credentials-file: \/[^\s]+$/.test(lines[1]) &&
    lines[2] === 'ingress:' &&
    lines[3] === '- hostname: origin-status.indiebuild.dev' &&
    lines[4] === 'service: http://127.0.0.1:18091' &&
    lines[5] === '- service: http_status:404',
  'Tunnel example must expose only the dedicated origin with terminal 404');
}
export function validateRunnerScript(script) {
  for (const requirement of [
    'set +x', 'umask 077', '$(id -u)', 'vm_uid=',
    '--ephemeral', '--disableupdate', '--no-default-labels',
    '--labels indiebuild-linux-arm64', '--cap-drop=ALL',
    '--security-opt no-new-privileges', '--pull=never',
    '--rm -i', '--pids-limit=1024', '--memory=4g',
    '--cpus=2', 'registration-token', IMAGE,
    'active.lock', 'mkdir -m 700 "$lock"', 'trap cleanup EXIT',
    'trap \'exit 143\' TERM', 'rmdir "$lock"',
    'nerdctl rm -f "$active_name"', 'wait "$client_pid"',
    'uuidgen',
  ]) requireValue(script.includes(requirement), `Missing runner guard: ${requirement}`);
  requireValue(!/--privileged\b|--network[= ]host\b|--volume\b/.test(script), 'Unsafe container flag');
}
export function validateFiles(root = ROOT) {
  const read = (path) => readFileSync(resolve(root, path), 'utf8');
  const allowed = validateRepoList(JSON.parse(read('config/macbook-ci-repositories.json')));
  validateRunnerScript(read('scripts/ci/run-local-runner.sh'));
  validateTunnel(read('cloudflare/local-ci-status/config.example.yml'));
  return [
    'docs/evidence/macbook-ci-2026-11-10.json',
    'docs/evidence/macbook-native-ci-2026-11-10.json',
  ].map(filename => ({filename, ...validateEvidence(JSON.parse(read(filename)), allowed, filename)}));
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    for (const record of validateFiles()) console.log(`${record.filename}: ${record.runs} runs, ${record.jobs} jobs, ${record.substantive} successful steps (offline receipt check)`);
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
