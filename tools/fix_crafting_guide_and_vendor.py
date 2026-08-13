#!/usr/bin/env python3
"""Bake Crafting (outfitting) skill-guide recipes from workbenches, and move
misplaced vendor_value/stack_limit off StatModifier sub-resources onto the
GearItem so shops can buy cloth/leather armour."""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
STATIONS = [
    ROOT / "source/common/gameplay/crafting/resources/workbench.tres",
    ROOT / "source/common/gameplay/crafting/resources/ascended_workbench.tres",
]
OUTFITTING = ROOT / "source/common/gameplay/jobs/outfitting.tres"
GEARS_DIR = ROOT / "source/common/gameplay/items/gears"

EXT_RE = re.compile(
    r'\[ext_resource[^\]]*path="([^"]+)"[^\]]*id="([^"]+)"\]'
    r'|\[ext_resource[^\]]*id="([^"]+)"[^\]]*path="([^"]+)"\]'
)
SUB_HEADER_RE = re.compile(r'^\[sub_resource[^\]]*id="([^"]+)"\]', re.M)
OUTPUT_RE = re.compile(r'output_item\s*=\s*ExtResource\("([^"]+)"\)')
LEVEL_RE = re.compile(r"required_level\s*=\s*(\d+)")
RECIPES_RE = re.compile(r"recipes\s*=\s*Array\[[^\]]*\]\(\[(.*?)\]\)", re.S)
SUBREF_RE = re.compile(r'SubResource\("([^"]+)"\)')
ITEM_NAME_RE = re.compile(r'item_name\s*=\s*&?"([^"]+)"')
UID_RE = re.compile(r'^\[gd_resource[^\]]*uid="([^"]+)"', re.M)
VENDOR_LINE_RE = re.compile(r"^vendor_value\s*=\s*(\d+)\s*$", re.M)
STACK_LINE_RE = re.compile(r"^stack_limit\s*=\s*(\d+)\s*$", re.M)
CAN_TRADE_RE = re.compile(r"^can_trade\s*=\s*(true|false)\s*$", re.M)


def _ext_map(text: str) -> dict[str, str]:
    out: dict[str, str] = {}
    for m in EXT_RE.finditer(text):
        if m.group(1) and m.group(2):
            out[m.group(2)] = m.group(1)
        elif m.group(3) and m.group(4):
            out[m.group(3)] = m.group(4)
    return out


def _sub_blocks(text: str) -> dict[str, str]:
    matches = list(SUB_HEADER_RE.finditer(text))
    blocks: dict[str, str] = {}
    for i, m in enumerate(matches):
        start = m.end()
        end = matches[i + 1].start() if i + 1 < len(matches) else text.find("\n[resource]")
        if end < 0:
            end = len(text)
        blocks[m.group(1)] = text[start:end]
    return blocks


def _item_name(path: Path) -> str:
    if not path.exists():
        return path.stem
    text = path.read_text(encoding="utf-8")
    m = ITEM_NAME_RE.search(text)
    if not m:
        return path.stem
    return m.group(1).replace("\\'", "'")


def _item_uid(path: Path) -> str:
    if not path.exists():
        return ""
    m = UID_RE.search(path.read_text(encoding="utf-8"))
    return m.group(1) if m else ""


def collect_recipes() -> list[tuple[str, int, str]]:
    """Return (res_path, min_level, item_name) sorted by level then name."""
    by_path: dict[str, int] = {}
    for station in STATIONS:
        text = station.read_text(encoding="utf-8")
        ext = _ext_map(text)
        blocks = _sub_blocks(text)
        recipes_m = RECIPES_RE.search(text)
        if recipes_m is None:
            raise SystemExit(f"no recipes array in {station}")
        used = SUBREF_RE.findall(recipes_m.group(1))
        for sub_id in used:
            body = blocks.get(sub_id, "")
            out_m = OUTPUT_RE.search(body)
            if out_m is None:
                continue
            res_path = ext.get(out_m.group(1), "")
            if not res_path:
                continue
            lvl_m = LEVEL_RE.search(body)
            level = int(lvl_m.group(1)) if lvl_m else 0
            prev = by_path.get(res_path)
            by_path[res_path] = level if prev is None else min(prev, level)
    rows: list[tuple[str, int, str]] = []
    for res_path, level in by_path.items():
        rel = res_path.replace("res://", "")
        name = _item_name(ROOT / rel)
        rows.append((res_path, level, name))
    rows.sort(key=lambda r: (r[1], r[2].lower()))
    return rows


