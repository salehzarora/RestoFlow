/**
 * THE WHATSAPP LAUNCHER SEAM - and the only implementation UI-001 ships.
 *
 * DEFERRED(WA-001): the real deep link. The approved handoff calls the
 * prototype's behaviour "a design-only stand-in for the deep link"
 * (INTERACTIONS.md:101) and the packet forbids any real WhatsApp navigation in
 * UI-001 (PACKET:797, :951). So this launcher OPENS NOTHING: no `wa.me`, no
 * `whatsapp://`, no `api.whatsapp.com`, no `window.open`, no anchor, no
 * message leaves the page. It reports that a launch was SIMULATED, and the
 * screen says so in words rather than claiming WhatsApp opened.
 *
 * The signature is the one a real launcher will satisfy. A real one returns
 * 'opened' or 'unavailable'; a simulated one can only ever return
 * 'simulated', so a screen cannot mistake the stub for evidence that anything
 * opened.
 */
export type LaunchResult = 'opened' | 'unavailable' | 'simulated';

export interface WhatsAppLauncher {
  /** Digits only, never a formatted number; the message is the composed text. */
  open(digits: string, message: string): LaunchResult;
}

export const demoLauncher: WhatsAppLauncher = {
  open() {
    return 'simulated';
  },
};
