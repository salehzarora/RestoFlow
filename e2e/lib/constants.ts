// RF-112 local browser smoke — surface targets.
//
// The three RestoFlow web surfaces run in REAL local mode on STABLE ports (see
// the repo-root _run_*_real.bat launchers). The ports are fixed on purpose:
// Flutter web otherwise picks a random port each run and the browser scopes
// storage (signed-in session, device pairing) per origin, so a new port looks
// like a wiped session. Each URL can be overridden by env for a non-default run,
// but ONLY to another local origin (enforced by assertLocalOnly).

export interface SurfaceTarget {
  /** Human label used in test titles and failure messages. */
  readonly name: string;
  /** The local origin the app is served from. */
  readonly url: string;
}

function envUrl(name: string, fallback: string): string {
  const value = process.env[name];
  return value && value.trim().length > 0 ? value.trim() : fallback;
}

// Defaults match _run_dashboard_real.bat / _run_pos_real.bat / _run_kds_real.bat.
export const DASHBOARD: SurfaceTarget = {
  name: 'Dashboard',
  url: envUrl('RF_E2E_DASHBOARD_URL', 'http://localhost:57026'),
};

export const POS: SurfaceTarget = {
  name: 'POS',
  url: envUrl('RF_E2E_POS_URL', 'http://localhost:52096'),
};

export const KDS: SurfaceTarget = {
  name: 'KDS',
  url: envUrl('RF_E2E_KDS_URL', 'http://localhost:49622'),
};

export const SURFACES: readonly SurfaceTarget[] = [DASHBOARD, POS, KDS];
