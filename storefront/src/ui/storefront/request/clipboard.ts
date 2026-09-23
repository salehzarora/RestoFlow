/**
 * THE ONE PLACE THE CLIPBOARD IS TOUCHED.
 *
 * Writes only, on an explicit visitor action, and only text the caller has
 * already decided is safe to hand to another application - the composed
 * demo message and its request code, which carry no contact field, no
 * address and no kitchen note. There is no read path: nothing here calls
 * `readText`, and a source rule keeps `navigator.clipboard` out of every other
 * file.
 *
 * The prototype (Storefront.dc.html:733) flipped its label to "copied" whether
 * or not the write succeeded. That is not reproduced: the result is the
 * browser's own answer, and a rejected write reports false so the screen
 * never claims a copy it did not make.
 */
export type CopyText = (text: string) => Promise<boolean>;

export const copyText: CopyText = async (text) => {
  try {
    const clipboard = globalThis.navigator?.clipboard;
    if (clipboard === undefined || typeof clipboard.writeText !== 'function') return false;
    await clipboard.writeText(text);
    return true;
  } catch {
    return false;
  }
};
