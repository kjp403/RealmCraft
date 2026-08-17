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
const PLAY_DESKTOP = "https://play.arkenelle.com/desktop/Arkenelle-windows.zip";
const DISCORD = "https://discord.gg/kSs3hxByV";
const ITCH_APP = "https://itch.io/app";
const STRIPE = {
  sapphireVip: "https://buy.stripe.com/28E00k1aF5w81uC8Ho6J207",
  emeraldVip: "https://buy.stripe.com/dRm7sM6uZbUw6OW3n46J206",
  rubyVip: "https://buy.stripe.com/3cI7sM06BcYAfls6zg6J205",
  sapphireOnce: "https://buy.stripe.com/14A3cw5qV2jWc9g1eW6J204",
  emeraldOnce: "https://buy.stripe.com/7sY4gAbPj1fSeho2j06J201",
  rubyOnce: "https://buy.stripe.com/3cIdRa4mRe2Ec9g2j06J203",
  custom: "https://buy.stripe.com/14A00k2eJ6Acb5c8Ho6J208",
};

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
const SKIP_ZONES = new Set(["jail", "vfx_vault", "dungeon_entrance", "quest_boss_arena", "boss_hunt_arena"]);
const SKIP_ENEMIES = new Set(["training_dummy"]);

const ZONE_BLURBS = {
  ossuary:
    "A sealed bone chapel off the main Sewers. The purple stair by the sewer entrance is the door. The Necromancer holds this floor — current hardest world pad, and the open-world source of Wyrmguard, Astral, and Nightglass.",
  sewers:
    "The culverts under the Capital. Stairs lead to The Gutterworks and The Drowned Cistern. A purple stair next to the entrance opens The Ossuary, where the Necromancer waits.",
  desert:
    "The Sunken Tombs basin. Unbound Sand King holds the north. The Necromancer is no longer here — he moved to The Ossuary under the Sewers.",
  the_hollow:
    "The Charter spine's last chamber. Unleashed Golem holds the center pad. The Hall Keeper sends you into a private story fight when that Charter quest is active.",
  woodland:
    "Goblin Woodland. The Goblin Chief still holds the camp. Warden Bren sends you into a private room for the story kill when that Charter quest is active.",
  FungusArea1:
    "The Fungal Heart still holds the cave. Forager Maela and Lira Voss send you into a private room for the story Heart.",
  bandit_hideout:
    "The Bandit Captain still holds the camp. The Watch Sergeant and Rook Hale send you into a private room for the story kill.",
  fire_forge:
    "Vurthek Unbound still holds the foundry. Cinderwright Maro sends you into a private room for the story Cinderborn.",
  drowned_cistern:
    "Drowned Keeper Vess sends you into a private room for the story Sovereign. The Bloated Sovereign remains on the main Sewers floor.",
};

const CAMPAIGN = {
  hollow_seep: {
    slug: "hollow-seep",
    name: "The Hollow Seep",
    blurb: "The Charter spine. The Clerk seals your papers, the Hall Keeper sends you into the woodland, and each climax's giver opens a private fight. Unique weapons land on turn-in. Smithing makes armour.",
  },
  fungus_cave: {
    slug: "fungus-cave",
    name: "Fungus Cave",
    blurb: "Work in the caps. The Heart's unique is granted on the Charter climax Cut the Heart, not these side jobs.",
  },
  bandit_hideout: {
    slug: "bandit-hideout",
    name: "Bandit Hideout",
    blurb: "The Watch's camp jobs. The Captain's unique is the Charter climax Break the Cage.",
  },
  side: {
    slug: "side",
    name: "Castle and professions",
    blurb: "Gathering, smithing, and introductions around the Hall. Find Your Footing is an optional errand after Blood in the Meadow.",
  },
};

const OBJ_KILL = 0;
const OBJ_COLLECT = 1;
const OBJ_CRAFT = 2;
const OBJ_VISIT = 3;

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

const LOC_BG_DIR = path.join(SRC, "location-bgs");

function locationBgUrl(slug) {
  const jpg = path.join(LOC_BG_DIR, slug + ".jpg");
  const png = path.join(LOC_BG_DIR, slug + ".png");
  if (fs.existsSync(jpg)) return `/media/locations/${slug}.jpg`;
  if (fs.existsSync(png)) return `/media/locations/${slug}.png`;
  return "";
}

function copyLocationBgs() {
  if (!fs.existsSync(LOC_BG_DIR)) return;
  const dest = path.join(DIST, "media", "locations");
  fs.mkdirSync(dest, { recursive: true });
  for (const name of fs.readdirSync(LOC_BG_DIR)) {
    if (!name.endsWith(".png") && !name.endsWith(".jpg")) continue;
    fs.copyFileSync(path.join(LOC_BG_DIR, name), path.join(dest, name));
  }
}

const DONATE_BADGE_DIR = path.join(SRC, "donate-badges");

function copyDonateBadges() {
  if (!fs.existsSync(DONATE_BADGE_DIR)) return;
  const dest = path.join(DIST, "media", "donate");
  fs.mkdirSync(dest, { recursive: true });
  for (const name of fs.readdirSync(DONATE_BADGE_DIR)) {
    if (!name.endsWith(".png")) continue;
    fs.copyFileSync(path.join(DONATE_BADGE_DIR, name), path.join(dest, name));
  }
}

function donateCard({ img, name, price, blurb, href, gem }) {
  return `<article class="donate-card gem-${gem}">
    <img src="/media/donate/${img}" alt="" width="256" height="256">
    <h3>${esc(name)}</h3>
    <p class="price">${esc(price)}</p>
    <p>${esc(blurb)}</p>
    <a class="btn" href="${href}" target="_blank" rel="noopener noreferrer">Donate</a>
  </article>`;
}

function catIcon(id) {
  const d = {
    start: `<circle cx="12" cy="12" r="8.5"/><path d="M12 3.8v2.6M12 17.6v2.6M3.8 12h2.6M17.6 12h2.6"/><circle cx="12" cy="12" r="1.5" fill="currentColor" stroke="none"/><path d="M12 7.2l1.7 4.3H12"/>`,
    items: `<path d="M7 8.6h10l.9 11.2H6.1L7 8.6z"/><path d="M9 8.6V7.1A3 3 0 0 1 12 4.2 3 3 0 0 1 15 7.1v1.5"/><path d="M9.5 12.2h5"/>`,
    creatures: `<path d="M8.2 10.4c0-3 1.7-5.4 3.8-5.4s3.8 2.4 3.8 5.4v1.3H8.2z"/><path d="M8.2 11.7c-1.8.4-3 1.6-3 3.3 0 1.1.7 2 2.1 2.3"/><path d="M15.8 11.7c1.8.4 3 1.6 3 3.3 0 1.1-.7 2-2.1 2.3"/><path d="M9.3 19c.8-1.3 1.6-1.9 2.7-1.9s1.9.6 2.7 1.9"/><circle cx="10.3" cy="11.2" r=".7" fill="currentColor" stroke="none"/><circle cx="13.7" cy="11.2" r=".7" fill="currentColor" stroke="none"/>`,
    locations: `<path d="M12 21s6.4-6.1 6.4-10.8A6.4 6.4 0 0 0 5.6 10.2C5.6 14.9 12 21 12 21z"/><circle cx="12" cy="10.2" r="2.1"/>`,
    npcs: `<circle cx="12" cy="8" r="3.1"/><path d="M5.6 19.4c.8-3.3 3.1-4.9 6.4-4.9s5.6 1.6 6.4 4.9"/>`,
    skills: `<path d="M8.4 14.3l-3.5 3.5 1.6 1.6 3.5-3.5"/><path d="M14.7 4.9l4.3 4.3-8.1 8.1H6.6V13z"/><path d="M16.2 8.3l1.7-1.7a1.5 1.5 0 0 0 0-2.1"/>`,
    slayer: `<path d="M4.8 19.2l8.8-8.8 2.1.7L19 8.1l-1-3-3 1-2.1 2.8L4.8 19.2z"/><path d="M19.2 19.2l-8.8-8.8-.7 2.1L8.1 5l3-1 2.8 2.1 5.3 13.1z"/>`,
    quests: `<path d="M7 4.6h10a1 1 0 0 1 1 1V19.6l-6-2.3-6 2.3V5.6a1 1 0 0 1 1-1z"/><path d="M9.2 9.2h5.6M9.2 12.4h5.6"/>`,
    guilds: `<path d="M6.2 4.6h11.6v3.3c0 2.2-1.4 3.8-3.2 4.7L12 14.2l-2.6-1.6c-1.8-.9-3.2-2.5-3.2-4.7z"/><path d="M12 14.2V20"/>`,
    boards: `<path d="M7.2 20V10.2h3.2V20H7.2zm6.4 0V6.2h3.2V20h-3.2zM4.4 20h15.2"/><path d="M8.6 7.2 12 4.4l3.4 2.8"/>`,
    play: `<path d="M8 6.4v11.2L19 12z"/>`,
    donate: `<path d="M12 20.4L4.8 12.2 8.2 5.6h7.6l3.4 6.6z"/><path d="M4.8 12.2h14.4M8.2 5.6 12 12.2 15.8 5.6"/>`,
    boss: `<path d="M4.8 16.6h14.4v2.1H4.8z"/><path d="M5.2 8.1l3.1 2.5L12 5.4l3.7 5.2 3.1-2.5v8.2H5.2z"/>`,
    enemy: `<path d="M8.2 10.4c0-3 1.7-5.4 3.8-5.4s3.8 2.4 3.8 5.4v1.3H8.2z"/><path d="M8.2 11.7c-1.8.4-3 1.6-3 3.3 0 1.1.7 2 2.1 2.3"/><path d="M15.8 11.7c1.8.4 3 1.6 3 3.3 0 1.1-.7 2-2.1 2.3"/><path d="M9.3 19c.8-1.3 1.6-1.9 2.7-1.9s1.9.6 2.7 1.9"/><circle cx="10.3" cy="11.2" r=".7" fill="currentColor" stroke="none"/><circle cx="13.7" cy="11.2" r=".7" fill="currentColor" stroke="none"/>`,
  };
  const inner = d[id];
  if (!inner) return "";
  return `<span class="cat-icon" aria-hidden="true"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">${inner}</svg></span>`;
}

