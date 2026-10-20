#!/usr/bin/env python3
"""MindMorph logo master — clean vector redraw of docs/icon-business-v3-512.png.

The user's company logo was only available as a 512 px PNG. Its geometry was recovered by
analysis-by-synthesis (a parametric model rendered with cairo and fitted to the PNG with
scipy: mean error 0.045/255 per channel). The shape and the five flat colours are unchanged:

  badge   #235D48  rounded square, corner radii 127.85 (TL, BR) and 166.72 (TR, BL)
  M       #FFFFFF  stroke 39.03, diagonals at 42.24 deg, rounded outer corner r 19.55
  chevron #A8CBB5  apex radius 17.22, thickness 31.48
  cube    #E0EEE4 top, #A8CBB5 left, #75A58B right; knock-out gap 8.07 (round joins)
  dome    knock-out under the V, concentric with the chevron apex, radius 28.82

Units are those of the 512 px original; the SVG keeps viewBox 0 0 512 512.

    python3 tools/brand/mindmorph_logo.py            # writes art/ui/mindmorph_logo.svg + .png (1024)
    python3 tools/brand/mindmorph_logo.py --size 2048 --png build/feedback-2026-10-19/D4/logo/mindmorph_2048.png
"""
from __future__ import annotations

import argparse
import math
import os

import cairo

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Fitted parameters (512-unit space). See module docstring.
P = dict(R1=127.848, R2=166.719, w=39.034, xL=98.885, yB=358.513, rtl=19.554,
         theta=42.238, yn=255.273, wd=39.043, cyc=303.468, rc=17.215, tc=31.482,
         lc=86.913, cyd=302.915, Rd=28.818, cx=393.580, cy=162.477, hw=42.829,
         a=24.903, s=50.014, g=8.065)

GREEN = "#235D48"
WHITE = "#FFFFFF"
MINT = "#A8CBB5"
SHADE = "#75A58B"
TOP = "#E0EEE4"


def _sub(a, b):
    return (a[0] - b[0], a[1] - b[1])


def _add(a, b):
    return (a[0] + b[0], a[1] + b[1])


def _mul(a, k):
    return (a[0] * k, a[1] * k)


def _norm(a):
    length = math.hypot(*a)
    return (a[0] / length, a[1] / length)


def _cross(a, b):
    return a[0] * b[1] - a[1] * b[0]


def _line_line(p, d, q, e):
    t = _cross(_sub(q, p), e) / _cross(d, e)
    return _add(p, _mul(d, t))


def _line_circle(p, d, c, r):
    """Both intersections (t ascending) of p + t d (unit d) with circle (c, r)."""
    f = _sub(p, c)
    b = f[0] * d[0] + f[1] * d[1]
    k = f[0] ** 2 + f[1] ** 2 - r * r
    disc = math.sqrt(b * b - k)
    return [_add(p, _mul(d, -b - disc)), _add(p, _mul(d, -b + disc))]


def _ang(c, q):
    return math.atan2(q[1] - c[1], q[0] - c[0])


