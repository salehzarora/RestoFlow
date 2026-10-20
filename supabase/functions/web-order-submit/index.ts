import { createHandler } from "./handler.mjs";

// Anonymous entry point; capability verification and both submit gates are server-side.
Deno.serve(createHandler({
  getEnv: (name: string) => Deno.env.get(name),
  // Access only during a successful scheduling handoff; unavailable runtimes fail
  // inside the wake's catch boundary before any notification HTTP starts.
  waitUntil: (task: Promise<unknown>) => EdgeRuntime.waitUntil(task),
}));
