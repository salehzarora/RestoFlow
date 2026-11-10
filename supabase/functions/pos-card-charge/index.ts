// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E - Supabase Edge Function `pos-card-charge` (API_CONTRACT
// section 4.55). verify_jwt = false at the gateway (supabase/config.toml): the handler requires a
// Bearer JWT and PostgREST verifies it inside the read-only context proof; the service-role key
// is read by lib/ledger.mjs only, after that proof. Dark by default: without
// POS_CARD_PAYMENTS_ENABLED=true, a valid POS_CARD_PROVIDER_CONFIG and a vendor wire profile no
// provider request is ever made. No vendor wire profile ships with 001E (execution packet
// section 6, gate W1), so every provider call fails closed as provider_unavailable.
import { createHandler } from "./handler.mjs";

declare const Deno: {
  env: { get(name: string): string | undefined };
  serve(handler: (request: Request) => Response | Promise<Response>): unknown;
};
declare const EdgeRuntime: { waitUntil(task: Promise<unknown>): void };

Deno.serve(createHandler({
  getEnv: (name: string) => Deno.env.get(name),
  waitUntil: (task: Promise<unknown>) => EdgeRuntime.waitUntil(task),
  providerProfile: null,
}));
