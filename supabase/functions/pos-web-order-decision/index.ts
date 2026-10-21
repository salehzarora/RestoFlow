import { createHandler } from "./handler.mjs";

// Native/product-web caller JWT is forwarded unchanged to PostgREST, which validates it;
// the authenticated RPC still proves real employee/PIN/device/tenant authority.
Deno.serve(createHandler({
  getEnv: (name: string) => Deno.env.get(name),
  waitUntil: (task: Promise<unknown>) => EdgeRuntime.waitUntil(task),
}));
