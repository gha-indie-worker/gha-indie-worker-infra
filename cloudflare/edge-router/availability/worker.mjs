const headers = {"cache-control":"no-store","content-type":"text/html; charset=utf-8"};
const escape = s => String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export async function probe(site, fetcher=fetch) {
  try {
    const r=await fetcher(site.origin+'/health',{signal:AbortSignal.timeout(5000),redirect:'manual',headers:{'cache-control':'no-cache'}});
    const j=await r.json();
    return {live:r.ok&&j.ok===true&&j.service===site.service,service:site.service,originHttpStatus:r.status,checkedAt:new Date().toISOString()};
  } catch {
    return {live:false,service:site.service,reason:'origin_unreachable',checkedAt:new Date().toISOString()};
  }
}
function page(site, state, statusOnly=false) {
 const title=state.live?'Server is live':'Local server is unavailable';
 return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${escape(site.name)} — server status</title><style>body{font:17px system-ui;max-width:760px;margin:70px auto;padding:24px;background:#101820;color:#eef5f7}a{color:#a0d9eb}h1{font-size:44px}pre{overflow:auto;padding:20px;background:#1d2a35;border-radius:12px}.pill{color:${state.live?'#9be7be':'#ffc099'}}button,a.button{display:inline-block;padding:12px 18px;border:1px solid #759dad;border-radius:8px;color:#d9f4ff;background:#233c4a;cursor:pointer;text-decoration:none}</style></head><body><p>${escape(site.name)} · Cloudflare edge status</p><h1 class="pill">${title}</h1><p>${state.live?'The application on the MacBook answered its health check.':'Cloudflare is running, but the local application could not be verified through its tunnel. The laptop may be asleep, disconnected, or the app may be restarting.'}</p><p>The local supervisor starts and restarts the application while the MacBook is available. A disconnected or powered-off laptop cannot be started by a tunnel request.</p><p><a class="button" href="/">${state.live?'Open application':'Retry application'}</a> <a class="button" href="/healthz">Health JSON</a></p><pre>${escape(JSON.stringify(state,null,2))}</pre><p>This page is served by Cloudflare and remains available without the laptop.</p>${!state.live&&!statusOnly?`<script>setInterval(()=>fetch('/healthz',{cache:'no-store'}).then(r=>r.json()).then(x=>{if(x.live)location.reload()}).catch(()=>{}),10000)</script>`:''}</body></html>`;
}
export default {
 async fetch(request, env) {
  const url=new URL(request.url), site=env.SITES[url.hostname];
  if(!site)return new Response('Unknown host',{status:404});
  if(url.pathname==='/healthz'||url.pathname==='/__server-status'){
    const state=await probe(site);
    if(url.pathname==='/healthz')return Response.json(state,{status:state.live?200:503,headers:{'cache-control':'no-store'}});
    return new Response(page(site,state,true),{status:200,headers});
  }
  try {
    const target=new URL(site.origin);
    target.pathname=url.pathname;
    target.search=url.search;
    const upstream=await fetch(new Request(target,request),{signal:AbortSignal.timeout(15000),redirect:'manual'});
    if(upstream.status>=500)return new Response(page(site,await probe(site)),{status:503,headers});
    const response=new Response(upstream.body,upstream);
    response.headers.set('cache-control','no-store');
    if((response.headers.get('content-type')||'').includes('text/html')){
      return new HTMLRewriter().on('footer',{element(el){if(site.name==='IndieBuild')el.setInnerContent('Actual GitHub results · Jobs on local IndieBuild runners avoid GitHub-hosted compute. Artifact and cache storage have separate billing.');}}).on('body',{element(el){el.append('<nav style="position:fixed;right:18px;bottom:18px;padding:12px 18px;border-radius:10px;background:#152638;color:#fff;z-index:9999;font:14px system-ui"><a href="/__server-status" style="color:#c5edff">Server status</a> · <a href="/healthz" style="color:#c5edff">healthz</a></nav>',{html:true});}}).transform(response);
    }
    return response;
  } catch {
    return new Response(page(site,{live:false,service:site.service,reason:'origin_unreachable',checkedAt:new Date().toISOString()}),{status:503,headers});
  }
 }
};
