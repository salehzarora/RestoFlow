import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import vm from 'node:vm';

const source = readFileSync(join(process.cwd(), 'src', 'main.js'), 'utf8');

class FakeClassList {
  constructor() { this.values = new Set(); }
  add(...names) { names.forEach((name) => this.values.add(name)); }
  remove(...names) { names.forEach((name) => this.values.delete(name)); }
  contains(name) { return this.values.has(name); }
  toggle(name, force) {
    const on = force === undefined ? !this.values.has(name) : !!force;
    if (on) this.values.add(name);
    else this.values.delete(name);
    return on;
  }
}

class FakeStyle {
  constructor() { this.values = new Map(); }
  setProperty(name, value) { this.values.set(name, String(value)); }
  removeProperty(name) { this.values.delete(name); }
  getPropertyValue(name) { return this.values.get(name) || ''; }
}

class FakeElement {
  constructor(window, kind, top, height) {
    this.window = window;
    this.attrs = new Map();
    this.classList = new FakeClassList();
    this.style = new FakeStyle();
    this.top = top || 0;
    this.height = height || 100;
    this.steps = [];
    if (kind) this.attrs.set('data-scroll', kind);
  }
  addEventListener() {}
  closest() { return null; }
  getAttribute(name) { return this.attrs.has(name) ? this.attrs.get(name) : null; }
  setAttribute(name, value) { this.attrs.set(name, String(value)); }
  removeAttribute(name) { this.attrs.delete(name); }
  querySelector() { return null; }
  querySelectorAll(selector) { return selector === '.jstep' ? this.steps : []; }
  getBoundingClientRect() {
    const top = this.top - this.window.pageYOffset;
    return { top, bottom: top + this.height, width: 100, height: this.height, left: 0 };
  }
}

class FakeMediaQuery {
  constructor(matches) { this.matches = matches; this.listeners = []; }
  addEventListener(type, listener) { if (type === 'change') this.listeners.push(listener); }
  addListener(listener) { this.listeners.push(listener); }
  set(matches) {
    this.matches = matches;
    this.listeners.forEach((listener) => listener({ matches }));
  }
}

function boot({ width = 768, height = 844, reduced = false, scroll = 0 } = {}) {
  const listeners = new Map();
  const rafs = [];
  const motionQuery = new FakeMediaQuery(reduced);
  const window = {
    innerWidth: width,
    innerHeight: height,
    pageYOffset: scroll,
    scrollY: scroll,
    matchMedia(query) {
      return query === '(prefers-reduced-motion: reduce)' ? motionQuery : new FakeMediaQuery(false);
    },
    addEventListener(type, listener, options) {
      const values = listeners.get(type) || [];
      values.push({ listener, options });
      listeners.set(type, values);
    },
  };
  const root = new FakeElement(window);
  root.scrollTop = 0;
  root.dir = 'rtl';
  root.classList.add('no-js');
  const hero = new FakeElement(window, 'hero', 0, 900);
  const journey = new FakeElement(window, 'journey', 1000, 3800);
  journey.steps = Array.from({ length: 5 }, () => new FakeElement(window));
  const reveal = new FakeElement(window);
  const video = {
    hidden: false,
    paused: false,
    pauseCount: 0,
    playCount: 0,
    matches(selector) { return selector === 'video'; },
    querySelector() { return null; },
    pause() { this.paused = true; this.pauseCount += 1; },
    play() { this.paused = false; this.playCount += 1; return Promise.resolve(); },
  };
  const document = {
    documentElement: root,
    body: { style: {} },
    activeElement: null,
    getElementById() { return null; },
    querySelector() { return null; },
    querySelectorAll(selector) {
      if (selector === '[data-scroll]') return [hero, journey];
      if (selector === '.reveal') return [reveal];
      if (selector === 'video') return [video];
      return [];
    },
    addEventListener() {},
  };
  function requestAnimationFrame(callback) { rafs.push(callback); return rafs.length; }
  function flushAnimationFrames() {
    while (rafs.length) rafs.shift()(0);
  }
  function dispatch(type) {
    for (const { listener } of listeners.get(type) || []) listener({ type });
  }
  const location = { hash: '', href: 'https://bizbot.systems/' };
  vm.runInNewContext(source, {
    window,
    document,
    location,
    requestAnimationFrame,
    setTimeout,
    clearTimeout,
    console,
  });
  return { window, root, hero, journey, reveal, video, motionQuery, listeners, dispatch, flushAnimationFrames };
}

