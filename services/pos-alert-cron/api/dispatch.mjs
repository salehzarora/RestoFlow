import { createHandler } from '../lib/handler.mjs';

// A standalone Vercel Node function; no framework or client bundle.
export const GET = createHandler();
