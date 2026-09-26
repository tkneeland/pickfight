#!/usr/bin/env python3
"""Line-level editor for stage scenes (scenes/stages/*.tscn), issue #137.

Stages are hand-written text scenes built from parts (ADR-0008), with a `; `
comment above most nodes explaining why it is where it is. Godot's own
resaver would drop those comments, so stage edits are made as text instead,
and this keeps them consistent: it finds a node or sub_resource by name, sets
properties, inserts nodes (above a node's own comment block, or after a node
and all its children), and recomputes `load_steps` on save.

    import sys; sys.path.insert(0, "tools")
    from stage_tscn import Scene, body, marker, add_spawns
    s = Scene("scenes/stages/Flatlands.tscn")
    s.set_sub("RectangleShape2D_ground", "size", "Vector2(1440, 40)")
    s.rect_visual("GroundVisual", 1440, 40)
    add_spawns(s, {4: (-640, 0), 5: (640, 0)}, "Why these spawns are here.")
    s.save()

Everything is plain text edits; nothing here loads Godot. Check the result in
the editor or with the stage scenarios afterwards.
"""
import re
from pathlib import Path


class Scene:
    def __init__(self, path):
        self.path = Path(path)
        self.name = self.path.stem
        self.lines = self.path.read_text().split("\n")

    # --- lookup ---------------------------------------------------------
    def _header(self, pattern):
        for i, line in enumerate(self.lines):
            if line.startswith("[") and re.match(pattern, line):
                return i
        raise KeyError(f"{self.name}: no header matching {pattern}")

    def node(self, name):
        return self._header(r'\[node name="%s"' % re.escape(name))

    def sub(self, rid):
        return self._header(r'\[sub_resource [^\]]*id="%s"' % re.escape(rid))

    def _body_end(self, header):
        """Index one past the section's last property line."""
        j = header + 1
        while j < len(self.lines) and not self.lines[j].startswith("["):
            j += 1
        while self.lines[j - 1].strip() == "" or self.lines[j - 1].startswith(";"):
            j -= 1
        return j

    def _comment_start(self, header):
        """First line of the comment block (and blank lines) sitting on top
        of a header, so inserts land above a node's own comment."""
        j = header
        while j > 0 and (self.lines[j - 1].startswith(";") or self.lines[j - 1].strip() == ""):
            j -= 1
        # keep one blank line between the previous section and what we insert
        while j < header and self.lines[j].strip() == "":
            j += 1
        return j

    # --- edits ----------------------------------------------------------
    def _set(self, header, key, value):
        end = self._body_end(header)
        for k in range(header + 1, end):
            if self.lines[k].startswith(key + " = "):
                self.lines[k] = f"{key} = {value}"
                return
        self.lines.insert(end, f"{key} = {value}")

    def set(self, node, key, value):
        self._set(self.node(node), key, value)

    def set_sub(self, rid, key, value):
        self._set(self.sub(rid), key, value)

    def pos(self, node, x, y):
        self.set(node, "position", f"Vector2({fmt(x)}, {fmt(y)})")

    def rect_visual(self, node, w, h):
        hw, hh = w / 2, h / 2
        self.set(node, "polygon", "PackedVector2Array(%s)" % ", ".join(
            fmt(v) for v in (-hw, -hh, hw, -hh, hw, hh, -hw, hh)))

    def poly(self, node, pts):
        self.set(node, "polygon", "PackedVector2Array(%s)" % ", ".join(
            fmt(v) for p in pts for v in p))

    def add_sub_rect(self, rid, w, h):
        first_node = self._header(r"\[node ")
        at = self._comment_start(first_node)
        self.lines[at:at] = [f'[sub_resource type="RectangleShape2D" id="{rid}"]',
                             f"size = Vector2({fmt(w)}, {fmt(h)})", ""]

    def insert_before(self, node, block):
        at = self._comment_start(self.node(node))
        self.lines[at:at] = block.strip("\n").split("\n") + [""]

    def insert_after(self, node, block):
        """After the node and all of its children."""
        h = self.node(node)
        j = h + 1
        while True:
            while j < len(self.lines) and not self.lines[j].startswith("["):
                j += 1
            if j < len(self.lines) and re.search(r'parent="%s(/|")' % re.escape(node), self.lines[j]):
                j += 1
                continue
            break
        k = j
        while self.lines[k - 1].strip() == "" or self.lines[k - 1].startswith(";"):
            k -= 1
        self.lines[k:k] = [""] + block.strip("\n").split("\n")

    def append(self, block):
        while self.lines and self.lines[-1] == "":
            self.lines.pop()
        self.lines += [""] + block.strip("\n").split("\n") + [""]

    def comment_before(self, node, text):
        self.insert_before(node, "\n".join("; " + l if l else ";" for l in text.strip("\n").split("\n")))
        # insert_before added a trailing blank; comments should hug the node
        h = self.node(node)
        if self.lines[h - 1] == "":
            del self.lines[h - 1]

    def save(self):
        n_ext = sum(1 for l in self.lines if l.startswith("[ext_resource"))
        n_sub = sum(1 for l in self.lines if l.startswith("[sub_resource"))
        self.lines[0] = re.sub(r"load_steps=\d+", f"load_steps={n_ext + n_sub + 1}", self.lines[0])
        text = "\n".join(self.lines)
        text = re.sub(r"\n{3,}", "\n\n", text)
        self.path.write_text(text)


def fmt(v):
    v = float(v)
    return str(int(v)) if v == int(v) else f"{v:g}"


def marker(name, x, y, comment=None):
    out = ""
    if comment:
        out += "\n".join("; " + l for l in comment.strip().split("\n")) + "\n"
    return out + f'[node name="{name}" type="Marker2D" parent="."]\nposition = Vector2({fmt(x)}, {fmt(y)})\n'


def body(name, x, y, shape_id, w, h, colour="Color(0.35, 0.35, 0.4, 1)"):
    hw, hh = w / 2, h / 2
    pts = ", ".join(fmt(v) for v in (-hw, -hh, hw, -hh, hw, hh, -hw, hh))
    return (f'[node name="{name}" type="StaticBody2D" parent="."]\n'
            f"position = Vector2({fmt(x)}, {fmt(y)})\n\n"
            f'[node name="{name}Shape" type="CollisionShape2D" parent="{name}"]\n'
            f'shape = SubResource("{shape_id}")\n\n'
            f'[node name="{name}Visual" type="Polygon2D" parent="{name}"]\n'
            f"color = {colour}\n"
            f"polygon = PackedVector2Array({pts})\n")


def add_spawns(s, spawns, comment, after="Spawn3"):
    """spawns: {index: (x, y)} for 4..7; existing 0..3 moved if listed."""
    block = []
    for i in sorted(spawns):
        x, y = spawns[i]
        if i <= 3:
            s.pos(f"Spawn{i}", x, y)
        else:
            block.append(marker(f"Spawn{i}", x, y, comment if i == 4 else None))
    if block:
        s.insert_after(after, "\n".join(block))


def shape_of(s, node):
    """The sub_resource id a CollisionShape2D node uses."""
    h = s.node(node)
    for k in range(h + 1, h + 4):
        m = re.search(r'SubResource\("([^"]+)"\)', s.lines[k])
        if m:
            return m.group(1)
    raise KeyError(node)
