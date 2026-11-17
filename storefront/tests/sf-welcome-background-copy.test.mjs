import './support/ts-resolver.mjs';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import React from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
await import('./browser/helpers/ssr-components.mjs');
const { WelcomeMedia } = await import('../src/ui/storefront/WelcomeMedia.tsx');
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

test('initial welcome markup defers speculative video loading while retaining the published resource, poster and real playback control', () => {
  const origin='https://oqmevrndtivqxgyvcmwy.supabase.co';
  const video={url:`${origin}/storage/v1/object/public/storefront-welcome-videos/${'a'.repeat(32)}/${'b'.repeat(64)}.mp4`,width:540,height:864};
  const image=`${origin}/storage/v1/object/public/storefront-media/${'a'.repeat(32)}/${'c'.repeat(64)}.webp`;
  const render=selected=>renderToStaticMarkup(React.createElement(WelcomeMedia,{video:selected,image,playLabel:'Play background',pauseLabel:'Pause background'}));
  const html=render(video), tag=html.match(/<video\b[^>]*>/i)?.[0];
  assert.ok(tag,'The shipped component must still render a real video, not pass by removing its source.');
  assert.match(tag,/\spreload="none"/i,'The initial document must not start a metadata-only fetch before the existing playback effect.');
  assert.ok(tag.includes(`src="${video.url}"`));assert.ok(tag.includes(`poster="${image}"`));
  assert.match(tag,/\swidth="540"/);assert.match(tag,/\sheight="864"/);
  for(const attribute of ['muted','loop','playsInline'])assert.match(tag,new RegExp(`\\s${attribute}(?:=|\\s|>)`,'i'));
  assert.doesNotMatch(tag,/\s(?:autoPlay|controls)(?:=|\s|>)/i,'Playback stays with the existing motion-aware effect and explicit button.');
  assert.match(html,/<button\b[^>]*data-sf-welcome-playback=""[^>]*aria-label="Play background"[^>]*aria-controls="sf-welcome-background-video"/);
  const fallback=render(null);
  assert.ok(fallback.includes(`src="${image}"`));assert.doesNotMatch(fallback,/<video\b|data-sf-welcome-playback/);
});