test('journey driver follows the 1024px layout boundary in both resize directions', () => {
  const app = boot({ width: 768 });
  assert.equal(app.journey.style.getPropertyValue('--p'), '', 'mobile starts without the pinned journey driver');

  app.window.innerWidth = 1280;
  app.window.pageYOffset = 3900;
  app.window.scrollY = 3900;
  app.dispatch('resize');
  app.flushAnimationFrames();
  assert.ok(Number(app.journey.style.getPropertyValue('--p')) >= 0.97, 'expanding registers and measures the journey driver');
  assert.equal(app.journey.getAttribute('data-step'), '5');
  assert.ok(app.journey.classList.contains('is-final'));

  app.window.innerWidth = 768;
  app.dispatch('resize');
  app.flushAnimationFrames();
  assert.equal(app.journey.style.getPropertyValue('--p'), '', 'shrinking removes the desktop-only inline progress');
  assert.equal(app.journey.getAttribute('data-step'), null);
  assert.ok(!app.journey.classList.contains('is-final'));

  app.window.innerWidth = 1280;
  app.dispatch('resize');
  app.flushAnimationFrames();
  assert.equal(app.journey.getAttribute('data-step'), '5', 'expanding again restores the current timeline state');

  const scrollListeners = app.listeners.get('scroll') || [];
  assert.ok(scrollListeners.length >= 2, 'header and timeline listen for scroll');
  assert.ok(scrollListeners.every(({ options }) => options && options.passive === true), 'all scroll listeners stay passive');
});

test('live reduced-motion changes clear scroll state, pause video and can restore the timeline', () => {
  const app = boot({ width: 1280, scroll: 3900 });
  assert.equal(app.journey.getAttribute('data-step'), '5');
  assert.notEqual(app.root.style.getPropertyValue('--hp'), '');

  app.motionQuery.set(true);
  assert.equal(app.root.style.getPropertyValue('--hp'), '', 'inline hero progress no longer overrides reduced-motion CSS');
  assert.equal(app.journey.style.getPropertyValue('--p'), '', 'inline journey progress is removed');
  assert.equal(app.journey.getAttribute('data-step'), null);
  assert.equal(app.video.pauseCount, 1, 'an already-playing video is paused');
  assert.equal(app.video.playCount, 0, 'preference change never autoplays video');

  app.window.pageYOffset = 1800;
  app.window.scrollY = 1800;
  app.dispatch('scroll');
  app.flushAnimationFrames();
  assert.equal(app.journey.style.getPropertyValue('--p'), '', 'scrolling cannot restart a disabled driver');

  app.motionQuery.set(false);
  assert.notEqual(app.root.style.getPropertyValue('--hp'), '', 'hero timeline is restored at the current position');
  assert.notEqual(app.journey.style.getPropertyValue('--p'), '', 'desktop journey driver is registered again');
  assert.equal(app.video.playCount, 0, 'video remains user-initiated after motion is re-enabled');
});

test('a page loaded with reduced motion can register timelines when the preference is disabled', () => {
  const app = boot({ width: 1280, reduced: true, scroll: 3900 });
  assert.equal(app.root.style.getPropertyValue('--hp'), '');
  assert.equal(app.journey.style.getPropertyValue('--p'), '');

  app.motionQuery.set(false);
  assert.equal(app.journey.getAttribute('data-step'), '5');
  assert.ok(app.journey.classList.contains('is-final'));
});

const journeyThresholds = [
  // Progress, active story step, KDS state. A kitchen ticket arrives at 0.56;
  // Ready begins with pickup at 0.72, not while Preparing is still active.
  [0, 1, null],
  [0.2599, 1, null],
  [0.26, 2, null],
  [0.45, 2, null],
  [0.54, 2, null],
  [0.5599, 2, null],
  [0.56, 3, '1'],
  [0.62, 3, '1'],
  [0.6399, 3, '1'],
  [0.64, 3, '2'],
  [0.7, 3, '2'],
  [0.7199, 3, '2'],
  [0.72, 4, '3'],
  [0.8, 4, '3'],
  [0.8599, 4, '3'],
  [0.86, 5, '3'],
  [0.9699, 5, '3'],
  [0.97, 5, '3'],
  [1, 5, '3'],
];

for (const direction of ['forward', 'reverse']) {
  test(`journey receipt, KDS and pickup thresholds stay synchronized during ${direction} scroll`, () => {
    // An integer 3000px travel span keeps exact boundary checks independent of
    // floating-point subtraction from the viewport height.
    const app = boot({ width: 1280, height: 800 });
    const checkpoints = direction === 'forward' ? journeyThresholds : [...journeyThresholds].reverse();
    for (const [progress, step, kds] of checkpoints) {
      const scroll = app.journey.top + progress * (app.journey.height - app.window.innerHeight);
      app.window.pageYOffset = scroll;
      app.window.scrollY = scroll;
      app.dispatch('scroll');
      app.flushAnimationFrames();
      const state = `${direction} at ${progress}`;
      assert.equal(app.journey.style.getPropertyValue('--p'), progress.toFixed(4), `${state}: CSS progress`);
      assert.equal(app.journey.getAttribute('data-step'), String(step), `${state}: active story step`);
      assert.equal(app.journey.getAttribute('data-kds'), kds, `${state}: visible kitchen state`);
      assert.equal(app.journey.classList.contains('is-final'), progress >= 0.97, `${state}: final frame`);
      app.journey.steps.forEach((item, index) => {
        assert.equal(item.classList.contains('is-on'), index + 1 === step, `${state}: step ${index + 1} emphasis`);
        assert.equal(item.classList.contains('is-done'), index + 1 < step, `${state}: step ${index + 1} completion`);
      });
    }
  });
}
