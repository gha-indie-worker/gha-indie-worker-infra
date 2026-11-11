import test from 'node:test';
import assert from 'node:assert/strict';
import worker,{probe} from './worker.mjs';
const site={name:'IndieBuild',origin:'https://origin-status.indiebuild.dev',service:'gha-indie-worker-web-server'};
test('health requires a real successful response from the expected service',async()=>{
 const result=await probe(site,async()=>Response.json({ok:true,service:site.service}));assert.equal(result.live,true);
 for(const response of [Response.json({ok:true,service:'wrong-service'}),Response.json({ok:true,service:site.service},{status:503})])assert.equal((await probe(site,async()=>response)).live,false);
});
test('connection loss is explicitly unavailable, never successful',async()=>{
 const result=await probe(site,async()=>{throw Error('tunnel unavailable')});assert.equal(result.live,false);assert.equal(result.reason,'origin_unreachable');
});
test('Cloudflare serves the unavailable page without a functioning laptop',async()=>{
 const original=globalThis.fetch;globalThis.fetch=async()=>{throw Error('offline')};try{const response=await worker.fetch(new Request('https://indiebuild.dev/'),{SITES:{'indiebuild.dev':site}});assert.equal(response.status,503);assert.match(await response.text(),/Local server is unavailable/);}finally{globalThis.fetch=original;}
});
test('unknown hosts are never proxied',async()=>{assert.equal((await worker.fetch(new Request('https://attacker.example/'),{SITES:{'indiebuild.dev':site}})).status,404)});
test('a network-path request cannot select a different upstream host',async()=>{
 const original=globalThis.fetch;let received;
 globalThis.fetch=async request=>{received=new URL(request.url);return new Response('app',{headers:{'content-type':'text/plain'}})};
 try{const response=await worker.fetch(new Request('https://indiebuild.dev//attacker.example/path?q=1'),{SITES:{'indiebuild.dev':site}});assert.equal(response.status,200);assert.equal(received.origin,site.origin);assert.equal(received.pathname,'//attacker.example/path');}finally{globalThis.fetch=original;}
});
