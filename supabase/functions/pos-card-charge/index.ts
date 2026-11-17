// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E - Supabase Edge Function `pos-card-charge` (API_CONTRACT
// section 4.55). verify_jwt = false at the gateway (supabase/config.toml): the handler requires a
// Bearer JWT and PostgREST verifies it inside the read-only context proof; the service-role key
// is read by lib/ledger.mjs only, after that proof. The entrypoint supplies the reviewed provider
// candidate (lib/provider/zcredit_profile.mjs, zcredit-ws-pinpad-candidate-1; wired by
// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001H-PROFILE-WIRING-001). With the master flag absent, start
// refuses before a database call. A start that reaches the claim also needs the existing revision
// and binding gates. Recovery operations retain their existing behavior; no provider request from
// a missing attempt is possible through those paths. The no-provider-request conclusion for a
// disabled deployment depends on the complete verified posture, including the absence of relevant
// recoverable attempts, not on the OFF flag alone.
import { createHandler } from "./handler.mjs";
import { ZCREDIT_PROFILE_CANDIDATE } from "./lib/provider/zcredit_profile.mjs";

declare const Deno: {
  env: { get(name: string): string | undefined };
  serve(handler: (request: Request) => Response | Promise<Response>): unknown;
};
declare const EdgeRuntime: { waitUntil(task: Promise<unknown>): void };

Deno.serve(createHandler({
  getEnv: (name: string) => Deno.env.get(name),
  waitUntil: (task: Promise<unknown>) => EdgeRuntime.waitUntil(task),
  providerProfile: ZCREDIT_PROFILE_CANDIDATE,
}));
