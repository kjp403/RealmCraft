(function () {
  const root = document.querySelector("[data-peddler]");
  if (!root) return;

  // Poll cadence. The cart's state only changes on a 4-hour boundary and at UTC
  // midnight, so a minute is generous; the countdowns below tick locally every
  // second and do not need the network.
  const REFRESH_MS = 60000;
  const TIERS = { S: "s", A: "a", B: "b" };

  // MIRRORS PeddlerSchedule ON THE WORLD SERVER. Windows open on the 4-hour
  // boundary counted from the unix epoch (00:00, 04:00 ... 20:00 UTC) and stand
  // for 30 minutes. Kept here as well as there because the schedule is the one
  // thing about the cart that is knowable WITHOUT the world: a restart leaves
  // the last snapshot sitting in the gateway's cache, and a page that trusts
  // that snapshot alone reports "roaming" straight through an open window.
  // If the constants below ever change, change them in both places.
  const CYCLE_S = 4 * 60 * 60;
  const ACTIVE_S = 30 * 60;

  const statusEl = root.querySelector("[data-pd-status]");
  const zoneEl = root.querySelector("[data-pd-zone]");
  // Schema 2 additions. Looked up defensively: a browser holding a cached copy
  // of the previous page would otherwise take the whole widget down on a null.
  const nextWrapEl = root.querySelector("[data-pd-next-wrap]");
  const nextZoneEl = root.querySelector("[data-pd-next-zone]");
  const clocksEl = root.querySelector("[data-pd-clocks]");
  const stockEl = root.querySelector("[data-pd-stock]");
  const noteEl = root.querySelector("[data-pd-note]");

  let payload = null;
  let poll = 0;
  let tick = 0;
  // Absolute UTC second the next window opens, as the world reported it. The
  // window END is deliberately not stored: the snapshot's `time_remaining_seconds`
  // was measured when the world sent it, and rebasing that onto "now" stretches
  // the window every time the page reloads. It is derived from the cycle instead.
  let nextAt = 0;
  // Whether the previous render fell inside an open window, so the page can
  // notice the boundary passing between polls and re-read once.
  let windowWasOpen = null;

  // Unix second the window covering `nowS` opened at.
  function cycleStart(nowS) {
    return Math.floor(nowS / CYCLE_S) * CYCLE_S;
  }

  // True while the cart is DUE — which is not the same as standing. The world
  // places it opportunistically: the biome is chosen the moment the window
  // opens, but the cart only appears once that biome has a loaded instance,
  // so "window open, nothing standing" is a real and reportable state.
  function windowIsOpen(nowS) {
    return nowS - cycleStart(nowS) < ACTIVE_S;
  }

  function apiUrl() {
    const host = location.hostname;
    if (host === "localhost" || host === "127.0.0.1") return "http://127.0.0.1:8088/v1/peddler";
    return "https://api.arkenelle.com/v1/peddler";
  }

  function esc(s) {
    return String(s ?? "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function gold(n) {
    return Number(n || 0).toLocaleString("en-US");
  }

  // Seconds -> "1h 04m 12s" / "4:09". Returns "" for nothing left, so a caller
  // can decide what an elapsed clock should say instead of printing "0:00".
  function clock(seconds) {
    const s = Math.max(0, Math.floor(seconds));
    if (!s) return "";
    const h = Math.floor(s / 3600);
    const m = Math.floor((s % 3600) / 60);
    const sec = s % 60;
    if (h) return h + "h " + String(m).padStart(2, "0") + "m";
    return m + ":" + String(sec).padStart(2, "0");
  }

  function nowUtc() {
    return Math.floor(Date.now() / 1000);
  }

  function setStatus(text, kind) {
    statusEl.textContent = text;
    statusEl.dataset.kind = kind || "";
  }

  // --- rendering ------------------------------------------------------------

  function skeleton() {
    // Three cards, because the cart always sells exactly three. Sizing the
    // skeleton to the real answer means the layout does not jump when the data
    // lands.
    stockEl.innerHTML = Array.from({ length: 3 })
      .map(
        () => `<article class="pd-card pd-skel">
          <div class="pd-skel-line pd-skel-title"></div>
          <div class="pd-skel-line"></div>
          <div class="pd-skel-line pd-skel-short"></div>
        </article>`
      )
      .join("");
  }

  function renderStock(rows) {
    if (!Array.isArray(rows) || !rows.length) {
      stockEl.innerHTML = `<p class="muted">No stock reported yet.</p>`;
      return;
    }
    stockEl.innerHTML = rows
      .map((row) => {
        const tier = TIERS[String(row.tier || "").toUpperCase()] || "b";
        return `<article class="pd-card pd-tier-${tier}">
          <header class="pd-card-head">
            <h3>${esc(row.name)}</h3>
            <span class="pd-badge pd-badge-${tier}">${esc(String(row.tier || "?"))}</span>
          </header>
          <p class="pd-desc">${esc(row.description)}</p>
          <p class="pd-price">${gold(row.price)} <span>G</span></p>
        </article>`;
      })
      .join("");
  }

  // The two countdowns. Driven off absolute timestamps and re-derived every
  // second, so the numbers stay right across a sleeping tab, a slow poll, or a
  // clock the user changes mid-session.
  function renderClocks() {
    // Deliberately NOT gated on a live snapshot. The cycle is fixed UTC maths, so
    // "next appearance" is answerable even while the tracker is down — and a page
    // that goes blank the moment the world hiccups is exactly what sends players
    // hunting for a cart that was never standing in the first place.
    const now = nowUtc();
    const open = windowIsOpen(now);
    const parts = [];
    if (open) {
      parts.push(
        `<div class="pd-clock"><span class="pd-clock-label">Window closes in</span>` +
          `<strong class="pd-clock-value">${clock(cycleStart(now) + ACTIVE_S - now)}</strong></div>`
      );
    }
    parts.push(
      `<div class="pd-clock"><span class="pd-clock-label">Next appearance</span>` +
        `<strong class="pd-clock-value">${clock(nextSpawnAt(now) - now)}</strong></div>`
    );
    clocksEl.innerHTML = parts.join("");

    // The window opened or closed between polls. Re-render off the new state and
    // pull a fresh snapshot, rather than describing a cart that has packed up or
    // sitting on "between appearances" through the first minute of a new window.
    if (windowWasOpen !== null && windowWasOpen !== open) {
      windowWasOpen = open;
      render();
      load();
      return;
    }
    windowWasOpen = open;
  }

  // Prefer the world's own answer while it is still in the future, and fall back
  // to the cycle when the snapshot predates the window that has just opened.
  function nextSpawnAt(nowS) {
    return nextAt > nowS ? nextAt : cycleStart(nowS) + CYCLE_S;
  }

  // The forecast half of the banner: the ZONE the next cart sets up in, and
  // nothing more precise. A zone is a whole map, so this says which map to be
  // standing in when the window opens and leaves the cart itself to be found —
  // the missing piece was the hint, not the search.
  //
  // Drawn only while the snapshot's own next-spawn timestamp is still in the
  // future. A snapshot goes stale the instant the window it was forecasting
  // opens, and a line reading "next zone" about the window you are already in is
  // worse than no line at all. Hidden rather than blanked, so the banner never
  // shows a label with nothing under it (an older world sends no next_zone).
  function renderNextZone() {
    if (!nextWrapEl || !nextZoneEl) return;
    const zone = payload && payload.ok ? payload.next_zone : "";
    const fresh = nextAt > nowUtc();
    nextZoneEl.textContent = zone || "";
    nextWrapEl.hidden = !zone || !fresh;
  }

  function renderBanner() {
    renderNextZone();
    // FOUR STATES, NOT THREE. The old banner collapsed "no cart exists right now"
    // and "a cart is due and has not been placed yet" into one grey VANISHED /
    // ROAMING, and players read that as a peddler hiding somewhere they had to
    // search. Whether the window is open is local maths, so the page can draw
    // that distinction even when the snapshot is old, or missing entirely.
    const open = windowIsOpen(nowUtc());

    // Two different failures that must not wear the same label. The tracker being
    // UNREACHABLE is a fault worth reporting; the gateway answering "no snapshot
    // yet" is the ordinary state between the world starting and the cart's next
    // spawn, and calling that "offline" both contradicts the line underneath and
    // sends people looking for a break that isn't there.
    if (!payload || payload.unreachable) {
      setStatus("TRACKER OFFLINE", "off");
      zoneEl.textContent = open ? "Due now — zone unknown" : "Nowhere — between appearances";
      return;
    }
    if (!payload.ok) {
      setStatus("AWAITING WORLD", "wait");
      zoneEl.textContent = open ? "Due now — zone unknown" : "Nowhere — between appearances";
      return;
    }
    if (payload.is_active) {
      setStatus("ACTIVE IN-GAME", "on");
      zoneEl.textContent = payload.current_zone || "Standing — zone not reported";
      return;
    }
    if (open) {
      // Due, but not standing. The world picks the biome the moment the window
      // opens and places the cart on the first tick that biome has a loaded
      // instance, so this state resolves itself as soon as somebody is there.
      // `current_zone` is empty on a world that predates the export change — the
      // page has to read correctly either way.
      setStatus("DUE — NOT ARRIVED", "wait");
      zoneEl.textContent = payload.current_zone
        ? payload.current_zone + " (setting up)"
        : "Zone not reported yet";
      return;
    }
    setStatus("BETWEEN APPEARANCES", "off");
    zoneEl.textContent = "Nowhere — the cart is packed up";
  }

  function render() {
    renderBanner();
    renderClocks();
    if (!payload || !payload.ok) {
      stockEl.innerHTML = `<p class="muted">${esc(
        (payload && payload.msg) || "Today's stock will appear when the world reports in."
      )}</p>`;
      noteEl.textContent = "";
      return;
    }
    renderStock(payload.daily_stock);
    noteEl.textContent = noteText();
  }

  // The line that answers "where is it, then?". Ordered by what a player can act
  // on: a cart that is due but unplaced is worth explaining in full, while a
  // stale reading is only worth mentioning when nothing more useful applies.
  function noteText() {
    if (!payload || !payload.ok) return "";
    if (!payload.is_active && windowIsOpen(nowUtc())) {
      return (
        "The window is open, but the world has not reported the cart standing yet. " +
        "It is placed on the first tick the biome it was assigned to has players in it, " +
        "so it can arrive part-way through a window — especially just after a restart."
      );
    }
    return payload.stale
      ? "This reading is over 15 minutes old — the world may be restarting."
      : "";
  }

  // --- data -----------------------------------------------------------------

  function load() {
    return fetch(apiUrl(), { cache: "no-store" })
      .then((r) => {
        if (!r.ok) throw new Error("http " + r.status);
        return r.json();
      })
      .then((data) => {
        payload =
          data && typeof data === "object" ? data : { ok: false, unreachable: true };
        if (payload.ok) {
          nextAt = Number(payload.next_spawn_utc_timestamp || 0);
        } else {
          nextAt = 0;
        }
        render();
      })
      .catch(() => {
        // Degrade in place. The banner reads offline, the cards say so, and the
        // rest of the page is untouched — a tracker that cannot reach the world
        // must not take the page down with it.
        payload = {
          ok: false,
          // The flag, not the absence of ok, is what earns the OFFLINE badge.
          unreachable: true,
          msg: "Could not reach the live world. The tracker returns when the server does.",
        };
        nextAt = 0;
        render();
      });
  }

  setStatus("CHECKING…", "wait");
  skeleton();
  load();
  poll = setInterval(load, REFRESH_MS);
  tick = setInterval(renderClocks, 1000);

  // Stop both timers while the tab is hidden, and take a fresh reading on the
  // way back — the same courtesy the leaderboards page pays.
  document.addEventListener("visibilitychange", () => {
    if (document.hidden) {
      clearInterval(poll);
      clearInterval(tick);
      poll = 0;
      tick = 0;
    } else if (!poll) {
      load();
      poll = setInterval(load, REFRESH_MS);
      tick = setInterval(renderClocks, 1000);
    }
  });
})();
