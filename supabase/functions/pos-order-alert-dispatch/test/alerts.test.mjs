import test from "node:test";
import assert from "node:assert/strict";
import { webcrypto } from "node:crypto";
import { createHandler as statusHandler } from "../../pos-order-alert-status/handler.mjs";
import { createHandler as dispatchHandler } from "../handler.mjs";
import { message, send, serviceAccount, accessToken } from "../fcm.mjs";
const PEM_BEGIN = ["-----BEGIN", "PRIVATE KEY-----"].join(" ");
const PEM_END = ["-----END", "PRIVATE KEY-----"].join(" ");
const id = (n) => `71000000-0000-4000-8000-${String(n).padStart(12,"0")}`;
const secret = "a".repeat(64); const worker = "b".repeat(64);
const now = () => Date.parse("2026-10-17T09:00:00Z");
const env = { POS_ORDER_ALERTS_ENABLED: "true", POS_ALERT_PILOT_START_UTC: "2026-10-17T09:00:00Z", POS_ALERT_PILOT_END_UTC: "2026-10-17T09:30:00Z",
  SUPABASE_URL: "https://synthetic.example.test", SUPABASE_SERVICE_ROLE_KEY: "synthetic-server-key",
  POS_ORDER_ALERT_WORKER_SECRET: worker, POS_ORDER_ALERT_FCM_SERVICE_ACCOUNT: JSON.stringify({ type: "service_account", project_id: "synthetic-project",
    client_email: "synthetic@synthetic-project.iam.gserviceaccount.com", private_key: `${PEM_BEGIN}\nSYNTHETIC\n${PEM_END}`, token_uri: "https://oauth2.googleapis.com/token" }) };
const reply = (body,status=200) => new Response(JSON.stringify(body), {status,headers:{"content-type":"application/json"}});
const request = (body={installation_id:id(1)}, path="/pos-order-alert-status", auth=secret) => new Request(`https://synthetic.example.test/functions/v1${path}`, {
  method:"POST", headers:{"authorization":`Bearer ${auth}`,"content-type":"application/json"}, body:JSON.stringify(body) });
const successful = {ok:true,server_time:"2026-10-17T09:00:00Z",registration_id:id(2),authority_expires_at:"2026-10-17T10:00:00Z",requests:[{request_id:id(3),expires_at:"2026-10-17T09:10:00Z"}]};
const delivery = { delivery_id:id(4),lease_id:id(5),registration_id:id(2),generation:id(6),request_id:id(3),kind:"pending",
  fcm_token:"synthetic-fcm-token-123456789",expires_at:"2026-10-17T09:10:00Z",authority_expires_at:"2026-10-17T10:00:00Z" };
