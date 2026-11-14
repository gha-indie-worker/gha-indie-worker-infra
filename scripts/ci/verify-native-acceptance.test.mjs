import test from 'node:test';
import assert from 'node:assert/strict';
import {validateNativeAcceptance} from './verify-native-acceptance.mjs';

const repository = 'ores-truffle-oreslang/oreslang-target-profiles';
const runId = 12345678;
const expectedSha = 'a'.repeat(40);
const options = {repository, runId, expectedSha};
function step(name) { return {name, status:'completed', conclusion:'success'}; }
function fixture() {
  return {
    run: {
      id:runId, repository:{full_name:repository}, event:'workflow_dispatch',
      path:'.github/workflows/indiebuild-native-acceptance.yml', head_sha:expectedSha,
      status:'completed', conclusion:'success', run_attempt:1,
      html_url:`https://github.com/${repository}/actions/runs/${runId}`,
    },
    jobs:{
      total_count:2, jobs:[
        {id:12, name:'Produce immutable evidence', runner_id:22,
         runner_name:'indiebuild-fixture-producer', labels:['indiebuild-linux-arm64'],
         started_at:'2026-11-14T00:00:00Z', completed_at:'2026-11-14T00:01:00Z',
         status:'completed', conclusion:'success',
         steps:['Pin and validate checkout','Assert native Linux guest and exact commit',
           'Write immutable SHA receipt','Upload receipt'].map(step)},
        {id:13, name:'Consume and verify artifact', runner_id:23,
         runner_name:'indiebuild-fixture-consumer', labels:['indiebuild-linux-arm64'],
         started_at:'2026-11-14T00:01:01Z', completed_at:'2026-11-14T00:02:00Z',
         status:'completed', conclusion:'success',
         steps:['Download receipt','Verify receipt integrity'].map(step)},
      ],
    },
    artifacts:{
      total_count:1,
      artifacts:[{id:33,name:`indiebuild-native-acceptance-${runId}-1`, expired:false,
        size_in_bytes:128, workflow_run:{id:runId}}],
    },
  };
}
test('accepts a complete ordered GitHub-native run with an artifact',()=>{
  const result=validateNativeAcceptance(fixture(),options);
  assert.equal(result.artifactId,33);
  assert.equal(result.jobs.length,2);
});
for (const [name,change] of [
  ['wrong repository',f=>f.run.repository.full_name='attacker/other'],
  ['wrong head',f=>f.run.head_sha='b'.repeat(40)],
  ['missing workflow',f=>f.run.path='.github/workflows/ci.yml'],
  ['push instead of trusted manual dispatch',f=>f.run.event='push'],
  ['pending run',f=>f.run.status='queued'],
  ['failed run',f=>f.run.conclusion='failure'],
  ['wrong run ID',f=>f.run.id=123],
  ['no attempt',f=>delete f.run.run_attempt],
  ['forged URL',f=>f.run.html_url='https://example.com/fake'],
  ['missing job',f=>f.jobs.jobs.pop()],
  ['extra job in total count',f=>f.jobs.total_count=3],
  ['duplicate job',f=>f.jobs.jobs[1]=structuredClone(f.jobs.jobs[0])],
  ['hosted runner',f=>f.jobs.jobs[0].runner_name='GitHub Actions 12'],
  ['no runner ID',f=>f.jobs.jobs[0].runner_id=0],
  ['wrong runner label',f=>f.jobs.jobs[0].labels=['ubuntu-latest']],
  ['failed required step',f=>f.jobs.jobs[0].steps[1].conclusion='failure'],
  ['skipped upload',f=>f.jobs.jobs[0].steps[3].conclusion='skipped'],
  ['step order altered',f=>f.jobs.jobs[0].steps.reverse()],
  ['consumer before producer',f=>f.jobs.jobs[1].started_at='2026-11-13T23:00:00Z'],
  ['missing artifact',f=>f.artifacts.artifacts=[]],
  ['old attempt artifact',f=>f.artifacts.artifacts[0].name='indiebuild-native-acceptance-12345678-0'],
  ['expired artifact',f=>f.artifacts.artifacts[0].expired=true],
  ['zero bytes artifact',f=>f.artifacts.artifacts[0].size_in_bytes=0],
  ['cross-run artifact',f=>f.artifacts.artifacts[0].workflow_run.id=123],
]) test(`fail-closed: ${name}`,()=>{
  const f=fixture();
  change(f);
  assert.throws(()=>validateNativeAcceptance(f,options));
});
test('malformed exact-head request cannot be accepted',()=>{
  assert.throws(()=>validateNativeAcceptance(fixture(),{...options,expectedSha:'main'}));
});