class Path:
    """Path commands kept as data so SVG and cairo draw the same geometry."""

    def __init__(self, fill: str):
        self.fill = fill
        self.ops: list[tuple] = []

    def M(self, q):
        self.ops.append(("M", q))
        return self

    def L(self, q):
        self.ops.append(("L", q))
        return self

    def A(self, c, r, q, sweep: int):
        """Circular arc around c (radius r) to q; sweep 1 = clockwise on screen."""
        self.ops.append(("A", c, r, q, sweep))
        return self

    def Z(self):
        self.ops.append(("Z",))
        return self

    def svg(self) -> str:
        out = []
        cur = None
        for op in self.ops:
            if op[0] == "M":
                out.append("M%s" % _fmt(op[1]))
                cur = op[1]
            elif op[0] == "L":
                out.append("L%s" % _fmt(op[1]))
                cur = op[1]
            elif op[0] == "A":
                _, c, r, q, sweep = op
                a0, a1 = _ang(c, cur), _ang(c, q)
                span = (a1 - a0) % (2 * math.pi) if sweep else (a0 - a1) % (2 * math.pi)
                large = 1 if span > math.pi else 0
                out.append("A%s %s 0 %d %d %s" % (_n(r), _n(r), large, sweep, _fmt(q)))
                cur = q
            else:
                out.append("Z")
        return "".join(out)

    def cairo(self, ctx):
        ctx.new_path()
        cur = None
        for op in self.ops:
            if op[0] == "M":
                ctx.move_to(*op[1])
                cur = op[1]
            elif op[0] == "L":
                ctx.line_to(*op[1])
                cur = op[1]
            elif op[0] == "A":
                _, c, r, q, sweep = op
                a0, a1 = _ang(c, cur), _ang(c, q)
                (ctx.arc if sweep else ctx.arc_negative)(c[0], c[1], r, a0, a1)
                cur = q
            else:
                ctx.close_path()
        r, g, b = (int(self.fill[i:i + 2], 16) / 255.0 for i in (1, 3, 5))
        ctx.set_source_rgb(r, g, b)
        ctx.fill()


def _n(v: float) -> str:
    s = ("%.3f" % v).rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def _fmt(q) -> str:
    return "%s %s" % (_n(q[0]), _n(q[1]))


def build(p=P, badge=True) -> list[Path]:
    th = math.radians(p["theta"])
    c, s = math.cos(th), math.sin(th)
    N = (256.0, p["yn"])
    w, xL, yB, wd, r = p["w"], p["xL"], p["yB"], p["wd"], p["rtl"]
    xLi, xRo = xL + w, 512.0 - xL
    xRi = xRo - w
    down_right, up_right = (c, s), (c, -s)
    left_lo = (256.0 - s * wd, N[1] + c * wd)       # point on the left diagonal's lower edge
    right_lo = (256.0 + s * wd, N[1] + c * wd)      # point on the right diagonal's lower edge
    paths: list[Path] = []

    if badge:
        R1, R2 = p["R1"], p["R2"]
        paths.append(Path(GREEN).M((R1, 0)).L((512 - R2, 0)).A((512 - R2, R2), R2, (512, R2), 1)
                     .L((512, 512 - R1)).A((512 - R1, 512 - R1), R1, (512 - R1, 512), 1)
                     .L((R2, 512)).A((R2, 512 - R2), R2, (0, 512 - R2), 1)
                     .L((0, R1)).A((R1, R1), R1, (R1, 0), 1).Z())

    # Cube hexagon (clockwise on screen) and its knock-out ring (offset g, round joins).
    cx, cy, hw, a, sv, gap = p["cx"], p["cy"], p["hw"], p["a"], p["s"], p["g"]
    T, UR, LR = (cx, cy - 2 * a), (cx + hw, cy - a), (cx + hw, cy - a + sv)
    B, LL, UL = (cx, cy + sv), (cx - hw, cy - a + sv), (cx - hw, cy - a)
    Cf = (cx, cy)

    def out_n(p0, p1):
        e = _norm(_sub(p1, p0))
        return (e[1], -e[0])

    n_bll = out_n(B, LL)     # lower-left edge, outward
    n_lrb = out_n(LR, B)     # lower-right edge, outward
    x_left = LL[0] - gap     # left vertical edge offset

    # --- White M, left stem + both diagonals ---------------------------------------
    cyy = N[1] + (r + (xL + r - N[0]) * s) / c
    arc_c = (xL + r, cyy)
    t1 = (xL, cyy)
    t2 = (xL + r + s * r, cyy - c * r)
    inner_c = _line_line(left_lo, down_right, (xLi, 0.0), (0.0, 1.0))
    up_hit = _line_line(N, up_right, (x_left, 0.0), (0.0, 1.0))
    assert UL[1] <= up_hit[1] <= LL[1], "upper edge must meet the halo's vertical side"
    lo_hit = _line_line(right_lo, up_right, _add(B, _mul(n_bll, gap)), _norm(_sub(LL, B)))
    dome = (256.0, p["cyd"])
    dl_pt = _line_circle(left_lo, down_right, dome, p["Rd"])[0]
    dr_pt = _line_circle(right_lo, up_right, dome, p["Rd"])[1]
    paths.append(Path(WHITE).M((xL, yB)).L(t1).A(arc_c, r, t2, 1).L(N).L(up_hit)
                 .L((x_left, LL[1])).A(LL, gap, _add(LL, _mul(n_bll, gap)), 0).L(lo_hit)
                 .L(dr_pt).A(dome, p["Rd"], dl_pt, 0).L(inner_c).L((xLi, yB)).Z())

    # --- White right stem, its top cut by the halo -----------------------------------
    stem_l = _line_line((xRi, 0.0), (0.0, 1.0), _add(B, _mul(n_bll, gap)), _norm(_sub(LL, B)))
    stem_r = _line_line((xRo, 0.0), (0.0, 1.0), _add(LR, _mul(n_lrb, gap)), _norm(_sub(B, LR)))
    paths.append(Path(WHITE).M((xRi, yB)).L(stem_l).L(_add(B, _mul(n_bll, gap)))
                 .A(B, gap, _add(B, _mul(n_lrb, gap)), 0).L(stem_r).L((xRo, yB)).Z())

    # --- Mint chevron ----------------------------------------------------------------
    C = (256.0, p["cyc"])
    rc, tc, lc = p["rc"], p["tc"], p["lc"]
    dl, dr = (-c, s), (c, s)
    nl, nr = (-s, -c), (s, -c)                    # outward (up-left / up-right) normals
    lo0, ro0 = _add(C, _mul(nl, rc)), _add(C, _mul(nr, rc))
    notch = _line_line(_sub(lo0, _mul(nl, tc)), dl, _sub(ro0, _mul(nr, tc)), dr)
    lo_end, ro_end = _add(lo0, _mul(dl, lc)), _add(ro0, _mul(dr, lc))
    li_end, ri_end = _sub(lo_end, _mul(nl, tc)), _sub(ro_end, _mul(nr, tc))
    paths.append(Path(MINT).M(li_end).L(lo_end).L(lo0).A(C, rc, ro0, 1).L(ro_end)
                 .L(ri_end).L(notch).Z())

    # --- Cube: whole hexagon in the left-face colour, then top and right faces on it
    #     (no anti-aliasing seam can show the badge through a shared edge).
    paths.append(Path(MINT).M(T).L(UR).L(LR).L(B).L(LL).L(UL).Z())
    paths.append(Path(TOP).M(T).L(UR).L(Cf).L(UL).Z())
    paths.append(Path(SHADE).M(Cf).L(UR).L(LR).L(B).Z())
    return paths


