/** Narrow typing for the unchanged procedural fixture generator used by CI. */
declare module '*storefront-media-publish/test/fixtures.mjs' {
  export function photoRgb(width: number, height: number, seed: number, noise: number): (y: number, row: import('node:buffer').Buffer) => void;
  export function png(options: { width: number; height: number; channels: number; rows: (y: number, row: import('node:buffer').Buffer) => void }): import('node:buffer').Buffer;
}