function pageHeading(cat, title) {
  return `<h1 class="section-title page-title">${catIcon(cat)}<span>${esc(title)}</span></h1>`;
}

function wikiCard(cat, href, title, bodyHtml) {
  return `<a class="card wiki-card cat-${cat}" href="${href}">${catIcon(cat)}<div><h3>${esc(title)}</h3><p>${bodyHtml}</p></div></a>`;
}

function shell({ title, active, body, scripts = [], theme = "", extraClass = "" }) {
  const home = "/";
  const wiki = "/wiki/";
  const extraScripts = scripts.map((src) => `  <script src="${src}"></script>`).join("\n");
  const classes = [theme ? `theme-${theme}` : "", extraClass].filter(Boolean).join(" ");
  const bodyClass = classes ? ` class="${classes}"` : "";
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
  <link href="https://fonts.googleapis.com/css2?family=Jersey+10&family=Pixelify+Sans:wght@400;500;700&family=Silkscreen:wght@400;700&display=swap" rel="stylesheet">
  <link rel="stylesheet" href="/styles.css?v=${CSS_V}">
</head>
<body${bodyClass}>
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
      <a href="${PLAY_DESKTOP}">Download</a>
      <a href="/donate/" class="${active === "donate" ? "active" : ""}">Donate</a>
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
      chestSlug: str(doc.resource.chest_slug),
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
      if (p.endsWith("quest_boss_interaction.gd")) offers.add("Story fight");
    }
    const questKeys = [];
    let storyEnemy = "";
    for (const sub of Object.values(doc.sub)) {
      for (const ref of asArray(sub.props?.quests)) {
        const qPath = resolveExt(doc, ref);
        if (qPath) questKeys.push(fileKey(qPath));
      }
      const et = str(sub.props?.enemy_type);
      if (et) storyEnemy = et;
    }
    npcs.push({
      slug: uniqueSlug(slug0, used),
      name,
      greeting: str(doc.resource.greeting),
      offers: [...offers],
      questKeys: [...new Set(questKeys)],
      quests: [],
      storyEnemy,
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
      ornateItem: resolveExt(doc, doc.resource.ornate_chest_item),
      ornateTopMin: num(doc.resource.ornate_chest_top_min),
      ornateTopMax: num(doc.resource.ornate_chest_top_max),
      ornateSecondMin: num(doc.resource.ornate_chest_second_min),
      ornateSecondMax: num(doc.resource.ornate_chest_second_max),
      ornateConsolation: num(doc.resource.ornate_chest_consolation_chance),
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
      description: str(doc.resource.description) || ZONE_BLURBS[inst] || "",
      recommended: num(doc.resource.recommended_level),
      levelMin: num(doc.resource.level_min),
      levelMax: num(doc.resource.level_max),
      wardstone: str(doc.resource.required_wardstone),
      party: num(doc.resource.party_size, isDungeon ? 4 : 0),
      mapPath: str(doc.resource.map_path),
      people: [],
      fauna: [],
      zoneKillLoot: dropsFrom(doc, doc.resource.zone_kill_loot),
      rewardPath: resolveExt(doc, doc.resource.reward),
      hardRewardPath: resolveExt(doc, doc.resource.hard_reward),
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

function questBodyCreature(creatures, enemyType) {
  const matches = creatures.filter((c) => c.type === enemyType);
  const quest = matches.find((c) => !c.file.replace(/\\/g, "/").includes("_world."));
  return quest || matches[0] || null;
}

function attachStoryBosses(npcs, creatures) {
  for (const n of npcs) {
    if (!n.storyEnemy) continue;
    const c = questBodyCreature(creatures, n.storyEnemy);
    if (!c) continue;
    c.storyGivers = c.storyGivers || [];
    if (!c.storyGivers.some((g) => g.slug === n.slug)) c.storyGivers.push(n);
  }
}

function storyFightHtml(c) {
  if (!c.storyGivers || !c.storyGivers.length) return "";
  const lis = c.storyGivers
    .map((n) => {
      const where = (n.locations || [])
        .map((z) => `<a class="cat-locations" href="/wiki/locations/${z.slug}/">${esc(z.name)}</a>`)
        .join(", ");
      return `<li><a class="cat-npcs" href="/wiki/npcs/${n.slug}/">${esc(n.name)}</a>${where ? ` (${where})` : ""} — Send me to the fight</li>`;
    })
    .join("");
  return `<h2>Story fight</h2><p>Private solo room. The quest giver sends you in while that Charter kill is active. World pads below (if any) are the farm — keys and unique weapons land on turn-in, not on the story kill.</p><ul>${lis}</ul>`;
}

function foundInHtml(locations) {
  if (!locations || !locations.length) return "";
  return `<h2>Found in</h2><ul>${locations
    .map((z) => `<li><a class="cat-locations" href="/wiki/locations/${z.slug}/">${esc(z.name)}</a></li>`)
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

function campaignOf(file) {
  const p = String(file || "").replace(/\\/g, "/");
  const m = p.match(/quests\/resources\/([^/]+)\//);
  const folder = m?.[1];
  // Bren's warren is the woodland chapter of the Charter spine.
  if (folder === "goblin_woodland") return "hollow_seep";
  return CAMPAIGN[folder] ? folder : "side";
}

function skillLabel(slug, level) {
  if (!slug) return "";
  const name = String(slug).replace(/_/g, " ").replace(/\b\w/g, (c) => c.toUpperCase());
  return level ? `${name} ${level}` : name;
}

function modVal(item, stat) {
  const m = (item?.modifiers || []).find((x) => x.stat === stat);
  return m ? m.value : 0;
}

function collectQuests() {
  const dir = path.join(ROOT, "source/common/gameplay/quests/resources");
  const rows = [];
  for (const file of walk(dir).filter((f) => f.endsWith(".tres"))) {
    const doc = parseTres(read(file));
    if (doc.header.script_class !== "QuestResource") continue;
    const name = str(doc.resource.quest_name);
    if (!name) continue;
    const campaign = campaignOf(file);
    rows.push({
      key: fileKey(file),
      slug: slugify(str(doc.resource["metadata/slug"]) || basenameSlug(file)),
      name,
      description: str(doc.resource.description),
      xp: num(doc.resource.reward_xp),
      masteryXp: num(doc.resource.reward_mastery_xp),
      gold: num(doc.resource.reward_gold),
      title: str(doc.resource.grant_title),
      wardstone: str(doc.resource.grants_wardstone),
      minLevel: num(doc.resource.min_level),
      minSkill: str(doc.resource.min_skill),
      minSkillLevel: num(doc.resource.min_skill_level),
      autoComplete: Boolean(doc.resource.auto_complete),
      completionAny: num(doc.resource.completion) === 1,
      requiresAny: num(doc.resource.requires_mode) === 1,
      campaign,
      campaignMeta: CAMPAIGN[campaign],
      file,
      prereqKeys: asArray(doc.resource.requires_quests)
        .map((ref) => fileKey(resolveExt(doc, ref)))
        .filter(Boolean),
      rewardItems: asArray(doc.resource.reward_items)
        .map((ref) => {
          const sub = resolveSub(doc, ref);
          if (!sub) return null;
          return {
            itemPath: resolveExt(doc, sub.props.item),
            amount: num(sub.props.amount, 1) || 1,
          };
        })
        .filter((r) => r && r.itemPath),
      styleWeapons: asArray(doc.resource.reward_style_weapons)
        .map((ref) => resolveExt(doc, ref))
        .filter(Boolean),
      grantOnAccept: resolveExt(doc, doc.resource.grant_on_accept),
      objectives: asArray(doc.resource.objectives)
        .map((ref) => {
          const sub = resolveSub(doc, ref);
          if (!sub) return null;
          return {
            type: num(sub.props.type, OBJ_KILL),
            enemy: str(sub.props.enemy_type),
            itemPath: resolveExt(doc, sub.props.item),
            amount: num(sub.props.required_amount, 1) || 1,
            visitName: str(sub.props.target_giver_name),
            visitKey: str(sub.props.target_giver_key),
            label: str(sub.props.label_override),
            grantItemPath: resolveExt(doc, sub.props.grant_item),
          };
        })
        .filter(Boolean),
      givers: [],
      prereqs: [],
      unlocks: [],
      depth: 0,
    });
  }
  return rows;
}

function attachQuestGraph(quests, npcs) {
  const byKey = new Map(quests.map((q) => [q.key, q]));
  for (const n of npcs) {
    n.quests = [];
    for (const key of n.questKeys || []) {
      const q = byKey.get(key);
      if (!q) continue;
      if (!q.givers.some((g) => g.slug === n.slug)) q.givers.push(n);
      if (!n.quests.some((x) => x.slug === q.slug)) n.quests.push(q);
    }
  }
  for (const q of quests) {
    q.prereqs = q.prereqKeys.map((k) => byKey.get(k)).filter(Boolean);
    q.unlocks = [];
  }
  for (const q of quests) {
    for (const pre of q.prereqs) pre.unlocks.push(q);
  }
  const seen = new Set();
  const visiting = new Set();
  const walkDepth = (q) => {
    if (seen.has(q.slug)) return q.depth;
    if (visiting.has(q.slug)) return 0;
    visiting.add(q.slug);
    q.depth = q.prereqs.reduce((d, pre) => Math.max(d, walkDepth(pre) + 1), 0);
    visiting.delete(q.slug);
    seen.add(q.slug);
    return q.depth;
  };
  for (const q of quests) walkDepth(q);
  quests.sort((a, b) => a.depth - b.depth || a.name.localeCompare(b.name));
  return byKey;
}

function questHref(q) {
  return `/wiki/quests/${q.slug}/`;
}

function campaignHref(id) {
  return `/wiki/quests/${CAMPAIGN[id]?.slug || id}/`;
}

function itemHrefLabel(items, itemPath) {
  const it = itemByPath(items, itemPath);
  if (it) return `<a class="cat-items" href="/wiki/items/${it.slug}/">${esc(it.name)}</a>`;
  return esc(fileKey(itemPath).replace(/_/g, " "));
}

function describeObjective(obj, items, creatures, npcs) {
  const amt = obj.amount > 1 ? `${obj.amount} ` : "";
  let core = "";
  if (obj.type === OBJ_VISIT) {
    const who = obj.visitName || obj.visitKey.replace(/_/g, " ") || "the indicated person";
    const npc = npcs.find((n) => n.slug === obj.visitKey || fileKey(n.file) === obj.visitKey);
    const label = npc ? `<a class="cat-npcs" href="/wiki/npcs/${npc.slug}/">${esc(who)}</a>` : esc(who);
    core = `Speak with ${label}`;
  } else if (obj.type === OBJ_CRAFT) {
    core = `Craft ${amt}${obj.label ? esc(obj.label) : itemHrefLabel(items, obj.itemPath)}`;
  } else if (obj.type === OBJ_COLLECT) {
    core = `Bring ${amt}${obj.label ? esc(obj.label) : itemHrefLabel(items, obj.itemPath)}`;
  } else {
    const c = creatures.find((x) => x.type === obj.enemy || x.slug === obj.enemy);
    const foe = c
      ? `<a class="cat-creatures" href="/wiki/creatures/${c.slug}/">${esc(c.name)}</a>`
      : esc((obj.enemy || "enemy").replace(/_/g, " ").replace(/\b\w/g, (ch) => ch.toUpperCase()));
    core = `Defeat ${amt}${foe}`;
  }
  if (obj.grantItemPath) core += ` <span class="muted">(yields ${itemHrefLabel(items, obj.grantItemPath)})</span>`;
  return core;
}

/** Every crafting station and what its recipes produce. */
function collectStations() {
  const dir = path.join(ROOT, "source/common/gameplay/crafting/resources");
  const rows = [];
  if (!fs.existsSync(dir)) return rows;
  for (const file of walk(dir).filter((f) => f.endsWith(".tres"))) {
    let doc;
    try {
      doc = parseTres(read(file));
    } catch {
      continue;
    }
    if (doc.header.script_class && doc.header.script_class !== "CraftingStationResource") continue;
    const recipes = asArray(doc.resource.recipes)
      .map((ref) => {
        const sub = resolveSub(doc, ref);
        if (!sub) return null;
        return {
          itemPath: resolveExt(doc, sub.props.output_item),
          amount: num(sub.props.output_amount, 1) || 1,
          level: num(sub.props.required_level),
          ingredients: asArray(sub.props.ingredients)
            .map((iref) => {
              const ing = resolveSub(doc, iref);
              if (!ing) return null;
              return { itemPath: resolveExt(doc, ing.props.item), amount: num(ing.props.amount, 1) || 1 };
            })
            .filter((i) => i && i.itemPath),
        };
      })
      .filter((r) => r && r.itemPath);
    if (!recipes.length) continue;
    rows.push({
      name: str(doc.resource.station_name) || basenameSlug(file).replace(/_/g, " "),
      // CraftingStationResource.profession defaults to &"smithing" in GDScript, so
      // a station that never writes the field still trains it.
      profession: str(doc.resource.profession) || "smithing",
      recipes,
    });
  }
  return rows;
}

function buildItemSources(items, creatures, shops, stations, chests, quests) {
  const map = new Map();
  const bucket = (itemPath) => {
    const item = itemByPath(items, itemPath);
    if (!item) return null;
    if (!map.has(item.slug)) {
      map.set(item.slug, { drops: [], shops: [], crafts: [], chests: [], quests: [] });
    }
    return map.get(item.slug);
  };

  for (const c of creatures) {
    for (const d of c.loot) {
      const b = bucket(d.itemPath);
      if (b) b.drops.push({ creature: c, chance: d.chance, min: d.min, max: d.max });
    }
  }
  for (const shop of shops) {
    for (const e of shop.entries) {
      const b = bucket(e.itemPath);
      if (b) b.shops.push({ shop, price: e.price, currencyPath: e.currencyPath });
    }
  }
  for (const st of stations) {
    for (const r of st.recipes) {
      const b = bucket(r.itemPath);
      if (b) b.crafts.push({ station: st, recipe: r });
    }
  }
  for (const chest of chests) {
    for (const d of chest.drops) {
      const b = bucket(d.itemPath);
      if (b) b.chests.push({ chest, chance: d.chance, min: d.min, max: d.max });
    }
  }
  for (const q of quests) {
    for (const r of q.rewardItems || []) {
      const b = bucket(r.itemPath);
      if (b) b.quests.push({ quest: q, amount: r.amount });
    }
    for (const itemPath of q.styleWeapons || []) {
      const b = bucket(itemPath);
      if (b) b.quests.push({ quest: q, amount: 1, stylePick: true });
    }
  }
  // Best sources first: a 60% drop is the answer, a 0.1% one is trivia.
  for (const v of map.values()) {
    v.drops.sort((a, b) => b.chance - a.chance);
    v.shops.sort((a, b) => a.price - b.price);
    v.chests.sort((a, b) => a.chest.tier - b.chest.tier);
  }
  return map;
}

function sourceSummary(src) {
  if (!src) return "—";
  const bits = [];
  if (src.quests.length) {
    bits.push(src.quests.some((q) => q.stylePick) ? "Quest (your style)" : "Quest");
  }
  if (src.drops.length) bits.push(`Drop (${esc(src.drops[0].creature.name)})`);
  if (src.crafts.length) {
    const best = src.crafts.reduce((a, b) => (a.recipe.level <= b.recipe.level ? a : b));
    bits.push(
      best.recipe.level
        ? `Craft (${esc(best.station.profession)} ${best.recipe.level})`
        : `Craft (${esc(best.station.name)})`
    );
  }
  if (src.shops.length) bits.push(`Buy (${esc(String(src.shops[0].price))}g)`);
  if (src.chests.length) bits.push("Chest");
  return bits.join(" · ") || "—";
}

function armourSetName(name) {
  return String(name)
    .replace(
      /\s+(Helmet|Helm|Hood|Hat|Crown|Mask|Chestplate|Chest|Platebody|Tunic|Robe|Boots|Shoes|Sandals|Greaves|Gloves|Gauntlets|Vambraces|Legs|Leggings|Skirt|Cape|Cloak|Shield|Kite|Pauldrons|Shoulders)$/i,
      ""
    )
    .trim();
}

function weaponPower(it) {
  const ad = modVal(it, "ad");
  const ap = modVal(it, "ap");
  if (ad && ap) return `${ad} AD / ${ap} AP`;
  if (ap) return `${ap} AP`;
  if (ad) return String(ad);
  return "—";
}

/**
 * The gear ladder, grouped by the mastery level that unlocks each piece.
 *
 * Generated rather than written: a hand-authored tier list goes stale the first
 * time someone re-tunes a required_mastery_level, and a stale ladder is worse
 * than none. Weapons group by their own mastery category; armour is gated on
 * &"any", meaning your BEST mastery, so it gets its own table.
 */
function gearPathPage(items, itemSources, quests) {
  const wearable = items.filter(
    (it) => (it.kind === "Weapon" || it.kind === "Armor") && (it.requiredMastery || 0) >= 0
  );
  const tierOf = (it) => it.requiredMastery || 0;
  const bands = [
    [0, 1, "Mastery 1 — what you start in"],
    [2, 9, "Mastery 2–9 — the first upgrade"],
    [10, 19, "Mastery 10–19 — mid game"],
    [20, 39, "Mastery 20–39 — late game"],
    [40, 999, "Mastery 40+ — endgame"],
  ];

  const weaponTable = (rows) =>
    rows.length
      ? `<table class="gear-table"><thead><tr><th>Item</th><th>Unlocks at</th><th>AD / AP</th><th>How to get it</th></tr></thead><tbody>${rows
          .map(
            (it) =>
              `<tr><td><a class="cat-items" href="/wiki/items/${it.slug}/">${esc(it.name)}</a></td><td>${esc(
                String(tierOf(it) || 1)
              )}</td><td>${weaponPower(it)}</td><td>${sourceSummary(itemSources.get(it.slug))}</td></tr>`
          )
          .join("")}</tbody></table>`
      : `<p class="muted">Nothing in this band yet.</p>`;

  const armourTable = (rows) =>
    rows.length
      ? `<table class="gear-table"><thead><tr><th>Item</th><th>Unlocks at</th><th>Armor</th><th>HP</th><th>How to get it</th></tr></thead><tbody>${rows
          .map(
            (it) =>
              `<tr><td><a class="cat-items" href="/wiki/items/${it.slug}/">${esc(it.name)}</a></td><td>${esc(
                String(tierOf(it) || 1)
              )}</td><td>${modVal(it, "armor") || "—"}</td><td>${modVal(it, "health_max") || "—"}</td><td>${sourceSummary(itemSources.get(it.slug))}</td></tr>`
          )
          .join("")}</tbody></table>`
      : `<p class="muted">Nothing in this band yet.</p>`;

  const climaxes = (quests || [])
    .filter((q) => q.styleWeapons.length)
    .sort((a, b) => a.depth - b.depth || a.name.localeCompare(b.name));
  const uniqueLadder = climaxes.length
    ? `<table class="gear-table"><thead><tr><th>Climax</th><th>Unique of your style</th></tr></thead><tbody>${climaxes
        .map((q) => {
          const links = q.styleWeapons
            .map((p) => itemHrefLabel(items, p))
            .join(", ");
          return `<tr><td><a href="${questHref(q)}">${esc(q.name)}</a></td><td>${links}</td></tr>`;
        })
        .join("")}</tbody></table>`
    : "";

  const sets = new Map();
  for (const it of wearable.filter((x) => x.kind === "Armor")) {
    const set = armourSetName(it.name);
    if (!set || set === it.name) continue;
    if (!sets.has(set)) sets.set(set, []);
    sets.get(set).push(it);
  }
  const setRows = [...sets.entries()]
    .filter(([, pieces]) => pieces.length >= 2)
    .sort((a, b) => {
      const ta = Math.min(...a[1].map(tierOf));
      const tb = Math.min(...b[1].map(tierOf));
      return ta - tb || a[0].localeCompare(b[0]);
    });
  const setTable = setRows.length
    ? `<table class="gear-table"><thead><tr><th>Set</th><th>Unlocks at</th><th>Armor</th><th>HP</th><th>MR</th><th>How to get it</th></tr></thead><tbody>${setRows
        .map(([name, pieces]) => {
          const src = pieces
            .map((p) => sourceSummary(itemSources.get(p.slug)))
            .find((s) => s && s !== "—") || "—";
          return `<tr><td>${esc(name)}</td><td>${Math.min(...pieces.map(tierOf))}</td><td>${pieces.reduce((s, p) => s + modVal(p, "armor"), 0)}</td><td>${pieces.reduce((s, p) => s + modVal(p, "health_max"), 0)}</td><td>${pieces.reduce((s, p) => s + modVal(p, "mr"), 0)}</td><td>${src}</td></tr>`;
        })
        .join("")}</tbody></table>`
    : "";

  const sections = bands
    .map(([lo, hi, label]) => {
      const inBand = wearable
        .filter((it) => tierOf(it) >= lo && tierOf(it) <= hi)
        .sort((a, b) => tierOf(a) - tierOf(b) || a.name.localeCompare(b.name));
      if (!inBand.length) return "";
      const weapons = inBand.filter((it) => it.kind === "Weapon");
      const armour = inBand.filter((it) => it.kind === "Armor");
      return `<h2>${esc(label)}</h2>
        ${weapons.length ? `<h3>Weapons</h3>${weaponTable(weapons)}` : ""}
        ${armour.length ? `<h3>Armour</h3>${armourTable(armour)}` : ""}`;
    })
    .join("");

  return shell({
    title: "Gear path — Arkenelle Wiki",
    active: "start",
    theme: "start",
    body: `<main class="wrap">
      ${crumb([
        { href: "/wiki/", label: "Wiki" },
        { href: "/wiki/getting-started/", label: "Getting started" },
        { label: "Gear path" },
      ])}
      <article class="page prose">
        ${pageHeading("start", "Gear path")}
        <p>Every weapon and armour piece is gated by <strong>Weapon Mastery</strong>, not by character level. Mastery is earned by killing things with a weapon of that class.</p>
        <ul>
          <li><strong>Unique weapons</strong> come from Charter climaxes. The quest giver sends you into a private fight; turn-in grants one unique matching the style in your hand. Later Unbound pads (Sand King, Cinderborn), Unleashed Golem, and the Ossuary Necromancer are the farm for other styles, armour mats, and relics.</li>
          <li><strong>Armour</strong> is smithing and later bossing. Bronze through Runite are forged. Plate is meant to cover a missed mechanic or two, not ten. Mitigation is <code>damage × 100 / (100 + armour)</code>.</li>
          <li><strong>Smithable metal weapons</strong> exist on the anvil, but they lose to the unique of that chapter. Proof of the Hammer is a bronze armour craft, not a bronze blade.</li>
          <li><strong>Armour</strong> requires <em>any</em> mastery at that level, so your best-trained weapon carries what you can wear. Weapons require mastery in their own class.</li>
        </ul>
        ${uniqueLadder ? `<h2>Charter unique weapons</h2><p>You never fight a boss with the weapon it grants. The blade lands on turn-in; you take it into the next fight. Story fights are private rooms from the quest giver — the shared Unbound pad is the farm.</p>${uniqueLadder}` : ""}
        ${setTable ? `<h2>Armour sets</h2><p>Totals are helm + chest + boots (and any other pieces in the set). Naked Heroes start around 15 armour.</p>${setTable}` : ""}
        <h2>Every piece</h2>
        <p class="muted">Generated from the game files, so stats and sources match the live build. Click any item for the full source list.</p>
        ${sections}
      </article>
    </main>`,
  });
}

function questCard(q) {
  const bits = [];
  if (q.styleWeapons.length) bits.push("Unique weapon");
  if (q.masteryXp) bits.push(`${q.masteryXp.toLocaleString()} mastery XP`);
  else if (q.xp) bits.push(`${q.xp} XP`);
  if (q.givers.length) bits.push(q.givers.map((g) => g.name).join(", "));
  return `<a class="item-card cat-quests" href="${questHref(q)}"><span><span class="name">${esc(q.name)}</span><span class="kind">${esc(bits.join(" · ") || "Quest")}</span></span></a>`;
}

function questListHtml(list) {
  return `<div class="item-grid">${list.map(questCard).join("")}</div>`;
}

function questPageHtml(q, items, creatures, npcs) {
  const stats = [
    q.givers.length ? ["Offered by", q.givers.map((g) => `<a class="cat-npcs" href="/wiki/npcs/${g.slug}/">${esc(g.name)}</a>`).join(", ")] : null,
    q.campaignMeta ? ["Campaign", `<a href="${campaignHref(q.campaign)}">${esc(q.campaignMeta.name)}</a>`] : null,
    q.minLevel ? ["Requires level", String(q.minLevel)] : null,
    q.minSkill ? ["Requires skill", esc(skillLabel(q.minSkill, q.minSkillLevel))] : null,
    q.prereqs.length
      ? [
          q.requiresAny ? "Requires any of" : "Requires",
          q.prereqs.map((p) => `<a href="${questHref(p)}">${esc(p.name)}</a>`).join(", "),
        ]
      : null,
    q.masteryXp ? ["Mastery XP", q.masteryXp.toLocaleString()] : null,
    q.xp ? ["Adventure XP", String(q.xp)] : null,
    q.gold ? ["Gold", String(q.gold)] : null,
    q.title ? ["Title", esc(q.title)] : null,
    q.wardstone ? ["Wardstone", esc(q.wardstone.replace(/_/g, " "))] : null,
    q.autoComplete ? ["Turn-in", "Completes when the last objective is met"] : null,
  ].filter(Boolean);

  const objHead = q.completionAny ? "Complete any one" : "Objectives";
  const objectives = q.objectives.length
    ? `<h2>${objHead}</h2><ul>${q.objectives.map((o) => `<li>${describeObjective(o, items, creatures, npcs)}</li>`).join("")}</ul>`
    : "";

  const rewardLis = [];
  if (q.styleWeapons.length) {
    rewardLis.push(
      `<li><strong>One unique of your equipped style:</strong> ${q.styleWeapons.map((p) => itemHrefLabel(items, p)).join(", ")}</li>`
    );
  }
  for (const r of q.rewardItems) {
    rewardLis.push(`<li>${itemHrefLabel(items, r.itemPath)}${r.amount > 1 ? ` ×${r.amount}` : ""}</li>`);
  }
  if (q.grantOnAccept) {
    rewardLis.push(`<li>${itemHrefLabel(items, q.grantOnAccept)} <span class="muted">(on accept)</span></li>`);
  }
  const rewards = rewardLis.length ? `<h2>Rewards</h2><ul>${rewardLis.join("")}</ul>` : "";

  const next = q.unlocks.length
    ? `<h2>Unlocks</h2><ul>${q.unlocks
        .sort((a, b) => a.depth - b.depth || a.name.localeCompare(b.name))
        .map((n) => `<li><a href="${questHref(n)}">${esc(n.name)}</a></li>`)
        .join("")}</ul>`
    : "";

  return `<main class="wrap"><article class="page prose">
          ${crumb([
            { href: "/wiki/", label: "Wiki" },
            { href: "/wiki/quests/", label: "Quests" },
            ...(q.campaignMeta
              ? [{ href: campaignHref(q.campaign), label: q.campaignMeta.name }]
              : []),
            { label: q.name },
          ])}
          <h1 class="section-title">${esc(q.name)}</h1>
          ${q.styleWeapons.length ? `<span class="tag">Unique weapon</span>` : ""}
          ${q.description ? `<p>${esc(q.description)}</p>` : ""}
          ${stats.length ? `<div class="stats">${stats.map(([k, v]) => `<div><span>${esc(k)}</span><span>${v}</span></div>`).join("")}</div>` : ""}
          ${objectives}
          ${rewards}
          ${next}
        </article></main>`;
}

function campaignPageHtml(id, quests, items) {
  const meta = CAMPAIGN[id];
  const list = quests
    .filter((q) => q.campaign === id)
    .sort((a, b) => a.depth - b.depth || a.name.localeCompare(b.name));
  const climaxes = list.filter((q) => q.styleWeapons.length);
  return shell({
    title: `${meta.name} — Arkenelle Wiki`,
    active: "wiki",
    theme: "quests",
    body: `<main class="wrap">
      ${crumb([
        { href: "/wiki/", label: "Wiki" },
        { href: "/wiki/quests/", label: "Quests" },
        { label: meta.name },
      ])}
      <article class="page prose">
        ${pageHeading("quests", meta.name)}
        <p>${esc(meta.blurb)}</p>
        ${
          climaxes.length
            ? `<h2>Unique weapons</h2><ul>${climaxes
                .map(
                  (q) =>
                    `<li><a href="${questHref(q)}">${esc(q.name)}</a> — ${q.styleWeapons
                      .map((p) => itemHrefLabel(items, p))
                      .join(", ")}</li>`
                )
                .join("")}</ul>`
            : ""
        }
        <h2>In order</h2>
        ${questListHtml(list)}
      </article>
    </main>`,
  });
}

function itemByPath(items, itemPath) {
  if (!itemPath) return null;
  const base = basenameSlug(itemPath);
  return items.find((it) => it.file.replace(/\\/g, "/").endsWith("/" + path.basename(itemPath.replace(/\\/g, "/"))))
    || items.find((it) => it.slug === slugify(base) || it.slug === base);
}

function creatureRole(c) {
  return c.boss ? "boss" : "enemy";
}

function creatureCard(c, extra = []) {
  const role = creatureRole(c);
  const kind = [c.boss ? "Boss" : "Enemy", c.level ? "Lv " + c.level : "", ...extra].filter(Boolean).join(" · ");
  return `<a class="item-card cat-${role}" data-kind="${c.boss ? "Boss" : "Enemy"}" href="/wiki/creatures/${c.slug}/"><span><span class="name">${esc(c.name)}</span><span class="kind">${esc(kind)}</span></span></a>`;
}

function creatureLink(c) {
  return `<a class="cat-${creatureRole(c)}" href="/wiki/creatures/${c.slug}/">${esc(c.name)}</a>`;
}

function lootList(drops, items) {
  if (!drops.length) return "<p class='muted'>No authored drops.</p>";
  return `<ul class="list-reset">${drops
    .map((d) => {
      const item = itemByPath(items, d.itemPath);
      const label = item ? `<a class="cat-items" href="/wiki/items/${item.slug}/">${esc(item.name)}</a>` : esc(basenameSlug(d.itemPath).replace(/_/g, " "));
      return `<li>${label}${esc(fmtAmt(d.min, d.max))} — ${esc(fmtChance(d.chance))}</li>`;
    })
    .join("")}</ul>`;
}

function fileKey(p) {
  return path.basename(String(p || "").replace(/\\/g, "/")).replace(/\.tres$/i, "").replace(/\.item$/, "");
}

function fmtGold(n) {
  return Math.round(n).toLocaleString("en-US");
}

function fmtAmtCell(min, max) {
  if (min === max) return String(min);
  return `${min}–${max}`;
}

function itemLink(items, itemPath) {
  const item = itemByPath(items, itemPath);
  return item
    ? `<a class="cat-items" href="/wiki/items/${item.slug}/">${esc(item.name)}</a>`
    : esc(basenameSlug(itemPath).replace(/_/g, " "));
}

function withShares(drops) {
  const total = drops.reduce((s, d) => s + (d.chance || 0), 0) || 1;
  return drops.map((d) => ({ ...d, share: d.chance / total }));
}

function lootTableHtml(drops, items, rateMode) {
  if (!drops.length) return "";
  const rows = rateMode === "weight" ? withShares(drops) : drops;
  const rateHead = rateMode === "weight" ? "Pool share" : "Chance";
  return `<table class="loot-table"><thead><tr><th>Item</th><th>Amount</th><th>${rateHead}</th></tr></thead><tbody>${rows
    .map((d) => {
      const rate = rateMode === "weight" ? fmtChance(d.share) : fmtChance(d.chance);
      return `<tr><td>${itemLink(items, d.itemPath)}</td><td>${esc(fmtAmtCell(d.min, d.max))}</td><td>${esc(rate)}</td></tr>`;
    })
    .join("")}</tbody></table>`;
}

function chestContentsHtml(table, items) {
  if (!table) return `<p class="muted">No loot table linked.</p>`;
  const rolls = table.rollsMin === table.rollsMax ? String(table.rollsMin) : `${table.rollsMin}–${table.rollsMax}`;
  const gold = table.goldMax > 0 ? ` plus ${fmtGold(table.goldMin)}–${fmtGold(table.goldMax)} gold` : "";
  let html = `<p class="loot-note">Each open grants <strong>${esc(rolls)}</strong> items from this table (weighted picks, no duplicates)${gold}.</p>`;
  html += lootTableHtml(table.loot, items, "weight");
  if (table.exclusive.length) {
    html += `<h2>Rare extras</h2><p class="loot-note">Independent rolls after the main table. At most ${table.exclusiveMax} of these per open.</p>`;
    html += lootTableHtml(table.exclusive, items, "chance");
  }
  return html;
}

function sourcesHtml(sources) {
  if (!sources.length) return `<p class="muted">No authored drop sources.</p>`;
  return `<ul class="source-list">${sources
    .map((s) => `<li><span>${s.label}</span><span class="src-note">${esc(s.note)}</span></li>`)
    .join("")}</ul>`;
}

function ornateNote(c) {
  const bits = [];
  if (c.ornateTopMax > 0) {
    bits.push(c.ornateTopMin === c.ornateTopMax ? `Top DPS ×${c.ornateTopMax}` : `Top DPS ×${c.ornateTopMin}–${c.ornateTopMax}`);
  }
  if (c.ornateSecondMax > 0) {
    bits.push(c.ornateSecondMin === c.ornateSecondMax ? `#2 DPS ×${c.ornateSecondMax}` : `#2 DPS ×${c.ornateSecondMin}–${c.ornateSecondMax}`);
  }
  if (c.ornateConsolation > 0) bits.push(`others ${fmtChance(c.ornateConsolation)}`);
  return bits.join(", ") || "Boss chest grant";
}

function collectChestTables() {
  const dir = path.join(ROOT, "source/common/gameplay/combat/chests");
  const tables = new Map();
  for (const file of walk(dir).filter((f) => f.endsWith(".tres"))) {
    let doc;
    try {
      doc = parseTres(read(file));
    } catch {
      continue;
    }
    if (doc.header.script_class && doc.header.script_class !== "ChestResource") continue;
    const slug = basenameSlug(file);
    tables.set(slug, {
      slug,
      name: str(doc.resource.display_name) || slug,
      tier: num(doc.resource.tier, 1),
      goldMin: num(doc.resource.gold_min),
      goldMax: num(doc.resource.gold_max),
      rollsMin: num(doc.resource.rolls_min, 1),
      rollsMax: num(doc.resource.rolls_max, 3),
      exclusiveMax: num(doc.resource.exclusive_max, 1),
      loot: dropsFrom(doc, doc.resource.loot),
      exclusive: dropsFrom(doc, doc.resource.exclusive_loot),
    });
  }
  return tables;
}

function collectShops() {
  const dir = path.join(ROOT, "source/common/gameplay/shops/resources");
  const rows = [];
  for (const file of walk(dir).filter((f) => f.endsWith(".tres"))) {
    let doc;
    try {
      doc = parseTres(read(file));
    } catch {
      continue;
    }
    if (doc.header.script_class && doc.header.script_class !== "ShopResource") continue;
    const entries = [];
    for (const ref of asArray(doc.resource.entries)) {
      const sub = resolveSub(doc, ref);
      if (!sub) continue;
      const itemPath = resolveExt(doc, sub.props.item);
      if (!itemPath) continue;
      entries.push({ itemPath, price: num(sub.props.price) });
    }
    rows.push({
      name: str(doc.resource.shop_name) || basenameSlug(file),
      currencyPath: resolveExt(doc, doc.resource.currency_item),
      entries,
    });
  }
  return rows;
}

function parseRewardFile(resPath) {
  const abs = resToFs(resPath);
  if (!abs || !fs.existsSync(abs)) return null;
  let doc;
  try {
    doc = parseTres(read(abs));
  } catch {
    return null;
  }
  return {
    loot: dropsFrom(doc, doc.resource.loot),
    exclusive: dropsFrom(doc, doc.resource.exclusive_loot),
  };
}

const DEFAULT_ORNATE_CHEST = "res://source/common/gameplay/items/chests/gold_pink_large.tres";

function attachItemWiki(items, creatures, zones, shops, chestTables, stations, quests) {
  const byKey = new Map();
  for (const it of items) {
    if (it.kind === "Chest") it.table = chestTables.get(it.chestSlug || basenameSlug(it.file)) || null;
    it.sources = [];
    byKey.set(fileKey(it.file), it);
  }

  function addSource(itemPath, source) {
    const it = byKey.get(fileKey(itemPath));
    if (it) it.sources.push(source);
  }

  for (const c of creatures) {
    for (const d of c.loot) {
      addSource(d.itemPath, {
        label: creatureLink(c),
        note: `${fmtChance(d.chance)}${fmtAmt(d.min, d.max)} on kill`,
      });
    }
    if (c.ornateTopMax > 0) {
      addSource(c.ornateItem || DEFAULT_ORNATE_CHEST, {
        label: creatureLink(c),
        note: ornateNote(c),
      });
    }
  }

  for (const z of zones) {
    for (const d of z.zoneKillLoot || []) {
      addSource(d.itemPath, {
        label: `<a class="cat-locations" href="/wiki/locations/${z.slug}/">${esc(z.name)}</a>`,
        note: `${fmtChance(d.chance)}${fmtAmt(d.min, d.max)} on any kill in this zone`,
      });
    }
    for (const [diff, resPath] of [
      ["Normal", z.rewardPath],
      ["Hard", z.hardRewardPath],
    ]) {
      if (!resPath) continue;
      const reward = parseRewardFile(resPath);
      if (!reward) continue;
      for (const d of [...reward.loot, ...reward.exclusive]) {
        addSource(d.itemPath, {
          label: `<a class="cat-locations" href="/wiki/locations/${z.slug}/">${esc(z.name)}</a>`,
          note: `${diff} completion · ${fmtChance(d.chance)}${fmtAmt(d.min, d.max)}`,
        });
      }
    }
  }

  for (const shop of shops) {
    const currency = byKey.get(fileKey(shop.currencyPath));
    const curName = currency ? currency.name : "Gold";
    for (const e of shop.entries) {
      addSource(e.itemPath, {
        label: esc(shop.name),
        note: e.price ? `${e.price} ${curName}` : "Sold",
      });
    }
  }

  for (const chest of items) {
    if (!chest.table) continue;
    const weighted = withShares(chest.table.loot);
    for (const d of weighted) {
      addSource(d.itemPath, {
        label: `<a class="cat-items" href="/wiki/items/${chest.slug}/">${esc(chest.name)}</a>`,
        note: `Chest table · ${fmtChance(d.share)}${fmtAmt(d.min, d.max)}`,
      });
    }
    for (const d of chest.table.exclusive) {
      addSource(d.itemPath, {
        label: `<a class="cat-items" href="/wiki/items/${chest.slug}/">${esc(chest.name)}</a>`,
        note: `Chest rare · ${fmtChance(d.chance)}${fmtAmt(d.min, d.max)}`,
      });
    }
  }

  for (const st of stations || []) {
    for (const r of st.recipes) {
      addSource(r.itemPath, {
        label: esc(st.name),
        note: r.level ? `Craft · ${st.profession} ${r.level}` : "Crafted",
      });
    }
  }
  for (const q of quests || []) {
    for (const r of q.rewardItems || []) {
      addSource(r.itemPath, {
        label: `<a class="cat-quests" href="${questHref(q)}">${esc(q.name)}</a>`,
        note: r.amount > 1 ? `Quest reward ×${r.amount}` : "Quest reward",
      });
    }
    for (const itemPath of q.styleWeapons || []) {
      addSource(itemPath, {
        label: `<a class="cat-quests" href="${questHref(q)}">${esc(q.name)}</a>`,
        note: "Unique of your equipped style",
      });
    }
  }
}

function listPage(title, intro, cardsHtml, active, cat) {
  return shell({
    title: `${title} — Arkenelle Wiki`,
    active,
    theme: cat,
    body: `<main class="wrap">
      ${crumb([{ href: "/wiki/", label: "Wiki" }, { label: title }])}
      ${pageHeading(cat, title)}
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
  attachStoryBosses(npcs, creatures);
  const jobs = collectJobs();
  const slayer = collectSlayer();
  const quests = collectQuests();
  attachQuestGraph(quests, npcs);
  const shops = collectShops();
  const stations = collectStations();
  const chestTables = collectChestTables();
  attachItemWiki(items, creatures, zones, shops, chestTables, stations, quests);
  const itemSources = buildItemSources(
    items,
    creatures,
    shops,
    stations,
    [...chestTables.values()].map((t) => ({
      name: t.name,
      tier: t.tier,
      drops: [...t.loot, ...t.exclusive],
    })),
    quests
  );

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
            <div class="cta-pair">
              <div class="cta-fx play">
                <span class="cta-sparkle s1" aria-hidden="true"></span>
                <span class="cta-sparkle s2" aria-hidden="true"></span>
                <span class="cta-sparkle s3" aria-hidden="true"></span>
                <a class="btn play" href="${PLAY_WEB}"><span class="cta-shine" aria-hidden="true"></span>Play in your browser</a>
              </div>
              <div class="cta-fx desk">
                <span class="cta-sparkle s1" aria-hidden="true"></span>
                <span class="cta-sparkle s2" aria-hidden="true"></span>
                <span class="cta-sparkle s3" aria-hidden="true"></span>
                <a class="btn desk" href="${PLAY_DESKTOP}"><span class="cta-shine" aria-hidden="true"></span>Desktop client</a>
              </div>
            </div>
            <p class="cta-note">No download for the browser client. Desktop zip updates itself.</p>
            <div class="cta-row">
              <a class="btn" href="${DISCORD}">Discord</a>
              <a class="btn" href="/wiki/">Wiki</a>
              <a class="btn" href="/leaderboards/">Leaderboards</a>
              <a class="btn" href="/donate/">Donate</a>
            </div>
          </div>
        </div>
      </section>
      <main class="wrap">
        <div class="grid-3">
          <article class="card wiki-card cat-play">
            ${catIcon("play")}
            <div>
            <h2>Play</h2>
            <p><a class="cat-play" href="${PLAY_WEB}">Play in the browser</a> at play.arkenelle.com — first load is a large download. For weather and a smoother client, <a class="cat-play" href="${PLAY_DESKTOP}">download the Windows app</a> (extract the zip, run Arkenelle.exe; it updates itself). itch.io remains an optional backup.</p>
            </div>
          </article>
          <article class="card wiki-card cat-start">
            ${catIcon("start")}
            <div>
            <h2>Where to start</h2>
            <p>The Charter Clerk seals your papers. Then the Hall Keeper in Castle Garden starts <strong>Blood in the Meadow</strong> — orientation, not a class lock. Every Hero can train every weapon and every profession.</p>
            <p><a class="cat-start" href="/wiki/getting-started/">Getting started →</a></p>
            </div>
          </article>
          <article class="card wiki-card cat-guilds">
            ${catIcon("guilds")}
            <div>
            <h2>Guilds</h2>
            <p>Join or found a guild, capture a territory banner, and earn Glory for as long as you hold it. See Guild in-game, or the <a class="cat-boards" href="/leaderboards/">live leaderboards</a>.</p>
            <p><a class="cat-guilds" href="/wiki/guilds/">Guilds &amp; territory →</a></p>
            </div>
          </article>
        </div>
      </main>`,
    })
  );

  write(
    "donate/index.html",
    shell({
      title: "Donate — Arkenelle",
      active: "donate",
      theme: "donate",
      body: `<main class="wrap">
        <article class="page prose donate-page">
          ${pageHeading("donate", "Support Arkenelle")}
          <p>Donations help pay for servers and keep development going. This is not MTX — a gift does not buy in-game items, gold, or power.</p>
          <div class="donate-thanks">
            <h2>A title as thanks</h2>
            <p>Arkenelle grants a matching title as a thank-you. It shows under your name on your profile and beside your name in chat. After you donate, send your <strong>character name</strong> in <a href="${DISCORD}">Discord</a> and we will put it on.</p>
            <p class="donate-title-samples" aria-hidden="true"><span class="c-sapphire">— Sapphire VIP —</span><span class="c-emerald">— Emerald Supporter —</span><span class="c-ruby">— Ruby VIP —</span><span class="c-custom">— Arkenelle Supporter —</span></p>
          </div>
          <h2>Give once</h2>
          <div class="donate-grid">
            ${donateCard({
              img: "onetime-sapphire.png",
              name: "Sapphire Supporter",
              price: "$5",
              blurb: "A one-time donation to help fund Arkenelle. Thank you for backing the project.",
              href: STRIPE.sapphireOnce,
              gem: "sapphire",
            })}
            ${donateCard({
              img: "onetime-emerald.png",
              name: "Emerald Supporter",
              price: "$10",
              blurb: "A larger one-time gift for servers and development. Thank you for helping keep Arkenelle independent.",
              href: STRIPE.emeraldOnce,
              gem: "emerald",
            })}
            ${donateCard({
              img: "onetime-ruby.png",
              name: "Ruby Supporter",
              price: "$25",
              blurb: "The highest one-time donation. Ruby funds the long stretch of alpha still ahead. Thank you.",
              href: STRIPE.rubyOnce,
              gem: "ruby",
            })}
            ${donateCard({
              img: "onetime-custom.png",
              name: "Choose your amount",
              price: "Any",
              blurb: "Pay what you can. This is a one-time donation — you choose the amount.",
              href: STRIPE.custom,
              gem: "custom",
            })}
          </div>
          <h2>Monthly VIP</h2>
          <p class="muted">Billed each month through Stripe. Cancel anytime from the receipt Stripe emails you.</p>
          <div class="donate-grid donate-grid-3">
            ${donateCard({
              img: "vip-sapphire.png",
              name: "Sapphire VIP",
              price: "$5 / month",
              blurb: "Help keep Arkenelle in development. Thank you for a monthly back.",
              href: STRIPE.sapphireVip,
              gem: "sapphire",
            })}
            ${donateCard({
              img: "vip-emerald.png",
              name: "Emerald VIP",
              price: "$10 / month",
              blurb: "A stronger monthly gift for servers and the work still ahead.",
              href: STRIPE.emeraldVip,
              gem: "emerald",
            })}
            ${donateCard({
              img: "vip-ruby.png",
              name: "Ruby VIP",
              price: "$25 / month",
              blurb: "The highest monthly tier. Ruby funds the long stretch of alpha still ahead.",
              href: STRIPE.rubyVip,
              gem: "ruby",
            })}
          </div>
          <p class="donate-foot">Choose-your-amount gifts receive the gold <strong>Arkenelle Supporter</strong> title. One-time and VIP gifts use the matching Sapphire, Emerald, or Ruby title.</p>
        </article>
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
          ${wikiCard("start", "/wiki/getting-started/", "Getting started", "Charter Seal, Blood in the Meadow, and how progression actually works.")}
          ${wikiCard("quests", "/wiki/quests/hollow-seep/", "The Hollow Seep", "The Charter campaign in order, with unique weapons at each climax.")}
          ${wikiCard("start", "/wiki/getting-started/gear/", "Gear path", "Charter unique weapons, armour set totals, and where every piece comes from.")}
          ${wikiCard("items", "/wiki/items/", "Items", `<strong>${items.length}</strong> weapons, armor, materials, potions, and more.`)}
          ${wikiCard("creatures", "/wiki/creatures/", "Creatures", `<strong>${creatures.length}</strong> enemies and bosses with authored loot.`)}
          ${wikiCard("locations", "/wiki/locations/", "Locations", `<strong>${zones.length}</strong> zones and dungeons.`)}
          ${wikiCard("npcs", "/wiki/npcs/", "NPCs", `<strong>${npcs.length}</strong> friendly faces.`)}
          ${wikiCard("skills", "/wiki/skills/", "Skills", `<strong>${jobs.length}</strong> gathering and crafting professions.`)}
          ${wikiCard("slayer", "/wiki/slayer/", "Slayer", "Masters, task pools, and creature assignments.")}
          ${wikiCard("quests", "/wiki/quests/", "Quests", `The Hollow Seep campaign and <strong>${quests.length}</strong> authored quests.`)}
          ${wikiCard("guilds", "/wiki/guilds/", "Guilds", "Territory, banners, and Glory.")}
          ${wikiCard("boards", "/leaderboards/", "Leaderboards", "Live ranks from the running world.")}
        </div>
      </main>`,
    })
  );

  write(
    "leaderboards/index.html",
    shell({
      title: "Leaderboards — Arkenelle",
      active: "boards",
      theme: "boards",
      scripts: ["/leaderboards.js"],
      body: `<main class="wrap" data-leaderboards>
        <div class="lb-head">
          ${pageHeading("boards", "Leaderboards")}
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
      theme: "start",
      body: `<main class="wrap">
        ${crumb([{ href: "/wiki/", label: "Wiki" }, { label: "Getting started" }])}
        <article class="page prose">
          ${pageHeading("start", "Getting started")}
          <h2>Play</h2>
          <ol>
            <li><strong>Browser:</strong> open <a href="${PLAY_WEB}">play.arkenelle.com</a>. First load downloads the whole client; later visits reuse the cache. This is the lighter build (no weather).</li>
            <li><strong>Desktop (recommended):</strong> <a href="${PLAY_DESKTOP}">download the Windows zip</a>, extract it somewhere stable (not Desktop or OneDrive), and run <code>Arkenelle.exe</code>. Later launches update themselves. The <a href="${ITCH_APP}">itch.io app</a> is an optional backup.</li>
          </ol>
          <h2>First steps</h2>
          <p>You wake at Charter Intake. The <strong>Charter Clerk</strong> has <strong>The Charter Seal</strong> — speak with the Hall Keeper in the chamber beyond. Leave the Daily Quest Board alone until that introduction is done.</p>
          <p>The Hall Keeper starts <strong>Blood in the Meadow</strong>: equip a weapon from your kit, open Mastery, and clear twenty goblin runts. Then find <strong>Warden Bren</strong> at the woodland gate. When the Chief kill is active, Bren has <strong>Send me to the fight</strong> — a private solo room, not the shared warren pad. Bone from that kill is your first real weapon — smithing will not match it.</p>
          <p><strong>Find Your Footing</strong> is an optional errand to the Foreman after Blood in the Meadow. It is not the start of the campaign. Arkenelle does not lock you into a weapon or profession.</p>
          <h2>Progression</h2>
          <ul>
            <li>Character level is derived from your five weapon masteries. Quest XP fills a bar; mastery XP is what actually moves you.</li>
            <li>The weapon you wield gains its own Mastery experience.</li>
            <li>Professions (Mining, Woodcutting, Smithing, and the rest) each have their own 1–99 track. Smithing makes armour.</li>
            <li>Training one path never closes another.</li>
          </ul>
          <h2>Weapons and armour</h2>
          <p>Each Charter climax grants a unique weapon of the style in your hand, on turn-in. The quest giver sends you into a private fight. Early biome pads (Chief, Heart, Captain, Sovereign) are the original fights; Unbound Sand King / Cinderborn, Unleashed Golem, and the Ossuary Necromancer are the farm. The Necromancer holds <a class="cat-locations" href="/wiki/locations/ossuary/">The Ossuary</a> off the Sewers — Wyrmguard, Astral, and Nightglass drop there. Plate is forged — bronze through runite on the anvil, later kits from bossing — and it is meant to cover a missed mechanic or two, not trivialise a fight.</p>
          <p><a class="cat-start" href="/wiki/getting-started/gear/"><strong>Read the gear path →</strong></a> — unique ladder, armour set totals, and every piece.</p>
          <p><a class="cat-quests" href="/wiki/quests/hollow-seep/"><strong>The Hollow Seep →</strong></a> — the Charter campaign in order.</p>
          <h2>While it is alpha</h2>
          <p>Expect rough edges. Patch notes land in your Mailbox. Type <code>/players</code> to see who is online, and <code>/feedback</code> to send a bug or idea. <a href="${DISCORD}">Discord</a> is the other door.</p>
        </article>
      </main>`,
    })
  );

  write("wiki/getting-started/gear/index.html", gearPathPage(items, itemSources, quests));

  write(
    "wiki/guilds/index.html",
    shell({
      title: "Guilds — Arkenelle Wiki",
      active: "wiki",
      theme: "guilds",
      body: `<main class="wrap">
        ${crumb([{ href: "/wiki/", label: "Wiki" }, { label: "Guilds" }])}
        <article class="page prose">
          ${pageHeading("guilds", "Guilds and territory")}
          <p>Join or found a guild, then take a territory by capturing its banner. Your guild earns Glory for as long as it holds that ground. The <a class="cat-boards" href="/leaderboards/">live leaderboards</a> show seasonal and eternal Glory, and the in-game Guild menu is the rest of the view.</p>
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
      theme: "items",
      body: `<main class="wrap">
      ${crumb([{ href: "/wiki/", label: "Wiki" }, { label: "Items" }])}
      ${pageHeading("items", "Items")}
      <p class="muted">${items.length} items pulled from game resources.</p>
      <div class="filters" data-filters>
        <button type="button" class="active" data-kind="">All</button>
        ${kinds.map((k) => `<button type="button" data-kind="${esc(k)}">${esc(k)}</button>`).join("")}
      </div>
      <div class="item-grid">${items
        .map(
          (it) =>
            `<a class="item-card cat-items" data-kind="${esc(it.kind)}" href="/wiki/items/${it.slug}/"><span class="icon-frame">${iconHtml(it.icon)}</span><span><span class="name">${esc(it.name)}</span><span class="kind">${esc(it.kind)}</span></span></a>`
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
    if (it.table) {
      stats.push(["Tier", String(it.table.tier)]);
      if (it.table.goldMax) stats.push(["Gold", `${fmtGold(it.table.goldMin)}–${fmtGold(it.table.goldMax)}`]);
      stats.push(["Item rolls", it.table.rollsMin === it.table.rollsMax ? String(it.table.rollsMin) : `${it.table.rollsMin}–${it.table.rollsMax}`]);
    }
    const inside = it.kind === "Chest" ? `<h2>Inside</h2>${chestContentsHtml(it.table, items)}` : "";
    const srcTitle = it.kind === "Chest" ? "Dropped by" : "Sources";
    const sources = it.kind === "Chest" || (it.sources && it.sources.length)
      ? `<h2>${srcTitle}</h2>${sourcesHtml(it.sources || [])}`
      : "";
    write(
      `wiki/items/${it.slug}/index.html`,
      shell({
        title: `${it.name} — Arkenelle Wiki`,
        active: "items",
        theme: "items",
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
          ${inside}
          ${sources}
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
            `<a class="item-card cat-npcs" href="/wiki/npcs/${n.slug}/"><span><span class="name">${esc(n.name)}</span><span class="kind">${esc(n.offers.join(" · ") || "Talk")}</span></span></a>`
        )
        .join(""),
      "npcs",
      "npcs"
    )
  );
  for (const n of npcs) {
    write(
      `wiki/npcs/${n.slug}/index.html`,
      shell({
        title: `${n.name} — Arkenelle Wiki`,
        active: "npcs",
        theme: "npcs",
        body: `<main class="wrap"><article class="page prose">
          ${crumb([{ href: "/wiki/", label: "Wiki" }, { href: "/wiki/npcs/", label: "NPCs" }, { label: n.name }])}
          <h1 class="section-title">${esc(n.name)}</h1>
          ${n.offers.map((o) => `<span class="tag">${esc(o)}</span>`).join("")}
          ${n.greeting ? `<p>${esc(n.greeting)}</p>` : ""}
          ${foundInHtml(n.locations)}
          ${
            n.quests.length
              ? `<h2>Quests</h2><ul>${n.quests
                  .sort((a, b) => a.depth - b.depth || a.name.localeCompare(b.name))
                  .map((q) => `<li><a class="cat-quests" href="${questHref(q)}">${esc(q.name)}</a>${q.styleWeapons.length ? " — unique weapon" : ""}</li>`)
                  .join("")}</ul>`
              : ""
          }
        </article></main>`,
      })
    );
  }

  const bosses = creatures.filter((c) => c.boss);
  const enemies = creatures.filter((c) => !c.boss);
  write(
    "wiki/creatures/index.html",
    shell({
      title: "Creatures — Arkenelle Wiki",
      active: "creatures",
      theme: "creatures",
      body: `<main class="wrap">
      ${crumb([{ href: "/wiki/", label: "Wiki" }, { label: "Creatures" }])}
      ${pageHeading("creatures", "Creatures")}
      <p class="muted">Hostile types. Combat numbers and loot are what the server actually uses.</p>
      <div class="filters" data-filters>
        <button type="button" class="active" data-kind="">All</button>
        <button type="button" data-kind="Boss">Bosses (${bosses.length})</button>
        <button type="button" data-kind="Enemy">Enemies (${enemies.length})</button>
      </div>
      <section data-kind-section="Boss">
        <h2 class="role-heading role-boss">Bosses</h2>
        <div class="item-grid">${bosses.map((c) => creatureCard(c)).join("")}</div>
      </section>
      <section data-kind-section="Enemy">
        <h2 class="role-heading role-enemy">Enemies</h2>
        <div class="item-grid">${enemies.map((c) => creatureCard(c)).join("")}</div>
      </section>
    </main>`,
    })
  );
  for (const c of creatures) {
    const role = creatureRole(c);
    const stats = [
      ["Type", c.type],
      ["Role", c.boss ? "Boss" : "Enemy"],
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
        theme: role,
        body: `<main class="wrap"><article class="page">
          ${crumb([{ href: "/wiki/", label: "Wiki" }, { href: "/wiki/creatures/", label: "Creatures" }, { label: c.name }])}
          ${pageHeading(role, c.name)}
          <p><span class="tag tag-${role}">${c.boss ? "Boss" : "Enemy"}</span></p>
          <div class="stats">${stats.map(([k, v]) => `<div><span>${esc(k)}</span><span>${esc(v)}</span></div>`).join("")}</div>
          ${storyFightHtml(c)}
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
            `<a class="item-card cat-locations" href="/wiki/locations/${z.slug}/"><span><span class="name">${esc(z.name)}</span><span class="kind">${z.isDungeon ? "Dungeon" : "Zone"}</span></span></a>`
        )
        .join(""),
      "locations",
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
    const bg = locationBgUrl(z.slug);
    write(
      `wiki/locations/${z.slug}/index.html`,
      shell({
        title: `${z.name} — Arkenelle Wiki`,
        active: "locations",
        theme: "locations",
        extraClass: bg ? "location-scene" : "",
        body: `${bg ? `<div class="location-scene-bg" style="background-image:url('${bg}')" aria-hidden="true"></div>` : ""}
        <main class="wrap"><article class="page prose">
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
                      ? `<a class="item-card cat-npcs" href="/wiki/npcs/${n.slug}/">${inner}</a>`
                      : `<div class="item-card cat-npcs">${inner}</div>`;
                  })
                  .join("")}</div>`
              : ""
          }
          ${
            z.fauna.length
              ? `<h2>Creatures</h2><div class="item-grid">${z.fauna
                  .map(({ creature: c, count }) => {
                    return creatureCard(c, [count > 1 ? "×" + count : ""]);
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
            `<a class="item-card cat-skills" href="/wiki/skills/${j.slug}/"><span class="icon-frame">${iconHtml(j.icon, 32)}</span><span><span class="name">${esc(j.name)}</span><span class="kind">${esc(j.category)}</span></span></a>`
        )
        .join(""),
      "wiki",
      "skills"
    )
  );
  for (const j of jobs) {
    const sourceRows = j.sources
      .map((p, i) => {
        const item = itemByPath(items, p);
        const lv = j.sourceLevels[i];
        const label = item ? `<a class="cat-items" href="/wiki/items/${item.slug}/">${esc(item.name)}</a>` : esc(basenameSlug(p).replace(/_/g, " "));
        return `<li>${label}${lv != null ? ` — level ${lv}` : ""}</li>`;
      })
      .join("");
    write(
      `wiki/skills/${j.slug}/index.html`,
      shell({
        title: `${j.name} — Arkenelle Wiki`,
        active: "wiki",
        theme: "skills",
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
      theme: "slayer",
      body: `<main class="wrap">
        ${crumb([{ href: "/wiki/", label: "Wiki" }, { label: "Slayer" }])}
        ${pageHeading("slayer", "Slayer")}
        <p class="muted">Masters assign creature tasks. Kill the assigned types to finish the count.</p>
        <h2>Masters</h2>
        <div class="card-grid">${slayer.masters
          .map(
            (m) => `<article class="card wiki-card cat-slayer">${catIcon("slayer")}<div><h3>${esc(m.name)}</h3>
            <p class="muted">${esc(m.location)}${m.min ? ` · Slayer ${m.min}+` : ""}</p>
            ${m.greeting ? `<p>${esc(m.greeting)}</p>` : ""}
            <ul>${m.pool
              .map((p) => {
                const t = taskBySlug[p.task];
                return `<li>${esc(t ? t.name : p.task)} (${p.min}–${p.max})</li>`;
              })
              .join("")}</ul></div></article>`
          )
          .join("")}</div>
        <h2>Task types</h2>
        <div class="card-grid">${slayer.tasks
          .map(
            (t) => `<article class="card wiki-card cat-slayer">${catIcon("slayer")}<div><h3>${esc(t.name)}</h3>
            <p class="muted">${esc(t.location)}${t.min ? ` · Slayer ${t.min}+` : ""} · ${t.xp} XP / kill</p>
            ${t.notes ? `<p>${esc(t.notes)}</p>` : ""}
            <p>${t.enemies
              .map((e) => {
                const c = creatures.find((x) => x.type === e || x.slug === e);
                return c ? creatureLink(c) : esc(e);
              })
              .join(", ")}</p></div></article>`
          )
          .join("")}</div>
      </main>`,
    })
  );

  const campaignOrder = ["hollow_seep", "fungus_cave", "bandit_hideout", "side"];
  const questIndexSections = campaignOrder
    .map((id) => {
      const meta = CAMPAIGN[id];
      const list = quests.filter((q) => q.campaign === id);
      if (!list.length) return "";
      return `<h2><a class="cat-quests" href="${campaignHref(id)}">${esc(meta.name)}</a></h2><p class="muted">${esc(meta.blurb)}</p>${questListHtml(list)}`;
    })
    .join("");
  write(
    "wiki/quests/index.html",
    shell({
      title: "Quests — Arkenelle Wiki",
      active: "wiki",
      theme: "quests",
      body: `<main class="wrap">
        ${crumb([{ href: "/wiki/", label: "Wiki" }, { label: "Quests" }])}
        <article class="page prose">
          ${pageHeading("quests", "Quests")}
          <p>Authored quests (not the rotating daily board). Charter climaxes grant a unique weapon of the style in your hand. Requirements, objectives, and rewards are generated from the game files.</p>
          ${questIndexSections}
        </article>
      </main>`,
    })
  );
  for (const id of campaignOrder) {
    if (quests.some((q) => q.campaign === id)) {
      write(`wiki/quests/${CAMPAIGN[id].slug}/index.html`, campaignPageHtml(id, quests, items));
    }
  }
  for (const q of quests) {
    write(
      `wiki/quests/${q.slug}/index.html`,
      shell({
        title: `${q.name} — Arkenelle Wiki`,
        active: "wiki",
        theme: "quests",
        body: questPageHtml(q, items, creatures, npcs),
      })
    );
  }

  const search = [
    ...items.map((x) => ({ title: x.name, kind: "Item · " + x.kind, href: `/wiki/items/${x.slug}/`, haystack: (x.name + " " + x.kind + " " + x.description).toLowerCase() })),
    ...npcs.map((x) => ({ title: x.name, kind: "NPC", href: `/wiki/npcs/${x.slug}/`, haystack: (x.name + " " + x.greeting + " " + (x.locations || []).map((z) => z.name).join(" ")).toLowerCase() })),
    ...creatures.map((x) => ({ title: x.name, kind: x.boss ? "Boss" : "Enemy", href: `/wiki/creatures/${x.slug}/`, haystack: (x.name + " " + x.type + " " + (x.locations || []).map((z) => z.name).join(" ")).toLowerCase() })),
    ...zones.map((x) => ({ title: x.name, kind: x.isDungeon ? "Dungeon" : "Location", href: `/wiki/locations/${x.slug}/`, haystack: (x.name + " " + x.description).toLowerCase() })),
    ...jobs.map((x) => ({ title: x.name, kind: "Skill", href: `/wiki/skills/${x.slug}/`, haystack: x.name.toLowerCase() })),
    ...quests.map((x) => ({
      title: x.name,
      kind: "Quest",
      href: questHref(x),
      haystack: (
        x.name +
        " " +
        x.description +
        " " +
        (x.campaignMeta?.name || "") +
        " " +
        x.givers.map((g) => g.name).join(" ")
      ).toLowerCase(),
    })),
    ...Object.entries(CAMPAIGN).map(([, meta]) => ({
      title: meta.name,
      kind: "Campaign",
      href: `/wiki/quests/${meta.slug}/`,
      haystack: (meta.name + " " + meta.blurb).toLowerCase(),
    })),
    { title: "Donate", kind: "Support", href: "/donate/", haystack: "donate donation supporter vip sapphire emerald ruby stripe" },
    { title: "Getting started", kind: "Guide", href: "/wiki/getting-started/", haystack: "getting started install hall keeper charter clerk blood in the meadow goblin chief bone" },
    { title: "Gear path", kind: "Guide", href: "/wiki/getting-started/gear/", haystack: "gear path weapon armor armour progression tier mastery unique bone spore sunsteel basilisk bronze iron steel mithril adamant runite how to get" },
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
  copyLocationBgs();
  copyDonateBadges();

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
