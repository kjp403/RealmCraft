import fs from "node:fs";

const p = "website/build.mjs";
let s = fs.readFileSync(p, "utf8");
const re = /<<<<<<< HEAD\n([\s\S]*?)\n=======\n([\s\S]*?)\n>>>>>>> origin\/main/g;
let n = 0;
s = s.replace(re, (_, ours, theirs) => {
  n++;
  const o = ours.trim();
  if (o.includes("Jersey+10")) return ours;
  if (o.startsWith('<a href="/donate/"') && o.includes("Donate")) return ours;
  if (o.includes("function listPage") && (o.includes("attachItemWiki") || o.includes("lootTableHtml") || o.includes("fmtGold"))) {
    const extraStart = theirs.indexOf("function armourSetName");
    const extra = extraStart >= 0 ? theirs.slice(extraStart).replace(/\nfunction listPage[\s\S]*$/, "") : "";
    const oursBody = ours.replace(/\nfunction listPage[\s\S]*$/, "");
    return `${oursBody}\n${extra}`;
  }
  if (o.includes("attachItemWiki")) {
    return `  attachQuestGraph(quests, npcs);
  attachItemWiki(items, creatures, zones, collectShops(), collectChestTables(), quests);
  const shops = collectShops();
  const stations = collectStations();
  const chests = collectChests();
  const itemSources = buildItemSources(items, creatures, shops, stations, chests, quests);`;
  }
  if (o.includes("cta-fx play")) return ours;
  if (o.includes('href="/donate/">Donate')) return ours;
  if (o.includes("wiki-card cat-play")) return ours;
  if (o.includes("Talk to the Hall Keeper in Castle Garden")) {
    return `            <p>The Charter Clerk seals your papers. Then the Hall Keeper in Castle Garden starts <strong>Blood in the Meadow</strong> — orientation, not a class lock. Every Hero can train every weapon and every profession.</p>
            <p><a class="cat-start" href="/wiki/getting-started/">Getting started →</a></p>
            </div>`;
  }
  if (o.includes('wikiCard("start"')) {
    return [
      '          ${wikiCard("start", "/wiki/getting-started/", "Getting started", "Charter Seal, Blood in the Meadow, and how progression actually works.")}',
      '          ${wikiCard("quests", "/wiki/quests/hollow-seep/", "The Hollow Seep", "The Charter campaign in order, with unique weapons at each climax.")}',
      '          ${wikiCard("items", "/wiki/getting-started/gear/", "Gear path", "Charter unique weapons, armour set totals, and where each piece comes from.")}',
      '          ${wikiCard("items", "/wiki/items/", "Items", `<strong>${items.length}</strong> weapons, armor, materials, potions, and more.`)}',
      '          ${wikiCard("creatures", "/wiki/creatures/", "Creatures", `<strong>${creatures.length}</strong> enemies and bosses with authored loot.`)}',
      '          ${wikiCard("locations", "/wiki/locations/", "Locations", `<strong>${zones.length}</strong> zones and dungeons.`)}',
      '          ${wikiCard("npcs", "/wiki/npcs/", "NPCs", `<strong>${npcs.length}</strong> friendly faces.`)}',
      '          ${wikiCard("skills", "/wiki/skills/", "Skills", `<strong>${jobs.length}</strong> gathering and crafting professions.`)}',
      '          ${wikiCard("slayer", "/wiki/slayer/", "Slayer", "Masters, task pools, and creature assignments.")}',
      '          ${wikiCard("quests", "/wiki/quests/", "Quests", `The Hollow Seep campaign and <strong>${quests.length}</strong> authored quests.`)}',
      '          ${wikiCard("guilds", "/wiki/guilds/", "Guilds", "Territory, banners, and Glory.")}',
      '          ${wikiCard("boards", "/leaderboards/", "Leaderboards", "Live ranks from the running world.")}',
    ].join("\n");
  }
  if (o.includes('pageHeading("start"')) return ours;
  if (o.includes('pageHeading("items"')) {
    return [
      '      ${pageHeading("items", "Items")}',
      '      <p class="muted">${items.length} items pulled from game resources. Every item page lists where it comes from — bought, crafted, dropped, quested, or given as a unique of your style.</p>',
      '      <p><a href="/wiki/getting-started/gear/">Read the gear path first</a> if you are not sure what to wear next.</p>',
    ].join("\n");
  }
  if (o.includes("${inside}")) return ours;
  if (o.includes("Authored quests (not the rotating daily board).") && o.includes("listPage")) {
    return [
      '    shell({',
      '      title: "Quests — Arkenelle Wiki",',
      '      active: "wiki",',
      '      theme: "quests",',
      "      body: `<main class=\"wrap\">",
      '        ${crumb([{ href: "/wiki/", label: "Wiki" }, { label: "Quests" }])}',
      '        <article class="page prose">',
      '          ${pageHeading("quests", "Quests")}',
      "          <p>Authored quests (not the rotating daily board). Charter climaxes grant a unique weapon of the style in your hand. Requirements, objectives, and rewards are generated from the game files.</p>",
      "          ${questIndexSections}",
      "        </article>",
      "      </main>`,",
      "    })",
    ].join("\n");
  }
  if (o.includes('theme: "quests"') && o.includes("q.description")) {
    return `        theme: "quests",
        body: questPageHtml(q, items, creatures, npcs),`;
  }
  if (o.includes("kind: \"Support\"") && o.includes("/donate/")) {
    return [
      "    ...quests.map((x) => ({",
      "      title: x.name,",
      '      kind: "Quest",',
      "      href: questHref(x),",
      "      haystack: (",
      "        x.name +",
      '        " " +',
      "        x.description +",
      '        " " +',
      "        (x.campaignMeta?.name || \"\") +",
      '        " " +',
      "        x.givers.map((g) => g.name).join(\" \")",
      "      ).toLowerCase(),",
      "    })),",
      "    ...Object.entries(CAMPAIGN).map(([, meta]) => ({",
      "      title: meta.name,",
      '      kind: "Campaign",',
      "      href: `/wiki/quests/${meta.slug}/`,",
      "      haystack: (meta.name + \" \" + meta.blurb).toLowerCase(),",
      "    })),",
      '    { title: "Donate", kind: "Support", href: "/donate/", haystack: "donate donation supporter vip sapphire emerald ruby stripe" },',
      '    { title: "Getting started", kind: "Guide", href: "/wiki/getting-started/", haystack: "getting started install hall keeper charter clerk blood in the meadow goblin chief bone" },',
      '    { title: "Gear path", kind: "Guide", href: "/wiki/getting-started/gear/", haystack: "gear path weapon armor armour progression tier mastery unique bone spore sunsteel basilisk bronze iron steel mithril adamant runite how to get" },',
    ].join("\n");
  }
  console.error("UNHANDLED CONFLICT", n, o.slice(0, 120).replace(/\n/g, " | "));
  return ours;
});
if (s.includes("<<<<<<<")) {
  console.error("Still has conflict markers");
  process.exit(1);
}
fs.writeFileSync(p, s);
console.log("resolved", n, "conflicts");
