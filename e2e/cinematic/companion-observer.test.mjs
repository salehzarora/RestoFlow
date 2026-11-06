import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { chromium } from '@playwright/test';
import { CompanionObserver, companionStatus, classifyCompanion } from './companion-observer.ts';

test('companion observations follow the actual HTTP request and user-visible terminal state', {timeout:30000}, async t => {
  const request = {slot:'background', request_id:'SECRET-local-request', base_media_id:'SECRET-local-base', base_rung:0, rung:0};
  const success = {ok:true,status:'published',recipe:'storefront-background-b1',rung:0,media:{base_media_id:request.base_media_id}};
  let respond;
  const server = createServer((req,res) => {
    if(req.url==='/' && req.method==='GET') return res.writeHead(200,{'content-type':'text/html'}).end('<main><output>ready</output><button>Retry</button></main>');
    if(req.url==='/publisher' && req.method==='POST') return respond(res);
    res.writeHead(404).end();
  });
  await new Promise(ok=>server.listen(0,'127.0.0.1',ok));
  const origin='http://127.0.0.1:'+server.address().port;
  const browser=await chromium.launch();
  try {
    async function fixture(fn) {
      const page=await browser.newPage(),observer=new CompanionObserver();
      observer.attach(page,origin+'/publisher');
      try {
        await page.goto(origin);
        const submit=async(body=request)=>{
          const observed=page.waitForRequest(r=>r.method()==='POST'&&r.url()===origin+'/publisher');
          await page.evaluate(body=>{void fetch('/publisher',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)}).then(r=>r.text()).catch(()=>{});},body);
          return observed;
        };
        const state=()=>page.locator('output').innerText();
        const setState=value=>page.locator('output').evaluate((el,value)=>{el.textContent=value;},value);
        let clicks=0;
        const retry=async()=>{await page.getByRole('button',{name:'Retry'}).click();clicks++};
        await fn({page,observer,submit,state,setState,retry,clicks:()=>clicks});
        assert.doesNotMatch(JSON.stringify(observer.evidence(request.base_media_id)),/SECRET|private-upstream-error/);
      } finally {await page.close();}
    }
    const publish=res=>res.writeHead(200,{'content-type':'application/json'}).end(JSON.stringify(success));
    await t.test('real Flutter status scope ignores the offscreen announcement copy',()=>fixture(async f=>{
      const text='الخلفية الأعلى دقة جاهزة: 2560×1920';
      await f.page.setContent('<flt-semantics><span>'+text+'</span></flt-semantics><div style="position:absolute;left:-9999px" aria-live="polite">'+text+'</div>');
      assert.equal(await f.page.getByText(text,{exact:true}).count(),2);
      const marker=companionStatus(f.page);
      assert.equal(await marker.count(),1);assert.ok(await marker.isVisible());
      assert.equal(classifyCompanion(await marker.innerText()),'ready');
      assert.equal(classifyCompanion(text+' لا يتيح الأصل نسخة أكبر'),'unknown');
    }));
    await t.test('ready waits for the exact delayed response; no retry',()=>fixture(async f=>{
      let release;const waiting=new Promise(ok=>release=ok);
      respond=res=>release(res);
      await f.submit();const delayed=await waiting;
      const verification=f.observer.verify(request.base_media_id,f.state,f.retry);
      publish(delayed);
      assert.deepEqual((await verification).body,success);assert.equal(f.clicks(),0);
      assert.equal(f.observer.evidence(request.base_media_id).attempts[0].terminal,'finished');
    }));
    await t.test('HTTP 200 headers followed by cancellation fail closed, without waiting on response.finished()',()=>fixture(async f=>{
      let socket;
      respond=res=>{socket=res.socket;res.writeHead(200,{'content-type':'application/json','content-length':'10000'});res.write('{"padding":"' + '.'.repeat(2048));};
      const headers=f.page.waitForResponse(r=>r.url()===origin+'/publisher');
      const failed=f.page.waitForEvent('requestfailed',{predicate:r=>r.url()===origin+'/publisher'});
      await f.submit();await headers;socket.destroy();await failed;
      await assert.rejects(f.observer.verify(request.base_media_id,f.state,f.retry),/Ready UI requires a readable/);
      const [attempt]=f.observer.evidence(request.base_media_id).attempts;
      assert.deepEqual([attempt.http,attempt.terminal,attempt.body,f.clicks()],[200,'failed','failed-request',0]);
    }));
    await t.test('finished malformed body is unreadable, not a retry or a fabricated success',()=>fixture(async f=>{
      respond=res=>res.writeHead(200,{'content-type':'application/json'}).end('private-upstream-error');
      await f.submit();
      await assert.rejects(f.observer.verify(request.base_media_id,f.state,f.retry),/Ready UI requires a readable/);
      const [attempt]=f.observer.evidence(request.base_media_id).attempts;
      assert.equal(attempt.body,'unreadable');assert.equal(attempt.failure,'invalid-json');assert.equal(f.clicks(),0);
    }));
    await t.test('a valid 200 for another base cannot confirm the saved image',()=>fixture(async f=>{
      respond=res=>res.writeHead(200,{'content-type':'application/json'}).end(JSON.stringify({...success,media:{base_media_id:'SECRET-other-base'}}));
      await f.submit();
      await assert.rejects(f.observer.verify(request.base_media_id,f.state,f.retry),/Ready UI requires a readable/);
      assert.equal(f.observer.evidence(request.base_media_id).attempts[0].responseBaseMatches,false);assert.equal(f.clicks(),0);
    }));
    await t.test('native, unavailable and unknown states never invoke retry',()=>fixture(async f=>{
      respond=publish;await f.submit();
      for(const state of ['native','unavailable','unknown']){
        await f.setState(state);
        await assert.rejects(f.observer.verify(request.base_media_id,f.state,f.retry),/terminal state/);
      }
      assert.equal(f.clicks(),0);
    }));
    for(const identical of [true,false]){
      await t.test(identical?'uncertain retries exactly once with the same identity':'changed replay identity fails even with a published reply',()=>fixture(async f=>{
        respond=res=>res.writeHead(503).end('private-upstream-error');await f.submit();await f.setState('uncertain');
        const retry=async()=>{
          await f.retry();respond=publish;
          await f.submit({...request,request_id:identical?request.request_id:'SECRET-alternate'});
          await f.setState('ready');
        };
        const verification=f.observer.verify(request.base_media_id,f.state,retry);
        if(identical)assert.deepEqual(await verification,{body:success,replayed:true});
        else await assert.rejects(verification,/identical uncertain request/);
        assert.equal(f.clicks(),1);assert.equal(f.observer.evidence(request.base_media_id).sameRequestReplay,identical);
      }));
    }
  } finally {await browser.close();await new Promise(ok=>server.close(ok));}
});
