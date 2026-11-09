// The network guard itself (test/no_network.mjs): every channel it closes throws and is recorded, so
// a real outbound request fails the test that makes it. Each probe passes arguments the real API
// refuses before any I/O, so even a weakened guard sends nothing; the record is cleared after each
// probe, and the after-hook still asserts that nothing else was recorded.
import "./no_network.mjs";
import test from "node:test";
import assert from "node:assert/strict";
import dgram from "node:dgram";
import dns from "node:dns";
import http from "node:http";
import http2 from "node:http2";
import https from "node:https";
import net from "node:net";
import tls from "node:tls";
import { blocked, settleAll, stray } from "./fixtures.mjs";

test.after(async () => { await settleAll(); assert.deepEqual(blocked, []); assert.deepEqual(stray, []); });

const BLOCKED = /real network access is blocked in this suite/;

function probe(name, access) {
  assert.throws(access, BLOCKED, name);
  assert.deepEqual(blocked, [name], name);
  blocked.length = 0;
}

test("fetch, sockets, TLS, HTTP, HTTP/2 and UDP throw and are recorded", (t) => {
  probe("fetch", () => fetch("https://synthetic-provider.test/", { method: "GET", body: "x" }));
  for (const name of ["WebSocket", "EventSource"]) {
    if (typeof globalThis[name] === "function") probe(name, () => new globalThis[name]("not a url"));
    else t.diagnostic(`${name} is not defined by this runtime`);
  }
  probe("net.connect", () => net.connect({ port: -1 }));
  probe("net.createConnection", () => net.createConnection({ port: -1 }));
  probe("net.Socket.connect", () => new net.Socket().connect({ port: -1 }));
  probe("tls.connect", () => tls.connect({ port: -1 }));
  probe("http.request", () => http.request("ftp://synthetic-provider.test/"));
  probe("http.get", () => http.get("ftp://synthetic-provider.test/"));
  probe("https.request", () => https.request("ftp://synthetic-provider.test/"));
  probe("https.get", () => https.get("ftp://synthetic-provider.test/"));
  probe("http2.connect", () => http2.connect("ftp://synthetic-provider.test"));
  probe("dgram.createSocket", () => dgram.createSocket("no-such-type"));
  for (const name of ["bind", "connect", "send"]) probe(`dgram.Socket.${name}`, () => dgram.Socket.prototype[name].call({}));
});

test("every resolver entry point of dns, dns.promises and both Resolver classes throws and is recorded", () => {
  const probed = [];
  for (const [owner, label] of [[dns, "dns"], [dns.promises, "dns.promises"], [dns.Resolver.prototype, "dns.Resolver"],
    [dns.promises.Resolver.prototype, "dns.promises.Resolver"]]) {
    for (const name of Object.getOwnPropertyNames(owner)) {
      if (!/^(?:lookup|lookupService|resolve|reverse)/.test(name) || typeof owner[name] !== "function") continue;
      probe(`${label}.${name}`, () => owner[name].call(owner, 123));
      probed.push(`${label}.${name}`);
    }
  }
  for (const required of ["dns.lookup", "dns.lookupService", "dns.resolve", "dns.resolve4", "dns.resolve6", "dns.resolveAny",
    "dns.reverse", "dns.promises.lookup", "dns.promises.resolve4", "dns.Resolver.resolve4", "dns.promises.Resolver.resolve4"]) {
    assert.ok(probed.includes(required), required);
  }
});
