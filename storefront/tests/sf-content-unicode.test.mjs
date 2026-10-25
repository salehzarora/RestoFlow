import './support/ts-resolver.mjs';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
const { graphemeBoundaries, scalarValues, normalizeContentText, contentTextValid, heroFormatValid, utf16SelectionToCodepoints } = await import('../src/content/unicode.ts');
const base=new URL('../../tools/storefront_content_unicode/',import.meta.url);
const corpus=JSON.parse(readFileSync(new URL('vectors.json',base),'utf8'));
test('Unicode15.1 official 1187 UAX29r43 default extended grapheme vectors',()=>{
  assert.equal(corpus.vectors.length,1187);
  for(const [i,v] of corpus.vectors.entries())assert.deepEqual(graphemeBoundaries(String.fromCodePoint(...v.codepoints)),v.boundaries,`official vector ${i}`);
});
test('checked-in official source hashes remain pinned; generators have no network dependency',()=>{
  const p=JSON.parse(readFileSync(new URL('provenance.json',base),'utf8'));
  for(const f of p.files)assert.equal(createHash('sha256').update(readFileSync(new URL(`vendor/${f.name}`,base))).digest('hex'),f.sha256);
  assert.equal(p.unicode,'15.1.0');
  assert.doesNotMatch(readFileSync(new URL('generate.mjs',base),'utf8'),/\bfetch\s*\(|https?\.request|child_process/);
});
test('literal scalar identity, explicit whitespace and old/new control domains',()=>{
  assert.equal(normalizeContentText('\u00a0 مرحبا \ufeff',120,true),'مرحبا');
  assert.equal(normalizeContentText('   ',120,true),null);
  assert.equal(normalizeContentText('Cafe\u0301',120),'Cafe\u0301');
  assert.notEqual(normalizeContentText('Cafe\u0301',120),normalizeContentText('Café',120));
  assert.equal(contentTextValid(' مرحبا',120,true),false);
  assert.equal(contentTextValid(null,120),true);
  assert.equal(contentTextValid('A\u2028B',120,true),true);
  assert.equal(contentTextValid('A\u2028B',120),false);
  for(const v of ['\nhello','hello\r','hello\x00','\ud800','\udc00'])assert.throws(()=>normalizeContentText(v,120,true));
  assert.equal(scalarValues('\ud800'),null);assert.equal(graphemeBoundaries('\ud800'),null);
});
test('AR/HE/nonBMP CP selection is exact, no rounding, normalization or split clusters',()=>{
  assert.equal(heroFormatValid('طَعْم رائع',0,5,6),true);
  assert.equal(heroFormatValid('שָׁלוֹם טעים',0,7,8),true);
  assert.equal(heroFormatValid('🍔 טָעִים',2,8,2),true);
  assert.deepEqual(utf16SelectionToCodepoints('🍔 טָעִים',3,9),[2,8]);
  assert.equal(utf16SelectionToCodepoints('🍔 טָעִים',1,9),null);
  assert.deepEqual(utf16SelectionToCodepoints('👩‍🍳 ברجر',10,6),[4,8]);
  assert.equal(heroFormatValid('A\u00a0 B',3,4,3),true);
  assert.equal(heroFormatValid('A\u00a0 B',3,4,2),false);
  assert.equal(heroFormatValid('A \u0301B',2,4,null),false);
  assert.equal(heroFormatValid('A B C',0,5,2),false);
  assert.equal(heroFormatValid('A B',0,null,null),false);
  assert.equal(heroFormatValid('A\u2028B',0,1,null),false);
  assert.equal(heroFormatValid(null,null,null,null),true);
  assert.equal(heroFormatValid(null,0,1,null),false);
  assert.equal(heroFormatValid('x'.repeat(61),0,61,null),false);
  assert.equal(heroFormatValid('A B',0,1.5,null),false);
});
