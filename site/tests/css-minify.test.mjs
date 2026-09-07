import assert from 'node:assert/strict';
import test from 'node:test';

import { minifyCss } from '../scripts/build.mjs';

test('CSS compaction removes only safe whitespace while preserving selector and value tokens', () => {
  const source = `
    /* ordinary comments are dropped */
    .card .label:hover,
    .card > .label {
      color: rgb(1, 2, 3);
      transform: translateX(calc(100% - 2px));
      background-image: url("/a path/hero (1).webp");
      content: "/* this is string content */ a  b";
      --tokens: 1 + 2, calc(3px - 1px);
    }
    @media (max-width: 40rem) {
      .a + .b { margin: 0; }
    }
  `;

  const expected = '.card .label:hover,.card>.label{color:rgb(1,2,3);transform:translateX(calc(100% - 2px));background-image:url("/a path/hero (1).webp");content:"/* this is string content */ a  b";--tokens: 1 + 2, calc(3px - 1px);}@media (max-width: 40rem){.a+.b{margin:0}}\n';
  assert.equal(minifyCss(source), expected);
});

test('CSS compaction preserves escapes, comment token boundaries and custom-property whitespace', () => {
  const source = String.raw`
    .escaped\:name/* token boundary */ .child {
      content: "quote: \" and slash: \\";
      background: url(/assets/a\ b.svg);
      --fallback:  alpha  beta ;
    }
  `;
  const compact = minifyCss(source);

  assert.equal(
    compact,
    String.raw`.escaped\:name .child{content:"quote: \" and slash: \\";background:url(/assets/a\ b.svg);--fallback: alpha beta ;}` + '\n',
  );
  assert.equal(minifyCss(compact), compact, 'compaction is idempotent');
});

test('CSS compaction understands declaration blocks nested in rule containers', () => {
  const source = `
    @supports (display: grid) {
      .grid, .grid > * { display: grid; gap: clamp(8px, 2vw, 20px); }
    }
    @keyframes enter {
      from { transform: translateX(calc(0px - 1px)); }
      to { transform: translateX(0); }
    }
  `;

  assert.equal(
    minifyCss(source),
    '@supports (display: grid){.grid,.grid>*{display:grid;gap:clamp(8px,2vw,20px)}}@keyframes enter{from{transform:translateX(calc(0px - 1px))}to{transform:translateX(0)}}\n',
  );
});

test('comments preserve token boundaries only when their removal would merge tokens', () => {
  assert.equal(
    minifyCss('.a/**/.b { color: red } @media/**/screen { .x { width: 10/**/px } }'),
    '.a.b{color:red}@media screen{.x{width:10 px}}\n',
  );
});

test('hex-escape terminators and meaningful following whitespace survive compaction', () => {
  const compact = minifyCss(String.raw`.one-\31 0 { color: red } .two-\31  .child { color: blue }`);
  assert.equal(compact, String.raw`.one-\31 0{color:red}.two-\31  .child{color:blue}` + '\n');
});

test('empty custom properties and opaque URL contents retain their meaning', () => {
  const source = ':root { --empty: ; --words:  alpha  beta ; } .asset { background: url(data:image/svg+xml,{fill:red;stroke:none}); }';
  assert.equal(
    minifyCss(source),
    ':root{--empty: ;--words: alpha beta ;}.asset{background:url(data:image/svg+xml,{fill:red;stroke:none})}\n',
  );
});

test('nested rule containers and balanced custom-property blocks stay parseable', () => {
  const source = '.host { @media (width > 20rem) { & .child { color: red; } } --map: {alpha: one; beta: [two; three]}; }';
  assert.equal(
    minifyCss(source),
    '.host{@media (width > 20rem){& .child{color:red}}--map: {alpha: one; beta: [two; three]};}\n',
  );
});
