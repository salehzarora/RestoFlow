import { dispatchPilot, sameDispatchPilot } from "./pos-order-alert-pilot.mjs";

// The master switch is the emergency shutdown for every tenant/caller. Normal
// operation is continuous; an explicitly selected pilot retains its UTC fence.
export function dispatchAuthority(getEnv, nowMs) {
  if (getEnv("POS_ORDER_ALERTS_ENABLED") !== "true" || !Number.isFinite(nowMs)) return null;
  const mode = getEnv("POS_ORDER_ALERT_MODE") ?? "continuous";
  if (mode === "continuous") return { mode };
  if (mode !== "pilot") return null;
  const pilot = dispatchPilot(getEnv, nowMs);
  return pilot ? { mode, ...pilot } : null;
}

export function sameDispatchAuthority(authority, getEnv, nowMs) {
  const current = dispatchAuthority(getEnv, nowMs);
  return current !== null && current.mode === authority.mode
    && (current.mode === "continuous" || sameDispatchPilot(authority, getEnv, nowMs));
}

export function dispatchBudget(authority, nowMs, maximumMs) {
  return authority.mode === "pilot" ? Math.min(maximumMs, authority.end - nowMs) : maximumMs;
}
