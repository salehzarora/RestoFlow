#!/usr/bin/env node
// STOREFRONT-READ-001 - a LOCAL stand-in for the Supabase API gateway.
//
// The hosted read goes to `https://<ref>.supabase.co/rest/v1/rpc/storefront_menu`
// through Supabase's gateway, which strips `/rest/v1` and forwards to PostgREST.
// On this machine the CLI stack's gateway (kong) is not running, while PostgREST
// is reachable on a loopback port (a docker port-forward to the `rest`
// container). This shim gives the storefront the SAME origin shape it uses in
// production: it listens on loopback, maps `/rest/v1/<path>` to PostgREST's
// `/<path>`, and forwards the request untouched (method, headers incl. the
// anon `apikey` / `Authorization`, body). Nothing else is served; anything
// outside `/rest/v1/` is 404.
//
// Loopback only, evidence only. It is not a deployment artifact and it is not
// what the hosted gate verifies.
import { createServer, request as httpRequest } from 'node:http';

const LISTEN = Number(process.env.STOREFRONT_SHIM_PORT ?? 4700);
const TARGET = process.env.STOREFRONT_SHIM_TARGET ?? 'http://127.0.0.1:55330';
const target = new URL(TARGET);
if (!['127.0.0.1', 'localhost'].includes(target.hostname)) {
  throw new Error('the shim forwards to loopback only');
}

const server = createServer((req, res) => {
  if (!req.url?.startsWith('/rest/v1/')) {
    res.writeHead(404, { 'content-type': 'application/json' });
    res.end('{"message":"not a PostgREST path"}');
    return;
  }
  const upstream = httpRequest(
    {
      hostname: target.hostname,
      port: target.port,
      method: req.method,
      path: req.url.slice('/rest/v1'.length),
      headers: { ...req.headers, host: `${target.hostname}:${target.port}` },
    },
    (up) => {
      res.writeHead(up.statusCode ?? 502, up.headers);
      up.pipe(res);
    },
  );
  upstream.on('error', (error) => {
    res.writeHead(502, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ message: `upstream: ${error.message}` }));
  });
  req.pipe(upstream);
});

server.listen(LISTEN, '127.0.0.1', () => {
  console.log(`api shim: http://127.0.0.1:${LISTEN}/rest/v1/* -> ${TARGET}/*`);
});
