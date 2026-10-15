// BIZBOT-POS-LEGACY-PRINT-CONTAINMENT-001: real lock races, disposable localhost database only.
// node <this file> --psql /absolute/path/to/psql \
//   --port 55439 --template containment_001 --expected-data-dir /isolated/postgres/data
// WORK-ID in the data directory's parent must contain this exact work item.
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { basename, dirname, isAbsolute, resolve } from "node:path";
import { createInterface } from "node:readline";


const args = process.argv.slice(2);
assert.equal(args.length, 8);
assert.equal(args[0], "--psql"); assert.equal(args[2], "--port"); assert.equal(args[4], "--template");
assert.equal(args[6], "--expected-data-dir");
const [psql, port, template] = [args[1], args[3], args[5]];
const normalize = (p) => process.platform === "win32" ? resolve(p).toLowerCase() : resolve(p);
const expectedData = args[7];
assert.ok(isAbsolute(psql)); assert.match(basename(psql), /^psql(?:\.exe)?$/i);
assert.ok(isAbsolute(expectedData));
assert.match(port, /^[0-9]{1,5}$/); assert.ok(Number(port) > 0 && Number(port) <= 65535);
assert.match(template, /^containment_001(?:_[a-zA-Z0-9_]+)?$/);
assert.equal((await readFile(resolve(dirname(expectedData), "WORK-ID"), "utf8")).trim(), "BIZBOT-POS-LEGACY-PRINT-CONTAINMENT-001");
const database = `containment_001_concurrency_${process.pid}_${Date.now()}`;
const lit = (v) => `'${String(v).replaceAll("'", "''")}'`;
function id(label) {
  const h = createHash("md5").update(`pos-online-inbox-001-${label}`).digest("hex");
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
}
const connectionArgs = (db) => ["-X", "-qAt", "--no-password", "--host=127.0.0.1", `--port=${port}`,
  "--username=postgres", `--dbname=${db}`, "--set=ON_ERROR_STOP=1"];
const sessions = new Set();
function sql(text, db = database) {
  return new Promise((resolveQuery, reject) => {
    const child = spawn(psql, connectionArgs(db), { stdio: ["pipe", "pipe", "pipe"], shell: false });
    let out = "", err = "";
    const timer = setTimeout(() => { child.kill(); reject(new Error("Local SQL command timed out")); }, 30_000);
    child.stdout.setEncoding("utf8").on("data", (x) => { out += x; });
    child.stderr.setEncoding("utf8").on("data", (x) => { err += x; });
    child.on("error", (e) => { clearTimeout(timer); reject(e); });
    child.on("close", (code) => { clearTimeout(timer); code === 0 ? resolveQuery(out.trim()) : reject(new Error(err.trim())); });
    child.stdin.on("error", () => {}); child.stdin.end(text);
  });
}
class Session {
  constructor(name) {
    this.name = name; this.pending = null; this.sequence = 0; this.stderr = "";
    this.child = spawn(psql, connectionArgs(database), { stdio: ["pipe", "pipe", "pipe"], shell: false });
    this.child.stderr.setEncoding("utf8").on("data", (x) => { this.stderr += x; });
    createInterface({ input: this.child.stdout }).on("line", (line) => {
      if (!this.pending) return;
      if (line === this.pending.marker) {
        const { done, rows, timer } = this.pending; clearTimeout(timer); this.pending = null; done(rows);
      } else if (line.trim()) this.pending.rows.push(line);
    });
    this.child.on("error", (e) => this.fail(e));
    this.child.stdin.on("error", (e) => this.fail(e));
    this.child.on("close", () => { this.exited = true; sessions.delete(this); this.fail(new Error(this.stderr || "psql exited")); });
    sessions.add(this);
  }
  fail(e) {
    this.failure = e;
    if (this.pending) { clearTimeout(this.pending.timer); this.pending.reject(e); this.pending = null; }
  }
  query(text) {
    assert.equal(this.pending, null);
    if (this.failure) return Promise.reject(this.failure);
    return new Promise((done, reject) => {
      const marker = `__pi_${this.name}_${++this.sequence}__`;
      const timer = setTimeout(() => this.fail(new Error(`${this.name} timed out`)), 20_000);
      this.pending = { marker, rows: [], timer, done, reject };
      this.child.stdin.write(`${text}\n\\echo ${marker}\n`);
    });
  }
  close() { if (!this.exited && !this.child.stdin.writableEnded) this.child.stdin.end("\\q\n"); }
}
const one = (rows) => { assert.equal(rows.length, 1); return JSON.parse(rows[0]); };
const auth = `set request.jwt.claim.sub=${lit(id("transport-only"))}; set role authenticated;`;
const request = (n) => lit(id(`request-${n}`));
const accept = (n) => `select lc_fixture.pi_accept(${request(n)},${n})::text;`;
const claim = (n, device = 1) => `select lc_fixture.tp_claim(${request(n)},${device})::text;`;
const begin = (n, attempt = n, device = 1) => `select lc_fixture.tp_begin(${request(n)},${attempt},${device})::text;`;
const fixture = async (n) => {
  await sql(`select lc_fixture.pi_request(${n});`);
  assert.equal(one(await new Session(`accept_${n}`).query(`${auth} ${accept(n)}`)).ok, true);
};
async function blocked(name, promise) {
  let settled = false; promise.then(() => { settled = true; }, () => { settled = true; });
  const deadline = Date.now() + 5000;
  while (Date.now() < deadline) {
    if (await sql(`select exists(select 1 from pg_stat_activity where datname=${lit(database)}
      and application_name=${lit(name)} and wait_event_type='Lock');`) === "t") return;
    assert.equal(settled, false, `${name} must wait for the peer transaction`);
    await new Promise((r) => setTimeout(r, 40));
  }
  assert.fail(`${name} did not wait on a database lock`);
}

