// HiFidelity Remote — service worker. Precaches the app shell so the
// installed PWA launches offline; dynamic data (/state, /artwork) and
// command POSTs always hit the network and are never cached.
"use strict";

// Bump this whenever the shell assets change so an already-installed PWA
// drops the stale cache on activate and picks up the new build.
var CACHE = "hifi-remote-v3";
var SHELL = [
  "/",
  "/index.html",
  "/assets/app.js",
  "/assets/style.css",
  "/manifest.webmanifest",
  "/assets/icon-192.png",
  "/assets/icon-512.png"
];

self.addEventListener("install", function (e) {
  e.waitUntil(
    caches.open(CACHE)
      .then(function (c) { return c.addAll(SHELL); })
      .then(function () { return self.skipWaiting(); })
  );
});

self.addEventListener("activate", function (e) {
  e.waitUntil(
    caches.keys()
      .then(function (keys) {
        return Promise.all(keys.map(function (k) {
          return k === CACHE ? null : caches.delete(k);
        }));
      })
      .then(function () { return self.clients.claim(); })
  );
});

self.addEventListener("fetch", function (e) {
  var req = e.request;
  // Commands POST straight to the network — never intercept.
  if (req.method !== "GET") return;

  var url = new URL(req.url);

  // Navigations: network-first, fall back to the cached shell when offline.
  if (req.mode === "navigate") {
    e.respondWith(
      fetch(req).catch(function () { return caches.match("/"); })
    );
    return;
  }

  // Only the static app shell is cacheable. Everything else — /state,
  // /artwork/<id>, and the dynamic library API (/tracks, /albums, /artists,
  // /playlists and their search variants with ?q=) — MUST hit the network so
  // results are never served stale. Caching those was making library search
  // and lists go empty/stale on an installed PWA.
  var isShell = url.pathname === "/" || SHELL.indexOf(url.pathname) !== -1;
  if (!isShell) return;

  // Static shell assets: stale-while-revalidate. Serve the cached copy
  // immediately (instant load, works offline) while fetching a fresh copy in
  // the background, so the next load self-heals after a new app build.
  e.respondWith(
    caches.open(CACHE).then(function (c) {
      return c.match(req).then(function (hit) {
        var network = fetch(req).then(function (res) {
          if (res && res.ok) c.put(req, res.clone());
          return res;
        }).catch(function () { return hit; });
        return hit || network;
      });
    })
  );
});
