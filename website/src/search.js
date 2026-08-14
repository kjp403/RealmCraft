(function () {
  const input = document.querySelector("[data-search]");
  const box = document.querySelector("[data-search-results]");
  if (!input || !box) return;

  const indexUrl = input.getAttribute("data-index") || "/wiki/search.json";
  let records = null;
  let timer = 0;

  function load() {
    if (records) return Promise.resolve(records);
    return fetch(indexUrl)
      .then((r) => r.json())
      .then((data) => {
        records = data;
        return records;
      });
  }

  function render(q) {
    const query = q.trim().toLowerCase();
    if (query.length < 2) {
      box.classList.remove("open");
      box.innerHTML = "";
      return;
    }
    const hits = records
      .filter((row) => row.haystack.includes(query))
      .slice(0, 12);
    if (!hits.length) {
      box.innerHTML = "<div style='padding:0.7rem;color:var(--muted)'>No matches.</div>";
      box.classList.add("open");
      return;
    }
    box.innerHTML = hits
      .map(
        (row) =>
          `<a href="${row.href}"><strong>${row.title}</strong><small>${row.kind}</small></a>`
      )
      .join("");
    box.classList.add("open");
  }

  input.addEventListener("input", () => {
    clearTimeout(timer);
    timer = setTimeout(() => {
      load().then(() => render(input.value)).catch(() => {});
    }, 80);
  });
  input.addEventListener("focus", () => {
    load().then(() => render(input.value)).catch(() => {});
  });
  document.addEventListener("click", (ev) => {
    if (!box.contains(ev.target) && ev.target !== input) box.classList.remove("open");
  });
})();

(function () {
  const grid = document.querySelector(".item-grid");
  const bar = document.querySelector("[data-filters]");
  if (!grid || !bar) return;
  bar.addEventListener("click", (ev) => {
    const btn = ev.target.closest("[data-kind]");
    if (!btn) return;
    const kind = btn.getAttribute("data-kind");
    bar.querySelectorAll("[data-kind]").forEach((b) => b.classList.toggle("active", b === btn));
    grid.querySelectorAll(".item-card").forEach((card) => {
      card.style.display = !kind || card.getAttribute("data-kind") === kind ? "" : "none";
    });
  });
})();