const handler = (values=env,fetchImpl=async()=>reply(successful)) => statusHandler({getEnv:(n)=>values[n],fetchImpl,cryptoImpl:webcrypto});
for (const value of [undefined,"false","TRUE","1"]) test(`status default OFF: ${value}`,async()=>{
  let calls=0; const result=await handler({...env,POS_ORDER_ALERTS_ENABLED:value},async()=>{calls++;})(request());
  assert.equal(result.status,503);assert.equal(calls,0);
});
test("status hashes delegated secret, never forwards caller API keys, projects PII away",async()=>{
  let call;const result=await handler(env,async(url,init)=>{call={url,init};return reply({...successful,customer:{phone:"do-not-expose"},requests:[{...successful.requests[0],customer_name:"do-not-expose"}]});})(request());
  assert.equal(result.status,200);assert.deepEqual(await result.json(),successful);
  assert.ok(call.url.endsWith("/rpc/pos_order_alert_status"));const body=JSON.parse(call.init.body);
  assert.notEqual(body.p_status_secret_hash,secret);assert.match(body.p_status_secret_hash,/^[0-9a-f]{64}$/);
  assert.equal(call.init.headers.Authorization,"Bearer synthetic-server-key");
});
for(const auth of ["short",secret.toUpperCase(),"a".repeat(63)]) test(`invalid delegation refused ${auth.length}`,async()=>{
  let calls=0;const result=await handler(env,async()=>{calls++;})(request(undefined,undefined,auth));assert.equal(result.status,401);assert.equal(calls,0);
});
test("foreign browser origin refused without CORS",async()=>{
  const req=request();req.headers.set("origin","https://foreign.example.test");const r=await handler()(req);assert.equal(r.status,403);assert.equal(r.headers.get("access-control-allow-origin"),null);
});
for(const input of [{installation_id:"not-an-id"},{installation_id:id(1),request_id:id(3)},{},[]]) test(`invalid status body ${JSON.stringify(input)}`,async()=>{
  const r=await handler()(request(input));assert.equal(r.status,400);
});
for(const result of [{ok:false,error:"unauthorized"},{...successful,requests:Array.from({length:51},(_,n)=>({request_id:id(100+n),expires_at:"2026-10-17T09:10:00Z"}))},
  {...successful,requests:[successful.requests[0],successful.requests[0]]},{...successful,authority_expires_at:"2026-10-17T08:00:00Z"},
  {...successful,requests:[{request_id:id(3),expires_at:"2026-10-17T08:00:00Z"}]}]) test("status malformed/expired/overflow fails closed",async()=>{
  const r=await handler(env,async()=>reply(result))(request());assert.notEqual(r.status,200);assert.equal((await r.json()).requests,undefined);
});
test("disable works while OFF, exact secret scoped; status path never calls disable",async()=>{
  let url;const r=await handler({...env,POS_ORDER_ALERTS_ENABLED:"false"},async(u)=>{url=u;return reply({ok:true,private:"discard"});})(request(undefined,"/pos-order-alert-status/disable"));
  assert.equal(r.status,200);assert.deepEqual(await r.json(),{ok:true});assert.ok(url.endsWith("/rpc/pos_disable_order_alert"));
});
test("status rejects unknown path/query and never sends upstream",async()=>{
  let calls=0;for(const path of ["/unknown","/pos-order-alert-status?secret=wrong"]){const r=await handler(env,async()=>{calls++;})(request(undefined,path));assert.equal(r.status,404);}assert.equal(calls,0);
});
test("status network uncertainty has no sensitive diagnostics",async()=>{
  const r=await handler(env,async()=>{throw new Error("secret private phone token");})(request());assert.equal(r.status,503);assert.deepEqual(await r.json(),{ok:false,error:"unavailable"});
});
test("FCM payload is opaque, high priority, bounded TTL and no notification PII",()=>{
  const p=message(delivery,now());assert.deepEqual(Object.keys(p.message.data).sort(),["expires_at","kind","registration_id","request_id","version"]);
  assert.equal(p.message.android.priority,"HIGH");assert.equal(p.message.android.ttl,"120s");assert.equal(p.message.notification,undefined);
  assert.equal(message({...delivery,expires_at:"2026-10-17T08:00:00Z"},now()),null);
  const cancel=message({...delivery,kind:"terminal",expires_at:"2026-10-17T08:00:00Z"},now());assert.equal(cancel.message.data.kind,"cancel");assert.equal(cancel.message.android.ttl,"60s");
});
test("FCM TTL never extends authority or request expiry",()=>{
  assert.equal(message({...delivery,expires_at:"2026-10-17T09:00:07Z"},now()).message.android.ttl,"7s");
  assert.equal(message({...delivery,authority_expires_at:"2026-10-17T09:00:02Z"},now()).message.android.ttl,"2s");
});
for (const terminalExpiry of ["2026-10-17T09:10:00Z", "2026-10-17T08:59:00Z"]) {
  test(`closed/offline tablet retains pending B after accepted/expired A signal (${terminalExpiry})`, () => {
    // FCM retains only the latest undelivered message for each collapse key.
    // Exercise the REAL payload constructor at the offline-delivery boundary,
    // including the expired cancellation that a stopped native client ignores.
    const waiting = new Map();
    const pendingB = message({ ...delivery, request_id: id(20) }, now()).message;
    const terminalA = message({ ...delivery, request_id: id(21), kind: "terminal", expires_at: terminalExpiry }, now()).message;
    for (const item of [pendingB, terminalA]) waiting.set(item.android.collapse_key, item);
    const delivered = [...waiting.values()];
    const actionableWake = delivered.filter((item) => item.data.kind === "pending" && Date.parse(item.data.expires_at) > now());
    assert.equal(actionableWake.length, 1);
    assert.equal(actionableWake[0].data.request_id, id(20));
    assert.equal(actionableWake[0].android.priority, "HIGH");
    assert.equal(delivered.length, 2);
    assert.ok(delivered.every((item) => item.notification === undefined));
  });
}
for(const [code,status,expected] of [["UNREGISTERED",404,"invalid_token"],["QUOTA_EXCEEDED",429,"retry"],[null,503,"retry"],["INVALID_ARGUMENT",400,"permanent_failure"]]) test(`FCM ${status}/${code}`,async()=>{
  const outcome=await send(serviceAccount(env.POS_ORDER_ALERT_FCM_SERVICE_ACCOUNT),"synthetic-access-token",delivery,{now,timeoutMs:1000,fetchImpl:async()=>reply({error:{details:[{"@type":"type.googleapis.com/google.firebase.fcm.v1.FcmError",errorCode:code}]}},status)});assert.equal(outcome,expected);
});
test("FCM success checks response identity; unknown success only retries hint",async()=>{
  const account=serviceAccount(env.POS_ORDER_ALERT_FCM_SERVICE_ACCOUNT);
  assert.equal(await send(account,"synthetic-token",delivery,{now,fetchImpl:async()=>reply({name:"projects/synthetic-project/messages/123"})}),"sent");
  assert.equal(await send(account,"synthetic-token",delivery,{now,fetchImpl:async()=>reply({})}),"retry");
});
const dispatch=(values=env,fetchImpl=async()=>reply({ok:true,deliveries:[]}))=>dispatchHandler({getEnv:n=>values[n],fetchImpl,cryptoImpl:webcrypto,now,tokenProvider:async()=>"synthetic-access-token"});
for(const values of [{...env,POS_ORDER_ALERTS_ENABLED:undefined},{...env,POS_ORDER_ALERT_WORKER_SECRET:undefined}]) test("private worker default OFF/missing authority does no HTTP",async()=>{
  let calls=0;const r=await dispatch(values,async()=>{calls++;})(request({},"/pos-order-alert-dispatch",worker));assert.notEqual(r.status,200);assert.equal(calls,0);
});
test("worker claims and finishes sequentially, exposes counts only, no order/print API",async()=>{
  const calls=[];const r=await dispatch(env,async(url,init)=>{calls.push({url,body:JSON.parse(init.body)});
    if(url.endsWith("/pos_claim_order_alert_deliveries"))return reply({ok:true,deliveries:[delivery]});
    if(url.includes("fcm.googleapis.com"))return reply({name:"projects/synthetic-project/messages/123"});
    if(url.endsWith("/pos_finish_order_alert_delivery"))return reply({ok:true});throw new Error("Unexpected API");})(request({},"/pos-order-alert-dispatch",worker));
  assert.equal(r.status,200);assert.deepEqual(await r.json(),{ok:true,sent:1,deferred:0});assert.equal(calls.length,3);
  assert.equal(calls[2].body.p_outcome,"sent");assert.ok(calls.every(c=>!/(accept_web_order|print|submit_web_order)/.test(c.url)));
});
test("unknown FCM send becomes bounded retry, never another order",async()=>{
  let outcome;const r=await dispatch(env,async(url,init)=>{
    if(url.endsWith("/pos_claim_order_alert_deliveries"))return reply({ok:true,deliveries:[delivery]});
    if(url.includes("fcm.googleapis.com"))throw new Error("unknown outcome");
    outcome=JSON.parse(init.body).p_outcome;return reply({ok:true});})(request({},"/pos-order-alert-dispatch",worker));
  assert.equal(r.status,200);assert.equal(outcome,"retry");
});
test("malicious OAuth token URI/project/email configuration fails closed",()=>{
  const valid=JSON.parse(env.POS_ORDER_ALERT_FCM_SERVICE_ACCOUNT);
  for(const value of [{...valid,token_uri:"https://foreign.test/token"},{...valid,project_id:"../../escape"},{...valid,client_email:"x@foreign.test"}])assert.equal(serviceAccount(JSON.stringify(value)),null);
});
test("OAuth signs scoped short-lived assertion using only server credentials",async()=>{
  const pair=await webcrypto.subtle.generateKey({name:"RSASSA-PKCS1-v1_5",modulusLength:2048,publicExponent:new Uint8Array([1,0,1]),hash:"SHA-256"},true,["sign","verify"]);
  const raw=await webcrypto.subtle.exportKey("pkcs8",pair.privateKey);const pem=`${PEM_BEGIN}\n${Buffer.from(raw).toString("base64")}\n${PEM_END}`;
  let assertion;const token=await accessToken({projectId:"synthetic-project",email:"synthetic@synthetic-project.iam.gserviceaccount.com",privateKey:pem},{now,cryptoImpl:webcrypto,timeoutMs:1000,fetchImpl:async(url,init)=>{
    assert.equal(url,"https://oauth2.googleapis.com/token");assertion=new URLSearchParams(init.body).get("assertion");return reply({access_token:"synthetic-access-token-123456",token_type:"Bearer",expires_in:3600});
  }});
  const [header,body,sig]=assertion.split(".");const claims=JSON.parse(Buffer.from(body,"base64url"));assert.equal(claims.exp-claims.iat,3600);assert.equal(claims.scope,"https://www.googleapis.com/auth/firebase.messaging");
  assert.equal(await webcrypto.subtle.verify("RSASSA-PKCS1-v1_5",pair.publicKey,Buffer.from(sig,"base64url"),new TextEncoder().encode(`${header}.${body}`)),true);assert.match(token,/synthetic/);
});
