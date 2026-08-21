"""Edit Godot .tscn node blocks by NAME. A blanket regex over the file moved
nodes it was never meant to touch, including a map's Ground sprite."""
import re

def split_nodes(text):
    """[(header_line, body_text)] for each [node ...] block, plus the preamble."""
    idx = [m.start() for m in re.finditer(r'^\[node ', text, re.M)]
    if not idx:
        return text, []
    preamble = text[:idx[0]]
    blocks = []
    for i, start in enumerate(idx):
        end = idx[i + 1] if i + 1 < len(idx) else len(text)
        chunk = text[start:end]
        header, _, body = chunk.partition("\n")
        blocks.append([header, body])
    return preamble, blocks

def node_name(header):
    m = re.search(r'\[node name="([^"]+)"', header)
    return m.group(1) if m else ""

def set_position(body, x, y):
    if re.search(r'^position = Vector2\([^)]*\)$', body, re.M):
        return re.sub(r'^position = Vector2\([^)]*\)$',
                      'position = Vector2(%d, %d)' % (x, y), body, count=1, flags=re.M)
    return body.rstrip("\n") + "\nposition = Vector2(%d, %d)\n\n" % (x, y)

def join(preamble, blocks):
    return preamble + "".join(h + "\n" + b for h, b in blocks)
