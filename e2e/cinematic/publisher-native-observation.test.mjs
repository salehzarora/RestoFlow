// UNIT_ONLY observer tests. No browser, HTTP, route, request replay, or application code.
import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { createHash, webcrypto } from 'node:crypto';
import { runInNewContext } from 'node:vm';
import { setImmediate as tick } from 'node:timers/promises';
const require = createRequire(new URL('../package.json', import.meta.url));
const ts = require('typescript');
const source = readFileSync(new URL('./publisher-native-observation.ts', import.meta.url), 'utf8');
const js = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText;
const { observePublisherNative, completeNativeBody, installPublisherClientLifecycle, projectPublisherClientLifecycle } = await import('data:text/javascript;base64,' + Buffer.from(js).toString('base64'));
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


// BIZBOT-STOREFRONT-WELCOME-EDITOR-001: the same passive reducer for one exact
// welcome-video kind. Existing image tests above remain unchanged.
const videoRequest = (extra = {}) => JSON.stringify({kind:'welcome_video_v1',
 request_id:'00000000-0000-4000-8000-000000000001',organization_id:'PRIVATE_ORGANIZATION_MARKER',
 restaurant_id:'PRIVATE_RESTAURANT_MARKER',source_key:'PRIVATE_VIDEO_ORIGINAL_MARKER',...extra});
const setupVideo = () => setup({expectedSlot:undefined,expectedKind:'welcome_video_v1'});

test('exact welcome-video kind uses the same original-body correlation without inventing an image slot',async()=>{
 const h=await setupVideo();try{
  const r=begin(h,{text:videoRequest()}),body={ok:true,status:'published',kind:'welcome_video_v1'};
  const bytes=await complete(h,r,body,{prefixSize:7,beforeAck:true});await h.o.assertComplete(r.response,body);
  const x=h.o.snapshot().requests[0];assert.equal(x.kind,'welcome_video_v1');assert.equal('slot' in x,false);
  assert.equal(x.bytes,bytes.length);assert.equal(x.digest,hash(bytes));assert.equal(x.nativeBodyComplete,true);
  assert.equal(x.identityHash,hash('00000000-0000-4000-8000-000000000001'));assert.equal(x.postDataHash,hash(r.body));
  assert.equal(x.playwright.terminal,'finished');assert.equal(x.frame,'f1');assert.equal(x.document,'d1');
  const publicText=JSON.stringify(h.o.snapshot());
  for(const secret of ['PRIVATE_VIDEO_ORIGINAL_MARKER','PRIVATE_ORGANIZATION_MARKER','PRIVATE_RESTAURANT_MARKER',r.body,JSON.stringify(body),'SECRET_AUTHORIZATION_MARKER'])assert.equal(publicText.includes(secret),false);
 }finally{await h.o.stop();}
});
test('video mode rejects unknown kinds, image slots and noncanonical request identities',async()=>{
 const h=await setupVideo();try{
  const values=[videoRequest({kind:'welcome_video_v2'}),videoRequest({kind:null}),videoRequest({slot:'hero'}),
   videoRequest({slot:null}),videoRequest({request_id:'not-a-uuid'}),videoRequest({request_id:'00000000-0000-4000-8000-00000000000A'}),
   JSON.stringify({request_id:'00000000-0000-4000-8000-000000000001',slot:'hero'})];
  for(let index=0;index<values.length;index++){
   const r=begin(h,{number:index+1,text:values[index]});await assert.rejects(h.o.assertComplete(r.response,{ok:true}),/uncorrelated/);
  }
  assert.equal(h.o.snapshot().requests.length,0);assert.equal(h.o.snapshot().invalidIdentity,values.length*2);
  assert.deepEqual(h.s.commands.map(value=>value.name),['Network.enable','Runtime.enable']);
 }finally{await h.o.stop();}
});
test('an image observer never accepts a mixed kind/slot payload or a video-kind request',async()=>{
 const h=await setup();try{
  for(const [index,text]of[videoRequest(),videoRequest({slot:'hero'}),videoRequest({kind:'unrecognized',slot:'hero'})].entries()){
   const r=begin(h,{number:index+1,text});await assert.rejects(h.o.assertComplete(r.response,{ok:true}),/uncorrelated/);
  }
  assert.equal(h.o.snapshot().requests.length,0);
  const valid=begin(h,{number:4});await complete(h,valid,{ok:true});await h.o.assertComplete(valid.response,{ok:true});
  const image=h.o.snapshot().requests[0];assert.equal(image.slot,'hero');assert.equal('kind' in image,false);
  assert.equal(image.identityHash,hash('00000000-0000-4000-8000-000000000001'));assert.equal(image.postDataHash,hash(valid.body));
 }finally{await h.o.stop();}
});
test('mutually exclusive slot/kind options and unknown option kinds fail before opening a native session',async()=>{
 for(const extra of [{expectedSlot:'hero',expectedKind:'welcome_video_v1'},{expectedKind:'welcome_video_v2'},{expectedKind:null}]){
  const page=new Page();await assert.rejects(observePublisherNative(page,{apiOrigin:API,deadlineAt:Date.now()+5000,...extra}),/Invalid bounded/);
  assert.equal(page.opens,0);assert.equal(page.session.commands.length,0);
 }
});
test('a welcome-video native abort remains failure despite HTTP200 and a captured complete JSON object',async()=>{
 const h=await setupVideo();try{
  const r=begin(h,{text:videoRequest()}),body={ok:true,status:'published',kind:'welcome_video_v1'};
  await complete(h,r,body,{terminal:'failed'});h.o.firstError('publisher-body');h.o.cleanup('upload-finally');
  const x=h.o.snapshot().requests[0];assert.equal(x.http,200);assert.equal(x.parse,'object');assert.equal(x.nativeBodyComplete,false);
  assert.equal(x.failureCode,'net::ERR_ABORTED');await assert.rejects(h.o.assertComplete(r.response,body),/request failed; incomplete/);
 }finally{await h.o.stop();}
});
test('a truncated welcome-video native JSON body cannot substitute for the original response object',async()=>{
 const h=await setupVideo();try{
  const r=begin(h,{text:videoRequest()});await complete(h,r,Buffer.from('{"ok":true,"status":'));
  const x=h.o.snapshot().requests[0];assert.equal(x.terminal,'finished');assert.equal(x.parse,'invalid-json');assert.equal(x.nativeBodyComplete,false);
  await assert.rejects(h.o.assertComplete(r.response,{ok:true,status:'published',kind:'welcome_video_v1'}),/mismatch or incomplete/);
  assert.deepEqual(h.s.commands.map(value=>value.name),['Network.enable','Runtime.enable','Network.streamResourceContent']);
 }finally{await h.o.stop();}
});

