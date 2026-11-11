import {readFileSync,writeFileSync} from 'node:fs';
const config=JSON.parse(readFileSync(new URL('./config.json',import.meta.url),'utf8'));
const routes=Object.keys(config.sites).map(host=>({pattern:host+'/*',zone_name:host.endsWith('multiapp.fyi')?'multiapp.fyi':'indiebuild.dev'}));
writeFileSync(new URL('./wrangler.json',import.meta.url),JSON.stringify({name:config.name,main:'worker.mjs',account_id:config.accountId,compatibility_date:'2026-11-10',workers_dev:false,routes,vars:{SITES:config.sites}},null,2)+'\n');
