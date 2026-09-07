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
    var focusWasInside = mobile.contains(doc.activeElement);
    toggle.setAttribute('aria-expanded', open ? 'true' : 'false');
    mobile.hidden = !open;
    doc.body.style.overflow = open ? 'hidden' : '';
    if (open) {
      var first = mobile.querySelector('a, button, [tabindex]:not([tabindex="-1"])');
      if (first) first.focus();
    } else if (focusWasInside) {
      toggle.focus();
    }
  }
  if (toggle && mobile) {
    toggle.addEventListener('click', function () {
      setMenu(toggle.getAttribute('aria-expanded') !== 'true');
    });
    mobile.addEventListener('click', function (e) {
      if (e.target.closest('a')) setMenu(false);
    });
    doc.addEventListener('keydown', function (e) {
      if (mobile.hidden) return;
      if (e.key === 'Escape') {
        e.preventDefault();
        setMenu(false);
        return;
      }
      if (e.key === 'Tab') {
        var items = [toggle].concat(Array.prototype.slice.call(mobile.querySelectorAll('a, button, [tabindex]:not([tabindex="-1"])')));
        var first = items[0];
        var last = items[items.length - 1];
        if (e.shiftKey && doc.activeElement === first) { e.preventDefault(); last.focus(); }
        else if (!e.shiftKey && doc.activeElement === last) { e.preventDefault(); first.focus(); }
      }
    });
    window.addEventListener('resize', function () {
      if (window.innerWidth > 1120) setMenu(false);
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

  /* ---------- scene depth: pointer tilt (fine pointers) + scroll parallax ---------- */
  var finePointer = window.matchMedia && window.matchMedia('(pointer: fine)').matches;
  var depthMotion = finePointer && window.innerWidth > 1024;
  var scenes = Array.prototype.slice.call(doc.querySelectorAll('.scene'));
  if (!reduceMotion && scenes.length) {
    if (depthMotion) {
      Array.prototype.forEach.call(doc.querySelectorAll('.scene[data-tilt]'), function (sc) {
        var host = sc.closest('.hero') || sc;
        var tx = 0, ty = 0, raf = 0;
        function apply() {
          raf = 0;
          sc.style.setProperty('--ry', (tx * 4).toFixed(2) + 'deg');
          sc.style.setProperty('--rx', (-ty * 3).toFixed(2) + 'deg');
          sc.style.setProperty('--px', (tx * 12).toFixed(1) + 'px');
          sc.style.setProperty('--py', (ty * 9).toFixed(1) + 'px');
        }
        host.addEventListener('pointermove', function (e) {
          var r = sc.getBoundingClientRect();
          if (!r.width) return;
          tx = Math.max(-1, Math.min(1, ((e.clientX - r.left) / r.width - 0.5) * 2));
          ty = Math.max(-1, Math.min(1, ((e.clientY - r.top) / r.height - 0.5) * 2));
          if (!raf) raf = requestAnimationFrame(apply);
        });
        host.addEventListener('pointerleave', function () {
          tx = 0; ty = 0;
          if (!raf) raf = requestAnimationFrame(apply);
        });
      });
    }
    // Soft spotlight that follows the pointer across the hero background.
    var heroEl = doc.querySelector('.hero');
    if (heroEl && depthMotion) {
      var lraf = 0, lx = 0, ly = 0;
      heroEl.addEventListener('pointermove', function (e) {
        var r = heroEl.getBoundingClientRect();
        lx = ((e.clientX - r.left) / r.width) * 100; ly = ((e.clientY - r.top) / r.height) * 100;
        if (!lraf) lraf = requestAnimationFrame(function () {
          lraf = 0;
          heroEl.style.setProperty('--mx', lx.toFixed(1) + '%');
          heroEl.style.setProperty('--my', ly.toFixed(1) + '%');
          heroEl.classList.add('is-lit');
        });
      });
      heroEl.addEventListener('pointerleave', function () { heroEl.classList.remove('is-lit'); });
    }
    // Gentle vertical parallax for device layers while a scene crosses the viewport.
    var live = [];
    var sraf = 0;
    function parallax() {
      sraf = 0;
      var vh = window.innerHeight || 1;
      live.forEach(function (sc) {
        var r = sc.getBoundingClientRect();
        var t = ((r.top + r.height / 2) - vh / 2) / vh; // -0.5 … 0.5 while visible
        sc.style.setProperty('--sy', (Math.max(-1, Math.min(1, t)) * -18).toFixed(1) + 'px');
      });
    }
    if (depthMotion && 'IntersectionObserver' in window) {
      var po = new IntersectionObserver(function (entries) {
        entries.forEach(function (en) {
          var i = live.indexOf(en.target);
          if (en.isIntersecting && i < 0) live.push(en.target);
          else if (!en.isIntersecting && i >= 0) live.splice(i, 1);
        });
        if (!sraf) sraf = requestAnimationFrame(parallax);
      }, { threshold: 0 });
      scenes.forEach(function (sc) { po.observe(sc); });
      window.addEventListener('scroll', function () { if (live.length && !sraf) sraf = requestAnimationFrame(parallax); }, { passive: true });
    }
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
      if (!on) pauseVideo(p);
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

  /* ---------- video: user-initiated, and paused when hidden/off-screen ---------- */
  function playVideo(v) {
    if (!v || v.hidden || reduceMotion) return;
    var pr = v.play();
    if (pr && pr.catch) pr.catch(function () {});
  }
  function pauseVideo(scope) {
    var v = scope.querySelector ? scope.querySelector('video') : scope;
    if (v && !v.paused) v.pause();
  }
  var videos = Array.prototype.slice.call(doc.querySelectorAll('video'));
  if ('IntersectionObserver' in window) {
    var vo = new IntersectionObserver(function (entries) {
      entries.forEach(function (en) {
        if (!en.isIntersecting) pauseVideo(en.target);
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
