import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const cwd=fileURLToPath(new URL('.',import.meta.url));
for(const [command,args] of [
 [process.execPath,['render.mjs']],
 [process.execPath,['--test','worker.test.mjs']],
 ['npx',['--yes','wrangler@4.160.0','deploy','--config','wrangler.json']]
]){const result=spawnSync(command,args,{cwd,stdio:'inherit'});if(result.status!==0)process.exit(result.status??1);}
