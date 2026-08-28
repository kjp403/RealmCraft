"""Point every ability .tres and every mastery PASSIVE node at its own icon.

Two rewrites, both text-level (never ResourceSaver — a headless save strips uid=
from the file and from every ext_resource in it):

1. Ability .tres: repoint the ext_resource behind `icon =`, or add one when the
   ability had no icon at all (20 of them did not).
2. Tree .tres: passive nodes used to SHARE one texture between four unrelated
   nodes, so each tree's ability_icons ext_resources are dropped and rebuilt, one
   per distinct icon the tree now uses.

New ext_resource lines are written WITHOUT uid=: the uid cache is not loaded
here, so any uid I wrote would be a guess, and path-only ext_resources resolve
fine (the pre-existing aftershock/rampage resources already ship that way).
"""
import io
import json
import os
import re

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ABILITY_DIR = os.path.join(REPO, "source", "common", "gameplay", "combat", "ability",
                           "ability_collection")
TREE_DIR = os.path.join(REPO, "source", "common", "gameplay", "mastery", "trees")
HERE = os.path.dirname(os.path.abspath(__file__))
ICON_RES = "res://assets/sprites/ui/ability_icons/%s"

with open(os.path.join(HERE, "icon_map.json")) as fh:
    ICON_MAP = json.load(fh)

EXT_ICON = re.compile(
    r'^\[ext_resource type="Texture2D"[^\]]*path="res://assets/sprites/ui/ability_icons/'
    r'([^"]+)"[^\]]*id="([^"]+)"\]$', re.M)


def rewrite_ability(path, slug):
    icon = ICON_MAP.get(slug)
    if icon is None:
        return "SKIP (unmapped)"
    s = io.open(path, encoding="utf-8").read()
    m = re.search(r'^icon = ExtResource\("([^"]+)"\)$', s, re.M)
    if m:
        eid = m.group(1)
        line = re.search(r'^\[ext_resource[^\]]*id="%s"\]$' % re.escape(eid), s, re.M)
        new_line = '[ext_resource type="Texture2D" path="%s" id="%s"]' % (ICON_RES % icon, eid)
        s = s[:line.start()] + new_line + s[line.end():]
        action = "repointed"
    else:
        # No icon at all: add the ext_resource after the last existing one, and
        # the `icon =` line right after `name =` so the file keeps its shape.
        eid = "99_icon"
        last = None
        for mm in re.finditer(r'^\[ext_resource[^\]]*\]$', s, re.M):
            last = mm
        new_line = '[ext_resource type="Texture2D" path="%s" id="%s"]' % (ICON_RES % icon, eid)
        if last is None:
            raise SystemExit("no ext_resource block in %s" % path)
        s = s[:last.end()] + "\n" + new_line + s[last.end():]
        mn = re.search(r'^name = ".*"$', s, re.M)
        if mn is None:
            raise SystemExit("no name= in %s" % path)
        s = s[:mn.end()] + '\nicon = ExtResource("%s")' % eid + s[mn.end():]
        action = "added"
    io.open(path, "w", encoding="utf-8", newline="\n").write(s)
    return action


def rewrite_tree(path):
    s = io.open(path, encoding="utf-8").read()
    # Which passive node wants which icon, and does the tree still need any of
    # its old ability_icons ext_resources?
    wanted = {}
    for blk in s.split("[sub_resource")[1:]:
        mid = re.search(r'id = &"([^"]+)"', blk)
        if mid is None or "ability = ExtResource" in blk:
            continue
        icon = ICON_MAP.get(mid.group(1))
        if icon:
            wanted[mid.group(1)] = icon
    if not wanted:
        return "no passives"

    # Fresh ids, one per distinct icon.
    ids = {}
    for i, icon in enumerate(sorted(set(wanted.values()))):
        ids[icon] = "ic%d_%s" % (i, os.path.splitext(icon)[0][:18])

    # Drop the tree's old ability-icon ext_resources, then append the new set
    # after the last remaining ext_resource line.
    s = EXT_ICON.sub("", s)
    s = re.sub(r"\n{3,}", "\n\n", s)
    last = None
    for mm in re.finditer(r'^\[ext_resource[^\]]*\]$', s, re.M):
        last = mm
    block = "".join(
        '\n[ext_resource type="Texture2D" path="%s" id="%s"]' % (ICON_RES % icon, eid)
        for icon, eid in sorted(ids.items()))
    s = s[:last.end()] + block + s[last.end():]

    # Point every passive node at its own icon (adding the line when missing).
    out = []
    for i, blk in enumerate(s.split("[sub_resource")):
        if i == 0:
            out.append(blk)
            continue
        mid = re.search(r'id = &"([^"]+)"', blk)
        if mid and mid.group(1) in wanted:
            eid = ids[wanted[mid.group(1)]]
            if re.search(r'^icon = ExtResource\("[^"]+"\)$', blk, re.M):
                blk = re.sub(r'^icon = ExtResource\("[^"]+"\)$',
                             'icon = ExtResource("%s")' % eid, blk, count=1, flags=re.M)
            else:
                mm = re.search(r'^id = &"[^"]+"$', blk, re.M)
                blk = blk[:mm.end()] + '\nicon = ExtResource("%s")' % eid + blk[mm.end():]
        out.append(blk)
    io.open(path, "w", encoding="utf-8", newline="\n").write("[sub_resource".join(out))
    return "%d passive nodes, %d icons" % (len(wanted), len(ids))


def main():
    done = {"repointed": 0, "added": 0, "SKIP (unmapped)": 0}
    for root, _dirs, files in os.walk(ABILITY_DIR):
        for f in sorted(files):
            if not f.endswith(".tres"):
                continue
            action = rewrite_ability(os.path.join(root, f), f[:-5])
            done[action] = done.get(action, 0) + 1
            if action.startswith("SKIP"):
                print("  UNMAPPED:", f)
    print("abilities:", done)
    for f in sorted(os.listdir(TREE_DIR)):
        if f.endswith(".tres"):
            print("tree %-12s %s" % (f, rewrite_tree(os.path.join(TREE_DIR, f))))


if __name__ == "__main__":
    main()
