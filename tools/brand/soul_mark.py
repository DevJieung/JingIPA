#!/usr/bin/env python3
"""Soul Stone mark — a one-colour vector of the brand emblem (stone on a winged shield).

Used for the Android 13 themed (monochrome) launcher layer, where the painted icon is tinted
to one colour and only a simple silhouette survives at 48 dp. The geometry follows the painted
emblem (art/ui/soul_emblem.png): tall faceted stone with a four-point star cut out, set off from
a heater shield by a thin cut, three-feather wings. Built with shapely (exact cuts), written as
one even-odd path, scaled so its farthest point sits on the 66 dp safe circle (r 132 of 432).

    python3 tools/brand/soul_mark.py [--write] [--png preview.png]
"""
from __future__ import annotations

import argparse
import hashlib
import math
from pathlib import Path

from shapely import affinity
from shapely.geometry import Point, Polygon
from shapely.ops import unary_union

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "build/feedback-2026-10-19/D4/icon"


def bezier(p0, p1, p2, n=24):
    return [((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0],
             (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1]) for t in [i / n for i in range(n + 1)]]


def mark():
    stone = Polygon([(0, -130), (42, -68), (42, 60), (0, 126), (-42, 60), (-42, -68)])
    # heater shield: chamfered top corners, straight sides, curved bottom to a point
    pts = [(-84, -64), (84, -64), (100, -48), (100, 30)] + bezier((100, 30), (98, 104), (0, 156))[1:]
    left = [(-x, y) for x, y in reversed(pts)]
    shield = Polygon(pts + left[1:-1])
    # wings: three overlapping feathers fanning up and out from behind the shield's shoulder
    feathers = []
    for ang, length, width, anchor in ((38, 126, 44, (-70, -40)), (16, 112, 40, (-74, -10)),
                                       (-6, 94, 36, (-74, 20))):
        f = affinity.scale(Point(0, 0).buffer(1.0, 64), length / 2, width / 2)
        f = affinity.translate(f, length / 2, 0)
        f = affinity.rotate(f, ang - 180, origin=(0, 0))    # (1,0) -> (-cos a, -sin a): left and up
        feathers.append(affinity.translate(f, *anchor))
    wing_l = unary_union(feathers)
    wing_r = affinity.scale(wing_l, -1, 1, origin=(0, 0))
    body = unary_union([shield, wing_l, wing_r])
    gap = 11.0
    white = body.difference(stone.buffer(gap, join_style=2, mitre_limit=3.0)).union(stone)
    star = []
    for k in range(8):
        a = -math.pi / 2 + k * math.pi / 4
        r = (36 if k % 4 == 0 else 28) if k % 2 == 0 else 8
        star.append((math.cos(a) * r, math.sin(a) * r - 4))
    return white.difference(Polygon(star))


def to_svg(geom, size=432, radius=132.0):
    minx, miny, maxx, maxy = geom.bounds
    c = ((minx + maxx) / 2, (miny + maxy) / 2)
    far = max(math.dist(c, p) for poly in getattr(geom, "geoms", [geom]) for p in poly.exterior.coords)
    k = radius / far
    g = affinity.translate(affinity.scale(geom, k, k, origin=c), size / 2 - c[0], size / 2 - c[1])
    parts = []
    for poly in getattr(g, "geoms", [g]):
        for ring in [poly.exterior, *poly.interiors]:
            coords = list(ring.coords)[:-1]
            parts.append("M" + "L".join("%.1f %.1f" % p for p in coords) + "Z")
    svg = ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">'
           '<path fill="#fff" fill-rule="evenodd" d="%s"/></svg>\n' % (size, size, size, size, "".join(parts)))
    return svg, g


def preview(g, path: Path, px=288, viewport=True):
    import cairo
    s = cairo.ImageSurface(cairo.FORMAT_ARGB32, px * 3 + 80, px)
    c = cairo.Context(s)
    c.set_source_rgb(0.24, 0.24, 0.24)
    c.paint()
    x = 0
    for size in (px, 96, 48):
        c.save()
        c.translate(x, 0)
        c.rectangle(0, 0, size, size)
        c.set_source_rgb(0.82, 0.86, 0.78)
        c.fill()
        sc = size / 288.0 if viewport else size / 432.0
        c.scale(sc, sc)
        if viewport:
            c.translate(-72, -72)
        c.set_fill_rule(cairo.FILL_RULE_EVEN_ODD)
        for poly in getattr(g, "geoms", [g]):
            for ring in [poly.exterior, *poly.interiors]:
                coords = list(ring.coords)
                c.move_to(*coords[0])
                for p in coords[1:]:
                    c.line_to(*p)
                c.close_path()
        c.set_source_rgb(0.17, 0.27, 0.13)
        c.fill()
        c.restore()
        x += size + 40
    s.write_to_png(str(path))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--png", default=str(OUT / "mono_preview.png"))
    args = ap.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    svg, g = to_svg(mark())
    dst = (ROOT / "art/ui/launcher_monochrome.svg") if args.write else (OUT / "launcher_monochrome.svg")
    dst.write_text(svg)
    preview(g, Path(args.png))
    print(dst, hashlib.sha256(dst.read_bytes()).hexdigest())


if __name__ == "__main__":
    main()
