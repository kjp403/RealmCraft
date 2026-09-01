(function () {
  const root = document.querySelector("[data-peddler]");
  if (!root) return;

  // Poll cadence. The cart's state only changes on a 4-hour boundary and at UTC
  // midnight, so a minute is generous; the countdowns below tick locally every
  // second and do not need the network.
  const REFRESH_MS = 60000;
  const TIERS = { S: "s", A: "a", B: "b" };

  const statusEl = root.querySelector("[data-pd-status]");
  const zoneEl = root.querySelector("[data-pd-zone]");
  const clocksEl = root.querySelector("[data-pd-clocks]");
  const stockEl = root.querySelector("[data-pd-stock]");
  const noteEl = root.querySelector("[data-pd-note]");

  let payload = null;
  let poll = 0;
  let tick = 0;
  // Wall-clock second the current zone window ends, and the next spawn. Both are
  // absolute UTC, so the countdowns keep working between polls and survive the
  // tab being backgrounded — a decrementing local counter would drift.
  let endsAt = 0;
  let nextAt = 0;

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
    if (!payload || !payload.ok) {
      clocksEl.innerHTML = "";
      return;
    }
    const now = nowUtc();
    const parts = [];
    if (payload.is_active && endsAt > now) {
      parts.push(
        `<div class="pd-clock"><span class="pd-clock-label">Leaves in</span>` +
          `<strong class="pd-clock-value">${clock(endsAt - now)}</strong></div>`
      );
    }
    if (nextAt > now) {
      parts.push(
        `<div class="pd-clock"><span class="pd-clock-label">Next appearance</span>` +
          `<strong class="pd-clock-value">${clock(nextAt - now)}</strong></div>`
      );
    }
    clocksEl.innerHTML = parts.join("");

    // The window ran out between polls — flip to roaming rather than showing a
    // cart that has already packed up, and pull a fresh snapshot.
    if (payload.is_active && endsAt && now >= endsAt) {
      payload.is_active = false;
      endsAt = 0;
      renderBanner();
      load();
    }
  }

  function renderBanner() {
    if (!payload || !payload.ok) {
      setStatus("TRACKER OFFLINE", "off");
      zoneEl.textContent = "Unknown (Roam Phase)";
      return;
    }
    if (payload.is_active) {
      setStatus("ACTIVE IN-GAME", "on");
      zoneEl.textContent = payload.current_zone || "Unknown (Roam Phase)";
    } else {
      setStatus("VANISHED / ROAMING", "off");
      zoneEl.textContent = "Unknown (Roam Phase)";
    }
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
    noteEl.textContent = payload.stale
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
        payload = data && typeof data === "object" ? data : { ok: false };
        if (payload.ok) {
          const now = nowUtc();
          endsAt = payload.is_active ? now + Number(payload.time_remaining_seconds || 0) : 0;
          nextAt = Number(payload.next_spawn_utc_timestamp || 0);
        } else {
          endsAt = 0;
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
          msg: "Could not reach the live world. The tracker returns when the server does.",
        };
        endsAt = 0;
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
