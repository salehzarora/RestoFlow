// Imported FIRST by every test file: any real outbound network access fails the test. The
// function under test only ever receives the injected fake transports (test/fixtures.mjs).
import dgram from "node:dgram";
import dns from "node:dns";
import http from "node:http";
import http2 from "node:http2";
import https from "node:https";
import net from "node:net";
import tls from "node:tls";

export const blocked = [];

function deny(name) {
  return function blockedNetworkAccess() {
    blocked.push(name);
    throw new Error(`real network access is blocked in this suite (${name})`);
  };
}

globalThis.fetch = deny("fetch");
if (typeof globalThis.WebSocket === "function") globalThis.WebSocket = deny("WebSocket");
if (typeof globalThis.EventSource === "function") globalThis.EventSource = deny("EventSource");
net.connect = deny("net.connect");
net.createConnection = deny("net.createConnection");
net.Socket.prototype.connect = deny("net.Socket.connect");
tls.connect = deny("tls.connect");
http.request = deny("http.request");
http.get = deny("http.get");
https.request = deny("https.request");
https.get = deny("https.get");
http2.connect = deny("http2.connect");
dgram.createSocket = deny("dgram.createSocket");
for (const name of ["bind", "connect", "send"]) dgram.Socket.prototype[name] = deny(`dgram.Socket.${name}`);
// Every resolver entry point: lookup, lookupService, resolve*, reverse - module, promises and Resolver classes.
const RESOLVING = /^(?:lookup|lookupService|resolve|reverse)/;
for (const [owner, label] of [[dns, "dns"], [dns.promises, "dns.promises"], [dns.Resolver.prototype, "dns.Resolver"],
  [dns.promises.Resolver.prototype, "dns.promises.Resolver"]]) {
  for (const name of Object.getOwnPropertyNames(owner)) {
    if (RESOLVING.test(name) && typeof owner[name] === "function") owner[name] = deny(`${label}.${name}`);
  }
}
