// HiFidelity Remote — vanilla ES2020. Polls /state every 800 ms with
// ETag-driven If-None-Match short-circuit; POSTs commands to the API.
// No build tooling, no npm. Runs in any modern Safari (macOS/iOS) or
// Chromium-based browser.
(function () {
  "use strict";

  var POLL_MS = 800;
  var BACKOFF_MS = 3000;

  var els = {
    title: document.getElementById("title"),
    artist: document.getElementById("artist"),
    album: document.getElementById("album"),
    art: document.getElementById("artwork"),
    artFallback: document.getElementById("art-fallback"),
    seek: document.getElementById("seek"),
    timeCurrent: document.getElementById("time-current"),
    timeTotal: document.getElementById("time-total"),
    btnPrev: document.getElementById("btn-prev"),
    btnNext: document.getElementById("btn-next"),
    btnToggle: document.getElementById("btn-toggle"),
    btnShuffle: document.getElementById("btn-shuffle"),
    btnRepeat: document.getElementById("btn-repeat"),
    btnFav: document.getElementById("btn-fav"),
    btnMute: document.getElementById("btn-mute"),
    playGlyph: document.getElementById("play-glyph"),
    muteGlyph: document.getElementById("mute-glyph"),
    vol: document.getElementById("vol"),
    conn: document.getElementById("conn-status"),
  };

  var state = null;
  var lastEtag = null;
  var seekDragging = false;
  var volDragging = false;
  var currentArtworkId = null;
  var pollTimer = null;

  // When /artwork/<id> 404s (or fails to decode), hide the broken <img>
  // and reveal the text fallback. Re-armed on every new trackId so that
  // navigating back to a working track restores the image.
  els.art.addEventListener("error", function () {
    els.art.style.display = "none";
    els.artFallback.hidden = false;
  });
  els.art.addEventListener("load", function () {
    els.art.style.display = "";
    els.artFallback.hidden = true;
  });

  function fmtTime(secs) {
    if (!isFinite(secs) || secs < 0) secs = 0;
    var s = Math.floor(secs);
    var h = Math.floor(s / 3600);
    var m = Math.floor((s % 3600) / 60);
    var sec = s % 60;
    if (h > 0) return h + ":" + String(m).padStart(2, "0") + ":" + String(sec).padStart(2, "0");
    return m + ":" + String(sec).padStart(2, "0");
  }

  function setConn(status, label) {
    els.conn.dataset.state = status;
    els.conn.textContent = label;
  }

  function render(s) {
    state = s;
    var t = s.currentTrack;
    if (t) {
      els.title.textContent = t.title || "—";
      els.artist.textContent = t.artist || "—";
      els.album.textContent = t.album || "";
      var artId = t.trackId;
      if (artId !== currentArtworkId) {
        currentArtworkId = artId;
        els.art.src = "/artwork/" + artId;
        els.art.style.display = "";
        els.artFallback.hidden = true;
      }
    } else {
      els.title.textContent = "Nothing playing";
      els.artist.textContent = "";
      els.album.textContent = "";
      currentArtworkId = null;
      els.art.removeAttribute("src");
      els.art.style.display = "none";
      els.artFallback.hidden = false;
    }

    if (!seekDragging) {
      var dur = s.duration > 0 ? s.duration : 0;
      els.seek.max = dur || 1;
      var currentTime = Math.min(s.currentTime || 0, dur || 0);
      els.seek.value = currentTime;
      var pct = dur > 0 ? (currentTime / dur) * 100 : 0;
      els.seek.style.setProperty('--value', pct + '%');
      els.timeCurrent.textContent = fmtTime(s.currentTime || 0);
      els.timeTotal.textContent = fmtTime(dur);
    }
    if (!volDragging) {
      var vol = s.volume == null ? 0.7 : s.volume;
      els.vol.value = vol;
      els.vol.style.setProperty('--value', (vol * 100) + '%');
    }

    els.playGlyph.textContent = s.isPlaying ? "❚❚" : "▶";
    els.btnToggle.setAttribute("aria-label", s.isPlaying ? "Pause" : "Play");
    els.btnShuffle.setAttribute("aria-pressed", s.isShuffleEnabled ? "true" : "false");
    els.btnRepeat.setAttribute("aria-pressed", s.repeatMode && s.repeatMode !== "off" ? "true" : "false");
    els.btnRepeat.firstElementChild.textContent = s.repeatMode === "one" ? "1↻" : "↻";
    els.btnFav.setAttribute("aria-pressed", t && t.isFavorite ? "true" : "false");
    els.btnMute.setAttribute("aria-pressed", s.isMuted ? "true" : "false");
    els.muteGlyph.textContent = s.isMuted ? "🔇" : "🔊";
  }

  function schedulePoll(delay) {
    if (pollTimer) clearTimeout(pollTimer);
    pollTimer = setTimeout(pollState, delay);
  }

  function pollState() {
    var headers = {};
    if (lastEtag) headers["If-None-Match"] = lastEtag;
    fetch("/state", { headers: headers, cache: "no-store" }).then(function (r) {
      if (r.status === 304) {
        setConn("ok", "Live");
        schedulePoll(POLL_MS);
        return null;
      }
      if (!r.ok) throw new Error("HTTP " + r.status);
      var et = r.headers.get("ETag");
      if (et) lastEtag = et;
      setConn("ok", "Live");
      return r.json();
    }).then(function (json) {
      if (json) render(json);
      schedulePoll(POLL_MS);
    }).catch(function (err) {
      // Invalidate the cached ETag on error so the next successful poll
      // receives a full 200 response — otherwise the server might match
      // the stale tag and reply 304, leaving the UI frozen.
      lastEtag = null;
      setConn("error", "Offline");
      schedulePoll(BACKOFF_MS);
    });
  }

  function postCmd(path, body) {
    var opts = { method: "POST" };
    if (body) {
      opts.headers = { "Content-Type": "application/json" };
      opts.body = JSON.stringify(body);
    }
    return fetch(path, opts).then(function (r) {
      // Force an immediate refresh so UI doesn't lag the polling cadence.
      schedulePoll(0);
      return r;
    }).catch(function (err) {
      setConn("error", "Offline");
    });
  }

  // Wire up controls
  els.btnPrev.addEventListener("click", function () { postCmd("/previous"); });
  els.btnNext.addEventListener("click", function () { postCmd("/next"); });
  els.btnToggle.addEventListener("click", function () { postCmd("/toggle"); });
  els.btnShuffle.addEventListener("click", function () { postCmd("/shuffle"); });
  els.btnRepeat.addEventListener("click", function () { postCmd("/repeat"); });
  els.btnFav.addEventListener("click", function () { postCmd("/favorite"); });
  els.btnMute.addEventListener("click", function () { postCmd("/mute"); });

  els.seek.addEventListener("mousedown", function () { seekDragging = true; });
  els.seek.addEventListener("touchstart", function () { seekDragging = true; }, { passive: true });
  function commitSeek() {
    var seconds = parseFloat(els.seek.value);
    if (isFinite(seconds)) postCmd("/seek", { seconds: seconds });
    seekDragging = false;
  }
  els.seek.addEventListener("mouseup", commitSeek);
  els.seek.addEventListener("touchend", commitSeek);
  els.seek.addEventListener("change", commitSeek);

  els.vol.addEventListener("mousedown", function () { volDragging = true; });
  els.vol.addEventListener("touchstart", function () { volDragging = true; }, { passive: true });
  function commitVol() {
    var v = parseFloat(els.vol.value);
    if (isFinite(v)) postCmd("/volume", { volume: v });
    volDragging = false;
  }
  els.vol.addEventListener("mouseup", commitVol);
  els.vol.addEventListener("touchend", commitVol);
  els.vol.addEventListener("change", commitVol);

  // Tap-to-toggle on artwork, for Apple-style remote feel.
  document.querySelector(".art-wrap").addEventListener("click", function () {
    postCmd("/toggle");
  });

  document.addEventListener("visibilitychange", function () {
    if (document.visibilityState === "visible") schedulePoll(0);
  });

  // ---------- Browse drawer (M7b) ----------
  var drawerEls = {
    drawer: document.getElementById("drawer"),
    open: document.getElementById("btn-browse"),
    close: document.getElementById("drawer-close"),
    back: document.getElementById("drawer-back"),
    title: document.getElementById("drawer-title"),
    list: document.getElementById("drawer-list"),
    search: document.getElementById("search"),
    tabs: Array.prototype.slice.call(document.querySelectorAll(".tab")),
  };

  // Stack of views: {kind:"list", tab:"tracks|albums|artists|playlists", q:""}
  // or {kind:"album", id, name, sub}
  // or {kind:"artist", id, name, sub}
  // or {kind:"playlist", id, name, sub}
  var navStack = [];
  var searchDebounce = null;

  // Monotonically increasing counter. Bumped on every nav transition and on
  // every fresh list load. Fetches capture the value at dispatch time and
  // check it on resolution — a mismatched seq means the context changed while
  // the request was in flight, so the result is silently dropped.
  var loadSeq = 0;

  var PAGE_SIZE = 100;

  // IntersectionObserver for the scroll sentinel. Disconnected on each fresh
  // list load and re-armed after the first page renders.
  var sentinelObserver = null;

  function teardownSentinel() {
    if (sentinelObserver) {
      sentinelObserver.disconnect();
      sentinelObserver = null;
    }
    var old = drawerEls.list.querySelector(".scroll-sentinel");
    if (old) old.remove();
  }

  // Cancel any pending search debounce — call on every nav transition
  // (tab switch, back, close, entity push) so a stale "Tracks" search
  // can't populate an "Albums" drawer after the tab changed.
  function cancelSearchDebounce() {
    if (searchDebounce) {
      clearTimeout(searchDebounce);
      searchDebounce = null;
    }
  }

  function fmtSeconds(secs) {
    return fmtTime(secs || 0);
  }

  function showDrawer() {
    drawerEls.drawer.hidden = false;
    if (navStack.length === 0) navStack.push({ kind: "list", tab: "tracks", q: "" });
    renderCurrent();
  }
  function hideDrawer() {
    cancelSearchDebounce();
    teardownSentinel();
    loadSeq++;
    drawerEls.drawer.hidden = true;
  }
  function popOrClose() {
    cancelSearchDebounce();
    teardownSentinel();
    loadSeq++;
    if (navStack.length > 1) {
      navStack.pop();
      renderCurrent();
    } else {
      hideDrawer();
    }
  }

  function setActiveTab(tab) {
    drawerEls.tabs.forEach(function (b) {
      b.setAttribute("aria-selected", b.dataset.tab === tab ? "true" : "false");
    });
  }

  function renderCurrent() {
    var top = navStack[navStack.length - 1];
    if (!top) { hideDrawer(); return; }
    if (top.kind === "list") {
      drawerEls.title.textContent = "Library";
      setActiveTab(top.tab);
      drawerEls.search.value = top.q || "";
      drawerEls.search.disabled = (top.tab === "playlists");
      drawerEls.search.placeholder = top.tab === "playlists" ? "" : "Search " + top.tab + "…";
      loadList(top);
    } else {
      drawerEls.title.textContent = top.name || "Tracks";
      drawerEls.tabs.forEach(function (b) { b.setAttribute("aria-selected", "false"); });
      drawerEls.search.value = "";
      drawerEls.search.disabled = true;
      drawerEls.search.placeholder = "";
      loadEntityTracks(top);
    }
  }

  function setListEmpty(text) {
    drawerEls.list.innerHTML = '<div class="list-empty">' + text + "</div>";
  }

  function setListSpinner() {
    setListEmpty("Loading…");
  }

  function listURL(top, offset) {
    var qs = [];
    qs.push("limit=" + PAGE_SIZE);
    qs.push("offset=" + offset);
    if (top.q) qs.push("q=" + encodeURIComponent(top.q));
    var path = "/" + top.tab;
    return path + "?" + qs.join("&");
  }

  // Append track rows for one page onto drawerEls.list.
  // `sharedIds` is the single array shared across all pages of this load;
  // rows close over it by reference so a click always sees the full
  // accumulated list at the moment it fires, not just the page snapshot.
  function appendTrackRows(tracks, sharedIds) {
    var startIdx = sharedIds.length;
    tracks.forEach(function (t) { sharedIds.push(t.trackId); });
    var frag = document.createDocumentFragment();
    tracks.forEach(function (t, i) {
      var idx = startIdx + i;
      var row = document.createElement("div");
      row.className = "row";
      row.innerHTML =
        '<div class="row-thumb" style="background-image:url(/artwork/' + t.trackId + ');"></div>' +
        '<div class="row-text">' +
          '<div class="row-title"></div>' +
          '<div class="row-sub"></div>' +
        '</div>' +
        '<div class="row-meta"></div>';
      row.querySelector(".row-title").textContent = t.title || "Unknown";
      row.querySelector(".row-sub").textContent = (t.artist || "") + (t.album ? " · " + t.album : "");
      row.querySelector(".row-meta").textContent = fmtSeconds(t.duration);
      row.addEventListener("click", function () {
        postCmd("/queue/playTracks", { trackIds: sharedIds, startAt: idx });
        hideDrawer();
      });
      frag.appendChild(row);
    });
    drawerEls.list.appendChild(frag);
  }

  function appendAlbumRows(albums) {
    var frag = document.createDocumentFragment();
    albums.forEach(function (a) {
      var row = document.createElement("div");
      row.className = "row";
      row.innerHTML =
        '<div class="row-thumb"></div>' +
        '<div class="row-text">' +
          '<div class="row-title"></div>' +
          '<div class="row-sub"></div>' +
        '</div>' +
        '<div class="row-meta"></div>';
      row.querySelector(".row-title").textContent = a.title || "Unknown Album";
      row.querySelector(".row-sub").textContent = (a.albumArtist || "Various Artists") + (a.year ? " · " + a.year : "");
      row.querySelector(".row-meta").textContent = a.trackCount + (a.trackCount === 1 ? " track" : " tracks");
      row.addEventListener("click", function () {
        cancelSearchDebounce();
        navStack.push({ kind: "album", id: a.id, name: a.title || "Album" });
        renderCurrent();
      });
      frag.appendChild(row);
    });
    drawerEls.list.appendChild(frag);
  }

  function appendArtistRows(artists) {
    var frag = document.createDocumentFragment();
    artists.forEach(function (a) {
      var row = document.createElement("div");
      row.className = "row";
      row.innerHTML =
        '<div class="row-text">' +
          '<div class="row-title"></div>' +
          '<div class="row-sub"></div>' +
        '</div>' +
        '<div class="row-meta"></div>';
      row.querySelector(".row-title").textContent = a.name || "Unknown Artist";
      row.querySelector(".row-sub").textContent = a.albumCount + (a.albumCount === 1 ? " album" : " albums");
      row.querySelector(".row-meta").textContent = a.trackCount + (a.trackCount === 1 ? " track" : " tracks");
      row.addEventListener("click", function () {
        cancelSearchDebounce();
        navStack.push({ kind: "artist", id: a.id, name: a.name || "Artist" });
        renderCurrent();
      });
      frag.appendChild(row);
    });
    drawerEls.list.appendChild(frag);
  }

  // Arm the IntersectionObserver sentinel that fires the next page load.
  // Called after each page that is not the last. `loadNextPage` is the
  // callback that fetches page N+1.
  function armSentinel(loadNextPage) {
    teardownSentinel();
    var sentinel = document.createElement("div");
    sentinel.className = "scroll-sentinel";
    drawerEls.list.appendChild(sentinel);

    // The list (.drawer-list) is an internally-scrolling flex child, NOT the
    // page — so the observer root MUST be that scroll container, not the
    // default viewport, or the sentinel never registers as intersecting and
    // only the first page ever loads. rootMargin prefetches the next page
    // before the bottom is reached; threshold:0 fires on the first pixel.
    sentinelObserver = new IntersectionObserver(function (entries) {
      if (entries[0].isIntersecting) {
        teardownSentinel();
        loadNextPage();
      }
    }, { root: drawerEls.list, rootMargin: "400px 0px", threshold: 0 });
    sentinelObserver.observe(sentinel);
  }

  function loadList(top) {
    teardownSentinel();
    loadSeq++;
    var seq = loadSeq;

    if (top.tab === "playlists") {
      setListSpinner();
      fetch(listURL(top, 0), { cache: "no-store" }).then(function (r) {
        if (!r.ok) throw new Error("HTTP " + r.status);
        return r.json();
      }).then(function (data) {
        if (seq !== loadSeq) return;
        renderPlaylists(data || []);
      }).catch(function () {
        if (seq !== loadSeq) return;
        setListEmpty("Couldn't load.");
      });
      return;
    }

    // One shared array for all pages of this load; rows close over it by
    // reference so early-page clicks always queue the full accumulated list.
    var sharedTrackIds = [];
    setListSpinner();
    loadPage(top, 0, seq, sharedTrackIds);
  }

  function loadPage(top, offset, seq, sharedTrackIds) {
    fetch(listURL(top, offset), { cache: "no-store" }).then(function (r) {
      if (!r.ok) throw new Error("HTTP " + r.status);
      return r.json();
    }).then(function (data) {
      // Drop result if context changed while this request was in flight.
      if (seq !== loadSeq) return;

      if (top.tab === "tracks") {
        var tracks = (data && data.tracks) ? data.tracks : [];
        var total = (data && data.total) ? data.total : 0;

        if (offset === 0) {
          if (!tracks.length) { setListEmpty("No tracks."); return; }
          drawerEls.list.replaceChildren();
        }
        if (!tracks.length) return;

        appendTrackRows(tracks, sharedTrackIds);
        var rendered = sharedTrackIds.length;
        var exhausted = total ? rendered >= total : tracks.length < PAGE_SIZE;
        if (!exhausted) {
          armSentinel(function () { loadPage(top, rendered, seq, sharedTrackIds); });
        }

      } else if (top.tab === "albums") {
        var albums = data || [];

        if (offset === 0) {
          if (!albums.length) { setListEmpty("No albums."); return; }
          drawerEls.list.replaceChildren();
        }
        if (!albums.length) return;

        appendAlbumRows(albums);
        if (albums.length >= PAGE_SIZE) {
          armSentinel(function () { loadPage(top, offset + albums.length, seq, sharedTrackIds); });
        }

      } else if (top.tab === "artists") {
        var artists = data || [];

        if (offset === 0) {
          if (!artists.length) { setListEmpty("No artists."); return; }
          drawerEls.list.replaceChildren();
        }
        if (!artists.length) return;

        appendArtistRows(artists);
        if (artists.length >= PAGE_SIZE) {
          armSentinel(function () { loadPage(top, offset + artists.length, seq, sharedTrackIds); });
        }
      }
    }).catch(function () {
      if (seq !== loadSeq) return;
      if (offset === 0) setListEmpty("Couldn't load.");
    });
  }

  // Hard-cap entity track fetches at 200 rows to avoid O(N) DOM
  // construction and a thundering herd of /artwork/<id> requests on
  // 1000-track albums or smart playlists. Server enforcement is out of
  // scope for v1; this is the client-side guard.
  var ENTITY_TRACKS_LIMIT = 200;

  function loadEntityTracks(top) {
    teardownSentinel();
    loadSeq++;
    var seq = loadSeq;
    setListSpinner();
    var path;
    if (top.kind === "album") path = "/albums/" + top.id + "/tracks";
    else if (top.kind === "artist") path = "/artists/" + top.id + "/tracks";
    else if (top.kind === "playlist") path = "/playlists/" + top.id + "/tracks";
    else { setListEmpty(""); return; }
    path += "?limit=" + ENTITY_TRACKS_LIMIT;

    fetch(path, { cache: "no-store" }).then(function (r) {
      if (!r.ok) throw new Error("HTTP " + r.status);
      return r.json();
    }).then(function (tracks) {
      if (seq !== loadSeq) return;
      renderTracks(tracks || []);
    }).catch(function () {
      if (seq !== loadSeq) return;
      setListEmpty("Couldn't load.");
    });
  }

  // renderTracks is used only for entity-track detail views (album/artist/
  // playlist). The paginated list tabs use appendTrackRows directly.
  function renderTracks(tracks) {
    if (!tracks.length) { setListEmpty("No tracks."); return; }
    drawerEls.list.replaceChildren();
    appendTrackRows(tracks, []);
  }

  function renderPlaylists(lists) {
    if (!lists.length) { setListEmpty("No playlists."); return; }
    var frag = document.createDocumentFragment();
    lists.forEach(function (p) {
      var row = document.createElement("div");
      row.className = "row";
      row.innerHTML =
        '<div class="row-text">' +
          '<div class="row-title"></div>' +
          '<div class="row-sub"></div>' +
        '</div>' +
        '<div class="row-meta"></div>';
      row.querySelector(".row-title").textContent = p.name || "Playlist";
      row.querySelector(".row-sub").textContent = p.isSmart ? "Smart playlist" : (p.description || "");
      row.querySelector(".row-meta").textContent = p.trackCount + (p.trackCount === 1 ? " track" : " tracks");
      row.addEventListener("click", function () {
        cancelSearchDebounce();
        navStack.push({ kind: "playlist", id: p.id, name: p.name || "Playlist" });
        renderCurrent();
      });
      frag.appendChild(row);
    });
    drawerEls.list.replaceChildren(frag);
  }

  drawerEls.open.addEventListener("click", showDrawer);
  drawerEls.close.addEventListener("click", hideDrawer);
  drawerEls.back.addEventListener("click", popOrClose);
  drawerEls.tabs.forEach(function (b) {
    b.addEventListener("click", function () {
      cancelSearchDebounce();
      teardownSentinel();
      loadSeq++;
      navStack = [{ kind: "list", tab: b.dataset.tab, q: "" }];
      renderCurrent();
    });
  });
  drawerEls.search.addEventListener("input", function (e) {
    var top = navStack[navStack.length - 1];
    if (!top || top.kind !== "list") return;
    cancelSearchDebounce();
    searchDebounce = setTimeout(function () {
      searchDebounce = null;
      top.q = e.target.value.trim();
      loadList(top);
    }, 220);
  });

  if ("serviceWorker" in navigator) {
    window.addEventListener("load", function () {
      navigator.serviceWorker.register("/sw.js").catch(function (err) {
        console.warn("SW registration failed", err);
      });
    });
  }

  pollState();
})();
