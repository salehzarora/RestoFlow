import './support/ts-resolver.mjs';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
const { welcomeBackgroundMessages } = await import('../src/i18n/welcomeBackground.ts');
const { storefrontMessages } = await import('../src/i18n/storefront.ts');
const { packStorefrontMessages, unpackStorefrontMessages } = await import('../src/i18n/storefrontValues.ts');

test('welcome controls have exact complete independent locale copy, without changing the shared checkout wire', () => {
  for (const locale of ['ar','he','en']) {
    const labels=welcomeBackgroundMessages(locale);
    assert.deepEqual(Object.keys(labels).sort(),['pause','play']);
    assert.ok(labels.play.trim()&&labels.pause.trim());assert.notEqual(labels.play,labels.pause);
    if(locale!=='en')for(const key of ['play','pause'])assert.notEqual(labels[key],welcomeBackgroundMessages('en')[key]);
    const shared=storefrontMessages(locale),wire=packStorefrontMessages(shared);
    assert.equal(wire.length,207);assert.deepEqual(unpackStorefrontMessages(wire),shared);
    assert.ok(!Object.keys(shared).some(key=>/WelcomeBackground/.test(key)));
  }
  const client=readFileSync(new URL('../src/ui/storefront/WelcomeMedia.tsx',import.meta.url),'utf8');
  assert.doesNotMatch(client,/import[^;]+(?:welcomeBackground|storefrontMessages|messages\/)/);
});
