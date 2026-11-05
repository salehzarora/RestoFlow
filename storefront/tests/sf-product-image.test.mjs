import './support/ts-resolver.mjs';
import assert from 'node:assert/strict';
import { test } from 'node:test';
const { carouselImageSources } = await import('../src/ui/storefront/home/productImage.ts');

test('legacy product sources are unchanged until validated variants exist', () => {
  assert.deepEqual(carouselImageSources({ image: '/existing.webp' }, true), {});
  assert.deepEqual(carouselImageSources({ image: '/existing.webp', imageVariants: [] }, false), {});
});

test('native small sources keep their actual width descriptors and input data', () => {
  const imageVariants = Object.freeze([
    Object.freeze({ url: '/small.webp', width: 120, height: 180 }),
  ]);
  const item = Object.freeze({ image: '/small.webp', imageVariants });
  assert.equal(carouselImageSources(item, true).srcSet, '/small.webp 120w');
  assert.equal(carouselImageSources(item, false).srcSet, '/small.webp 120w');
  assert.equal(item.imageVariants, imageVariants);
});
