// Inline SVG icon set for the BIZBOT marketing site (24×24, stroke-based).
// All icons are decorative unless a label is supplied by the caller.

const P = {
  bolt: '<path d="M13 2 4.5 13.5H11L10 22l8.5-11.5H12L13 2Z"/>',
  globe:
    '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18"/>',
  devices:
    '<rect x="2.5" y="5" width="13" height="10" rx="2"/><path d="M6 19h6M9 15v4"/><rect x="17" y="9" width="4.5" height="10" rx="1.4"/>',
  store:
    '<path d="M3.5 9 5 4.5h14L20.5 9M3.5 9v1.5a2.5 2.5 0 0 0 5 0V9m-5 0h5m0 0v1.5a2.5 2.5 0 0 0 5 0V9m-5 0h5m0 0v1.5a2.5 2.5 0 0 0 5 0V9m-5 0h5M5 13v6.5h14V13M10 19.5v-4h4v4"/>',
  orders:
    '<path d="M7 3.5h10a1.5 1.5 0 0 1 1.5 1.5v15.5l-2.5-1.6-2.5 1.6-1.5-1-1.5 1-2.5-1.6-2.5 1.6V5A1.5 1.5 0 0 1 7 3.5Z"/><path d="M9 8.5h6M9 12h6M9 15.5h3.5"/>',
  chart:
    '<path d="M4 20h16"/><path d="M6.5 16.5v-5M11 16.5V7M15.5 16.5v-3M20 16.5V9.5"/>',
  box: '<path d="M12 3 20 7v10l-8 4-8-4V7l8-4Z"/><path d="m4 7 8 4 8-4M12 11v10"/>',
  team:
    '<circle cx="9" cy="8" r="3.2"/><path d="M3.5 19.5a5.5 5.5 0 0 1 11 0"/><circle cx="17" cy="9" r="2.4"/><path d="M15.5 14.5a4.5 4.5 0 0 1 5 4.5"/>',
  touch:
    '<path d="M9 11.5V5a2 2 0 1 1 4 0v5.5"/><path d="M13 10a2 2 0 1 1 4 0v1.5M17 11.5a2 2 0 1 1 4 0v3.5a6 6 0 0 1-6 6h-2.2a6 6 0 0 1-4.9-2.5L4.7 14.2a1.8 1.8 0 0 1 2.9-2.1L9 13.5"/>',
  chef:
    '<path d="M8 15.5h8V19a1.5 1.5 0 0 1-1.5 1.5h-5A1.5 1.5 0 0 1 8 19v-3.5Z"/><path d="M8 15.5c-2.5-.2-4.5-2-4.5-4.4 0-2 1.5-3.7 3.5-4.1A5 5 0 0 1 17 7c2 .4 3.5 2.1 3.5 4.1 0 2.4-2 4.2-4.5 4.4"/>',
  offline:
    '<path d="M6.5 18.5h10a4 4 0 0 0 .8-7.9A6 6 0 0 0 6.2 9.8a4.3 4.3 0 0 0 .3 8.7Z"/><path d="M9.5 11.5 14.5 16.5M14.5 11.5 9.5 16.5"/>',
  pulse:
    '<path d="M3 12h4l2.5-6 4 12 2.5-6H21"/>',
  restaurant:
    '<path d="M7 3v8.5M4.5 3v4a2.5 2.5 0 0 0 5 0V3M7 11.5V21"/><path d="M16.5 3c-1.7 1.4-2.5 3.6-2.5 6.5 0 1.4.7 2 2.5 2V21M16.5 3v8.5"/>',
  cafe:
    '<path d="M4 9h12v6.5a4.5 4.5 0 0 1-4.5 4.5h-3A4.5 4.5 0 0 1 4 15.5V9Z"/><path d="M16 11h1.5a2.5 2.5 0 0 1 0 5H16M7 6c0-1.2 1-1.4 1-2.5M10.5 6c0-1.2 1-1.4 1-2.5"/>',
  sweets:
    '<path d="M6.5 12h11l-1.2 8H7.7l-1.2-8Z"/><path d="M5 12a3.5 3.5 0 0 1 2.2-3.3A5 5 0 0 1 16.8 8.7 3.5 3.5 0 0 1 19 12H5Z"/><path d="M12 3.5v2M10 5l2-1.5L14 5"/>',
  fastfood:
    '<path d="M4 10.5a8 8 0 0 1 16 0H4Z"/><path d="M3.5 14h17M4.5 17.5h15v.5a2.5 2.5 0 0 1-2.5 2.5H7a2.5 2.5 0 0 1-2.5-2.5v-.5Z"/>',
  cloud:
    '<path d="M7 18.5h10a4 4 0 0 0 .8-7.9A6 6 0 0 0 6.2 9.8 4.3 4.3 0 0 0 7 18.5Z"/>',
  more:
    '<rect x="4" y="4" width="6.5" height="6.5" rx="1.6"/><rect x="13.5" y="4" width="6.5" height="6.5" rx="1.6"/><rect x="4" y="13.5" width="6.5" height="6.5" rx="1.6"/><path d="M16.75 14v6M13.75 17h6"/>',
  shield:
    '<path d="M12 3 5 5.8v5.4c0 4.4 2.9 8.2 7 9.8 4.1-1.6 7-5.4 7-9.8V5.8L12 3Z"/><path d="m9 12 2 2 4-4.5"/>',
  branches:
    '<rect x="9" y="3" width="6" height="5" rx="1.4"/><rect x="3" y="16" width="6" height="5" rx="1.4"/><rect x="15" y="16" width="6" height="5" rx="1.4"/><path d="M12 8v3.5M6 16v-2.5a2 2 0 0 1 2-2h8a2 2 0 0 1 2 2V16"/>',
  printer:
    '<path d="M7 8V3.5h10V8"/><rect x="3.5" y="8" width="17" height="8" rx="2"/><path d="M7 13h10v7.5H7z"/><path d="M17 11h.5"/>',
  audit:
    '<rect x="5" y="4" width="14" height="17" rx="2"/><path d="M9 4.5V3h6v1.5"/><path d="m8.5 13 2.3 2.3L15.5 10.5"/>',
  update:
    '<path d="M20 12a8 8 0 0 1-14.3 4.9M4 12a8 8 0 0 1 14.3-4.9"/><path d="M18.5 3.5v4h-4M5.5 20.5v-4h4"/>',
  check: '<path d="m5 12.5 4.5 4.5L19 7.5"/>',
  arrow: '<path d="M4 12h16M13 5l7 7-7 7"/>',
  play: '<path d="M8 5.5v13l10-6.5-10-6.5Z"/>',
  mail:
    '<rect x="3" y="5.5" width="18" height="13" rx="2.5"/><path d="m4 7.5 8 6 8-6"/>',
  phone:
    '<path d="M6.5 3.5h3l1.8 4.5-2.2 1.6a10.5 10.5 0 0 0 5.3 5.3l1.6-2.2 4.5 1.8v3a2 2 0 0 1-2.1 2A16.5 16.5 0 0 1 4.5 5.6a2 2 0 0 1 2-2.1Z"/>',
  whatsapp:
    '<path d="M4 20l1.3-4A8.5 8.5 0 1 1 8.4 19L4 20Z"/><path d="M9 8.5c0 3.5 3 6.5 6.5 6.5l.7-1.7-2-.9-.9 1a4.8 4.8 0 0 1-2.7-2.7l1-.9-.9-2L9 8.5Z"/>',
  menu: '<path d="M4 7h16M4 12h16M4 17h16"/>',
  close: '<path d="M6 6l12 12M18 6 6 18"/>',
  external:
    '<path d="M14 4h6v6M20 4l-9 9"/><path d="M19 14v4.5A1.5 1.5 0 0 1 17.5 20h-11A1.5 1.5 0 0 1 5 18.5v-11A1.5 1.5 0 0 1 6.5 6H11"/>',
  spark: '<path d="M12 3v4M12 17v4M3 12h4M17 12h4M6 6l2.5 2.5M15.5 15.5 18 18M18 6l-2.5 2.5M8.5 15.5 6 18"/>',
  login: '<path d="M10 4h7.5A1.5 1.5 0 0 1 19 5.5v13a1.5 1.5 0 0 1-1.5 1.5H10"/><path d="M4 12h9M9.5 8l4 4-4 4"/>',
};

export function icon(name, cls = '') {
  const body = P[name];
  if (!body) throw new Error(`unknown icon: ${name}`);
  const flip = name === 'arrow' || name === 'login' || name === 'external' ? ' data-flip="1"' : '';
  return `<svg class="ic${cls ? ' ' + cls : ''}"${flip} viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false">${body}</svg>`;
}

export const iconNames = Object.keys(P);
