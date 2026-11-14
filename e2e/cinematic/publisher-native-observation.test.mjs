// UNIT_ONLY observer tests. No browser, HTTP, route, request replay, or application code.
import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { createHash } from 'node:crypto';
import { setImmediate as tick } from 'node:timers/promises';
const require = createRequire(new URL('../package.json', import.meta.url));
const ts = require('typescript');
const source = readFileSync(new URL('./publisher-native-observation.ts', import.meta.url), 'utf8');
const js = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText;
const { observePublisherNative, completeNativeBody } = await import('data:text/javascript;base64,' + Buffer.from(js).toString('base64'));
const API = 'http://127.0.0.1:54321', PATH = '/functions/v1/storefront-media-publish';
const hash = value => createHash('sha256').update(value).digest('hex');
const b64 = value => Buffer.from(value).toString('base64');
const deferred = () => { let resolve, reject; const promise = new Promise((a,b) => { resolve=a; reject=b; }); return { promise, resolve, reject }; };
class Session extends EventEmitter {
  commands=[]; streams=new Map(); detached=0;
  send(name,args) { this.commands.push({name,args}); if(name==='Network.streamResourceContent') { const value=deferred();this.streams.set(args.requestId,value);return value.promise; } return Promise.resolve({}); }
  async detach() {this.detached++;this.emit('close',this);}
}
class Page extends EventEmitter {
  session=new Session(); frame={}; opens=0;
  contextObject=Object.assign(new EventEmitter(), {newCDPSession:async()=>{this.opens++;return this.session;}});
  context() {return this.contextObject;}
  mainFrame() {return this.frame;}
}
async function setup(extra={}) {
 const page=new Page(), observer=await observePublisherNative(page,{apiOrigin:API,expectedSlot:'hero',deadlineAt:Date.now()+5000,...extra});
 return {page,s:page.session,o:observer};
}
function begin(h, {number=1,rung=0,requestId='00000000-0000-4000-8000-000000000001',text,method='POST',url=API+PATH}={}) {
 const body=text??JSON.stringify({request_id:requestId,slot:'hero',rung,source_key:'PRIVATE_ORIGINAL_MARKER'});
 const pw={url:()=>url,method:()=>method,postData:()=>body,failure:()=>({errorText:'net::ERR_ABORTED'})};
 const id='native-private-'+number;
 h.page.emit('request',pw);
 h.s.emit('Network.requestWillBeSent',{requestId:id,frameId:'RAW_PRIVATE_FRAME',loaderId:'RAW_PRIVATE_LOADER',request:{url,method,postData:body,headers:{Authorization:'SECRET_AUTHORIZATION_MARKER'}}});
 const response={request:()=>pw,status:()=>200};
 h.page.emit('response',response);h.s.emit('Network.responseReceived',{requestId:id,response:{status:200,headers:{Authorization:'SECRET_RESPONSE_MARKER'}}});
 return {id,pw,response,body};
}
async function complete(h,r,body={ok:true,status:'published'}, {terminal='finished',prefixSize=0,beforeAck=false,emitPw=true}={}) {
 const bytes=Buffer.isBuffer(body)?body:Buffer.from(JSON.stringify(body));
 const prefix=bytes.subarray(0,prefixSize),chunk=bytes.subarray(prefixSize);
 if(prefix.length)h.s.emit('Network.dataReceived',{requestId:r.id,dataLength:prefix.length,encodedDataLength:prefix.length});
 if(beforeAck&&chunk.length)h.s.emit('Network.dataReceived',{requestId:r.id,dataLength:chunk.length,encodedDataLength:chunk.length,data:b64(chunk)});
 h.s.streams.get(r.id).resolve({bufferedData:b64(prefix)});await tick();
 if(!beforeAck&&chunk.length)h.s.emit('Network.dataReceived',{requestId:r.id,dataLength:chunk.length,encodedDataLength:chunk.length,data:b64(chunk)});
 h.s.emit(terminal==='finished'?'Network.loadingFinished':'Network.loadingFailed',{requestId:r.id,errorText:terminal==='failed'?'net::ERR_ABORTED':undefined,canceled:terminal==='failed'?true:undefined});
 if(emitPw)h.page.emit(terminal==='finished'?'requestfinished':'requestfailed',r.pw);await tick();return bytes;
}
test('actual event reducer keeps prefix and early chunks once, then compares the original parsed object',async()=>{
 const h=await setup();try {const r=begin(h),body={ok:true,status:'published'};const bytes=await complete(h,r,body,{prefixSize:7,beforeAck:true});
 await h.o.assertComplete(r.response,body);const x=h.o.snapshot().requests[0];
 assert.equal(x.bytes,bytes.length);assert.equal(x.digest,hash(bytes));assert.equal(x.nativeBodyComplete,true);assert.equal(x.postDataHash,hash(r.body));assert.equal(x.identityHash,hash('00000000-0000-4000-8000-000000000001'));
 assert.equal(x.playwright.terminal,'finished');assert.equal(x.frame,'f1');assert.equal(x.document,'d1');
 const publicText=JSON.stringify(h.o.snapshot());for(const secret of ['PRIVATE_ORIGINAL_MARKER','SECRET_AUTHORIZATION_MARKER','SECRET_RESPONSE_MARKER','RAW_PRIVATE_FRAME','RAW_PRIVATE_LOADER','native-private-',r.body,JSON.stringify(body)])assert.equal(publicText.includes(secret),false);
 }finally{await h.o.stop();}
});
test('a real native abort remains incomplete even with valid whole JSON and HTTP200',async()=>{
 const h=await setup();try{const r=begin(h),body={ok:true,status:'published'};await complete(h,r,body,{terminal:'failed'});h.o.firstError('publisher-body');h.o.firstError('upload-assertion');h.o.cleanup('upload-finally');
 assert.equal(h.o.snapshot().requests[0].parse,'object');assert.equal(h.o.snapshot().requests[0].nativeBodyComplete,false);
 await assert.rejects(h.o.assertComplete(r.response,body),/request failed; incomplete/);assert.equal(h.o.snapshot().firstError.boundary,'publisher-body');assert.equal(h.o.snapshot().cleanup.boundary,'upload-finally');
 }finally{await h.o.stop();}
});
test('native failure before body observation is not accepted by the completeness validator',()=>{
 assert.equal(completeNativeBody({terminal:'failed',stream:'enabled',problems:[],bytes:12,parse:'object',paired:true}),false);
 assert.equal(completeNativeBody({terminal:'pending',stream:'enabled',problems:[],bytes:12,parse:'object',paired:true}),false);
});
test('the checker waits only for native event completion within the existing deadline',async()=>{
 const h=await setup();try{const r=begin(h),body={ok:true};let done=false;const waiting=h.o.assertComplete(r.response,body).then(()=>{done=true;});await tick();assert.equal(done,false);
 await complete(h,r,body,{emitPw:false});await tick();assert.equal(done,false);h.page.emit('requestfinished',r.pw);await waiting;assert.equal(done,true);
 }finally{await h.o.stop();}
});
test('no data/event byte gap may pass even if retained bytes parse as valid JSON',async()=>{
 const h=await setup();try{const r=begin(h);h.s.emit('Network.dataReceived',{requestId:r.id,dataLength:3,encodedDataLength:3});await complete(h,r,{ok:true});
 assert.ok(h.o.snapshot().requests[0].problems.includes('byte-event-gap'));await assert.rejects(h.o.assertComplete(r.response,{ok:true}),/incomplete/);
 }finally{await h.o.stop();}
});
test('captured actual object must equal the object returned by original response.json',async()=>{
 const h=await setup();try{const r=begin(h);await complete(h,r,{ok:true});await assert.rejects(h.o.assertComplete(r.response,{ok:false}),/mismatch/);
 }finally{await h.o.stop();}
});
test('operation identity hash remains equal but rung/body hashes are distinct and individually paired',async()=>{
 const h=await setup();try{const a=begin(h,{number:1,rung:0}),b=begin(h,{number:2,rung:1});await complete(h,a,{ok:true});await complete(h,b,{ok:true});
 await h.o.assertComplete(a.response,{ok:true});await h.o.assertComplete(b.response,{ok:true});const [x,y]=h.o.snapshot().requests;
 assert.equal(x.identityHash,y.identityHash);assert.notEqual(x.postDataHash,y.postDataHash);assert.equal(x.playwright.sequence,1);assert.equal(y.playwright.sequence,1);
 }finally{await h.o.stop();}
});
test('overlapping identical POST occurrences are ambiguous and cannot pass',async()=>{
 const h=await setup();try{const a=begin(h,{number:1}),b=begin(h,{number:2});await complete(h,a,{ok:true});await complete(h,b,{ok:true});await assert.rejects(h.o.assertComplete(a.response,{ok:true}),/incomplete/);
 assert.equal(h.o.snapshot().requests[1].identitySequence,2);assert.equal(h.o.snapshot().requests[1].playwright.sequence,2);
 }finally{await h.o.stop();}
});
test('native stream command failure is preserved without getResponseBody, retry, or alternate fetch',async()=>{
 const h=await setup();try{const r=begin(h);h.s.streams.get(r.id).reject(new Error('provided ID does not exists PRIVATE_ORIGINAL_MARKER'));await tick();
 assert.equal(h.o.snapshot().requests[0].stream,'missing-resource');await assert.rejects(h.o.assertComplete(r.response,{ok:true}),/incomplete/);
 assert.deepEqual(h.s.commands.map(x=>x.name),['Network.enable','Runtime.enable','Network.streamResourceContent']);assert.equal(JSON.stringify(h.o.snapshot()).includes('PRIVATE_ORIGINAL_MARKER'),false);
 }finally{await h.o.stop();}
});
test('request and byte caps remain hard bounds and do not cancel any application request',async()=>{
 const h=await setup();try{for(let i=1;i<=9;i++)begin(h,{number:i,requestId:`00000000-0000-4000-8000-${String(i).padStart(12,'0')}`});assert.equal(h.o.snapshot().requests.length,8);assert.equal(h.s.commands.filter(x=>x.name==='Network.streamResourceContent').length,8);assert.ok(h.o.snapshot().requestOverflow>0);
 const first=h.o.snapshot().requests[0];assert.equal(first.bytes,0);assert.equal(h.s.detached,0);
 }finally{await h.o.stop();}
 const x=await setup();try{const r=begin(x);x.s.streams.get(r.id).resolve({bufferedData:b64(Buffer.alloc(65536))});await tick();x.s.emit('Network.dataReceived',{requestId:r.id,dataLength:1,encodedDataLength:1,data:b64('x')});
 assert.ok(x.o.snapshot().requests[0].problems.includes('byte-or-chunk-cap'));await assert.rejects(x.o.assertComplete(r.response,{ok:true}),/incomplete/);
 }finally{await x.o.stop();}
});
test('invalid UTF8, non-object JSON, and malformed JSON are not complete evidence',async()=>{
 for(const [bytes,expected] of [[Buffer.from([0xff]),'invalid-utf8'],[Buffer.from('[]'),'non-object'],[Buffer.from('{'),'invalid-json']]){
 const h=await setup();try{const r=begin(h);await complete(h,r,bytes);assert.equal(h.o.snapshot().requests[0].parse,expected);await assert.rejects(h.o.assertComplete(r.response,{}),/incomplete/);}finally{await h.o.stop();}}
});
test('lifecycle and cleanup ordering use local opaque identifiers and remove every listener',async()=>{
 const h=await setup();const r=begin(h);h.s.emit('Runtime.executionContextCreated',{context:{id:99,origin:'PRIVATE_ORIGIN',auxData:{isDefault:true,frameId:'RAW_PRIVATE_FRAME'}}});h.s.emit('Runtime.executionContextDestroyed',{executionContextId:99});h.page.emit('framenavigated',h.page.frame);h.page.emit('framedetached',h.page.frame);h.page.context().emit('close');h.o.firstError('publisher-body');h.o.cleanup('probe-finally');await h.o.stop();await h.o.stop();
 assert.equal(h.page.eventNames().length,0);assert.equal(h.page.context().eventNames().length,0);assert.equal(h.s.eventNames().length,0);assert.equal(h.s.detached,1);assert.ok(h.o.snapshot().events.some(x=>x.event==='default-context-destroyed'));assert.ok(h.o.snapshot().events.some(x=>x.event==='browser-context-close'));assert.ok(h.o.snapshot().events.some(x=>x.event==='main-frame-detached'));assert.equal(JSON.stringify(h.o.snapshot()).includes('PRIVATE_ORIGIN'),false);assert.equal(h.o.snapshot().events.some(x=>x.event==='unexpected-session-close'),false);assert.ok(h.o.snapshot().requests[0].problems.includes('observer-stopped-before-ack'));
});
test('expired observation never enlarges the deadline or produces complete evidence',async()=>{
 let clock=100;const h=await setup({now:()=>clock,deadlineAt:500});try{const r=begin(h);clock=501;h.s.emit('Network.loadingFinished',{requestId:r.id});await assert.rejects(h.o.assertComplete(r.response,{ok:true}),/ended before completeness/);assert.equal(h.o.snapshot().deadlineExceeded,true);assert.equal(h.o.snapshot().requests[0].nativeBodyComplete,false);}finally{await h.o.stop();}
});

test('completed stopped evidence stays unchanged when a later full journey exceeds its upload deadline',async()=>{
 let clock=100;const h=await setup({now:()=>clock,deadlineAt:500});const r=begin(h);await complete(h,r,{ok:true});await h.o.assertComplete(r.response,{ok:true});clock=120;await h.o.stop();const saved=h.o.snapshot();clock=10000;assert.deepEqual(h.o.snapshot(),saved);assert.equal(saved.deadlineExceeded,false);assert.equal(saved.requests[0].nativeBodyComplete,true);
});
