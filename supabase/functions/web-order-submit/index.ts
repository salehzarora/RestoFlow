import { createHandler } from "./handler.mjs";

// Anonymous entry point; capability verification and both submit gates are server-side.
Deno.serve(createHandler({ getEnv: (name: string) => Deno.env.get(name) }));
