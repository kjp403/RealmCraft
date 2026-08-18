(function () {
  const root = document.querySelector("[data-leaderboards]");
  if (!root) return;

  const CATEGORIES = [
    { id: "combat", label: "Combat" },
    { id: "progression", label: "Progression" },
    { id: "guild", label: "Guild" },
    { id: "dungeon", label: "Dungeons" },
  ];
  const BOARDS = [
    { id: "pvp_total", label: "PvP · All-Time", category: "combat", format: "count" },
    { id: "pvp_week", label: "PvP · This Week", category: "combat", format: "count" },
    { id: "pve_total", label: "PvE · All-Time", category: "combat", format: "count" },
    { id: "pve_week", label: "PvE · This Week", category: "combat", format: "count" },
    { id: "arena_wins", label: "Arena Wins", category: "combat", format: "count" },
    { id: "total_level", label: "Total Level", category: "progression", format: "count" },
    { id: "level", label: "Combat Level", category: "progression", format: "count" },
    { id: "gold", label: "Richest", category: "progression", format: "gold" },
    { id: "glory_seasonal", label: "Glory · Seasonal", category: "guild", format: "count" },
    { id: "glory_eternal", label: "Glory · Eternal", category: "guild", format: "count" },
    { id: "dungeon:Dungeon", label: "The Dark Cave (Hard)", category: "dungeon", format: "time" },
    { id: "dungeon:fungus_dungeon", label: "Fungus Domain (Hard)", category: "dungeon", format: "time" },
    { id: "dungeon:hell_dungeon", label: "Fire and Flames (Hard)", category: "dungeon", format: "time" },
  ];
  const REFRESH_MS = 30000;

  const catBar = root.querySelector("[data-lb-cats]");
  const boardBar = root.querySelector("[data-lb-boards]");
  const tableWrap = root.querySelector("[data-lb-table]");
  const status = root.querySelector("[data-lb-status]");
  const title = root.querySelector("[data-lb-title]");

  let catId = CATEGORIES[0].id;
  let boardId = BOARDS[0].id;
  let payload = null;
  let timer = 0;

  function apiUrl() {
    const host = location.hostname;
    if (host === "localhost" || host === "127.0.0.1") return "http://127.0.0.1:8088/v1/leaderboards";
    return "https://api.arkenelle.com/v1/leaderboards";
  }

  function esc(s) {
    return String(s ?? "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function formatScore(value, format) {
    const n = Number(value) || 0;
    if (format === "gold") return n.toLocaleString();
    if (format === "time") {
      const m = Math.floor(n / 60);
      const s = n % 60;
      return m + ":" + String(s).padStart(2, "0");
    }
    return n.toLocaleString();
  }

  function scoreLabel(format) {
    if (format === "gold") return "Gold";
    if (format === "time") return "Time";
    return "Score";
  }

  function setStatus(text, kind) {
    status.textContent = text;
    status.dataset.kind = kind || "";
  }

  function boardsInCat(id) {
    return BOARDS.filter((b) => b.category === id);
  }

  function currentBoard() {
    return BOARDS.find((b) => b.id === boardId) || BOARDS[0];
  }

  function renderNav() {
    catBar.innerHTML = CATEGORIES.map(
      (c) =>
        `<button type="button" data-cat="${esc(c.id)}" class="${c.id === catId ? "active" : ""}">${esc(c.label)}</button>`
    ).join("");
    boardBar.innerHTML = boardsInCat(catId)
      .map(
        (b) =>
          `<button type="button" data-board="${esc(b.id)}" class="${b.id === boardId ? "active" : ""}">${esc(b.label)}</button>`
      )
      .join("");
  }

  function updatedLabel(unix) {
    const ts = Number(unix) || 0;
    if (!ts) return "Live from the world";
    const ago = Math.max(0, Math.floor(Date.now() / 1000 - ts));
    if (ago < 15) return "Updated just now";
    if (ago < 60) return "Updated " + ago + "s ago";
    const mins = Math.floor(ago / 60);
    return "Updated " + mins + "m ago";
  }

  function renderTable() {
    const board = currentBoard();
    title.textContent = board.label;
    const rows = (payload && payload.boards && payload.boards[board.id]) || [];
    if (!rows.length) {
      tableWrap.innerHTML = "<p class='muted'>No scores on this board yet.</p>";
      return;
    }
    const body = rows
      .map((row, i) => {
        const rank = i + 1;
        const medal = rank <= 3 ? " rank-" + rank : "";
        return `<tr class="${medal.trim()}">
          <td class="lb-rank">${rank}</td>
          <td class="lb-name">${esc(row.name)}</td>
          <td class="lb-score">${esc(formatScore(row.score, board.format))}</td>
        </tr>`;
      })
      .join("");
    tableWrap.innerHTML = `<table class="lb-table">
      <thead><tr><th>#</th><th>Name</th><th>${esc(scoreLabel(board.format))}</th></tr></thead>
      <tbody>${body}</tbody>
    </table>`;
  }

  function render() {
    renderNav();
    if (!payload) {
      tableWrap.innerHTML = "";
      return;
    }
    if (!payload.ok) {
      tableWrap.innerHTML = `<p class="muted">${esc(payload.msg || "Leaderboards are not available yet.")}</p>`;
      return;
    }
    const world = payload.world ? " · " + payload.world : "";
    setStatus("Live" + world + " · " + updatedLabel(payload.updated_at), "ok");
    renderTable();
  }

  function load() {
    return fetch(apiUrl(), { cache: "no-store" })
      .then((r) => {
        if (!r.ok) throw new Error("http " + r.status);
        return r.json();
      })
      .then((data) => {
        payload = data && typeof data === "object" ? data : { ok: false };
        if (!payload.ok) {
          setStatus(payload.msg || "Waiting on the live world.", "wait");
        }
        render();
      })
      .catch(() => {
        payload = {
          ok: false,
          msg: "Could not reach the live world. The boards appear after the next server deploy.",
        };
        setStatus("World unreachable", "wait");
        render();
      });
  }

  catBar.addEventListener("click", (ev) => {
    const btn = ev.target.closest("[data-cat]");
    if (!btn) return;
    catId = btn.getAttribute("data-cat");
    const first = boardsInCat(catId)[0];
    if (first) boardId = first.id;
    render();
  });
  boardBar.addEventListener("click", (ev) => {
    const btn = ev.target.closest("[data-board]");
    if (!btn) return;
    boardId = btn.getAttribute("data-board");
    render();
  });

  renderNav();
  setStatus("Loading live ranks…", "wait");
  load();
  timer = setInterval(load, REFRESH_MS);
  document.addEventListener("visibilitychange", () => {
    if (document.hidden) {
      clearInterval(timer);
      timer = 0;
    } else if (!timer) {
      load();
      timer = setInterval(load, REFRESH_MS);
    }
  });
})();