// Execute the exact serialized probe installer without a browser or network.
function clientRealm() {
 const calls=[],digests=[],timers=new Map();let next=Promise.resolve(null),throwFetch=null,timerSequence=0;
 class Reader {
  readCalls=[];cancelCalls=[];readResults=[];cancelPromise=Promise.resolve(undefined);
  read(...args){this.readCalls.push({receiver:this,args});if(this.readThrow)throw this.readThrow;return this.readResults.shift()??Promise.resolve({done:true,value:undefined});}
  cancel(...args){this.cancelCalls.push({receiver:this,args});if(this.cancelThrow)throw this.cancelThrow;this.onCancel?.();return this.cancelPromise;}
 }
 class Stream { constructor(reader){this.reader=reader;this.calls=[];}getReader(...args){this.calls.push({receiver:this,args});return this.reader;} }
 class NativeResponse { constructor(body){this.originalBody=body;this.bodyGets=0;}get body(){this.bodyGets++;if(this.bodyThrow)throw this.bodyThrow;return this.originalBody;}json(){throw new Error('Observer must not call original json');} }
 const originalFetch=function(...args){calls.push({receiver:this,args});if(throwFetch)throw throwFetch;return next;};
 const realm={location:{origin:'http://127.0.0.1:57026'},fetch:originalFetch,Response:NativeResponse,ReadableStream:Stream,
  ReadableStreamDefaultReader:Reader,AbortSignal,Promise,Uint8Array,TextEncoder,TextDecoder,Date,Error,
  crypto:{subtle:{digest(...args){const p=webcrypto.subtle.digest(...args);digests.push(p);return p;}}},
  setTimeout(fn){const key=++timerSequence;timers.set(key,fn);return key;},clearTimeout(key){timers.delete(key);}};
 realm.window=realm;realm.top=realm;
 const install=runInNewContext('('+installPublisherClientLifecycle.toString()+')',realm);
 const body=JSON.stringify({request_id:'00000000-0000-4000-8000-000000000001',slot:'hero',source_key:'PRIVATE_SOURCE_NEVER_EXPORT'});
 return {realm,install,calls,timers,originalFetch,Reader,Stream,NativeResponse,body,
  init:signal=>({method:'POST',body:new TextEncoder().encode(body),signal}),
  setNext:p=>{next=p;throwFetch=null;},setThrow:e=>{throwFetch=e;},
  start:()=>install({began:Date.now(),deadlineAt:Date.now()+5000}),
  control:()=>realm.__cinematicPublisherLifecycleProbe,
  flush:async()=>{await Promise.all(digests);await tick();}};
}
test('probe decorators retain original native Promise/Response/body/reader/result identities, this, arguments and one actual read',async()=>{
 const h=clientRealm(),fetchGate=deferred(),readGate=deferred(),controller=new AbortController(),reader=new h.Reader(),stream=new h.Stream(reader),response=new h.NativeResponse(stream);
 const receiver={opaque:true},readArg={opaqueReadArgument:true},getArg={opaqueReaderArgument:true};reader.readResults.push(readGate.promise);h.setNext(fetchGate.promise);
 const fetchDescriptor=Object.getOwnPropertyDescriptor(h.realm,'fetch');assert.equal(h.start().status,'INSTALLED');
 const init=h.init(controller.signal),fetched=h.realm.fetch.call(receiver,API+PATH,init);
 assert.equal(fetched,fetchGate.promise);assert.equal(h.calls.length,1);assert.equal(h.calls[0].receiver,receiver);assert.equal(h.calls[0].args[1],init);
 fetchGate.resolve(response);assert.equal(await fetched,response);assert.equal(response.bodyGets,0,'No observer body access');assert.equal(response.json,h.NativeResponse.prototype.json);
 assert.equal(response.body,stream);assert.equal(response.bodyGets,1);assert.equal(stream.getReader(getArg),reader);assert.equal(stream.calls[0].args[0],getArg);
 const read=reader.read(readArg);assert.equal(read,readGate.promise);assert.equal(reader.readCalls.length,1);assert.equal(reader.readCalls[0].receiver,reader);assert.equal(reader.readCalls[0].args[0],readArg);
 const chunk=new Uint8Array([1,2,3]),result={done:false,value:chunk};readGate.resolve(result);assert.equal(await read,result);assert.equal(result.value,chunk);
 const done={done:true,value:undefined};reader.readResults.push(Promise.resolve(done));assert.equal(await reader.read(),done);await h.flush();
 const foreignReader=new h.Reader(),foreignStream=new h.Stream(foreignReader),foreignResponse=new h.NativeResponse(foreignStream),foreignPromise=Promise.resolve(done),foreignArg={borrowed:true};
 foreignReader.readResults.push(foreignPromise);assert.equal(reader.read.call(foreignReader,foreignArg),foreignPromise);assert.equal(foreignReader.readCalls[0].receiver,foreignReader);assert.equal(foreignReader.readCalls[0].args[0],foreignArg);
 assert.equal(stream.getReader.call(foreignStream,foreignArg),foreignReader);assert.equal(foreignStream.calls[0].args[0],foreignArg);assert.equal(Object.hasOwn(foreignReader,'read'),false);
 assert.equal(Object.getOwnPropertyDescriptor(response,'body').get.call(foreignResponse),foreignStream);assert.equal(Object.hasOwn(foreignResponse,'body'),false);
 const raw=h.control().stop(),proof=projectPublisherClientLifecycle(raw);assert.equal(proof.status,'OBSERVED');assert.equal(proof.records[0].identityHash,hash('00000000-0000-4000-8000-000000000001'));assert.equal(proof.records[0].postDataHash,hash(h.body));
 assert.deepEqual(Array.from(proof.records[0].events.filter(e=>e.event==='read-fulfilled'),e=>[e.done,e.bytes]),[[false,3],[true,0]]);
 assert.deepEqual(Object.getOwnPropertyDescriptor(h.realm,'fetch'),fetchDescriptor);assert.equal(h.control(),undefined);assert.equal(h.timers.size,0);
 for(const [object,key]of[[response,'body'],[stream,'getReader'],[reader,'read'],[reader,'cancel']])assert.equal(Object.hasOwn(object,key),false,'Original property absence is restored');
 assert.equal(reader.readCalls.length,2,'Only the two application reads occurred');
 for(const secret of ['PRIVATE_SOURCE_NEVER_EXPORT',h.body,'authorization','access_token'])assert.equal(JSON.stringify(proof).includes(secret),false);
});
test('probe observations distinguish original signal abort, reader cancel and rejected native promises without replacing errors',async()=>{
 const h=clientRealm(),controller=new AbortController(),reader=new h.Reader(),stream=new h.Stream(reader),response=new h.NativeResponse(stream),failure=new Error('PRIVATE_ERROR_VALUE');
 h.setNext(Promise.resolve(response));h.start();await h.realm.fetch(API+PATH,h.init(controller.signal));response.body.getReader();
 const readGate=deferred();reader.readResults.push(readGate.promise);const read=reader.read();readGate.reject(failure);await assert.rejects(read,error=>error===failure);
 reader.onCancel=()=>controller.abort('PRIVATE_ABORT_REASON');const cancelGate=deferred();reader.cancelPromise=cancelGate.promise;
 const reason={privateReason:'DO_NOT_EXPORT'},cancel=reader.cancel(reason);assert.equal(cancel,cancelGate.promise);assert.equal(reader.cancelCalls[0].args[0],reason);
 cancelGate.reject(failure);await assert.rejects(cancel,error=>error===failure);
 reader.readThrow=failure;assert.throws(()=>reader.read(),error=>error===failure);reader.cancelThrow=failure;assert.throws(()=>reader.cancel(),error=>error===failure);
 response.bodyThrow=failure;assert.throws(()=>response.body,error=>error===failure);
 await h.flush();const proof=projectPublisherClientLifecycle(h.control().stop()),events=proof.records[0].events;
 assert(events.some(e=>e.event==='read-rejected'));assert(events.some(e=>e.event==='read-throw'));assert(events.some(e=>e.event==='cancel-rejected'));assert(events.some(e=>e.event==='cancel-throw'));
 assert(events.findIndex(e=>e.event==='cancel-call')<events.findIndex(e=>e.event==='signal-abort'),'Cancel invocation is recorded before the native synchronous abort callback');
 assert.equal(events.filter(e=>e.event==='signal-abort').length,1);
 assert.equal(events.find(e=>e.event==='signal-abort').signalAborted,true);
 for(const secret of ['PRIVATE_ERROR_VALUE','PRIVATE_ABORT_REASON','DO_NOT_EXPORT',h.body])assert.equal(JSON.stringify(proof).includes(secret),false);
 assert.equal(h.realm.fetch,h.originalFetch);assert.equal(Object.hasOwn(response,'body'),false);assert.equal(Object.hasOwn(reader,'read'),false);
 const x=clientRealm(),fetchError=new TypeError('PRIVATE_FETCH_ERROR');x.start();x.setThrow(fetchError);assert.throws(()=>x.realm.fetch(API+PATH,x.init(new AbortController().signal)),error=>error===fetchError);x.control().stop();
 const y=clientRealm(),fetchGate=deferred();y.setNext(fetchGate.promise);y.start();const original=y.realm.fetch(API+PATH,y.init(new AbortController().signal));assert.equal(original,fetchGate.promise);fetchGate.reject(fetchError);await assert.rejects(original,error=>error===fetchError);await y.flush();assert(y.control().stop().records[0].events.some(e=>e.event==='fetch-rejected'));
});
test('signal call sites expose only exact owned compiled-script coordinates and never its URL, argument or stack',async()=>{
 const h=clientRealm(),controller=new AbortController();h.realm.controller=controller;h.setNext(Promise.resolve(null));h.start();
 await h.realm.fetch(API+PATH,h.init(controller.signal));runInNewContext("controller.abort('PRIVATE_REASON')",h.realm,{filename:'http://127.0.0.1:57026/main.dart.js'});await h.flush();
 const proof=projectPublisherClientLifecycle(h.control().stop()),event=proof.records[0].events.find(e=>e.event==='signal-abort');
 assert.equal(event.signalAborted,true);assert(event.sites.some(s=>s.kind==='dashboard-main'&&s.line===1&&Number.isInteger(s.column)));
 for(const forbidden of ['http://','main.dart.js','PRIVATE_REASON','stack'])assert.equal(JSON.stringify(proof).includes(forbidden),false);
});
test('probe stack projection bounds actual listener inspection to8192characters,32lines andfour owned coordinates',async()=>{
 const owned=n=>` at http://127.0.0.1:57026/main.dart.js:${n}:2`;
 for(const [stack,expected]of[['x'.repeat(8192)+'\n'+owned(99),[]],
  [Array(32).fill('PRIVATE_UNOWNED_LINE').join('\n')+'\n'+owned(99),[]],
  [Array.from({length:8},(_,i)=>owned(i+1)).join('\n'),[1,2,3,4]]]){
  const h=clientRealm(),controller=new AbortController();h.realm.Error=class{constructor(){this.stack=stack;}};
  h.setNext(Promise.resolve(null));h.start();await h.realm.fetch(API+PATH,h.init(controller.signal));controller.abort();await h.flush();
  const proof=projectPublisherClientLifecycle(h.control().stop()),event=proof.records[0].events.find(e=>e.event==='signal-abort');
  assert.deepEqual(Array.from(event.sites.filter(s=>s.kind==='dashboard-main'),s=>s.line),expected);
  assert.equal(JSON.stringify(proof).includes('PRIVATE_UNOWNED_LINE'),false);
 }
});
test('unrelated calls and unsupported getters are not inspected, consumed, replayed or decorated',async()=>{
 const h=clientRealm(),sentinel={},headers={};let bodyGets=0,headerGets=0;h.setNext(sentinel);h.start();
 Object.defineProperty(headers,'Authorization',{get(){headerGets++;throw new Error('DO_NOT_READ');}});
 const init={method:'POST',headers};Object.defineProperty(init,'body',{get(){bodyGets++;throw new Error('DO_NOT_READ');}});
 assert.equal(h.realm.fetch(API+'/auth/v1/token',init),sentinel);assert.equal(h.realm.fetch(API+'/storage/v1/object/private',init),sentinel);
 assert.equal(bodyGets,0);assert.equal(headerGets,0);assert.equal(h.control().snapshot().records.length,0);
 assert.equal(h.realm.fetch(API+PATH,init),sentinel);assert.equal(bodyGets,0);assert.equal(headerGets,0);assert.equal(h.calls.length,3);
 const facts=h.control().stop();assert.equal(facts.status,'UNAVAILABLE');assert.equal(h.realm.fetch,h.originalFetch);
 const wrong=clientRealm();wrong.realm.location.origin='https://external.test';assert.equal(wrong.start().status,'UNAVAILABLE');assert.equal(wrong.realm.fetch,wrong.originalFetch);assert.equal(wrong.control(),undefined);
 const child=clientRealm();child.realm.top={};assert.equal(child.start().status,'UNAVAILABLE');assert.equal(child.realm.fetch,child.originalFetch);
});
test('oversized string and binary inputs or body accessors return the original native value without extra encode or inspection',()=>{
 const h=clientRealm(),sentinel={},encodedLengths=[];let bodyReads=0;
 h.realm.TextEncoder=class extends TextEncoder{encode(value){encodedLengths.push(value.length);return super.encode(value);}};
 h.setNext(sentinel);h.start();
 assert.equal(h.realm.fetch(API+PATH,{method:'POST',body:'x'.repeat(4097)}),sentinel);
 assert.equal(h.realm.fetch(API+PATH,{method:'POST',body:new Uint8Array(4097)}),sentinel);
 const accessor={method:'POST'};Object.defineProperty(accessor,'body',{get(){bodyReads++;throw new Error('DO_NOT_INSPECT');}});
 assert.equal(h.realm.fetch(API+PATH,accessor),sentinel);assert.equal(bodyReads,0);assert.deepEqual(encodedLengths,[]);
 assert.equal(h.realm.fetch(API+PATH,{method:'POST',body:'ش'.repeat(4096)}),sentinel);
 assert.deepEqual(encodedLengths,[4096],'The post-encoding byte cap still rejects a within-character-limit multibyte input');
 const proof=projectPublisherClientLifecycle(h.control().stop());assert.equal(proof.records.length,0);assert.equal(proof.status,'UNAVAILABLE');assert.equal(h.calls.length,4);assert.equal(h.realm.fetch,h.originalFetch);
});
test('probe limits, automatic expiry and public projection preserve bounded scalar diagnostics and exact cleanup',async()=>{
 const h=clientRealm(),reader=new h.Reader(),stream=new h.Stream(reader),response=new h.NativeResponse(stream),controller=new AbortController();h.setNext(Promise.resolve(response));h.start();
 for(let i=0;i<9;i++)await h.realm.fetch(API+PATH,h.init(controller.signal));
 response.body.getReader();const reads=[];for(let i=0;i<150;i++){reader.readResults.push(Promise.resolve({done:false,value:new Uint8Array(1)}));reads.push(reader.read());}await Promise.all(reads);await h.flush();
 const control=h.control();for(const expire of [...h.timers.values()])expire();const raw=control.snapshot(),proof=projectPublisherClientLifecycle(raw);
 assert.equal(proof.records.length,8);assert(proof.overflow>0);assert(proof.records.reduce((n,r)=>n+r.events.length,0)<=128);assert.equal(proof.status,'PARTIAL');
 assert.equal(proof.stopped,true);assert.equal(h.control(),undefined);assert.equal(h.realm.fetch,h.originalFetch);assert.equal(Object.hasOwn(reader,'read'),false);assert.equal(h.timers.size,0);
 const changed=structuredClone(proof);changed.authorization='PRIVATE_TOKEN';changed.records[0].body='PRIVATE_JSON';changed.records[0].events.push({event:'read-rejected',ms:1,errorClass:'PRIVATE_ERROR',sites:[{kind:'PRIVATE_URL',line:1,column:1}],rawStack:'PRIVATE_STACK'});
 const safe=JSON.stringify(projectPublisherClientLifecycle(changed));for(const secret of ['PRIVATE_TOKEN','PRIVATE_JSON','PRIVATE_ERROR','PRIVATE_URL','PRIVATE_STACK'])assert.equal(safe.includes(secret),false);
 assert.deepEqual(projectPublisherClientLifecycle({status:'OBSERVED',records:Array(9).fill({})}),{status:'UNAVAILABLE'});
});
test('only explicit probe opt-in evaluates the one existing CDP main context and restores it before detach',async()=>{
 const h=clientRealm(),page=new Page(),baseSend=page.session.send.bind(page.session);
 page.session.send=function(name,args){
  if(name==='Runtime.enable'){this.commands.push({name,args});this.emit('Runtime.executionContextCreated',{context:{id:7,auxData:{isDefault:true,frameId:'MAIN'}}});this.emit('Runtime.executionContextCreated',{context:{id:9,auxData:{isDefault:true,frameId:'CHILD'}}});return Promise.resolve({});}
  if(name==='Page.getFrameTree'){this.commands.push({name,args});return Promise.resolve({frameTree:{frame:{id:'MAIN'}}});}
  if(name==='Runtime.evaluate'){this.commands.push({name,args});assert.equal(args.contextId,7);return Promise.resolve({result:{value:runInNewContext(args.expression,h.realm)}});}
  return baseSend(name,args);
 };
 const observer=await observePublisherNative(page,{apiOrigin:API,expectedSlot:'hero',deadlineAt:Date.now()+5000,clientLifecycleProbe:true});
 assert.equal(page.opens,1);assert.equal(observer.snapshot().clientLifecycle.status,'INSTALLED');assert.notEqual(h.realm.fetch,h.originalFetch);
 await observer.stop();assert.equal(h.realm.fetch,h.originalFetch);assert.equal(h.control(),undefined);assert.equal(page.session.detached,1);
 assert.equal(page.session.commands.filter(c=>c.name==='Runtime.evaluate').length,2);assert.equal(observer.snapshot().clientLifecycle.stopped,true);
 const ordinary=await setup();assert.equal(ordinary.s.commands.some(c=>c.name==='Runtime.evaluate'||c.name==='Page.getFrameTree'),false);assert.equal('clientLifecycle'in ordinary.o.snapshot(),false);await ordinary.o.stop();
 const spec=readFileSync(new URL('./dashboard.spec.ts',import.meta.url),'utf8');assert.equal((spec.match(/upload\(page, 'publisher-native-probe\.png', diagnostics, 200, 'banner', bytes, true\)/g)??[]).length,1);
});
