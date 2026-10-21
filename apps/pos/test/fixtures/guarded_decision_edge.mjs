// Offline adapter for the real Edge handler. All input is synthetic test data.
// No sockets, production configuration, global fetch or real credentials.
import { createHandler } from "../../../../supabase/functions/pos-web-order-decision/handler.mjs";

let input = "";
for await (const chunk of process.stdin) input += chunk;
const { url, method, headers, body, rpcError, replayed = false } = JSON.parse(input);
const rpcCalls = [];
const handler = createHandler({
  getEnv: (key) => ({ SUPABASE_URL: "https://synthetic.invalid", SUPABASE_ANON_KEY: "synthetic-public-key" })[key],
  fetchImpl: async (url, options) => {
    rpcCalls.push({ url, method: options.method, headers: options.headers, body: JSON.parse(options.body) });
    // The RPC boundary is synthetic; actual database tenant/PIN/RLS contracts
    // remain covered by the existing isolated pgTAP suites, not this adapter.
    if (options.headers.Authorization !== "Bearer synthetic.device.jwt") return new Response(null, { status: 401 });
    const args = JSON.parse(options.body);
    const rejected = url.endsWith("/pos_reject_web_order_customer");
    return Response.json(rpcError ? { ok: false, error: rpcError } : {
      ok: true, request_id: args.p_request_id, decision_id: args.p_decision_id,
      status: rejected ? "rejected" : "accepted", replayed,
      canonical_order_id: rejected ? null : "20000000-0000-4000-8000-000000000001",
    });
  },
});
const response = await handler(new Request(url, { method, headers, body }));
process.stdout.write(JSON.stringify({ status: response.status, body: await response.json(), rpcCalls }));
