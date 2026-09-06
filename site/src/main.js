/* BIZBOT marketing site — progressive enhancement only. The page is fully
   readable without this file; it adds motion, tabs, the mobile menu and the
   lead-form submission. */
(function () {
  'use strict';
  var doc = document;
  var root = doc.documentElement;
  root.classList.remove('no-js');

  var reduceMotion = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  /* ---------- header ---------- */
  var header = doc.getElementById('header');
  function onScroll() {
    if (header) header.classList.toggle('is-scrolled', window.scrollY > 8);
  }
  window.addEventListener('scroll', onScroll, { passive: true });
  onScroll();

  var toggle = doc.querySelector('.nav-toggle');
  var mobile = doc.getElementById('mobile-menu');
  function setMenu(open) {
    if (!toggle || !mobile) return;
    toggle.setAttribute('aria-expanded', open ? 'true' : 'false');
    mobile.hidden = !open;
    doc.body.style.overflow = open ? 'hidden' : '';
  }
  if (toggle && mobile) {
    toggle.addEventListener('click', function () {
      setMenu(toggle.getAttribute('aria-expanded') !== 'true');
    });
    mobile.addEventListener('click', function (e) {
      if (e.target.closest('a')) setMenu(false);
    });
    doc.addEventListener('keydown', function (e) {
      if (e.key === 'Escape') setMenu(false);
    });
    window.addEventListener('resize', function () {
      if (window.innerWidth > 1060) setMenu(false);
    });
  }

  /* ---------- reveal on scroll ---------- */
  var reveals = Array.prototype.slice.call(doc.querySelectorAll('.reveal'));
  if (!('IntersectionObserver' in window) || reduceMotion) {
    reveals.forEach(function (el) { el.classList.add('in'); });
  } else {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (en) {
        if (en.isIntersecting) { en.target.classList.add('in'); io.unobserve(en.target); }
      });
    }, { rootMargin: '0px 0px -8% 0px', threshold: 0.08 });
    reveals.forEach(function (el) { io.observe(el); });
    // Anything already above the fold on load.
    setTimeout(function () {
      reveals.forEach(function (el) {
        var r = el.getBoundingClientRect();
        if (r.top < window.innerHeight && r.bottom > 0) el.classList.add('in');
      });
    }, 60);
  }

  /* ---------- active nav link ---------- */
  var navLinks = Array.prototype.slice.call(doc.querySelectorAll('.main-nav a[href^="#"]'));
  var sections = navLinks.map(function (a) { return doc.querySelector(a.getAttribute('href')); }).filter(Boolean);
  if ('IntersectionObserver' in window && sections.length) {
    var visible = {};
    var so = new IntersectionObserver(function (entries) {
      entries.forEach(function (en) { visible[en.target.id] = en.isIntersecting; });
      var current = null;
      sections.forEach(function (s) { if (!current && visible[s.id]) current = s.id; });
      navLinks.forEach(function (a) {
        a.classList.toggle('is-active', current !== null && a.getAttribute('href') === '#' + current);
      });
    }, { rootMargin: '-40% 0px -55% 0px', threshold: 0 });
    sections.forEach(function (s) { so.observe(s); });
  }

  /* ---------- showcase tabs ---------- */
  var tabs = Array.prototype.slice.call(doc.querySelectorAll('.tab[role="tab"]'));
  var panels = Array.prototype.slice.call(doc.querySelectorAll('.panel[role="tabpanel"]'));
  function selectTab(id, focus) {
    tabs.forEach(function (t) {
      var on = t.dataset.tab === id;
      t.setAttribute('aria-selected', on ? 'true' : 'false');
      t.tabIndex = on ? 0 : -1;
      if (on && focus) t.focus();
    });
    panels.forEach(function (p) {
      var on = p.id === 'panel-' + id;
      p.hidden = !on;
      if (on) syncVideo(p);
      else pauseVideo(p);
    });
  }
  tabs.forEach(function (t, i) {
    t.addEventListener('click', function () { selectTab(t.dataset.tab, false); });
    t.addEventListener('keydown', function (e) {
      var dir = e.key === 'ArrowRight' ? 1 : e.key === 'ArrowLeft' ? -1 : 0;
      if (!dir) return;
      if (root.dir === 'rtl') dir = -dir;
      e.preventDefault();
      var next = tabs[(i + dir + tabs.length) % tabs.length];
      selectTab(next.dataset.tab, true);
    });
  });
  // "Discover more" links and footer product links open the matching tab.
  doc.addEventListener('click', function (e) {
    var a = e.target.closest('a[data-tab]');
    if (!a) return;
    selectTab(a.dataset.tab, false);
  });
  if (location.hash.indexOf('#showcase-') === 0) {
    var wanted = location.hash.replace('#showcase-', '');
    if (tabs.some(function (t) { return t.dataset.tab === wanted; })) {
      selectTab(wanted, false);
      var sc = doc.getElementById('showcase');
      if (sc) setTimeout(function () { sc.scrollIntoView(); }, 0);
    }
  }

  /* ---------- thumbnails → stage ---------- */
  var LAND = [480, 800, 1200, 1600];
  var PORT = [360, 600, 900];
  function srcsetFor(name) {
    var ws = name.indexOf('kiosk') === 0 ? PORT : LAND;
    return ws.map(function (w) { return '/assets/shots/' + name + '-' + w + '.webp ' + w + 'w'; }).join(', ');
  }
  panels.forEach(function (p) {
    var img = p.querySelector('[data-stage-img]');
    var video = p.querySelector('video.kiosk-video');
    var caption = p.querySelector('[data-caption]');
    var thumbs = Array.prototype.slice.call(p.querySelectorAll('.thumb'));
    thumbs.forEach(function (b) {
      b.addEventListener('click', function () {
        var shot = b.dataset.shot;
        thumbs.forEach(function (x) {
          var on = x === b;
          x.classList.toggle('is-active', on);
          x.setAttribute('aria-pressed', on ? 'true' : 'false');
        });
        if (caption) caption.textContent = b.getAttribute('aria-label') || '';
        if (shot === 'video') {
          if (img) img.hidden = true;
          if (video) { video.hidden = false; playVideo(video); }
          return;
        }
        if (video) { video.hidden = true; video.pause(); }
        if (img) {
          var ws = shot.indexOf('kiosk') === 0 ? PORT : LAND;
          img.src = '/assets/shots/' + shot + '-' + ws[ws.length - 2] + '.webp';
          img.srcset = srcsetFor(shot);
          img.hidden = false;
          img.alt = (p.querySelector('h3') ? p.querySelector('h3').textContent + ' — ' : '') + (b.getAttribute('aria-label') || '');
        }
      });
    });
  });

  /* ---------- video: play only while visible ---------- */
  function playVideo(v) {
    if (!v || v.hidden || reduceMotion) return;
    var pr = v.play();
    if (pr && pr.catch) pr.catch(function () {});
  }
  function pauseVideo(scope) {
    var v = scope.querySelector ? scope.querySelector('video') : scope;
    if (v && !v.paused) v.pause();
  }
  function syncVideo(scope) {
    var v = scope.querySelector('video');
    if (!v) return;
    var r = v.getBoundingClientRect();
    if (r.top < window.innerHeight && r.bottom > 0) playVideo(v);
  }
  var videos = Array.prototype.slice.call(doc.querySelectorAll('video'));
  if ('IntersectionObserver' in window) {
    var vo = new IntersectionObserver(function (entries) {
      entries.forEach(function (en) {
        if (en.isIntersecting) playVideo(en.target); else pauseVideo(en.target);
      });
    }, { threshold: 0.25 });
    videos.forEach(function (v) { vo.observe(v); });
  }

  /* ---------- lead form ---------- */
  var form = doc.getElementById('lead-form');
  if (form) {
    var t0 = form.querySelector('input[name="t0"]');
    if (t0) t0.value = String(Date.now());
    var status = form.querySelector('.form-status');
    var submit = form.querySelector('button[type="submit"]');
    var sales = form.dataset.sales || '';

    function setStatus(kind, text, withMail) {
      if (!status) return;
      status.className = 'form-status' + (kind ? ' is-' + kind : '');
      status.innerHTML = '';
      status.appendChild(doc.createTextNode(text));
      if (withMail && sales) {
        status.appendChild(doc.createTextNode(' '));
        var a = doc.createElement('a');
        a.href = 'mailto:' + sales + '?subject=' + encodeURIComponent('BIZBOT demo request');
        a.textContent = sales;
        a.dir = 'ltr';
        status.appendChild(a);
      }
    }
    function markInvalid(el, bad) {
      var f = el.closest('.field');
      if (f) f.classList.toggle('is-invalid', bad);
    }
    Array.prototype.forEach.call(form.elements, function (el) {
      el.addEventListener('input', function () { markInvalid(el, false); });
      el.addEventListener('change', function () { markInvalid(el, false); });
    });

    form.addEventListener('submit', function (e) {
      e.preventDefault();
      var bad = false;
      Array.prototype.forEach.call(form.querySelectorAll('[required]'), function (el) {
        var ok = el.checkValidity();
        markInvalid(el, !ok);
        if (!ok && !bad) { bad = true; el.focus(); }
      });
      if (bad) { setStatus('error', status.dataset.invalid, false); return; }

      var data = {};
      new FormData(form).forEach(function (v, k) { data[k] = typeof v === 'string' ? v : ''; });
      data.page = location.href;

      submit.setAttribute('aria-busy', 'true');
      var label = submit.firstChild;
      var original = label && label.nodeType === 3 ? label.nodeValue : null;
      if (original !== null) label.nodeValue = submit.dataset.sending || original;
      setStatus('', '');

      var ctrl = 'AbortController' in window ? new AbortController() : null;
      var timer = ctrl ? setTimeout(function () { ctrl.abort(); }, 15000) : null;
      fetch(form.action, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        body: JSON.stringify(data),
        signal: ctrl ? ctrl.signal : undefined,
      })
        .then(function (r) { return r.json().catch(function () { return {}; }).then(function (j) { return { ok: r.ok, body: j }; }); })
        .then(function (res) {
          if (res.ok && res.body && res.body.ok) {
            form.classList.add('is-sent');
            setStatus('success', status.dataset.success);
            return;
          }
          if (res.body && res.body.code === 'invalid' && res.body.fields) {
            res.body.fields.forEach(function (name) {
              var el = form.elements[name];
              if (el) markInvalid(el, true);
            });
            setStatus('error', status.dataset.invalid, false);
            return;
          }
          setStatus('error', status.dataset.error, true);
        })
        .catch(function () { setStatus('error', status.dataset.error, true); })
        .then(function () {
          if (timer) clearTimeout(timer);
          submit.removeAttribute('aria-busy');
          if (original !== null) label.nodeValue = original;
        });
    });
  }
})();
