// RF-112 local browser smoke — global setup.
//
// Runs ONCE before any spec. It enforces the two hard boundaries before a single
// browser is launched: the run must be local-only, and the environment must not
// carry a service-role/secret-looking credential (DECISION D-011, RISK R-003).

import { SURFACES } from './lib/constants';
import { assertLocalOnly, assertNoServiceRoleKey } from './lib/guards';

export default async function globalSetup(): Promise<void> {
  assertNoServiceRoleKey();
  for (const surface of SURFACES) {
    assertLocalOnly(surface.url);
  }
  // eslint-disable-next-line no-console
  console.log(
    `RF-112 smoke: local-only + no-service-role guards passed; targets → ` +
      SURFACES.map((s) => `${s.name} ${s.url}`).join(', '),
  );
}