const results=[]; let created=false;
const dispatcher=(n)=>`(select d.id from kitchen_print_dispatches d join web_order_requests w on w.canonical_order_id=d.order_id where w.id=${request(n)} and d.dispatch_type='initial_order')`;
const pull=(limit=50)=>`select public.pull_kitchen_print_dispatches(${lit(id('device-1'))},'synthetic-pos-token-1',${limit})::text;`;
const hold=(n)=>`select lc_fixture.lc_hold(${dispatcher(n)});`;
const policy=(mode,n=null,expiry='null')=>`select lc_fixture.lc_policy(${lit(mode)},${n===null?'null':request(n)},${expiry});`;
try {
 const server=JSON.parse(await sql(`select jsonb_build_object('data',current_setting('data_directory'),'listen',current_setting('listen_addresses'),'address',inet_server_addr(),'port',inet_server_port())::text;`,'postgres'));
 assert.equal(normalize(server.data),normalize(expectedData));
 assert.ok(['127.0.0.1','localhost'].includes(server.listen));
 assert.equal(server.address,'127.0.0.1'); assert.equal(server.port,Number(port));
 created=true; await sql(`create database "${database}" template "${template}";`,'postgres');
 const suite=await readFile(new URL('../bizbot_pos_legacy_print_containment_001_test.sql',import.meta.url),'utf8');
 const marker='-- CONTAINMENT-001 HARNESS SETUP END:';
 assert.equal(suite.split(marker).length,2);
 const setup=suite.slice(0,suite.indexOf(marker)).replace('select no_plan();','').replaceAll('pg_temp.','lc_fixture.');
 await sql(`create schema lc_fixture; grant usage on schema lc_fixture to authenticated; ${setup} commit;`);

 // Hold wins the branch fence. The blocked pull's candidate/page/has_more
 // statements execute AFTER the committed hold, even though RPC began earlier.
 const writer=new Session('hold_first'), reader=new Session('pull_after_hold');
 await writer.query(`begin; ${hold(2)}`);
 const pending=reader.query(`set application_name='pull_after_hold'; ${auth} ${pull()}`);
 await blocked('pull_after_hold',pending); await writer.query('commit;');
 const page=one(await pending);
 const held2=JSON.parse(await sql(`select to_json(${dispatcher(2)})::text;`));
 assert.equal(page.ok,true); assert.ok(!page.dispatches.some(d=>d.id===held2));
 assert.equal(await sql(`select claimed_at is null from kitchen_print_dispatches where id=${dispatcher(2)};`),'t');
 writer.close(); reader.close();
 results.push({scenario:'hold-before-broad-pull',actual_lock_wait:true,held_claims:0,held_page_rows:0});

 // A broad transaction that wins first linearizes first. Its uncommitted
 // lease mutation makes the pre-claim manifest stale: the waiting hold
 // MUST fail, rather than silently rewrite dispatch evidence or accept drift.
 await sql(`update kitchen_print_dispatches set claimed_at=null,claimed_by_device_id=null,claim_expires_at=null where id=${dispatcher(3)};`);
 const pullFirst=new Session('pull_first'), staleWriter=new Session('stale_hold');
 await pullFirst.query(`begin; ${auth} ${pull()}`);
 const stale=staleWriter.query(`set application_name='stale_hold'; ${hold(3)}`);
 const rejected=stale.then(()=>{throw Error('stale snapshot hold unexpectedly succeeded');},e=>e);
 await blocked('stale_hold',stale); await pullFirst.query('commit;');
 assert.match((await rejected).message,/hold snapshot changed/);
 assert.equal(await sql(`select count(*) from kitchen_print_dispatch_holds where dispatch_id=${dispatcher(3)};`),'0');
 pullFirst.close(); staleWriter.close();
 results.push({scenario:'claim-before-stale-manifest-hold',actual_lock_wait:true,drift_rejected:true,no_fabricated_outcome:true});

 // Post-row-lock recheck: an independent authentic terminal observation
 // commits while a pull is waiting on this exact dispatch row. No claim or
 // response may resurrect it after the lock becomes available.
 await sql(`update kitchen_print_dispatches set claimed_at=null,claimed_by_device_id=null,claim_expires_at=null where id=${dispatcher(4)};`);
 const terminal=new Session('terminal'), lockReader=new Session('post_lock_pull');
 await terminal.query(`begin; update kitchen_print_dispatches set last_client_status='possibly_printed' where id=${dispatcher(4)};`);
 const postLock=lockReader.query(`set application_name='post_lock_pull'; ${auth} ${pull()}`);
 await blocked('post_lock_pull',postLock); await terminal.query('commit;');
 const postPage=one(await postLock);
 const did4=JSON.parse(await sql(`select to_json(${dispatcher(4)})::text;`));
 assert.ok(!postPage.dispatches.some(d=>d.id===did4));
 assert.equal(await sql(`select claimed_at is null from kitchen_print_dispatches where id=${dispatcher(4)};`),'t');
 terminal.close(); lockReader.close();
 results.push({scenario:'authentic-terminal-state-during-row-lock-wait',actual_lock_wait:true,post_lock_claims:0});

 // A policy writer also wins before a waiting pull; no readiness report,
 // however qualifying, can bypass the committed target-only block.
 const policyWriter=new Session('policy_writer'), policyReader=new Session('policy_pull');
 await policyWriter.query(`begin; ${policy('target_only',9,"clock_timestamp()+interval '10 minutes'")}`);
 const policyPending=policyReader.query(`set application_name='policy_pull'; ${auth} ${pull()}`);
 await blocked('policy_pull',policyPending); await policyWriter.query('commit;');
 assert.equal(one(await policyPending).error,'containment_blocked');
 policyWriter.close(); policyReader.close();
 results.push({scenario:'target-only-before-pull',actual_lock_wait:true,broad_claims:0});

 // Expiry crossing a final printer lock cannot grant begin, and an expired
 // target-only row stays blocked after restart/new connection.
 const acceptor=new Session('accept9');
 assert.equal(one(await acceptor.query(`${auth} ${accept(9)}`)).ok,true); acceptor.close();
 const target=new Session('target9');
 assert.equal(one(await target.query(`${auth} ${claim(9)}`)).state,'claimed');
 await sql(policy('target_only',9,"clock_timestamp()+interval '700 milliseconds'"));
 const printer=new Session('printer_lock');
 await printer.query(`begin; select id from printer_devices where id=${lit(id('printer'))} for update;`);
 const expiring=target.query(`set application_name='expiring_begin'; ${begin(9)}`);
 await blocked('expiring_begin',expiring);
 await new Promise(r=>setTimeout(r,850)); await printer.query('commit;');
 assert.equal(one(await expiring).error,'containment_blocked');
 assert.equal(await sql(`select attempt_id is null from web_order_print_attempts where request_id=${request(9)};`),'t');
 assert.equal(JSON.parse(await sql(`select app.kitchen_print_containment_state(${lit(id('org'))},${lit(id('restaurant'))},${lit(id('branch'))})::text;`)).mode,'blocked');
 target.close(); printer.close();
 results.push({scenario:'target-expiry-during-printer-lock-wait-and-restart',actual_lock_wait:true,send_grants:0,expired_mode:'blocked'});

 const repeatable=new Session('repeatable');
 const rr=repeatable.query(`begin isolation level repeatable read; ${auth} select public.pos_kitchen_print_containment(${lit(id('device-1'))},'synthetic-pos-token-1')::text;`).then(()=>{throw Error('stale isolation accepted');},e=>e);
 assert.match((await rr).message,/read committed isolation/); repeatable.close();
 results.push({scenario:'stale-snapshot-isolation',fail_closed:true});
} finally {
 for(const session of sessions) session.close();
 if(created){ assert.match(database,/^containment_001_concurrency_[0-9]+_[0-9]+$/); await sql(`drop database if exists "${database}" with(force);`,'postgres'); }
}
console.log(JSON.stringify({work_id:'BIZBOT-POS-LEGACY-PRINT-CONTAINMENT-001',local_only:true,results,disposable_database_removed:true},null,2));
