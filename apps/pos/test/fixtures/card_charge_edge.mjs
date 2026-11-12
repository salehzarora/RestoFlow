// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001C: offline adapter for the REAL, unchanged pos-card-charge handler.
// Synthetic input only: the master flag is off, no provider profile is passed (index.ts passes none either)
// and every fetch is refused here, so no proof, ledger write or provider call can happen. The global fetch
// is replaced (refusing and recording) before the handler is loaded, so no other fetch path exists. No
// sockets or real credentials. The body arrives base64-encoded so its exact bytes reach the handler.
const globalFetches = [];
globalThis.fetch = async (target) => {
  globalFetches.push(typeof target?.url === "string" ? target.url : String(target));
  throw new Error("network denied");
};
const { createHandler } = await import("../../../../supabase/functions/pos-card-charge/handler.mjs");

let input = "";
for await (const chunk of process.stdin) input += chunk;
const { url, method, headers, body } = JSON.parse(input);
const fetches = [];
const handler = createHandler({
  getEnv: (key) => ({ SUPABASE_URL: "https://synthetic.invalid", SUPABASE_ANON_KEY: "synthetic-public-key" })[key],
  fetchImpl: async (target) => {
    fetches.push(String(target));
    throw new Error("network denied");
  },
  waitUntil: () => {
    throw new Error("no background work expected");
  },
});
const response = await handler(new Request(url, { method, headers, body: Buffer.from(body, "base64") }));
process.stdout.write(JSON.stringify({ status: response.status, body: await response.json(), fetches, globalFetches }));
