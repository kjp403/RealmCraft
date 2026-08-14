#!/usr/bin/env node
/**
 * Builds the Arkenelle marketing site + wiki from Godot .tres data.
 * Run from anywhere: node website/build.mjs
 */
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const DIST = path.join(ROOT, "website", "dist");
const SRC = path.join(ROOT, "website", "src");
const CSS_V = crypto
  .createHash("sha1")
  .update(fs.readFileSync(path.join(SRC, "styles.css")))
  .digest("hex")
  .slice(0, 10);

const ITCH = "https://kjp403.itch.io/arkenelle";
const PLAY_WEB = "https://play.arkenelle.com/";
const DISCORD = "https://discord.gg/kSs3hxByV";
const ITCH_APP = "https://itch.io/app";

const STAT_NAMES = {
  health_max: "Max Health",
  mana_max: "Max Mana",
  mana_regen: "Mana Regen",
  armor: "Armor",
  mr: "Magic Resist",
  ad: "Attack Damage",
  ap: "Ability Power",
  attack_speed: "Attack Speed",
  attack_range: "Attack Range",
  move_speed: "Move Speed",
  crit_chance: "Crit Chance",
  crit_damage: "Crit Damage",
  ability_haste: "Ability Haste",
  damage_vs_low_hp: "Damage vs Low HP",
  lifesteal: "Lifesteal",
};

const ITEM_KIND = {
  WeaponItem: "Weapon",
  ToolItem: "Tool",
  GearItem: "Armor",
  ConsumableItem: "Consumable",
  MaterialItem: "Material",
  AmmoItem: "Ammo",
  QuestItem: "Quest item",
  LootChestItem: "Chest",
  DungeonKeyItem: "Dungeon key",
  Item: "Item",
};

const SKIP_NPCS = new Set(["dev_all_merchant", "vfx_curator"]);
const SKIP_ZONES = new Set(["jail", "vfx_vault", "dungeon_entrance"]);
const SKIP_ENEMIES = new Set(["training_dummy"]);

const usedMedia = new Set();
const pngSizeCache = new Map();

function walk(dir, out = []) {
  if (!fs.existsSync(dir)) return out;
  for (const ent of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, ent.name);
    if (ent.isDirectory()) walk(p, out);
    else out.push(p);
  }
  return out;
}

function read(p) {
  return fs.readFileSync(p, "utf8").replace(/^\uFEFF/, "").replace(/\r\n/g, "\n");
}