def svg_text(paths: list[Path], size: int = 1024) -> str:
    body = "\n".join('  <path fill="%s" d="%s"/>' % (pa.fill, pa.svg()) for pa in paths)
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 512 512">\n'
            '  <title>MindMorph</title>\n%s\n</svg>\n' % (size, size, body))


def render_png(paths: list[Path], size: int, out: str) -> None:
    surf = cairo.ImageSurface(cairo.FORMAT_ARGB32, size, size)
    ctx = cairo.Context(surf)
    ctx.set_antialias(cairo.ANTIALIAS_BEST)
    ctx.scale(size / 512.0, size / 512.0)
    for pa in paths:
        pa.cairo(ctx)
    surf.write_to_png(out)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--size", type=int, default=1024)
    ap.add_argument("--svg", default=os.path.join(ROOT, "art/ui/mindmorph_logo.svg"))
    ap.add_argument("--png", default=os.path.join(ROOT, "art/ui/mindmorph_logo.png"))
    ap.add_argument("--no-badge", action="store_true", help="mark only (transparent background)")
    args = ap.parse_args()
    paths = build(badge=not args.no_badge)
    if args.svg:
        with open(args.svg, "w") as f:
            f.write(svg_text(paths))
    if args.png:
        render_png(paths, args.size, args.png)
    print("wrote", args.svg, args.png)


if __name__ == "__main__":
    main()