def bake_outfitting(rows: list[tuple[str, int, str]]) -> None:
    text = OUTFITTING.read_text(encoding="utf-8")
    # Drop old recipe ext_resources (keep script + icon + Item script).
    kept_ext: list[str] = []
    for line in text.splitlines(True):
        if line.startswith("[ext_resource") and 'path="res://source/common/gameplay/items/' in line:
            continue
        kept_ext.append(line)
        if line.startswith("[resource]"):
            break
    header = "".join(kept_ext)
    # header currently includes through [resource]\n — rebuild from original preamble.
    preamble_end = text.find("[resource]")
    preamble = text[:preamble_end]
    preamble_lines = [
        ln
        for ln in preamble.splitlines(True)
        if not (
            ln.startswith("[ext_resource")
            and 'type="Resource"' in ln
            and 'path="res://source/common/gameplay/items/' in ln
        )
    ]
    ext_lines: list[str] = []
    ids: list[str] = []
    for i, (res_path, _level, _name) in enumerate(rows):
        rid = f"r_{i}"
        ids.append(rid)
        rel = res_path.replace("res://", "")
        uid = _item_uid(ROOT / rel)
        if uid:
            ext_lines.append(
                f'[ext_resource type="Resource" uid="{uid}" path="{res_path}" id="{rid}"]\n'
            )
        else:
            ext_lines.append(
                f'[ext_resource type="Resource" path="{res_path}" id="{rid}"]\n'
            )
    resource_body = text[text.find("[resource]") :]
    # Replace recipe_items / recipe_levels; drop deferred if any (none expected).
    item_arr = ", ".join(f'ExtResource("{rid}")' for rid in ids)
    level_arr = ", ".join(str(r[1]) for r in rows)
    resource_body = re.sub(
        r"recipe_items = Array\[ExtResource\(\"[^\"]+\"\)\]\(\[.*?\]\)",
        f'recipe_items = Array[ExtResource("1_u1igm")]([{item_arr}])',
        resource_body,
        count=1,
        flags=re.S,
    )
    resource_body = re.sub(
        r"recipe_levels = Array\[int\]\(\[.*?\]\)",
        f"recipe_levels = Array[int]([{level_arr}])",
        resource_body,
        count=1,
        flags=re.S,
    )
    new_text = "".join(preamble_lines) + "".join(ext_lines) + "\n" + resource_body
    if not new_text.endswith("\n"):
        new_text += "\n"
    OUTFITTING.write_text(new_text, encoding="utf-8")
    print(f"baked outfitting.tres: {len(rows)} recipes")


def _split_resource(text: str) -> tuple[str, str]:
    idx = text.find("\n[resource]")
    if idx < 0:
        idx = text.find("[resource]")
        if idx < 0:
            return text, ""
        return text[:idx], text[idx:]
    return text[: idx + 1], text[idx + 1 :]


def fix_vendor_values() -> int:
    """Move vendor_value/stack_limit off StatModifier subs onto the GearItem."""
    fixed = 0
    for path in sorted(GEARS_DIR.rglob("*.tres")):
        text = path.read_text(encoding="utf-8")
        if 'script_class="GearItem"' not in text and "class_name GearItem" not in text:
            if "gear_item.gd" not in text:
                continue
        pre, resource = _split_resource(text)
        if not resource:
            continue
        # Values sitting on modifiers (before [resource]).
        v_matches = list(VENDOR_LINE_RE.finditer(pre))
        s_matches = list(STACK_LINE_RE.finditer(pre))
        if not v_matches and not s_matches:
            continue
        vendor = int(v_matches[0].group(1)) if v_matches else None
        stack = int(s_matches[0].group(1)) if s_matches else None
        new_pre = VENDOR_LINE_RE.sub("", pre)
        new_pre = STACK_LINE_RE.sub("", new_pre)
        # Collapse extra blank lines left inside sub-resources.
        new_pre = re.sub(r"\n{3,}", "\n\n", new_pre)

        res_has_vendor = bool(VENDOR_LINE_RE.search(resource))
        res_has_stack = bool(STACK_LINE_RE.search(resource))
        res_has_trade = bool(CAN_TRADE_RE.search(resource))
        insert: list[str] = []
        if vendor is not None and not res_has_vendor:
            insert.append(f"vendor_value = {vendor}")
        if stack is not None and not res_has_stack:
            insert.append(f"stack_limit = {stack}")
        if not res_has_trade:
            insert.append("can_trade = true")
        if insert:
            # Insert after item_icon / item_name block, before metadata.
            lines = resource.splitlines(True)
            out_lines: list[str] = []
            injected = False
            for i, line in enumerate(lines):
                out_lines.append(line)
                if injected:
                    continue
                stripped = line.strip()
                if stripped.startswith("item_icon") or stripped.startswith("item_name"):
                    nxt = lines[i + 1].strip() if i + 1 < len(lines) else ""
                    if nxt.startswith("metadata/") or nxt.startswith("description") or nxt == "":
                        for extra in insert:
                            out_lines.append(extra + "\n")
                        injected = True
            if not injected:
                # Fallback: before first metadata/ line.
                rebuilt: list[str] = []
                for line in out_lines:
                    if not injected and line.startswith("metadata/"):
                        for extra in insert:
                            rebuilt.append(extra + "\n")
                        injected = True
                    rebuilt.append(line)
                out_lines = rebuilt
            resource = "".join(out_lines)
        new_text = new_pre + resource
        if new_text != text:
            path.write_text(new_text, encoding="utf-8")
            fixed += 1
            print(f"  vendor fix: {path.relative_to(ROOT)}")
    print(f"fixed vendor_value on {fixed} gear files")
    return fixed


def main() -> None:
    rows = collect_recipes()
    cloth = [r for r in rows if "/gears/cloth/" in r[0]]
    print(f"crafting recipes: {len(rows)} total, {len(cloth)} cloth gear")
    bake_outfitting(rows)
    fix_vendor_values()


if __name__ == "__main__":
    main()