function esc(s) {
  return String(s ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function slugify(s) {
  return String(s || "")
    .replace(/^&/, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "") || "entry";
}

function basenameSlug(file) {
  return path.basename(file, path.extname(file)).replace(/\.item$/, "");
}

function resToFs(resPath) {
  if (!resPath || typeof resPath !== "string") return null;
  if (resPath.startsWith("res://")) return path.join(ROOT, resPath.slice(6));
  if (resPath.startsWith("uid://")) return null;
  if (path.isAbsolute(resPath)) return resPath;
  return path.join(ROOT, resPath);
}

function pngSize(abs) {
  if (pngSizeCache.has(abs)) return pngSizeCache.get(abs);
  try {
    const buf = fs.readFileSync(abs);
    if (buf.length < 24 || buf[0] !== 0x89) return null;
    const size = { w: buf.readUInt32BE(16), h: buf.readUInt32BE(20) };
    pngSizeCache.set(abs, size);
    return size;
  } catch {
    return null;
  }
}

function mediaHref(absPath) {
  const rel = path.relative(ROOT, absPath).replace(/\\/g, "/");
  const destRel = rel.startsWith("assets/") ? rel.slice("assets/".length) : rel;
  usedMedia.add(absPath);
  return "/media/" + destRel;
}

function skipWs(s, i) {
  while (i < s.length) {
    const c = s[i];
    if (c === " " || c === "\t" || c === "\n" || c === "\r") i++;
    else if (c === ";") {
      while (i < s.length && s[i] !== "\n") i++;
    } else break;
  }
  return i;
}

function parseString(s, i) {
  const named = s[i] === "&";
  if (named) i++;
  if (s[i] !== '"') return [null, i];
  i++;
  let out = "";
  while (i < s.length) {
    const c = s[i++];
    if (c === "\\") {
      const n = s[i++];
      out += n === "n" ? "\n" : n === "t" ? "\t" : n;
    } else if (c === '"') break;
    else out += c;
  }
  return [out, i];
}

function parseNumber(s, i) {
  const m = /^-?\d+(?:\.\d+)?/.exec(s.slice(i));
  if (!m) return [null, i];
  return [Number(m[0]), i + m[0].length];
}

function parseList(s, i, closer) {
  const items = [];
  i = skipWs(s, i);
  while (i < s.length && s[i] !== closer) {
    const [v, n] = parseValue(s, i);
    items.push(v);
    i = skipWs(s, n);
    if (s[i] === ",") i = skipWs(s, i + 1);
  }
  if (s[i] === closer) i++;
  return [items, i];
}

function parseDict(s, i) {
  const obj = {};
  i = skipWs(s, i);
  while (i < s.length && s[i] !== "}") {
    i = skipWs(s, i);
    let key;
    if (s[i] === '"' || s[i] === "&") {
      [key, i] = parseString(s, i);
    } else {
      const m = /^[A-Za-z0-9_]+/.exec(s.slice(i));
      if (!m) break;
      key = m[0];
      i += key.length;
    }
    i = skipWs(s, i);
    if (s[i] === ":") i++;
    const [val, n] = parseValue(s, i);
    obj[key] = val;
    i = skipWs(s, n);
    if (s[i] === ",") i = skipWs(s, i + 1);
  }
  if (s[i] === "}") i++;
  return [obj, i];
}

function parseCall(s, i) {
  const name = /^[A-Za-z_][A-Za-z0-9_]*/.exec(s.slice(i));
  if (!name) return [null, i];
  let j = i + name[0].length;
  j = skipWs(s, j);
  if (s[j] === "[") {
    const close = s.indexOf("]", j);
    j = skipWs(s, (close < 0 ? j : close) + 1);
  }
  if (s[j] !== "(") return [null, i];
  j++;
  const [args, n] = parseList(s, j, ")");
  const kind = name[0];
  if (kind === "ExtResource") return [{ type: "ext", id: String(args[0] ?? "") }, n];
  if (kind === "SubResource") return [{ type: "sub", id: String(args[0] ?? "") }, n];
  if (kind === "Rect2") return [{ type: "rect", x: args[0], y: args[1], w: args[2], h: args[3] }, n];
  // Godot writes Array[Type]([a, b, c]) — unwrap the inner list.
  if (kind === "Array") return [args.length === 1 && Array.isArray(args[0]) ? args[0] : args, n];
  if (kind === "PackedStringArray" || kind === "PackedFloat32Array" || kind === "PackedInt32Array") {
    return [args, n];
  }
  return [{ type: kind, args }, n];
}

function parseValue(s, i) {
  i = skipWs(s, i);
  if (s.startsWith("null", i) && !/[A-Za-z0-9_]/.test(s[i + 4] || "")) return [null, i + 4];
  if (s.startsWith("true", i) && !/[A-Za-z0-9_]/.test(s[i + 4] || "")) return [true, i + 4];
  if (s.startsWith("false", i) && !/[A-Za-z0-9_]/.test(s[i + 5] || "")) return [false, i + 5];
  if (s[i] === '"' || s[i] === "&") return parseString(s, i);
  if (s[i] === "[") {
    const [items, n] = parseList(s, i + 1, "]");
    return [items, n];
  }
  if (s[i] === "{") return parseDict(s, i + 1);
  if (/[A-Za-z_]/.test(s[i])) {
    const call = parseCall(s, i);
    if (call[0] != null) return call;
  }
  if (s[i] === "-" || (s[i] >= "0" && s[i] <= "9")) return parseNumber(s, i);
  return [s[i], i + 1];
}

function parseProps(body) {
  const props = {};
  let i = 0;
  while (i < body.length) {
    i = skipWs(body, i);
    if (i >= body.length) break;
    const m = /^[A-Za-z0-9_/]+/.exec(body.slice(i));
    if (!m) {
      i++;
      continue;
    }
    const key = m[0];
    i = skipWs(body, i + key.length);
    if (body[i] !== "=") continue;
    i = skipWs(body, i + 1);
    const [val, n] = parseValue(body, i);
    props[key] = val;
    i = n;
  }
  return props;
}

function parseTres(text) {
  const ext = {};
  const sub = {};
  let header = {};
  let resource = {};
  const re = /\[(gd_resource|ext_resource|sub_resource|resource)([^\]]*)\]/g;
  const marks = [];
  let m;
  while ((m = re.exec(text))) marks.push({ kind: m[1], meta: m[2], start: m.index, headEnd: re.lastIndex });
  for (let i = 0; i < marks.length; i++) {
    const cur = marks[i];
    const body = text.slice(cur.headEnd, i + 1 < marks.length ? marks[i + 1].start : text.length);
    const attrs = {};
    for (const am of cur.meta.matchAll(/(\w+)="([^"]*)"/g)) attrs[am[1]] = am[2];
    if (cur.kind === "gd_resource") header = attrs;
    else if (cur.kind === "ext_resource") ext[attrs.id] = attrs;
    else if (cur.kind === "sub_resource") sub[attrs.id] = { type: attrs.type, props: parseProps(body) };
    else if (cur.kind === "resource") resource = parseProps(body);
  }
  return { header, ext, sub, resource };
}

function str(v) {
  if (v == null) return "";
  if (typeof v === "string") return v;
  if (typeof v === "number" || typeof v === "boolean") return String(v);
  return "";
}

function num(v, fallback = 0) {
  return typeof v === "number" && Number.isFinite(v) ? v : fallback;
}

function resolveExt(doc, val) {
  if (!val || val.type !== "ext") return null;
  const rec = doc.ext[val.id];
  return rec ? rec.path : null;
}

function resolveSub(doc, val) {
  if (!val || val.type !== "sub") return null;
  return doc.sub[val.id] || null;
}

function asArray(v) {
  return Array.isArray(v) ? v : [];
}

function uniqueSlug(base, used) {
  let s = slugify(base);
  let n = 2;
  while (used.has(s)) {
    s = `${slugify(base)}-${n++}`;
  }
  used.add(s);
  return s;
}

function iconFrom(doc, val) {
  if (!val) return null;
  if (val.type === "ext") {
    const p = resolveExt(doc, val);
    const abs = resToFs(p);
    if (!abs || !fs.existsSync(abs)) return null;
    return { kind: "image", src: mediaHref(abs) };
  }
  const sub = resolveSub(doc, val);
  if (!sub || !sub.props) return null;
  const atlas = resolveExt(doc, sub.props.atlas);
  const abs = resToFs(atlas);
  const region = sub.props.region;
  if (!abs || !fs.existsSync(abs) || !region || region.type !== "rect") {
    if (abs && fs.existsSync(abs)) return { kind: "image", src: mediaHref(abs) };
    return null;
  }
  const sheet = pngSize(abs);
  return {
    kind: "atlas",
    src: mediaHref(abs),
    x: num(region.x),
    y: num(region.y),
    w: num(region.w, 16),
    h: num(region.h, 16),
    sheetW: sheet?.w || 256,
    sheetH: sheet?.h || 256,
  };
}

function iconHtml(icon, size = 48) {
  if (!icon) return `<span class="icon-missing"></span>`;
  if (icon.kind === "image") {
    return `<img class="icon-img" src="${esc(icon.src)}" alt="" width="${size}" height="${size}">`;
  }
  const scale = Math.min(size / icon.w, size / icon.h, 4);
  const dw = Math.max(1, Math.round(icon.w * scale));
  const dh = Math.max(1, Math.round(icon.h * scale));
  const sw = Math.round(icon.sheetW * scale);
  const sh = Math.round(icon.sheetH * scale);
  return `<span class="px-icon" style="width:${dw}px;height:${dh}px;background-image:url('${esc(icon.src)}');background-size:${sw}px ${sh}px;background-position:${Math.round(-icon.x * scale)}px ${Math.round(-icon.y * scale)}px"></span>`;
}

function modifiersFrom(doc, arr) {
  const out = [];
  for (const ref of asArray(arr)) {
    const sub = resolveSub(doc, ref);
    if (!sub) continue;
    const name = str(sub.props.stat_name);
    const value = num(sub.props.value);
    if (!name || !value) continue;
    out.push({ stat: name, value });
  }
  return out;
}

function dropsFrom(doc, arr) {
  const out = [];
  for (const ref of asArray(arr)) {
    const sub = resolveSub(doc, ref);
    if (!sub) continue;
    const itemPath = resolveExt(doc, sub.props.item);
    if (!itemPath) continue;
    out.push({
      itemPath,
      chance: sub.props.chance == null ? 1 : num(sub.props.chance, 1),
      min: num(sub.props.min_amount, 1),
      max: num(sub.props.max_amount, num(sub.props.min_amount, 1)),
    });
  }
  return out;
}

function fmtChance(c) {
  if (c >= 1) return "Always";
  const pct = c * 100;
  return pct >= 1 ? `${pct.toFixed(pct >= 10 ? 0 : 1)}%` : `${pct.toFixed(2)}%`;
}

function fmtAmt(min, max) {
  if (min === max) return min === 1 ? "" : ` ×${min}`;
  return ` ×${min}–${max}`;
}

function statLabel(key) {
  return STAT_NAMES[key] || key.replace(/_/g, " ").replace(/\b\w/g, (c) => c.toUpperCase());
}

function itemKindFrom(file, scriptClass) {
  if (ITEM_KIND[scriptClass]) return ITEM_KIND[scriptClass];
  const p = file.replace(/\\/g, "/");
  if (p.includes("/weapons/tools/")) return "Tool";
  if (p.includes("/weapons/")) return "Weapon";
  if (p.includes("/gears/")) return "Armor";
  if (p.includes("/consumables/")) return "Consumable";
  if (p.includes("/materials/")) return "Material";
  if (p.includes("/ammo/")) return "Ammo";
  if (p.includes("/chests/")) return "Chest";
  return "Item";
}

function rmDist() {
  fs.rmSync(DIST, { recursive: true, force: true });
  fs.mkdirSync(DIST, { recursive: true });
}

function write(rel, contents) {
  const abs = path.join(DIST, rel);
  fs.mkdirSync(path.dirname(abs), { recursive: true });
  fs.writeFileSync(abs, contents);
}

function copyMedia() {
  for (const abs of usedMedia) {
    if (!fs.existsSync(abs)) continue;
    const rel = path.relative(ROOT, abs).replace(/\\/g, "/");
    const destRel = rel.startsWith("assets/") ? rel.slice("assets/".length) : rel;
    const dest = path.join(DIST, "media", destRel);
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    fs.copyFileSync(abs, dest);
  }
}

function shell({ title, active, body, scripts = [] }) {
  const home = "/";
  const wiki = "/wiki/";
  const extraScripts = scripts.map((src) => `  <script src="${src}"></script>`).join("\n");
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${esc(title)}</title>
  <meta name="description" content="Arkenelle — a hard sandbox MMORPG. Wiki generated from live game data.">
  <link rel="icon" href="/media/project_icon/arkenelle_icon.png">
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Figtree:wght@400;600;700&family=Instrument+Serif&display=swap" rel="stylesheet">
  <link rel="stylesheet" href="/styles.css?v=${CSS_V}">
</head>
<body>
  <header class="site-header">
    <a class="brand" href="${home}"><img src="/media/project_icon/arkenelle_icon.png" alt="">Arkenelle</a>
    <nav class="primary">
      <a href="${wiki}" class="${active === "wiki" ? "active" : ""}">Wiki</a>
      <a href="/leaderboards/" class="${active === "boards" ? "active" : ""}">Leaderboards</a>
      <a href="/wiki/getting-started/" class="${active === "start" ? "active" : ""}">Getting started</a>
      <a href="/wiki/items/" class="${active === "items" ? "active" : ""}">Items</a>
      <a href="/wiki/creatures/" class="${active === "creatures" ? "active" : ""}">Creatures</a>
      <a href="/wiki/locations/" class="${active === "locations" ? "active" : ""}">Locations</a>
      <a href="/wiki/npcs/" class="${active === "npcs" ? "active" : ""}">NPCs</a>
      <a href="${PLAY_WEB}" class="${active === "play" ? "active" : ""}">Play</a>
      <a href="${ITCH}">Download</a>
      <a href="${DISCORD}">Discord</a>
    </nav>
    <div class="search-wrap">
      <input data-search data-index="/wiki/search.json" type="search" placeholder="Search wiki…" aria-label="Search wiki">
      <div class="search-results" data-search-results></div>
    </div>
  </header>
  ${body}
  <footer class="footer">Arkenelle is in alpha. Wiki pages are generated from the game files.</footer>
  <script src="/search.js"></script>
${extraScripts}
</body>
</html>`;
}

function crumb(parts) {
  return `<nav class="crumb">${parts
    .map((p, i) => (i === parts.length - 1 ? esc(p.label) : `<a href="${p.href}">${esc(p.label)}</a>`))
    .join(" / ")}</nav>`;
}

function collectItems() {
  const dir = path.join(ROOT, "source/common/gameplay/items");
  const used = new Set();
  const items = [];
  for (const file of walk(dir).filter((f) => f.endsWith(".tres"))) {
    if (file.replace(/\\/g, "/").includes("/item_slot/")) continue;
    let doc;
    try {
      doc = parseTres(read(file));
    } catch {
      continue;
    }
    const rawName = str(doc.resource.item_name);
    if (!rawName) continue;
    const name = rawName === rawName.toLowerCase() ? rawName.replace(/\b\w/g, (c) => c.toUpperCase()) : rawName;
    const slug = uniqueSlug(str(doc.resource["metadata/slug"]) || basenameSlug(file), used);
    items.push({
      slug,
      name,
      description: str(doc.resource.description),
      kind: itemKindFrom(file, doc.header.script_class),
      category: str(doc.resource.category),
      vendor: num(doc.resource.vendor_value),
      trade: Boolean(doc.resource.can_trade),
      stack: num(doc.resource.stack_limit),
      requiredLevel: num(doc.resource.required_level),
      requiredMastery: num(doc.resource.required_mastery_level),
      masteryCats: asArray(doc.resource.required_mastery_categories).map(str).filter(Boolean),
      heal: num(doc.resource.heal_amount),
      mana: num(doc.resource.mana_amount),
      buffStat: str(doc.resource.buff_stat),
      buffAmount: num(doc.resource.buff_amount),
      buffDuration: num(doc.resource.buff_duration_s),
      modifiers: modifiersFrom(doc, doc.resource.base_modifiers),
      icon: iconFrom(doc, doc.resource.item_icon),
      file,
    });
  }
  items.sort((a, b) => a.name.localeCompare(b.name));
  return items;
}

function collectNpcs() {
  const dir = path.join(ROOT, "source/common/gameplay/characters/npc/npcs");
  const used = new Set();
  const npcs = [];
  for (const file of walk(dir).filter((f) => f.endsWith(".tres"))) {
    const slug0 = basenameSlug(file);
    if (SKIP_NPCS.has(slug0)) continue;
    let doc;
    try {
      doc = parseTres(read(file));
    } catch {
      continue;
    }
    if (doc.header.script_class && doc.header.script_class !== "NPCResource") continue;
    const name = str(doc.resource.npc_name);
    if (!name) continue;
    const offers = new Set();
    for (const rec of Object.values(doc.ext)) {
      const p = String(rec.path || "");
      if (p.endsWith("shop_interaction.gd")) offers.add("Shop");
      if (p.endsWith("quest_interaction.gd")) offers.add("Quests");
      if (p.endsWith("dialogue_interaction.gd")) offers.add("Talk");
      if (p.endsWith("slayer_interaction.gd")) offers.add("Slayer");
      if (p.endsWith("dungeon_interaction.gd")) offers.add("Dungeon");
      if (p.endsWith("wardrobe_interaction.gd")) offers.add("Wardrobe");
      if (p.endsWith("name_change_interaction.gd")) offers.add("Name change");
      if (p.endsWith("attribute_reset_interaction.gd")) offers.add("Attribute reset");
    }
    npcs.push({
      slug: uniqueSlug(slug0, used),
      name,
      greeting: str(doc.resource.greeting),
      offers: [...offers],
      file,
    });
  }
  npcs.sort((a, b) => a.name.localeCompare(b.name));
  return npcs;
}

function collectCreatures() {
  const dir = path.join(ROOT, "source/common/gameplay/characters/npc/types");
  const used = new Set();
  const rows = [];
  for (const file of walk(dir).filter((f) => f.endsWith(".tres"))) {
    const slug0 = basenameSlug(file);
    if (SKIP_ENEMIES.has(slug0)) continue;
    let doc;
    try {
      doc = parseTres(read(file));
    } catch {
      continue;
    }
    if (doc.header.script_class && doc.header.script_class !== "EnemyTypeResource") continue;
    const name = str(doc.resource.display_name) || str(doc.resource.enemy_type) || slug0;
    rows.push({
      slug: uniqueSlug(str(doc.resource.enemy_type) || slug0, used),
      name,
      type: str(doc.resource.enemy_type) || slug0,
      boss: Boolean(doc.resource.is_boss),
      level: num(doc.resource.combat_level),
      hp: num(doc.resource.max_health),
      damage: num(doc.resource.attack_damage),
      armor: num(doc.resource.armor),
      mr: num(doc.resource.mr),
      xp: num(doc.resource.xp_reward),
      loot: dropsFrom(doc, doc.resource.loot),
      file,
    });
  }
  rows.sort((a, b) => Number(b.boss) - Number(a.boss) || a.name.localeCompare(b.name));
  return rows;
}

function collectZones() {
  const dir = path.join(ROOT, "source/common/gameplay/maps/instance/instance_collection");
  const used = new Set();
  const rows = [];
  for (const file of walk(dir).filter((f) => f.endsWith(".tres"))) {
    let doc;
    try {
      doc = parseTres(read(file));
    } catch {
      continue;
    }
    const klass = doc.header.script_class || "";
    if (klass === "AdminOnlyInstanceResource") continue;
    const inst = str(doc.resource.instance_name);
    if (!inst || SKIP_ZONES.has(inst) || SKIP_ZONES.has(basenameSlug(file))) continue;
    const isDungeon = klass === "DungeonResource";
    rows.push({
      slug: uniqueSlug(str(doc.resource["metadata/slug"]) || inst, used),
      name: str(doc.resource.display_name) || str(doc.resource.zone_title) || inst.replace(/_/g, " "),
      instance: inst,
      isDungeon,
      description: str(doc.resource.description),
      recommended: num(doc.resource.recommended_level),
      levelMin: num(doc.resource.level_min),
      levelMax: num(doc.resource.level_max),
      wardstone: str(doc.resource.required_wardstone),
      party: num(doc.resource.party_size, isDungeon ? 4 : 0),
      mapPath: str(doc.resource.map_path),
      people: [],
      fauna: [],
      file,
    });
  }
  rows.sort((a, b) => Number(b.isDungeon) - Number(a.isDungeon) || a.name.localeCompare(b.name));
  return rows;
}

function buildUidIndex() {
  const map = new Map();
  const root = path.join(ROOT, "source");
  for (const file of walk(root)) {
    if (!file.endsWith(".tscn") && !file.endsWith(".tres")) continue;
    let fd;
    try {
      fd = fs.openSync(file, "r");
      const buf = Buffer.alloc(512);
      const n = fs.readSync(fd, buf, 0, 512, 0);
      const head = buf.slice(0, n).toString("utf8");
      const m = head.match(/uid="(uid:\/\/[^"]+)"/);
      if (m) map.set(m[1], file);
    } catch {
      /* skip */
    } finally {
      if (fd != null) fs.closeSync(fd);
    }
  }
  return map;
}

function parseExtResources(text) {
  const ext = {};
  for (const m of text.matchAll(/\[ext_resource ([^\]]*)\]/g)) {
    const id = /(?:^|\s)id="([^"]+)"/.exec(m[1]);
    const p = /(?:^|\s)path="([^"]+)"/.exec(m[1]);
    if (id && p) ext[id[1]] = p[1];
  }
  return ext;
}

function subResourceBody(text, id) {
  const re = new RegExp(`\\[sub_resource[^\\]]*id="${id}"\\]\\r?\\n([\\s\\S]*?)(?=\\n\\[)`);
  const m = text.match(re);
  return m ? m[1] : "";
}

function scanMapScene(absPath, seen = new Set()) {
  const out = { npcPaths: [], inline: [], enemyPaths: [] };
  if (!absPath || seen.has(absPath) || !fs.existsSync(absPath)) return out;
  seen.add(absPath);
  let text;
  try {
    text = read(absPath);
  } catch {
    return out;
  }
  const ext = parseExtResources(text);
  for (const m of text.matchAll(/npc_resource = ExtResource\("([^"]+)"\)/g)) {
    const p = ext[m[1]];
    if (p && p.includes("/npc/npcs/")) out.npcPaths.push(p);
  }
  for (const m of text.matchAll(/npc_resource = SubResource\("([^"]+)"\)/g)) {
    const body = subResourceBody(text, m[1]);
    const name = /npc_name = "([^"]+)"/.exec(body);
    if (!name) continue;
    const greet = /greeting = "([^"]*)"/.exec(body);
    out.inline.push({ name: name[1], greeting: greet ? greet[1] : "" });
  }
  for (const m of text.matchAll(/\n(?:enemy_data|enemy_type) = ExtResource\("([^"]+)"\)/g)) {
    const p = ext[m[1]];
    if (p && p.includes("/npc/types/")) out.enemyPaths.push(p);
  }
  for (const p of Object.values(ext)) {
    if (!p.endsWith(".tscn")) continue;
    if (!p.includes("/gameplay/maps/")) continue;
    const child = resToFs(p);
    if (!child || child === absPath) continue;
    const nested = scanMapScene(child, seen);
    out.npcPaths.push(...nested.npcPaths);
    out.inline.push(...nested.inline);
    out.enemyPaths.push(...nested.enemyPaths);
  }
  return out;
}

function npcByPath(npcs, resPath) {
  if (!resPath) return null;
  const base = path.basename(resPath.replace(/\\/g, "/"));
  return npcs.find((n) => n.file.replace(/\\/g, "/").endsWith("/" + base));
}

function creatureByPath(creatures, resPath) {
  if (!resPath) return null;
  const base = basenameSlug(resPath);
  return (
    creatures.find((c) => c.file.replace(/\\/g, "/").endsWith("/" + path.basename(resPath.replace(/\\/g, "/")))) ||
    creatures.find((c) => c.type === base || c.slug === slugify(base))
  );
}

function attachMapInhabitants(zones, npcs, creatures) {
  const uids = buildUidIndex();
  for (const z of zones) {
    let mapFile = null;
    if (z.mapPath.startsWith("uid://")) mapFile = uids.get(z.mapPath) || null;
    else mapFile = resToFs(z.mapPath);
    const scan = scanMapScene(mapFile);
    const seenNpc = new Set();
    for (const p of scan.npcPaths) {
      const n = npcByPath(npcs, p);
      if (!n || SKIP_NPCS.has(n.slug) || seenNpc.has(n.slug)) continue;
      seenNpc.add(n.slug);
      z.people.push(n);
      n.locations = n.locations || [];
      n.locations.push({ slug: z.slug, name: z.name });
    }
    const seenInline = new Set();
    for (const row of scan.inline) {
      if (seenInline.has(row.name)) continue;
      seenInline.add(row.name);
      z.people.push({ slug: "", name: row.name, greeting: row.greeting, offers: [], locations: [] });
    }
    const counts = new Map();
    for (const p of scan.enemyPaths) {
      const c = creatureByPath(creatures, p);
      if (!c) continue;
      counts.set(c.slug, (counts.get(c.slug) || 0) + 1);
    }
    for (const [slug, count] of counts) {
      const c = creatures.find((x) => x.slug === slug);
      if (!c) continue;
      z.fauna.push({ creature: c, count });
      c.locations = c.locations || [];
      if (!c.locations.some((loc) => loc.slug === z.slug)) c.locations.push({ slug: z.slug, name: z.name });
    }
    z.people.sort((a, b) => a.name.localeCompare(b.name));
    z.fauna.sort((a, b) => Number(b.creature.boss) - Number(a.creature.boss) || a.creature.name.localeCompare(b.creature.name));
  }
}

function foundInHtml(locations) {
  if (!locations || !locations.length) return "";
  return `<h2>Found in</h2><ul>${locations
    .map((z) => `<li><a href="/wiki/locations/${z.slug}/">${esc(z.name)}</a></li>`)
    .join("")}</ul>`;
}

function collectJobs() {
  const dir = path.join(ROOT, "source/common/gameplay/jobs");
  const rows = [];
  for (const file of walk(dir).filter((f) => f.endsWith(".tres"))) {
    let doc;
    try {
      doc = parseTres(read(file));
    } catch {
      continue;
    }
    if (doc.header.script_class && doc.header.script_class !== "JobPerks") continue;
    const name = str(doc.resource.display_name);
    if (!name) continue;
    const iconPath = resolveExt(doc, doc.resource.icon);
    const abs = resToFs(iconPath);
    const perks = asArray(doc.resource.perks).filter((p) => p && typeof p === "object");
    const sources = asArray(doc.resource.source_items)
      .map((ref) => resolveExt(doc, ref))
      .filter(Boolean);
    rows.push({
      slug: slugify(str(doc.resource.job_slug) || basenameSlug(file)),
      name,
      category: str(doc.resource.category) || "profession",
      icon: abs && fs.existsSync(abs) ? { kind: "image", src: mediaHref(abs) } : null,
      perks,
      sources,
      sourceLevels: asArray(doc.resource.source_levels).map((n) => num(n)),
      describe: asArray(doc.resource.describe_lines).map(str).filter(Boolean),
    });
  }
  rows.sort((a, b) => a.name.localeCompare(b.name));
  return rows;
}

function collectSlayer() {
  const masters = [];
  const tasks = [];
  const masterDir = path.join(ROOT, "source/common/gameplay/slayer/masters");
  const taskDir = path.join(ROOT, "source/common/gameplay/slayer/tasks");
  for (const file of walk(taskDir).filter((f) => f.endsWith(".tres"))) {
    const doc = parseTres(read(file));
    tasks.push({
      slug: basenameSlug(file),
      name: str(doc.resource.display_name) || basenameSlug(file),
      min: num(doc.resource.min_slayer_level),
      xp: num(doc.resource.xp_per_kill),
      notes: str(doc.resource.guide_notes),
      location: str(doc.resource.location_hint),
      enemies: asArray(doc.resource.enemy_types).map(str).filter(Boolean),
    });
  }
  for (const file of walk(masterDir).filter((f) => f.endsWith(".tres"))) {
    const doc = parseTres(read(file));
    const pool = [];
    for (const ref of asArray(doc.resource.pool)) {
      const sub = resolveSub(doc, ref);
      if (!sub) continue;
      const taskPath = resolveExt(doc, sub.props.task);
      pool.push({
        task: taskPath ? basenameSlug(taskPath) : "",
        weight: num(sub.props.weight),
        min: num(sub.props.min_amount),
        max: num(sub.props.max_amount),
      });
    }
    masters.push({
      slug: basenameSlug(file),
      name: str(doc.resource.master_name),
      greeting: str(doc.resource.greeting),
      min: num(doc.resource.min_slayer_level),
      location: str(doc.resource.location_hint),
      points: num(doc.resource.base_points_per_task),
      free: Boolean(doc.resource.free_reassign),
      pool,
    });
  }
  return { masters, tasks };
}

function collectQuests() {
  const dir = path.join(ROOT, "source/common/gameplay/quests/resources");
  const rows = [];
  for (const file of walk(dir).filter((f) => f.endsWith(".tres"))) {
    const doc = parseTres(read(file));
    if (doc.header.script_class !== "QuestResource") continue;
    const name = str(doc.resource.quest_name);
    if (!name) continue;
    rows.push({
      slug: slugify(str(doc.resource["metadata/slug"]) || basenameSlug(file)),
      name,
      description: str(doc.resource.description),
      xp: num(doc.resource.reward_xp),
      gold: num(doc.resource.reward_gold),
      title: str(doc.resource.grant_title),
    });
  }
  rows.sort((a, b) => a.name.localeCompare(b.name));
  return rows;
}

function itemByPath(items, itemPath) {
  if (!itemPath) return null;
  const base = basenameSlug(itemPath);
  return items.find((it) => it.file.replace(/\\/g, "/").endsWith("/" + path.basename(itemPath.replace(/\\/g, "/"))))
    || items.find((it) => it.slug === slugify(base) || it.slug === base);
}

function lootList(drops, items) {
  if (!drops.length) return "<p class='muted'>No authored drops.</p>";
  return `<ul class="list-reset">${drops
    .map((d) => {
      const item = itemByPath(items, d.itemPath);
      const label = item ? `<a href="/wiki/items/${item.slug}/">${esc(item.name)}</a>` : esc(basenameSlug(d.itemPath).replace(/_/g, " "));
      return `<li>${label}${esc(fmtAmt(d.min, d.max))} — ${esc(fmtChance(d.chance))}</li>`;
    })
    .join("")}</ul>`;
}

function listPage(title, intro, cardsHtml, active) {
  return shell({
    title: `${title} — Arkenelle Wiki`,
    active,
    body: `<main class="wrap">
      ${crumb([{ href: "/wiki/", label: "Wiki" }, { label: title }])}
      <h1 class="section-title">${esc(title)}</h1>
      <p class="muted">${esc(intro)}</p>
      <div class="item-grid">${cardsHtml}</div>
    </main>`,
  });
}

function build() {
  rmDist();
  const iconAbs = path.join(ROOT, "assets/project_icon/arkenelle_icon.png");
  if (fs.existsSync(iconAbs)) usedMedia.add(iconAbs);
  const heroAbs = path.join(ROOT, "assets/sprites/ui/backgrounds/castle_garden.png");
  const heroCss = fs.existsSync(heroAbs)
    ? `background-image:url('${mediaHref(heroAbs)}')`
    : "";

  const items = collectItems();
  const npcs = collectNpcs();
  const creatures = collectCreatures();
  const zones = collectZones();
  attachMapInhabitants(zones, npcs, creatures);
  const jobs = collectJobs();
  const slayer = collectSlayer();
  const quests = collectQuests();

  fs.copyFileSync(path.join(SRC, "styles.css"), path.join(DIST, "styles.css"));
  fs.copyFileSync(path.join(SRC, "search.js"), path.join(DIST, "search.js"));
  fs.copyFileSync(path.join(SRC, "leaderboards.js"), path.join(DIST, "leaderboards.js"));
  write(
    "_headers",
    `/*
  X-Content-Type-Options: nosniff
  Referrer-Policy: strict-origin-when-cross-origin
/styles.css
  Cache-Control: public, max-age=60, must-revalidate
/media/*
  Cache-Control: public, max-age=604800
`
  );
  write("robots.txt", "User-agent: *\nAllow: /\n");

  write(
    "index.html",
    shell({
      title: "Arkenelle",
      active: "home",
      body: `<section class="hero">
        <div class="hero-bg" style="${heroCss}"></div>
        <div class="hero-inner">
          <div class="alpha">Private alpha</div>
          <h1>Arkenelle</h1>
          <p class="lede">A hard sandbox MMORPG. No forced path and no hand-holding. Explore, fight, build a guild, take territory. Finding your own footing is the point.</p>
          <div class="cta-stack">
            <div class="play-wrap">
              <span class="play-halo" aria-hidden="true"></span>
              <span class="play-sparkle s1" aria-hidden="true"></span>
              <span class="play-sparkle s2" aria-hidden="true"></span>
              <span class="play-sparkle s3" aria-hidden="true"></span>
              <a class="btn play" href="${PLAY_WEB}"><span class="play-shine" aria-hidden="true"></span>Play in your browser</a>
            </div>
            <p class="cta-note">No download. Opens the live game in Chrome or Firefox.</p>
            <div class="cta-row">
              <a class="btn" href="${ITCH}">Desktop client</a>
              <a class="btn" href="${DISCORD}">Discord</a>
              <a class="btn" href="/wiki/">Wiki</a>
              <a class="btn" href="/leaderboards/">Leaderboards</a>
            </div>
          </div>
        </div>
      </section>
      <main class="wrap">
        <div class="grid-3">
          <article class="card">
            <h2>Play</h2>
            <p><a href="${PLAY_WEB}">Play in the browser</a> at play.arkenelle.com — first load is a large download. For weather and a smoother client, install with the <a href="${ITCH_APP}">itch.io app</a> from <a href="${ITCH}">kjp403.itch.io/arkenelle</a>.</p>
          </article>
          <article class="card">
            <h2>Where to start</h2>
            <p>Talk to the Hall Keeper in Castle Garden. That first quest is orientation, not a class lock. Every Hero can train every weapon and every profession.</p>
            <p><a href="/wiki/getting-started/">Getting started →</a></p>
          </article>
          <article class="card">
            <h2>Guilds</h2>
            <p>Join or found a guild, capture a territory banner, and earn Glory for as long as you hold it. See Guild in-game, or the <a href="/leaderboards/">live leaderboards</a>.</p>
            <p><a href="/wiki/guilds/">Guilds &amp; territory →</a></p>
          </article>
        </div>
      </main>`,
    })
  );

  write(
    "wiki/index.html",
    shell({
      title: "Wiki — Arkenelle",
      active: "wiki",
      body: `<main class="wrap">
        <h1 class="section-title">Wiki</h1>
        <p class="muted">Generated from the live Godot resources, so names, stats, and drops match the game.</p>
        <div class="card-grid">
          <a class="card" href="/wiki/getting-started/"><h3>Getting started</h3><p>First steps, install, and how progression works.</p></a>
          <a class="card" href="/wiki/items/"><h3>Items</h3><p>${items.length} weapons, armor, materials, potions, and more.</p></a>
          <a class="card" href="/wiki/creatures/"><h3>Creatures</h3><p>${creatures.length} enemies and bosses with authored loot.</p></a>
          <a class="card" href="/wiki/locations/"><h3>Locations</h3><p>${zones.length} zones and dungeons.</p></a>
          <a class="card" href="/wiki/npcs/"><h3>NPCs</h3><p>${npcs.length} friendly faces.</p></a>
          <a class="card" href="/wiki/skills/"><h3>Skills</h3><p>${jobs.length} gathering and crafting professions.</p></a>
          <a class="card" href="/wiki/slayer/"><h3>Slayer</h3><p>Masters, task pools, and creature assignments.</p></a>
          <a class="card" href="/wiki/quests/"><h3>Quests</h3><p>${quests.length} authored quests.</p></a>
          <a class="card" href="/wiki/guilds/"><h3>Guilds</h3><p>Territory, banners, and Glory.</p></a>
          <a class="card" href="/leaderboards/"><h3>Leaderboards</h3><p>Live ranks from the running world.</p></a>
        </div>
      </main>`,
    })
  );

  write(
    "leaderboards/index.html",
    shell({
      title: "Leaderboards — Arkenelle",
      active: "boards",
      scripts: ["/leaderboards.js"],
      body: `<main class="wrap" data-leaderboards>
        <div class="lb-head">
          <h1 class="section-title">Leaderboards</h1>
          <p class="lb-status" data-lb-status>Loading live ranks…</p>
        </div>
        <p class="muted">The same public boards as in-game, refreshed from the live world about every 30 seconds. Staff characters stay hidden.</p>
        <div class="filters lb-cats" data-lb-cats></div>
        <div class="filters lb-boards" data-lb-boards></div>
        <section class="lb-panel">
          <h2 data-lb-title>PvP · All-Time</h2>
          <div data-lb-table></div>
        </section>
      </main>`,
    })
  );

  write(
    "wiki/getting-started/index.html",
    shell({
      title: "Getting started — Arkenelle Wiki",
      active: "start",
      body: `<main class="wrap">
        ${crumb([{ href: "/wiki/", label: "Wiki" }, { label: "Getting started" }])}
        <article class="page prose">
          <h1 class="section-title">Getting started</h1>
          <h2>Play</h2>
          <ol>
            <li><strong>Browser:</strong> open <a href="${PLAY_WEB}">play.arkenelle.com</a>. First load downloads the whole client; later visits reuse the cache. This is the lighter build (no weather).</li>
            <li><strong>Desktop (recommended):</strong> install the <a href="${ITCH_APP}">itch.io app</a>, open <a href="${ITCH}">Arkenelle on itch.io</a> <em>inside the app</em>, and click Install. Updates arrive in the app after each release.</li>
          </ol>
          <h2>First steps</h2>
          <p>You wake in Castle Garden. The Hall Keeper near your starting cell has your first quest, <strong>Find Your Footing</strong>. It is orientation, not a class choice. Arkenelle does not lock you into a weapon or profession.</p>
          <p>Talk to NPCs when you want a thread to pull. Quest givers are the main way the world points you somewhere. After the Hall, take the main exit into the overworld and find the Foreman.</p>
          <h2>Progression</h2>
          <ul>
            <li>Character level is overall growth from quests and kills.</li>
            <li>Weapon Mastery is separate. The weapon you wield gains its own experience.</li>
            <li>Professions (Mining, Woodcutting, Smithing, and the rest) each have their own 1–99 track.</li>
            <li>Training one path never closes another.</li>
          </ul>
          <h2>While it is alpha</h2>
          <p>Expect rough edges. Patch notes land in your Mailbox. Type <code>/players</code> to see who is online, and <code>/feedback</code> to send a bug or idea. <a href="${DISCORD}">Discord</a> is the other door.</p>
        </article>
      </main>`,
    })
  );

  write(
    "wiki/guilds/index.html",
    shell({
      title: "Guilds — Arkenelle Wiki",
      active: "wiki",
      body: `<main class="wrap">
        ${crumb([{ href: "/wiki/", label: "Wiki" }, { label: "Guilds" }])}
        <article class="page prose">
          <h1 class="section-title">Guilds and territory</h1>
          <p>Join or found a guild, then take a territory by capturing its banner. Your guild earns Glory for as long as it holds that ground. The <a href="/leaderboards/">live leaderboards</a> show seasonal and eternal Glory, and the in-game Guild menu is the rest of the view.</p>
          <p>This is sandbox PvE/PvP infrastructure, not a theme-park campaign. Holding land is the point; the wiki will not tell you which banner to hit first.</p>
        </article>
      </main>`,
    })
  );

  const kinds = [...new Set(items.map((i) => i.kind))].sort();
  write(
    "wiki/items/index.html",
    shell({
      title: "Items — Arkenelle Wiki",
      active: "items",
      body: `<main class="wrap">
      ${crumb([{ href: "/wiki/", label: "Wiki" }, { label: "Items" }])}
      <h1 class="section-title">Items</h1>
      <p class="muted">${items.length} items pulled from game resources.</p>
      <div class="filters" data-filters>
        <button type="button" class="active" data-kind="">All</button>
        ${kinds.map((k) => `<button type="button" data-kind="${esc(k)}">${esc(k)}</button>`).join("")}
      </div>
      <div class="item-grid">${items
        .map(
          (it) =>
            `<a class="item-card" data-kind="${esc(it.kind)}" href="/wiki/items/${it.slug}/"><span class="icon-frame">${iconHtml(it.icon)}</span><span><span class="name">${esc(it.name)}</span><span class="kind">${esc(it.kind)}</span></span></a>`
        )
        .join("")}</div>
    </main>`,
    })
  );

  for (const it of items) {
    const stats = [];
    if (it.category) stats.push(["Mastery", it.category]);
    for (const mod of it.modifiers) stats.push([statLabel(mod.stat), (mod.value > 0 ? "+" : "") + String(mod.value)]);
    if (it.heal) stats.push(["Restores health", String(it.heal)]);
    if (it.mana) stats.push(["Restores mana", String(it.mana)]);
    if (it.buffStat) stats.push([statLabel(it.buffStat), `${it.buffAmount} for ${it.buffDuration >= 60 ? it.buffDuration / 60 + "m" : it.buffDuration + "s"}`]);
    if (it.requiredMastery) stats.push(["Requires mastery", `${it.masteryCats.join(" / ") || "any"} ${it.requiredMastery}`]);
    else if (it.requiredLevel) stats.push(["Requires level", String(it.requiredLevel)]);
    if (it.vendor) stats.push(["Vendor value", String(it.vendor)]);
    if (it.stack) stats.push(["Stack", it.stack === 1 ? "Not stackable" : String(it.stack)]);
    write(
      `wiki/items/${it.slug}/index.html`,
      shell({
        title: `${it.name} — Arkenelle Wiki`,
        active: "items",
        body: `<main class="wrap"><article class="page">
          ${crumb([{ href: "/wiki/", label: "Wiki" }, { href: "/wiki/items/", label: "Items" }, { label: it.name }])}
          <div class="detail-head">
            <span class="icon-frame detail-icon">${iconHtml(it.icon, 64)}</span>
            <div>
              <h1>${esc(it.name)}</h1>
              <div><span class="tag">${esc(it.kind)}</span></div>
            </div>
          </div>
          ${it.description ? `<p>${esc(it.description)}</p>` : ""}
          ${stats.length ? `<div class="stats">${stats.map(([k, v]) => `<div><span>${esc(k)}</span><span>${esc(v)}</span></div>`).join("")}</div>` : ""}
        </article></main>`,
      })
    );
  }

  write(
    "wiki/npcs/index.html",
    listPage(
      "NPCs",
      "Friendly NPCs. Names and greetings come from their resource files.",
      npcs
        .map(
          (n) =>
            `<a class="item-card" href="/wiki/npcs/${n.slug}/"><span><span class="name">${esc(n.name)}</span><span class="kind">${esc(n.offers.join(" · ") || "Talk")}</span></span></a>`
        )
        .join(""),
      "npcs"
    )
  );
  for (const n of npcs) {
    write(
      `wiki/npcs/${n.slug}/index.html`,
      shell({
        title: `${n.name} — Arkenelle Wiki`,
        active: "npcs",
        body: `<main class="wrap"><article class="page prose">
          ${crumb([{ href: "/wiki/", label: "Wiki" }, { href: "/wiki/npcs/", label: "NPCs" }, { label: n.name }])}
          <h1 class="section-title">${esc(n.name)}</h1>
          ${n.offers.map((o) => `<span class="tag">${esc(o)}</span>`).join("")}
          ${n.greeting ? `<p>${esc(n.greeting)}</p>` : ""}
          ${foundInHtml(n.locations)}
        </article></main>`,
      })
    );
  }

  write(
    "wiki/creatures/index.html",
    listPage(
      "Creatures",
      "Hostile types. Combat numbers and loot are what the server actually uses.",
      creatures
        .map(
          (c) =>
            `<a class="item-card" href="/wiki/creatures/${c.slug}/"><span><span class="name">${esc(c.name)}</span><span class="kind">${c.boss ? "Boss" : "Enemy"}${c.level ? " · Lv " + c.level : ""}</span></span></a>`
        )
        .join(""),
      "creatures"
    )
  );
  for (const c of creatures) {
    const stats = [
      ["Type", c.type],
      c.boss ? ["Role", "Boss"] : null,
      c.level ? ["Combat level", String(c.level)] : null,
      c.hp ? ["Max health", String(c.hp)] : null,
      c.damage ? ["Attack damage", String(c.damage)] : null,
      c.armor ? ["Armor", String(c.armor)] : null,
      c.mr ? ["Magic resist", String(c.mr)] : null,
      c.xp ? ["XP", String(c.xp)] : null,
    ].filter(Boolean);
    write(
      `wiki/creatures/${c.slug}/index.html`,
      shell({
        title: `${c.name} — Arkenelle Wiki`,
        active: "creatures",
        body: `<main class="wrap"><article class="page">
          ${crumb([{ href: "/wiki/", label: "Wiki" }, { href: "/wiki/creatures/", label: "Creatures" }, { label: c.name }])}
          <h1 class="section-title">${esc(c.name)}</h1>
          <div class="stats">${stats.map(([k, v]) => `<div><span>${esc(k)}</span><span>${esc(v)}</span></div>`).join("")}</div>
          ${foundInHtml(c.locations)}
          <h2>Loot</h2>
          ${lootList(c.loot, items)}
        </article></main>`,
      })
    );
  }

  write(
    "wiki/locations/index.html",
    listPage(
      "Locations",
      "Zones and dungeons from the instance collection.",
      zones
        .map(
          (z) =>
            `<a class="item-card" href="/wiki/locations/${z.slug}/"><span><span class="name">${esc(z.name)}</span><span class="kind">${z.isDungeon ? "Dungeon" : "Zone"}</span></span></a>`
        )
        .join(""),
      "locations"
    )
  );
  for (const z of zones) {
    const stats = [
      z.isDungeon ? ["Type", "Dungeon"] : ["Type", "Zone"],
      z.recommended ? ["Recommended level", String(z.recommended)] : null,
      z.levelMin || z.levelMax ? ["Level band", `${z.levelMin || "?"}–${z.levelMax || "?"}`] : null,
      z.party ? ["Party size", String(z.party)] : null,
      z.wardstone ? ["Wardstone", z.wardstone] : null,
    ].filter(Boolean);
    write(
      `wiki/locations/${z.slug}/index.html`,
      shell({
        title: `${z.name} — Arkenelle Wiki`,
        active: "locations",
        body: `<main class="wrap"><article class="page prose">
          ${crumb([{ href: "/wiki/", label: "Wiki" }, { href: "/wiki/locations/", label: "Locations" }, { label: z.name }])}
          <h1 class="section-title">${esc(z.name)}</h1>
          ${z.description ? `<p>${esc(z.description)}</p>` : ""}
          <div class="stats">${stats.map(([k, v]) => `<div><span>${esc(k)}</span><span>${esc(v)}</span></div>`).join("")}</div>
          ${
            z.people.length
              ? `<h2>People</h2><div class="item-grid">${z.people
                  .map((n) => {
                    const kind = (n.offers && n.offers.length ? n.offers.join(" · ") : "") || "NPC";
                    const inner = `<span><span class="name">${esc(n.name)}</span><span class="kind">${esc(kind)}</span>${n.greeting ? `<span class="kind">${esc(n.greeting.length > 140 ? n.greeting.slice(0, 137) + "…" : n.greeting)}</span>` : ""}</span>`;
                    return n.slug
                      ? `<a class="item-card" href="/wiki/npcs/${n.slug}/">${inner}</a>`
                      : `<div class="item-card">${inner}</div>`;
                  })
                  .join("")}</div>`
              : ""
          }
          ${
            z.fauna.length
              ? `<h2>Creatures</h2><div class="item-grid">${z.fauna
                  .map(({ creature: c, count }) => {
                    const extra = [c.boss ? "Boss" : "", c.level ? "Lv " + c.level : "", count > 1 ? "×" + count : ""]
                      .filter(Boolean)
                      .join(" · ");
                    return `<a class="item-card" href="/wiki/creatures/${c.slug}/"><span><span class="name">${esc(c.name)}</span><span class="kind">${esc(extra)}</span></span></a>`;
                  })
                  .join("")}</div>`
              : ""
          }
        </article></main>`,
      })
    );
  }

  write(
    "wiki/skills/index.html",
    listPage(
      "Skills",
      "Professions. Each has its own 1–99 track.",
      jobs
        .map(
          (j) =>
            `<a class="item-card" href="/wiki/skills/${j.slug}/"><span class="icon-frame">${iconHtml(j.icon, 32)}</span><span><span class="name">${esc(j.name)}</span><span class="kind">${esc(j.category)}</span></span></a>`
        )
        .join(""),
      "wiki"
    )
  );
  for (const j of jobs) {
    const sourceRows = j.sources
      .map((p, i) => {
        const item = itemByPath(items, p);
        const lv = j.sourceLevels[i];
        const label = item ? `<a href="/wiki/items/${item.slug}/">${esc(item.name)}</a>` : esc(basenameSlug(p).replace(/_/g, " "));
        return `<li>${label}${lv != null ? ` — level ${lv}` : ""}</li>`;
      })
      .join("");
    write(
      `wiki/skills/${j.slug}/index.html`,
      shell({
        title: `${j.name} — Arkenelle Wiki`,
        active: "wiki",
        body: `<main class="wrap"><article class="page prose">
          ${crumb([{ href: "/wiki/", label: "Wiki" }, { href: "/wiki/skills/", label: "Skills" }, { label: j.name }])}
          <div class="detail-head">
            <span class="icon-frame detail-icon">${iconHtml(j.icon, 48)}</span>
            <div><h1>${esc(j.name)}</h1><span class="tag">${esc(j.category)}</span></div>
          </div>
          ${j.describe.length ? `<ul>${j.describe.map((d) => `<li>${esc(d)}</li>`).join("")}</ul>` : ""}
          ${j.perks.length ? `<h2>Perks</h2><ul>${j.perks.map((p) => `<li><strong>${esc(p.name || p.id || "Perk")}</strong>${p.max_rank ? ` (max ${p.max_rank})` : ""}</li>`).join("")}</ul>` : ""}
          ${sourceRows ? `<h2>Resources</h2><ul>${sourceRows}</ul>` : ""}
        </article></main>`,
      })
    );
  }

  const taskBySlug = Object.fromEntries(slayer.tasks.map((t) => [t.slug, t]));
  write(
    "wiki/slayer/index.html",
    shell({
      title: "Slayer — Arkenelle Wiki",
      active: "wiki",
      body: `<main class="wrap">
        ${crumb([{ href: "/wiki/", label: "Wiki" }, { label: "Slayer" }])}
        <h1 class="section-title">Slayer</h1>
        <p class="muted">Masters assign creature tasks. Kill the assigned types to finish the count.</p>
        <h2>Masters</h2>
        <div class="card-grid">${slayer.masters
          .map(
            (m) => `<article class="card"><h3>${esc(m.name)}</h3>
            <p class="muted">${esc(m.location)}${m.min ? ` · Slayer ${m.min}+` : ""}</p>
            ${m.greeting ? `<p>${esc(m.greeting)}</p>` : ""}
            <ul>${m.pool
              .map((p) => {
                const t = taskBySlug[p.task];
                return `<li>${esc(t ? t.name : p.task)} (${p.min}–${p.max})</li>`;
              })
              .join("")}</ul></article>`
          )
          .join("")}</div>
        <h2>Task types</h2>
        <div class="card-grid">${slayer.tasks
          .map(
            (t) => `<article class="card"><h3>${esc(t.name)}</h3>
            <p class="muted">${esc(t.location)}${t.min ? ` · Slayer ${t.min}+` : ""} · ${t.xp} XP / kill</p>
            ${t.notes ? `<p>${esc(t.notes)}</p>` : ""}
            <p>${t.enemies
              .map((e) => {
                const c = creatures.find((x) => x.type === e || x.slug === e);
                return c ? `<a href="/wiki/creatures/${c.slug}/">${esc(c.name)}</a>` : esc(e);
              })
              .join(", ")}</p></article>`
          )
          .join("")}</div>
      </main>`,
    })
  );

  write(
    "wiki/quests/index.html",
    listPage(
      "Quests",
      "Authored quests (not the rotating daily board).",
      quests
        .map(
          (q) =>
            `<a class="item-card" href="/wiki/quests/${q.slug}/"><span><span class="name">${esc(q.name)}</span><span class="kind">${q.xp ? q.xp + " XP" : "Quest"}</span></span></a>`
        )
        .join(""),
      "wiki"
    )
  );
  for (const q of quests) {
    write(
      `wiki/quests/${q.slug}/index.html`,
      shell({
        title: `${q.name} — Arkenelle Wiki`,
        active: "wiki",
        body: `<main class="wrap"><article class="page prose">
          ${crumb([{ href: "/wiki/", label: "Wiki" }, { href: "/wiki/quests/", label: "Quests" }, { label: q.name }])}
          <h1 class="section-title">${esc(q.name)}</h1>
          ${q.description ? `<p>${esc(q.description)}</p>` : ""}
          <div class="stats">
            ${q.xp ? `<div><span>XP</span><span>${q.xp}</span></div>` : ""}
            ${q.gold ? `<div><span>Gold</span><span>${q.gold}</span></div>` : ""}
            ${q.title ? `<div><span>Title</span><span>${esc(q.title)}</span></div>` : ""}
          </div>
        </article></main>`,
      })
    );
  }

  const search = [
    ...items.map((x) => ({ title: x.name, kind: "Item · " + x.kind, href: `/wiki/items/${x.slug}/`, haystack: (x.name + " " + x.kind + " " + x.description).toLowerCase() })),
    ...npcs.map((x) => ({ title: x.name, kind: "NPC", href: `/wiki/npcs/${x.slug}/`, haystack: (x.name + " " + x.greeting + " " + (x.locations || []).map((z) => z.name).join(" ")).toLowerCase() })),
    ...creatures.map((x) => ({ title: x.name, kind: x.boss ? "Boss" : "Creature", href: `/wiki/creatures/${x.slug}/`, haystack: (x.name + " " + x.type + " " + (x.locations || []).map((z) => z.name).join(" ")).toLowerCase() })),
    ...zones.map((x) => ({ title: x.name, kind: x.isDungeon ? "Dungeon" : "Location", href: `/wiki/locations/${x.slug}/`, haystack: (x.name + " " + x.description).toLowerCase() })),
    ...jobs.map((x) => ({ title: x.name, kind: "Skill", href: `/wiki/skills/${x.slug}/`, haystack: x.name.toLowerCase() })),
    ...quests.map((x) => ({ title: x.name, kind: "Quest", href: `/wiki/quests/${x.slug}/`, haystack: (x.name + " " + x.description).toLowerCase() })),
    { title: "Getting started", kind: "Guide", href: "/wiki/getting-started/", haystack: "getting started install hall keeper" },
    { title: "Guilds", kind: "Guide", href: "/wiki/guilds/", haystack: "guilds territory glory banner" },
    { title: "Leaderboards", kind: "Live", href: "/leaderboards/", haystack: "leaderboards pvp pve glory gold arena dungeon ranks" },
    { title: "Slayer", kind: "Guide", href: "/wiki/slayer/", haystack: "slayer turael durael tasks" },
  ];
  write("wiki/search.json", JSON.stringify(search));

  write(
    "404.html",
    shell({
      title: "Not found — Arkenelle",
      active: "",
      body: `<main class="wrap"><h1 class="section-title">No such page</h1><p class="muted">That path is not in the wiki. Try <a href="/wiki/">the index</a> or search.</p></main>`,
    })
  );

  copyMedia();

  console.log(
    [
      "Arkenelle site built → website/dist",
      `  items ${items.length}`,
      `  npcs ${npcs.length}`,
      `  creatures ${creatures.length}`,
      `  locations ${zones.length}`,
      `  skills ${jobs.length}`,
      `  quests ${quests.length}`,
      `  slayer masters ${slayer.masters.length} / tasks ${slayer.tasks.length}`,
      `  media files ${usedMedia.size}`,
      `  zone people ${zones.reduce((n, z) => n + z.people.length, 0)} / creatures ${zones.reduce((n, z) => n + z.fauna.length, 0)}`,
    ].join("\n")
  );
}

build();
