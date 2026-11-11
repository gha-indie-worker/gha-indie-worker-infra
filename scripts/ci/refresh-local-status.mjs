#!/usr/bin/env node
import {execFileSync} from 'node:child_process';
import {mkdirSync, readFileSync, writeFileSync, renameSync} from 'node:fs';
import {dirname, join} from 'node:path';
import {homedir} from 'node:os';
const repositories=JSON.parse(readFileSync(new URL('../../config/macbook-ci-repositories.json',import.meta.url),'utf8'));
const destination=join(homedir(),'.local/share/indiebuild/runs.json');
const runs=repositories.flatMap(repository=>{
 const result=JSON.parse(execFileSync('/opt/homebrew/bin/gh',['run','list','--repo',repository,'--workflow','ci.yml','--limit','1','--json','databaseId,status,conclusion,headSha,url,updatedAt'],{encoding:'utf8',timeout:20000}));
 return result.map(run=>({repository,...run}));
});
mkdirSync(dirname(destination),{recursive:true,mode:0o700});
writeFileSync(destination+'.next',JSON.stringify({updatedAt:new Date().toISOString(),runs}),{mode:0o600});
renameSync(destination+'.next',destination);
console.log(`Recorded ${runs.length} actual GitHub runs.`);
