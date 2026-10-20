#!/usr/bin/env python3
"""The 76 constellation node glyphs (2026-10-19, feedback F3), drawn with cairo.

Used by tools/talent_art.py, which writes art/ui/talents/<id>.png (128 px). One style for
every node: an ivory enamel shape with an ink outline, a second softer tone for handles
and inner parts, ink details and a soft drop shadow. The glyph is neutral so the seal
tints it (ivory on a lit face, the constellation colour on an open one, grey when
locked). Variants of one idea share a base and carry a small badge (+1, +2, a clock, a
ring, two chevrons) on the lower right.

Coordinates are in glyph units: (0, 0) is the centre of the 128 px canvas, 1 unit is U px,
y grows downwards.
"""
from __future__ import annotations

import math

import cairo
import numpy as np
from scipy.ndimage import gaussian_filter, shift as nd_shift

SIZE = 128
CX = CY = SIZE / 2
U = 46.0
OUT = 4.4                     # outline width in px (each side of a fill)
INK = (0.043, 0.075, 0.106)
MAIN = ((1.0, 0.995, 0.96), (0.84, 0.81, 0.75))
SUB = ((0.74, 0.71, 0.65), (0.56, 0.53, 0.49))
PALE = ((0.93, 0.92, 0.89), (0.80, 0.78, 0.74))


def P(x: float, y: float):
    return (CX + x * U, CY + y * U)


# --------------------------------------------------------------------------- #
# Glyph: parts in layers, rendered shadow -> (outline, fill, ink) per layer
# --------------------------------------------------------------------------- #
class Glyph:
    def __init__(self):
        self.layers = [[]]

    def layer(self):
        self.layers.append([])
        return self

    def fill(self, build, tone=MAIN):
        self.layers[-1].append(("fill", build, tone, 0.0))
        return self

    def stroke(self, build, width, tone=MAIN, cap=cairo.LINE_CAP_ROUND):
        self.layers[-1].append(("stroke", build, tone, width, cap))
        return self

    def ink(self, build, width=0.0):
        self.layers[-1].append(("ink", build, None, width))
        return self

    def light(self, build, width=0.07, alpha=0.75):
        self.layers[-1].append(("light", build, alpha, width))
        return self


def _tone(tone):
    g = cairo.LinearGradient(0, CY - U * 1.05, 0, CY + U * 1.05)
    g.add_color_stop_rgb(0.0, *tone[0])
    g.add_color_stop_rgb(1.0, *tone[1])
    return g


def _ctx(surface):
    c = cairo.Context(surface)
    c.set_line_join(cairo.LINE_JOIN_ROUND)
    c.set_line_cap(cairo.LINE_CAP_ROUND)
    return c


def render(glyph: Glyph, rgba) -> np.ndarray:
    """Straight-alpha float RGBA of a glyph (rgba = talent_art.rgba)."""
    # Shadow: every fill and stroke in black, blurred and dropped.
    s = cairo.ImageSurface(cairo.FORMAT_ARGB32, SIZE, SIZE)
    c = _ctx(s)
    for layer in glyph.layers:
        for part in layer:
            kind, build = part[0], part[1]
            if kind == "fill":
                c.new_path()
                build(c)
                c.set_source_rgba(0, 0, 0, 1)
                c.set_line_width(OUT * 2)
                c.stroke_preserve()
                c.fill()
            elif kind == "stroke":
                c.new_path()
                build(c)
                c.set_source_rgba(0, 0, 0, 1)
                c.set_line_cap(part[4])
                c.set_line_width(part[3] * U + OUT * 2)
                c.stroke()
                c.set_line_cap(cairo.LINE_CAP_ROUND)
    shadow = rgba(s)[..., 3]
    shadow = nd_shift(gaussian_filter(shadow, 2.4), (3.2, 0.6), order=1) * 0.55
    out = np.zeros((SIZE, SIZE, 4), np.float32)
    out[..., 3] = shadow
    # The glyph, layer by layer.
    s = cairo.ImageSurface(cairo.FORMAT_ARGB32, SIZE, SIZE)
    c = _ctx(s)
    for layer in glyph.layers:
        for part in layer:
            kind, build = part[0], part[1]
            if kind == "fill":
                c.new_path()
                build(c)
                c.set_source_rgba(*INK, 1)
                c.set_line_width(OUT * 2)
                c.stroke()
            elif kind == "stroke":
                c.new_path()
                build(c)
                c.set_source_rgba(*INK, 1)
                c.set_line_cap(part[4])
                c.set_line_width(part[3] * U + OUT * 2)
                c.stroke()
                c.set_line_cap(cairo.LINE_CAP_ROUND)
        for part in layer:
            kind, build = part[0], part[1]
            if kind == "fill":
                c.new_path()
                build(c)
                c.set_source(_tone(part[2]))
                c.fill()
            elif kind == "stroke":
                c.new_path()
                build(c)
                c.set_source(_tone(part[2]))
                c.set_line_cap(part[4])
                c.set_line_width(part[3] * U)
                c.stroke()
                c.set_line_cap(cairo.LINE_CAP_ROUND)
        for part in layer:
            kind, build = part[0], part[1]
            if kind == "ink":
                c.new_path()
                build(c)
                c.set_source_rgba(*INK, 1)
                if part[3] > 0:
                    c.set_line_width(part[3] * U)
                    c.stroke()
                else:
                    c.fill()
            elif kind == "light":
                c.new_path()
                build(c)
                c.set_source_rgba(1, 1, 1, part[2])
                c.set_line_width(part[3] * U)
                c.stroke()
    glyph_px = rgba(s)
    a = glyph_px[..., 3:4]
    base_a = out[..., 3:4]
    oa = a + base_a * (1 - a)
    rgb = glyph_px[..., :3] * a / np.maximum(oa, 1e-6)
    return np.concatenate([np.where(oa > 0, rgb, 0), oa], axis=-1)


# --------------------------------------------------------------------------- #
# Path helpers (unit coordinates)
# --------------------------------------------------------------------------- #
def poly(c, pts, close=True):
    c.move_to(*P(*pts[0]))
    for p in pts[1:]:
        c.line_to(*P(*p))
    if close:
        c.close_path()


def circle(c, x, y, r, reverse=False):
    c.new_sub_path()
    if reverse:
        c.arc_negative(*P(x, y), r * U, 0, -math.tau)
    else:
        c.arc(*P(x, y), r * U, 0, math.tau)
    c.close_path()


def arc(c, x, y, r, a0, a1, negative=False):
    if negative:
        c.arc_negative(*P(x, y), r * U, math.radians(a0), math.radians(a1))
    else:
        c.arc(*P(x, y), r * U, math.radians(a0), math.radians(a1))


def rrect(c, x0, y0, x1, y1, r):
    r = min(r, (x1 - x0) / 2, (y1 - y0) / 2)
    c.new_sub_path()
    c.arc(*P(x1 - r, y0 + r), r * U, -math.pi / 2, 0)
    c.arc(*P(x1 - r, y1 - r), r * U, 0, math.pi / 2)
    c.arc(*P(x0 + r, y1 - r), r * U, math.pi / 2, math.pi)
    c.arc(*P(x0 + r, y0 + r), r * U, math.pi, 1.5 * math.pi)
    c.close_path()


def curve(c, *pts):
    """curve_to over unit points (3 per segment)."""
    for i in range(0, len(pts), 3):
        c.curve_to(*P(*pts[i]), *P(*pts[i + 1]), *P(*pts[i + 2]))


def star_pts(x, y, r, inner=0.45, n=5, rot=-90.0):
    out = []
    for k in range(n * 2):
        a = math.radians(rot + 180.0 / n * k)
        rr = r if k % 2 == 0 else r * inner
        out.append((x + rr * math.cos(a), y + rr * math.sin(a)))
    return out


def rotated(pts, ang, cx=0.0, cy=0.0):
    ca, sa = math.cos(math.radians(ang)), math.sin(math.radians(ang))
    return [(cx + (x - cx) * ca - (y - cy) * sa, cy + (x - cx) * sa + (y - cy) * ca) for x, y in pts]


def moved(pts, dx, dy, s=1.0):
    return [(dx + x * s, dy + y * s) for x, y in pts]


# --------------------------------------------------------------------------- #
# Shapes (each adds parts to a glyph)
# --------------------------------------------------------------------------- #
def sword(g, p0, p1, w=0.12, guard=0.34, ridge=True):
    """A sword from pommel p0 to tip p1."""
    x0, y0 = p0
    x1, y1 = p1
    L = math.hypot(x1 - x0, y1 - y0)
    dx, dy = (x1 - x0) / L, (y1 - y0) / L
    nx, ny = -dy, dx
    gx, gy = x0 + dx * 0.26 * L, y0 + dy * 0.26 * L
    tb = (x1 - dx * w * 2.2, y1 - dy * w * 2.2)
    blade = [(gx + nx * w, gy + ny * w), (tb[0] + nx * w, tb[1] + ny * w), (x1, y1), (tb[0] - nx * w, tb[1] - ny * w), (gx - nx * w, gy - ny * w)]
    g.fill(lambda c: poly(c, blade))
    if ridge:
        g.ink(lambda c: poly(c, [(gx + dx * 0.06 * L, gy + dy * 0.06 * L), (tb[0] - dx * 0.04, tb[1] - dy * 0.04)], False), 0.045)
    g.layer()
    t = 0.075
    gd = [(gx + nx * guard - dx * t, gy + ny * guard - dy * t), (gx + nx * guard + dx * t, gy + ny * guard + dy * t),
          (gx - nx * guard + dx * t, gy - ny * guard + dy * t), (gx - nx * guard - dx * t, gy - ny * guard - dy * t)]
    gw = w * 0.72
    sx, sy = x0 + dx * 0.08 * L, y0 + dy * 0.08 * L
    grip = [(sx + nx * gw, sy + ny * gw), (gx + nx * gw, gy + ny * gw), (gx - nx * gw, gy - ny * gw), (sx - nx * gw, sy - ny * gw)]
    g.fill(lambda c: poly(c, grip), SUB)
    g.fill(lambda c: poly(c, gd))
    g.fill(lambda c: circle(c, x0 + dx * 0.04 * L, y0 + dy * 0.04 * L, w * 0.95))


def flame(g, x=0.0, y=0.0, s=1.0, inner=True):
    def outer(c):
        pts = [(0, 1.0), (-0.62, 0.95), (-0.82, 0.40), (-0.56, 0.02), (-0.42, -0.22), (-0.46, -0.44), (-0.30, -0.70),
               (-0.20, -0.46), (-0.10, -0.36), (-0.04, -0.30), (-0.06, -0.62), (0.04, -0.86), (0.16, -1.06),
               (0.28, -0.78), (0.52, -0.56), (0.58, -0.24), (0.62, -0.36), (0.66, -0.46), (0.72, -0.56),
               (0.88, -0.20), (0.84, 0.46), (0.56, 0.80), (0.40, 0.98), (0.16, 1.02), (0, 1.0)]
        pts = moved(pts, x, y, s)
        c.move_to(*P(*pts[0]))
        curve(c, *pts[1:])
        c.close_path()
    g.fill(outer)
    if inner:
        def core(c):
            pts = [(0, 0.86), (-0.34, 0.84), (-0.42, 0.46), (-0.22, 0.16), (-0.10, 0.0), (0.0, -0.20), (0.05, -0.42),
                   (0.16, -0.16), (0.40, 0.10), (0.36, 0.46), (0.33, 0.72), (0.16, 0.87), (0, 0.86)]
            pts = moved(pts, x, y, s)
            c.move_to(*P(*pts[0]))
            curve(c, *pts[1:])
            c.close_path()
        g.fill(core, SUB)


def drop(g, x=0.0, y=0.0, s=1.0):
    def build(c):
        pts = moved([(0, -1.0), (0.16, -0.70), (0.70, -0.16), (0.70, 0.30), (0.70, 0.72), (0.38, 1.0), (0, 1.0),
                     (-0.38, 1.0), (-0.70, 0.72), (-0.70, 0.30), (-0.70, -0.16), (-0.16, -0.70), (0, -1.0)], x, y, s)
        c.move_to(*P(*pts[0]))
        curve(c, *pts[1:])
        c.close_path()
    g.fill(build)
    g.light(lambda c: arc(c, x - 0.05 * s, y + 0.30 * s, 0.42 * s, 150, 215), 0.09, 0.9)


def snowflake(g, x=0.0, y=0.0, s=1.0, w=0.15):
    def build(c):
        for k in range(6):
            a = math.radians(-90 + 60 * k)
            dx, dy = math.cos(a), math.sin(a)
            c.move_to(*P(x, y))
            c.line_to(*P(x + dx * s, y + dy * s))
            for t, b in ((0.55, 0.32), (0.80, 0.20)):
                bx, by = x + dx * s * t, y + dy * s * t
                for side in (-1, 1):
                    ang = a + side * math.radians(48)
                    c.move_to(*P(bx, by))
                    c.line_to(*P(bx + math.cos(ang) * s * b, by + math.sin(ang) * s * b))
    g.stroke(build, w * s / max(s, 0.6) if s < 0.6 else w)
    g.fill(lambda c: circle(c, x, y, 0.16 * s))


def bolt(g, x=0.0, y=0.0, s=1.0, tone=MAIN):
    pts = moved([(0.10, -1.00), (0.56, -1.00), (0.20, -0.22), (0.58, -0.22), (-0.24, 1.02), (-0.02, 0.12), (-0.44, 0.12)], x, y, s)
    g.fill(lambda c: poly(c, pts), tone)


def shield_path(c, x=0.0, y=0.0, s=1.0):
    pts = moved([(0, -0.92), (0.30, -0.78), (0.60, -0.80), (0.80, -0.74), (0.82, -0.10), (0.62, 0.52), (0, 0.96),
                 (-0.62, 0.52), (-0.82, -0.10), (-0.80, -0.74), (-0.60, -0.80), (-0.30, -0.78), (0, -0.92)], x, y, s)
    c.move_to(*P(*pts[0]))
    curve(c, *pts[1:])
    c.close_path()


def crystal(g, x=0.0, y=0.0, s=1.0):
    outer = moved([(0, -1.0), (0.56, -0.44), (0.56, 0.40), (0, 1.0), (-0.56, 0.40), (-0.56, -0.44)], x, y, s)
    right = moved([(0, -1.0), (0.56, -0.44), (0.56, 0.40), (0, 1.0), (0.18, 0.28), (0.18, -0.36)], x, y, s)
    g.fill(lambda c: poly(c, outer))
    g.fill(lambda c: poly(c, right), SUB)
    g.ink(lambda c: poly(c, moved([(-0.18, -0.36), (0.18, -0.36), (0.18, 0.28), (-0.18, 0.28), (-0.18, -0.36)], x, y, s), False), 0.04)
    g.ink(lambda c: (poly(c, moved([(0, -1.0), (-0.18, -0.36)], x, y, s), False), poly(c, moved([(0, -1.0), (0.18, -0.36)], x, y, s), False),
                     poly(c, moved([(0, 1.0), (-0.18, 0.28)], x, y, s), False), poly(c, moved([(0, 1.0), (0.18, 0.28)], x, y, s), False)), 0.035)
    g.light(lambda c: poly(c, moved([(-0.42, -0.36), (-0.12, -0.70)], x, y, s), False), 0.07, 0.85)


def coin(g, x=0.0, y=0.0, s=1.0, mark="star"):
    g.fill(lambda c: circle(c, x, y, 0.92 * s))
    g.ink(lambda c: circle(c, x, y, 0.70 * s), 0.05)
    if mark == "star":
        g.ink(lambda c: poly(c, star_pts(x, y + 0.02 * s, 0.44 * s, 0.45)))
    elif mark == "G":
        def gee(c):
            c.new_sub_path()
            c.arc(*P(x, y), 0.40 * s * U, math.radians(-40), math.radians(270))
            c.move_to(*P(x + 0.08 * s, y + 0.02 * s))
            c.line_to(*P(x + 0.40 * s, y + 0.02 * s))
            c.line_to(*P(x + 0.40 * s, y + 0.30 * s))
        g.ink(gee, 0.12 * s)
    g.light(lambda c: arc(c, x, y, 0.80 * s, 200, 290), 0.08, 0.9)


def eye(g, x=0.0, y=0.0, s=1.0):
    def almond(c):
        c.move_to(*P(x - 1.0 * s, y))
        curve(c, (x - 0.50 * s, y - 0.66 * s), (x + 0.50 * s, y - 0.66 * s), (x + 1.0 * s, y),
              (x + 0.50 * s, y + 0.66 * s), (x - 0.50 * s, y + 0.66 * s), (x - 1.0 * s, y))
        c.close_path()
    g.fill(almond)
    g.layer()
    g.fill(lambda c: circle(c, x, y, 0.40 * s), SUB)
    g.ink(lambda c: circle(c, x, y, 0.19 * s))
    g.light(lambda c: arc(c, x - 0.12 * s, y - 0.12 * s, 0.06 * s, 0, 360), 0.10, 1.0)


def reticle(g, x=0.0, y=0.0, s=1.0, w=0.14):
    def build(c):
        c.new_sub_path()
        c.arc(*P(x, y), 0.70 * s * U, 0, math.tau)
        for k in range(4):
            a = math.radians(90 * k)
            c.move_to(*P(x + math.cos(a) * 0.40 * s, y + math.sin(a) * 0.40 * s))
            c.line_to(*P(x + math.cos(a) * 1.02 * s, y + math.sin(a) * 1.02 * s))
    g.stroke(build, w)
    g.fill(lambda c: circle(c, x, y, 0.13 * s))


def gear(g, x=0.0, y=0.0, s=1.0, teeth=8, hole=0.34):
    def build(c):
        pts = []
        for k in range(teeth):
            a = math.tau * k / teeth
            for da, r in ((-0.16, 0.74), (-0.11, 1.0), (0.11, 1.0), (0.16, 0.74)):
                aa = a + da * 8 / teeth
                pts.append((x + math.cos(aa) * r * s, y + math.sin(aa) * r * s))
        poly(c, pts)
        circle(c, x, y, hole * s, reverse=True)
    g.fill(build)


def chevrons(g, n=2, x=0.0, y=0.0, s=1.0, w=0.20, up=True, tone=MAIN):
    def build(c):
        for k in range(n):
            o = (k - (n - 1) / 2) * 0.46 * s
            if up:
                poly(c, [(x - 0.62 * s, y + o + 0.30 * s), (x, y + o - 0.30 * s), (x + 0.62 * s, y + o + 0.30 * s)], False)
            else:
                poly(c, [(x + o - 0.30 * s, y - 0.62 * s), (x + o + 0.30 * s, y), (x + o - 0.30 * s, y + 0.62 * s)], False)
    g.stroke(build, w, tone, cairo.LINE_CAP_SQUARE)


def arrow(g, p0, p1, w=0.10, head=0.30, fletch=True, tone=MAIN):
    x0, y0 = p0
    x1, y1 = p1
    L = math.hypot(x1 - x0, y1 - y0)
    dx, dy = (x1 - x0) / L, (y1 - y0) / L
    nx, ny = -dy, dx
    bx, by = x1 - dx * head * 1.3, y1 - dy * head * 1.3
    g.stroke(lambda c: poly(c, [(x0 + dx * 0.05, y0 + dy * 0.05), (bx, by)], False), w, SUB, cairo.LINE_CAP_BUTT)
    if fletch:
        f = [(x0, y0), (x0 + dx * 0.32 + nx * 0.20, y0 + dy * 0.32 + ny * 0.20), (x0 + dx * 0.40, y0 + dy * 0.40),
             (x0 + dx * 0.32 - nx * 0.20, y0 + dy * 0.32 - ny * 0.20)]
        g.fill(lambda c: poly(c, f), tone)
    hd = [(x1, y1), (bx + nx * head * 0.85, by + ny * head * 0.85), (bx + dx * head * 0.35, by + dy * head * 0.35),
          (bx - nx * head * 0.85, by - ny * head * 0.85)]
    g.fill(lambda c: poly(c, hd), tone)


def card(g, x, y, ang, s=1.0, tone=MAIN, mark=True):
    pts = rotated([(-0.36, -0.54), (0.36, -0.54), (0.36, 0.54), (-0.36, 0.54)], ang)
    pts = moved(pts, x, y, s)

    def build(c):
        # a rounded card: draw the polygon with round joins via a thin inset rect path
        poly(c, pts)
    g.fill(build, tone)
    if mark:
        g.ink(lambda c: poly(c, star_pts(x, y, 0.18 * s, 0.45, 4, -90 + ang)))


def _quad_ctrl(p0, q, p1):
    return ((p0[0] + 2 / 3 * (q[0] - p0[0]), p0[1] + 2 / 3 * (q[1] - p0[1])),
            (p1[0] + 2 / 3 * (q[0] - p1[0]), p1[1] + 2 / 3 * (q[1] - p1[1])))


def slash(c, p0, p1, bulge=0.20, width=0.16):
    """A claw mark: a crescent from p0 to p1, swollen `width` at its middle."""
    mx, my = (p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2
    dx, dy = p1[0] - p0[0], p1[1] - p0[1]
    L = math.hypot(dx, dy)
    nx, ny = -dy / L, dx / L
    q_out = (mx + nx * (bulge + width), my + ny * (bulge + width))
    q_in = (mx + nx * bulge, my + ny * bulge)
    c1, c2 = _quad_ctrl(p0, q_out, p1)
    c3, c4 = _quad_ctrl(p1, q_in, p0)
    c.move_to(*P(*p0))
    c.curve_to(*P(*c1), *P(*c2), *P(*p1))
    c.curve_to(*P(*c3), *P(*c4), *P(*p0))
    c.close_path()


def claws(g, tone=MAIN):
    for k, off in enumerate((-0.42, 0.0, 0.42)):
        ln = 0.86 if k == 1 else 0.70
        p0 = (0.10 + off * 0.7 + ln * 0.62, -0.06 + off * 0.7 - ln * 0.78)
        p1 = (0.10 + off * 0.7 - ln * 0.62, -0.06 + off * 0.7 + ln * 0.78)
        g.fill(lambda c, p0=p0, p1=p1: slash(c, p0, p1, 0.12, 0.27), tone)


def flame_path(c, x=0.0, y=0.0, s=1.0):
    pts = [(0, 1.0), (-0.62, 0.95), (-0.82, 0.40), (-0.56, 0.02), (-0.42, -0.22), (-0.46, -0.44), (-0.30, -0.70),
           (-0.20, -0.46), (-0.10, -0.36), (-0.04, -0.30), (-0.06, -0.62), (0.04, -0.86), (0.16, -1.06),
           (0.28, -0.78), (0.52, -0.56), (0.58, -0.24), (0.62, -0.36), (0.66, -0.46), (0.72, -0.56),
           (0.88, -0.20), (0.84, 0.46), (0.56, 0.80), (0.40, 0.98), (0.16, 1.02), (0, 1.0)]
    pts = moved(pts, x, y, s)
    c.move_to(*P(*pts[0]))
    curve(c, *pts[1:])
    c.close_path()


def badge(g, kind):
    """A small round badge on the lower right: '+1', '+2', 'clock', 'ring', 'up2'."""
    bx, by, br = 0.64, 0.64, 0.36
    g.layer()
    g.fill(lambda c: circle(c, bx, by, br), PALE)
    if kind in ("+1", "+2"):
        g.ink(lambda c: (poly(c, [(bx - 0.25, by), (bx - 0.03, by)], False), poly(c, [(bx - 0.14, by - 0.11), (bx - 0.14, by + 0.11)], False)), 0.075)
        if kind == "+1":
            g.ink(lambda c: (poly(c, [(bx + 0.07, by - 0.08), (bx + 0.13, by - 0.16), (bx + 0.13, by + 0.17)], False)), 0.075)
        else:
            def two(c):
                c.move_to(*P(bx + 0.03, by - 0.08))
                curve(c, (bx + 0.05, by - 0.20), (bx + 0.24, by - 0.20), (bx + 0.24, by - 0.07),
                      (bx + 0.24, by + 0.03), (bx + 0.10, by + 0.08), (bx + 0.03, by + 0.16))
                c.line_to(*P(bx + 0.25, by + 0.16))
            g.ink(two, 0.07)
    elif kind == "plus":
        g.ink(lambda c: (poly(c, [(bx - 0.18, by), (bx + 0.18, by)], False), poly(c, [(bx, by - 0.18), (bx, by + 0.18)], False)), 0.09)
    elif kind == "clock":
        g.ink(lambda c: circle(c, bx, by, 0.22), 0.06)
        g.ink(lambda c: poly(c, [(bx, by - 0.14), (bx, by), (bx + 0.11, by + 0.06)], False), 0.06)
    elif kind == "ring":
        g.ink(lambda c: circle(c, bx, by, 0.22), 0.05)
        g.ink(lambda c: circle(c, bx, by, 0.10), 0.05)
    elif kind == "up2":
        chev = lambda c: (poly(c, [(bx - 0.17, by + 0.02), (bx, by - 0.14), (bx + 0.17, by + 0.02)], False),
                          poly(c, [(bx - 0.17, by + 0.17), (bx, by + 0.01), (bx + 0.17, by + 0.17)], False))
        g.ink(chev, 0.075)


def burst(g, x=0.0, y=0.0, r=1.0, n=10, inner=0.62, tone=MAIN):
    pts = star_pts(x, y, r, inner, n, -90)
    g.fill(lambda c: poly(c, pts), tone)


def talisman(g, sym):
    pts = [(-0.48, -0.96), (0.48, -0.96), (0.48, 0.62), (0.0, 0.98), (-0.48, 0.62)]
    g.fill(lambda c: poly(c, pts))
    g.ink(lambda c: poly(c, [(-0.34, -0.80), (0.34, -0.80)], False), 0.05)
    g.ink(lambda c: poly(c, [(-0.34, 0.50), (0.34, 0.50)], False), 0.05)
    if sym == "snow":
        def flake(c):
            for k in range(3):
                a = math.radians(90 + 60 * k)
                c.move_to(*P(math.cos(a) * 0.30, -0.14 + math.sin(a) * 0.30))
                c.line_to(*P(-math.cos(a) * 0.30, -0.14 - math.sin(a) * 0.30))
        g.ink(flake, 0.085)
    else:
        g.ink(lambda c: flame_path(c, 0.0, -0.14, 0.36))


def g_fury_edge(g):
    claws(g)


def g_fury_heavy(g):
    g.stroke(lambda c: poly(c, [(0, 0.98), (0, 0.10)], False), 0.20, SUB, cairo.LINE_CAP_BUTT)
    g.fill(lambda c: rrect(c, -0.30, 0.04, 0.30, 0.26, 0.06), SUB)
    head = [(0, -1.0), (0.66, 0.06), (0.30, 0.0), (0, 0.16), (-0.30, 0.0), (-0.66, 0.06)]
    g.layer()
    g.fill(lambda c: poly(c, head))
    g.ink(lambda c: poly(c, [(0, -0.80), (0, 0.04)], False), 0.05)


def g_fury_first(g):
    burst(g, 0.0, -0.05, 0.98, 12, 0.60, PALE)
    g.layer()
    sword(g, (-0.72, 0.78), (0.70, -0.74), 0.12, 0.32)


def g_fury_blaze(g):
    flame(g, 0.0, 0.04, 0.98, False)
    g.layer()
    claws(g)


def g_fury_over(g):
    g.fill(lambda c: (circle(c, 0, -0.18, 0.74)))
    g.fill(lambda c: rrect(c, -0.40, 0.30, 0.40, 0.88, 0.12))
    g.ink(lambda c: (circle(c, -0.28, -0.14, 0.20), circle(c, 0.28, -0.14, 0.20)))
    g.ink(lambda c: poly(c, [(0, 0.14), (0.09, 0.32), (-0.09, 0.32)]))
    g.ink(lambda c: (poly(c, [(-0.16, 0.58), (-0.16, 0.86)], False), poly(c, [(0.0, 0.58), (0.0, 0.86)], False), poly(c, [(0.16, 0.58), (0.16, 0.86)], False)), 0.05)
    g.ink(lambda c: poly(c, [(0.30, -0.90), (0.16, -0.66), (0.32, -0.52), (0.18, -0.36)], False), 0.06)
    g.layer()
    g.fill(lambda c: poly(c, star_pts(0.66, -0.70, 0.34, 0.32, 4, -45)), PALE)


def g_fury_giant(g):
    pts = [(-0.80, 0.50), (-0.86, -0.38), (-0.40, 0.02), (0, -0.62), (0.40, 0.02), (0.86, -0.38), (0.80, 0.50)]
    g.fill(lambda c: poly(c, pts))
    g.fill(lambda c: rrect(c, -0.82, 0.42, 0.82, 0.74, 0.06), SUB)
    g.fill(lambda c: (circle(c, -0.86, -0.42, 0.11), circle(c, 0, -0.66, 0.12), circle(c, 0.86, -0.42, 0.11)))
    g.layer()
    sword(g, (0.80, 0.98), (-0.30, -0.98), 0.09, 0.24, False)


def g_fury_wrath(g):
    flame(g, 0, 0.0, 1.0, False)
    g.layer()
    sword(g, (-0.66, 0.80), (0.62, -0.80), 0.10, 0.28, False)
    sword(g, (0.66, 0.80), (-0.62, -0.80), 0.10, 0.28, False)


def g_tempo_quick(g):
    for k, (y, x0) in enumerate([(-0.42, -0.98), (0.0, -1.0), (0.42, -0.98)]):
        g.stroke(lambda c, y=y, x0=x0: poly(c, [(x0, y), (x0 + 0.42, y)], False), 0.10, PALE)
    arrow(g, (-0.46, 0.36), (0.94, -0.36), 0.11, 0.34)


def g_tempo_repeat(g):
    gear(g, -0.16, 0.18, 0.74, 8, 0.30)
    g.layer()
    for k, off in enumerate((-0.30, 0.0, 0.30)):
        arrow(g, (-0.10, 0.10 + off), (0.98, -0.30 + off), 0.075, 0.22, False)


def g_tempo_feet(g):
    boot = [(-0.40, -0.96), (0.16, -0.96), (0.18, 0.18), (0.76, 0.38), (0.86, 0.62), (0.84, 0.88), (-0.44, 0.88), (-0.46, 0.20)]
    for y, x0 in [(-0.50, -1.02), (-0.10, -1.04), (0.30, -1.02)]:
        g.stroke(lambda c, y=y, x0=x0: poly(c, [(x0, y), (x0 + 0.34, y)], False), 0.10, PALE)
    g.fill(lambda c: poly(c, boot))
    g.fill(lambda c: rrect(c, -0.48, -1.02, 0.20, -0.74, 0.06), SUB)
    g.ink(lambda c: poly(c, [(-0.44, 0.66), (0.84, 0.66)], False), 0.05)


def g_tempo_rush(g):
    chevrons(g, 3, 0.0, 0.0, 1.0, 0.22, False)


def g_tempo_rage(g):
    glass = [(-0.50, -0.74), (0.50, -0.74), (0.08, 0.0), (0.50, 0.74), (-0.50, 0.74), (-0.08, 0.0)]
    g.fill(lambda c: poly(c, glass), PALE)
    g.fill(lambda c: poly(c, [(-0.30, 0.74), (0.30, 0.74), (0.0, 0.34)]), SUB)
    g.layer()
    g.fill(lambda c: rrect(c, -0.66, -0.98, 0.66, -0.74, 0.08))
    g.fill(lambda c: rrect(c, -0.66, 0.74, 0.66, 0.98, 0.08))
    g.layer()
    flame(g, 0.0, -0.28, 0.44, False)


def g_tempo_surge(g):
    g.fill(lambda c: (rrect(c, -0.22, -1.0, 0.22, 0.40, 0.22), circle(c, 0, 0.62, 0.36)))
    g.ink(lambda c: poly(c, [(0, -0.70), (0, 0.50)], False), 0.13)
    g.ink(lambda c: circle(c, 0, 0.62, 0.20))
    for k in range(3):
        g.ink(lambda c, k=k: poly(c, [(0.24, -0.62 + k * 0.30), (0.40, -0.62 + k * 0.30)], False), 0.05)
    g.layer()
    flame(g, 0.62, -0.38, 0.36, False)


def g_tempo_storm(g):
    rows = [(-0.82, 0.98, 0.00), (-0.44, 0.80, 0.12), (-0.06, 0.62, -0.04), (0.30, 0.46, 0.10), (0.64, 0.30, 0.00), (0.92, 0.14, 0.06)]
    for y, w, dx in rows:
        g.stroke(lambda c, y=y, w=w, dx=dx: (c.move_to(*P(dx - w, y - 0.04)), curve(c, (dx - w * 0.5, y + 0.10), (dx + w * 0.5, y + 0.10), (dx + w, y - 0.04))), 0.17)
    g.layer()
    g.fill(lambda c: poly(c, star_pts(0.66, -0.56, 0.30, 0.45)), PALE)


def g_prec_aim(g):
    eye(g, 0, 0.02, 1.0)


def g_prec_scope(g):
    reticle(g, 0, 0, 1.0)


def g_prec_edge(g):
    blade = [(0.0, -1.0), (0.24, -0.50), (0.18, 0.30), (-0.18, 0.30), (-0.24, -0.50)]
    g.fill(lambda c: poly(c, blade))
    g.ink(lambda c: poly(c, [(0, -0.78), (0, 0.24)], False), 0.045)
    g.layer()
    g.fill(lambda c: rrect(c, -0.40, 0.28, 0.40, 0.44, 0.06))
    g.fill(lambda c: rrect(c, -0.10, 0.44, 0.10, 0.90, 0.05), SUB)
    g.layer()
    g.fill(lambda c: poly(c, star_pts(0.52, -0.56, 0.36, 0.25, 4)), PALE)


def g_prec_deadly(g):
    burst(g, 0, 0, 1.0, 9, 0.62)
    g.ink(lambda c: rrect(c, -0.09, -0.48, 0.09, 0.14, 0.06))
    g.ink(lambda c: circle(c, 0, 0.34, 0.10))
    badge(g, "up2")


def g_prec_heads(g):
    g.stroke(lambda c: poly(c, [(-0.80, 0.94), (0.42, -0.62)], False), 0.14, SUB)
    g.layer()

    def blade(c):
        c.move_to(*P(0.10, -0.86))
        curve(c, (0.62, -1.02), (1.02, -0.56), (0.96, -0.02))
        curve(c, (0.66, -0.20), (0.44, -0.20), (0.26, -0.34))
        c.close_path()
    g.fill(blade)
    g.light(lambda c: (c.move_to(*P(0.30, -0.80)), curve(c, (0.62, -0.88), (0.86, -0.56), (0.86, -0.20))), 0.06, 0.8)


def g_prec_hawk(g):
    def head(c):
        c.move_to(*P(-0.72, 0.96))
        curve(c, (-0.86, 0.20), (-0.70, -0.62), (-0.10, -0.80))
        curve(c, (0.30, -0.90), (0.62, -0.66), (0.70, -0.40))
        curve(c, (0.90, -0.34), (1.02, -0.10), (0.92, 0.18))
        curve(c, (0.84, 0.06), (0.74, 0.00), (0.56, 0.02))
        curve(c, (0.46, 0.30), (0.30, 0.58), (0.20, 0.96))
        c.close_path()
    g.fill(head)
    g.fill(lambda c: (c.move_to(*P(0.56, 0.02)), curve(c, (0.62, -0.10), (0.68, -0.30), (0.70, -0.40)),
                      curve(c, (0.90, -0.34), (1.02, -0.10), (0.92, 0.18)), curve(c, (0.84, 0.06), (0.74, 0.0), (0.56, 0.02)), c.close_path()), SUB)
    g.ink(lambda c: circle(c, 0.20, -0.38, 0.12))
    g.ink(lambda c: (c.move_to(*P(-0.06, -0.52)), curve(c, (0.10, -0.62), (0.30, -0.60), (0.46, -0.48))), 0.06)
    g.ink(lambda c: (c.move_to(*P(-0.50, 0.10)), curve(c, (-0.36, 0.30), (-0.30, 0.56), (-0.32, 0.86))), 0.045)


def g_elem_fire(g):
    flame(g)


def g_elem_ice(g):
    snowflake(g)


def g_elem_elec(g):
    bolt(g)


def g_elem_water(g):
    drop(g)


def g_elem_none(g):
    outer = [(0, -1.0), (0.66, -0.30), (0, 1.0), (-0.66, -0.30)]
    g.fill(lambda c: poly(c, outer))
    g.fill(lambda c: poly(c, [(0, -1.0), (0.66, -0.30), (0, 1.0), (0.16, -0.30)]), SUB)
    g.ink(lambda c: poly(c, [(-0.66, -0.30), (0.66, -0.30)], False), 0.04)
    g.ink(lambda c: poly(c, [(0, -1.0), (-0.16, -0.30), (0, 1.0)], False), 0.035)
    g.light(lambda c: poly(c, [(-0.46, -0.40), (-0.12, -0.80)], False), 0.07)


def g_st_frost(g):
    talisman(g, "snow")


def g_st_flame(g):
    talisman(g, "fire")


def g_st_deepfrost(g):
    shards = [[(-0.62, 0.92), (-0.86, 0.10), (-0.52, -0.40), (-0.30, 0.92)],
              [(0.30, 0.92), (0.58, -0.30), (0.86, 0.20), (0.66, 0.92)],
              [(-0.34, 0.94), (-0.20, -0.30), (0.02, -1.0), (0.22, -0.30), (0.36, 0.94)]]
    for k, sh in enumerate(shards):
        g.fill(lambda c, sh=sh: poly(c, sh), SUB if k < 2 else MAIN)
        g.layer()
    g.ink(lambda c: poly(c, [(0.02, -0.80), (0.02, 0.86)], False), 0.04)


def g_st_inferno(g):
    flame(g, -0.32, 0.18, 0.66, False)
    g.layer()
    flame(g, 0.20, -0.02, 0.92)


def g_st_shock(g):
    g.stroke(lambda c: circle(c, 0, 0, 0.84), 0.10, PALE)
    for a in (30, 150, 270):
        rr = math.radians(a)
        g.fill(lambda c, rr=rr: poly(c, star_pts(math.cos(rr) * 0.84, math.sin(rr) * 0.84, 0.22, 0.40, 4)), PALE)
    g.layer()
    bolt(g, 0.02, 0.0, 0.72)


def g_st_tide(g):
    def wave(c):
        c.move_to(*P(-1.0, 0.92))
        c.line_to(*P(-1.0, 0.30))
        curve(c, (-0.70, -0.10), (-0.30, -0.70), (0.30, -0.82), (0.86, -0.92), (1.02, -0.50), (0.84, -0.20),
              (0.70, -0.50), (0.40, -0.52), (0.26, -0.30), (0.10, 0.0), (0.40, 0.40), (1.0, 0.36))
        c.line_to(*P(1.0, 0.92))
        c.close_path()
    g.fill(wave)
    g.fill(lambda c: (c.move_to(*P(-1.0, 0.92)), c.line_to(*P(-1.0, 0.60)), curve(c, (-0.40, 0.50), (0.30, 0.74), (1.0, 0.56)),
                      c.line_to(*P(1.0, 0.92)), c.close_path()), SUB)


def g_st_bolt(g):
    def cloud(c):
        circle(c, -0.40, -0.40, 0.36)
        circle(c, 0.06, -0.56, 0.44)
        circle(c, 0.50, -0.36, 0.34)
        rrect(c, -0.76, -0.40, 0.84, -0.04, 0.18)
    g.fill(cloud, PALE)
    g.layer()
    bolt(g, -0.30, 0.42, 0.56)
    bolt(g, 0.40, 0.48, 0.48)


def g_st_chain(g):
    def links(c):
        for k, (x, y) in enumerate([(-0.48, 0.44), (0.0, 0.0), (0.48, -0.44)]):
            c.save()
            pts = rotated([(-0.40, -0.20), (0.40, -0.20), (0.40, 0.20), (-0.40, 0.20)], -42)
            c.restore()
            cx, cy = P(x, y)
            c.save()
            c.translate(cx, cy)
            c.rotate(math.radians(-42))
            c.scale(0.44 * U, 0.24 * U)
            c.new_sub_path()
            c.arc(0, 0, 1.0, 0, math.tau)
            c.restore()
    g.stroke(links, 0.13, PALE)
    g.layer()
    bolt(g, 0.0, 0.0, 0.60)


def g_st_wild(g):
    flame(g, -0.56, 0.32, 0.46, False)
    flame(g, 0.56, 0.32, 0.46, False)
    g.layer()
    flame(g, 0.0, -0.06, 0.74)


def g_st_reson(g):
    g.stroke(lambda c: (poly(c, [(-0.30, -0.98), (-0.30, -0.10)], False), arc(c, 0, -0.10, 0.30, 180, 0, True),
                        poly(c, [(0.30, -0.10), (0.30, -0.98)], False)), 0.16)
    g.stroke(lambda c: poly(c, [(0, 0.20), (0, 0.96)], False), 0.17, SUB)
    for k in (-1, 1):
        g.stroke(lambda c, k=k: arc(c, 0, -0.56, 0.62, -30 if k > 0 else 150, 30 if k > 0 else 210), 0.08, PALE)
        g.stroke(lambda c, k=k: arc(c, 0, -0.56, 0.86, -26 if k > 0 else 154, 26 if k > 0 else 206), 0.07, PALE)


def g_st_anti(g):
    def left(c):
        c.move_to(*P(-0.08, -0.92))
        curve(c, (-0.30, -0.78), (-0.60, -0.80), (-0.80, -0.74), (-0.82, -0.10), (-0.62, 0.52), (-0.08, 0.96))
        poly(c, [(-0.08, 0.96), (0.06, 0.40), (-0.12, 0.06), (0.06, -0.30), (-0.08, -0.92)], False)
        c.close_path()

    def right(c):
        c.move_to(*P(0.10, -0.92))
        curve(c, (0.30, -0.78), (0.60, -0.80), (0.80, -0.74), (0.82, -0.10), (0.62, 0.52), (0.10, 0.96))
        poly(c, [(0.10, 0.96), (0.24, 0.40), (0.06, 0.06), (0.24, -0.30), (0.10, -0.92)], False)
        c.close_path()
    g.fill(left)
    c_off = 0.12
    g.fill(lambda c: (c.save(), c.translate(c_off * U, 0.06 * U), right(c), c.restore()), SUB)


def g_arms_sword(g):
    g.stroke(lambda c: arc(c, -0.12, 0.10, 0.86, 200, 290), 0.08, PALE)
    sword(g, (-0.66, 0.80), (0.74, -0.80), 0.12, 0.34)


def g_arms_gun(g):
    body = [(-0.96, -0.40), (0.90, -0.40), (0.90, -0.10), (-0.10, -0.10), (-0.26, 0.10), (-0.40, 0.86), (-0.86, 0.86), (-0.70, 0.04), (-0.96, -0.06)]
    g.fill(lambda c: poly(c, body))
    g.fill(lambda c: rrect(c, 0.10, -0.56, 0.96, -0.24, 0.05), SUB)
    g.ink(lambda c: (c.move_to(*P(-0.26, 0.10)), curve(c, (-0.18, 0.36), (0.04, 0.36), (0.04, 0.10))), 0.06)
    g.ink(lambda c: poly(c, [(-0.80, -0.26), (0.80, -0.26)], False), 0.04)


def g_arms_bow(g):
    g.ink(lambda c: poly(c, [(-0.34, -0.94), (-0.34, 0.94)], False), 0.04)
    g.stroke(lambda c: (c.move_to(*P(-0.34, -0.96)), curve(c, (0.40, -0.80), (0.70, -0.30), (0.70, 0.0),
                                                            (0.70, 0.30), (0.40, 0.80), (-0.34, 0.96))), 0.16)
    g.layer()
    arrow(g, (-0.96, 0.0), (0.98, 0.0), 0.08, 0.26)


def g_arms_whip(g):
    g.stroke(lambda c: (c.move_to(*P(-0.50, 0.30)), curve(c, (0.40, -0.30), (1.0, 0.10), (0.70, 0.60),
                                                           (0.46, 0.96), (-0.30, 0.80), (-0.10, 0.40),
                                                           (0.08, 0.04), (0.60, -0.10), (0.94, -0.56))), 0.10)
    g.layer()
    g.stroke(lambda c: poly(c, [(-0.96, 0.92), (-0.48, 0.30)], False), 0.20, SUB)
    g.fill(lambda c: circle(c, -0.98, 0.96, 0.11))


def g_arms_deck(g):
    card(g, -0.40, 0.10, -18, 1.0, SUB, False)
    g.layer()
    card(g, 0.40, 0.10, 18, 1.0, SUB, False)
    g.layer()
    card(g, 0.0, -0.06, 0, 1.06)


def g_arms_reach(g):
    g.fill(lambda c: slash(c, (0.83, -0.21), (0.19, -0.85), 0.14, 0.24), PALE)
    g.fill(lambda c: slash(c, (1.02, -0.50), (0.49, -1.03), 0.12, 0.17), PALE)
    g.layer()
    sword(g, (-0.86, 0.84), (0.30, -0.32), 0.11, 0.30)

def g_arms_pierce(g):
    g.fill(lambda c: (circle(c, 0.06, 0, 0.62), circle(c, 0.06, 0, 0.36, True)), SUB)
    g.ink(lambda c: circle(c, 0.06, 0, 0.14))
    g.layer()
    arrow(g, (-0.98, 0.42), (0.98, -0.42), 0.09, 0.28)


def g_arms_split(g):
    g.fill(lambda c: (c.move_to(*P(-0.98, 0.24)), c.line_to(*P(-0.30, 0.24)), curve(c, (0.0, 0.24), (0.14, 0.10), (0.14, 0.0)),
                      curve(c, (0.14, -0.10), (0.0, -0.24), (-0.30, -0.24)), c.line_to(*P(-0.98, -0.24)), c.close_path()))
    g.ink(lambda c: poly(c, [(-0.74, -0.24), (-0.74, 0.24)], False), 0.05)
    g.layer()
    for (x, y, s) in [(0.58, -0.52, 0.22), (0.74, 0.06, 0.20), (0.50, 0.58, 0.18)]:
        g.fill(lambda c, x=x, y=y, s=s: poly(c, star_pts(x, y, s * 1.4, 0.45, 4, 15)))
    burst(g, 0.30, 0.0, 0.28, 8, 0.5, PALE)


def g_arms_mortar(g):
    barrel = moved(rotated([(-0.56, -0.28), (0.50, -0.34), (0.50, 0.34), (-0.56, 0.28)], -38), -0.16, 0.10)
    g.fill(lambda c: poly(c, barrel))
    muzzle = moved(rotated([(0.42, -0.40), (0.62, -0.40), (0.62, 0.40), (0.42, 0.40)], -38), -0.16, 0.10)
    g.fill(lambda c: poly(c, muzzle), SUB)
    g.layer()
    g.fill(lambda c: (c.move_to(*P(-0.92, 0.92)), arc(c, -0.30, 0.92, 0.62, 180, 360), c.close_path()), SUB)
    g.fill(lambda c: circle(c, -0.30, 0.66, 0.16))
    g.layer()
    g.fill(lambda c: circle(c, 0.82, -0.84, 0.19))
    for k in range(2):
        g.stroke(lambda c, k=k: poly(c, [(0.40 + k * 0.14, -0.40 - k * 0.14 + 0.06), (0.56 + k * 0.14, -0.56 - k * 0.14 + 0.06)], False), 0.07, PALE)


def g_arms_zone(g):
    g.stroke(lambda c: circle(c, 0, 0, 0.30), 0.12)
    g.stroke(lambda c: circle(c, 0, 0, 0.64), 0.10, PALE)
    for k in range(4):
        a = math.radians(45 + 90 * k)
        tip = (math.cos(a) * 1.02, math.sin(a) * 1.02)
        b = (math.cos(a) * 0.80, math.sin(a) * 0.80)
        n = (-math.sin(a) * 0.16, math.cos(a) * 0.16)
        g.fill(lambda c, tip=tip, b=b, n=n: poly(c, [tip, (b[0] + n[0], b[1] + n[1]), (b[0] - n[0], b[1] - n[1])]))


def g_arms_bounce(g):
    g.stroke(lambda c: poly(c, [(-0.96, -0.10), (-0.56, 0.62), (-0.10, -0.30), (0.26, 0.40)], False), 0.08, PALE)
    g.layer()
    g.fill(lambda c: poly(c, star_pts(0.46, -0.22, 0.56, 0.45, 5, -80)))


def g_arms_air(g):
    g.stroke(lambda c: circle(c, 0, 0, 0.84), 0.13)
    g.layer()
    arrow(g, (0, 0.62), (0, -0.66), 0.12, 0.32, False)
    g.fill(lambda c: poly(c, [(-0.40, 0.62), (0.40, 0.62), (0.22, 0.46), (-0.22, 0.46)]), SUB)


def g_arms_down(g):
    def wing(c):
        c.move_to(*P(-0.96, -0.56))
        curve(c, (-0.40, -0.92), (0.30, -0.80), (0.90, -0.30))
        curve(c, (0.50, -0.30), (0.10, -0.22), (-0.10, 0.0))
        curve(c, (-0.40, -0.14), (-0.70, -0.30), (-0.96, -0.56))
        c.close_path()
    g.fill(wing, PALE)
    g.ink(lambda c: (c.move_to(*P(-0.60, -0.56)), curve(c, (-0.20, -0.62), (0.20, -0.54), (0.50, -0.36))), 0.04)
    g.layer()
    arrow(g, (0.30, -0.40), (0.30, 0.98), 0.11, 0.30, False)


def g_guard_hp(g):
    crystal(g, -0.12, 0.0, 0.92)
    badge(g, "plus")


def g_guard_mend(g):
    crystal(g, 0.0, 0.02, 0.74)
    g.layer()
    g.stroke(lambda c: arc(c, 0, 0.02, 0.92, 120, 400), 0.11, PALE, cairo.LINE_CAP_BUTT)
    a = math.radians(40)
    tip = (math.cos(a) * 0.92, 0.02 + math.sin(a) * 0.92)
    g.fill(lambda c: poly(c, [(tip[0] + 0.24, tip[1] - 0.10), (tip[0] - 0.14, tip[1] - 0.22), (tip[0] - 0.02, tip[1] + 0.20)]), PALE)


def g_guard_mire(g):
    g.fill(lambda c: (c.move_to(*P(-0.96, 0.84)), curve(c, (-0.92, 0.50), (-0.40, 0.40), (0.10, 0.48), (0.60, 0.36), (0.98, 0.50), (0.98, 0.84)), c.close_path()), SUB)
    g.layer()

    def body(c):
        c.move_to(*P(-0.80, 0.60))
        curve(c, (-0.70, 0.30), (0.20, 0.34), (0.66, 0.30))
        curve(c, (0.84, 0.10), (0.86, -0.14), (0.78, -0.30))
        curve(c, (0.92, 0.0), (0.98, 0.40), (0.80, 0.60))
        c.close_path()
    g.fill(body, PALE)
    g.ink(lambda c: (poly(c, [(0.76, -0.24), (0.66, -0.62)], False), poly(c, [(0.84, -0.20), (0.96, -0.56)], False)), 0.05)
    g.ink(lambda c: (circle(c, 0.66, -0.66, 0.06), circle(c, 0.97, -0.60, 0.06)))
    g.layer()
    g.fill(lambda c: circle(c, -0.14, -0.06, 0.58))

    def spiral(c):
        c.move_to(*P(-0.14, -0.06))
        for k in range(1, 40):
            t = k / 39
            a = t * math.tau * 1.6
            r = 0.06 + t * 0.40
            c.line_to(*P(-0.14 + math.cos(a) * r, -0.06 + math.sin(a) * r))
    g.ink(spiral, 0.05)


def g_guard_bul(g):
    g.fill(lambda c: shield_path(c, 0, 0.02, 1.0))
    g.layer()
    crystal(g, 0, 0.04, 0.50)


def g_guard_calm(g):
    g.stroke(lambda c: (c.move_to(*P(0, -0.98)), c.line_to(*P(0, -0.74))), 0.08, SUB)
    g.fill(lambda c: circle(c, 0, -0.98, 0.10), SUB)
    g.layer()
    g.fill(lambda c: circle(c, 0, 0.12, 0.84))
    g.fill(lambda c: circle(c, 0, 0.12, 0.58), SUB)
    g.fill(lambda c: circle(c, 0, 0.12, 0.34), PALE)
    g.ink(lambda c: circle(c, 0, 0.12, 0.16))
    g.light(lambda c: arc(c, 0, 0.12, 0.72, 200, 280), 0.07)


def g_guard_now(g):
    def heart(c):
        c.move_to(*P(0, 0.94))
        curve(c, (-0.50, 0.56), (-1.0, 0.16), (-0.94, -0.30), (-0.88, -0.76), (-0.30, -0.92), (0, -0.50),
              (0.30, -0.92), (0.88, -0.76), (0.94, -0.30), (1.0, 0.16), (0.50, 0.56), (0, 0.94))
        c.close_path()
    g.fill(heart)
    g.ink(lambda c: (rrect(c, -0.12, -0.42, 0.12, 0.30, 0.04), rrect(c, -0.36, -0.18, 0.36, 0.06, 0.04)))
    g.light(lambda c: arc(c, -0.48, -0.36, 0.30, 190, 260), 0.07)


def g_guard_wall(g):
    tower = [(-0.62, 0.96), (-0.54, -0.40), (-0.70, -0.40), (-0.70, -0.92), (-0.42, -0.92), (-0.42, -0.70), (-0.14, -0.70),
             (-0.14, -0.92), (0.14, -0.92), (0.14, -0.70), (0.42, -0.70), (0.42, -0.92), (0.70, -0.92), (0.70, -0.40),
             (0.54, -0.40), (0.62, 0.96)]
    g.fill(lambda c: poly(c, tower))
    g.fill(lambda c: rrect(c, -0.70, -0.46, 0.70, -0.32, 0.03), SUB)
    g.ink(lambda c: (c.move_to(*P(-0.22, 0.96)), c.line_to(*P(-0.22, 0.52)), arc(c, 0, 0.52, 0.22, 180, 360), c.line_to(*P(0.22, 0.96)), c.close_path()))
    g.ink(lambda c: poly(c, star_pts(0, -0.06, 0.24, 0.45)))


def meteor(g, x=0.0, y=0.0, s=1.0):
    for (o, w, ln) in [(-0.24, 0.12, 0.96), (0.0, 0.17, 1.24), (0.24, 0.12, 0.90)]:
        ang = math.radians(135)
        dx, dy = math.cos(ang), math.sin(ang)
        px, py = -dy, dx
        sx, sy = x + 0.26 * s + px * o * s, y - 0.26 * s + py * o * s
        g.fill(lambda c, sx=sx, sy=sy, px=px, py=py, dx=dx, dy=dy, w=w, ln=ln:
               poly(c, [(sx + px * w * s, sy + py * w * s), (sx + dx * ln * s, sy + dy * ln * s), (sx - px * w * s, sy - py * w * s)]), SUB)
    g.layer()
    burst(g, x + 0.30 * s, y - 0.30 * s, 0.62 * s, 9, 0.78, PALE)
    g.layer()
    rock = [(x + 0.30 * s + math.cos(math.radians(a)) * r * s, y - 0.30 * s + math.sin(math.radians(a)) * r * s)
            for a, r in [(0, 0.44), (45, 0.40), (90, 0.45), (135, 0.41), (180, 0.44), (225, 0.40), (270, 0.45), (315, 0.42)]]
    g.fill(lambda c: poly(c, rock))
    g.ink(lambda c: (circle(c, x + 0.42 * s, y - 0.42 * s, 0.10 * s), circle(c, x + 0.18 * s, y - 0.20 * s, 0.07 * s), circle(c, x + 0.44 * s, y - 0.14 * s, 0.05 * s)))
    g.light(lambda c: arc(c, x + 0.30 * s, y - 0.30 * s, 0.32 * s, 200, 270), 0.07)


def dome(g, x=0.0, y=0.0, s=1.0, thick=False):
    g.fill(lambda c: (c.move_to(*P(x - 0.92 * s, y + 0.52 * s)), arc(c, x, y + 0.52 * s, 0.92 * s, 180, 360), c.close_path()), PALE)
    if thick:
        g.fill(lambda c: (c.move_to(*P(x - 0.62 * s, y + 0.52 * s)), arc(c, x, y + 0.52 * s, 0.62 * s, 180, 360), c.close_path()), SUB)
    g.layer()
    g.fill(lambda c: rrect(c, x - 1.0 * s, y + 0.48 * s, x + 1.0 * s, y + 0.76 * s, 0.06))
    g.light(lambda c: arc(c, x, y + 0.52 * s, 0.76 * s, 200, 250), 0.08)


def g_star_meteor(g):
    meteor(g, 0.04, 0.04, 1.06)


def g_star_wide(g):
    g.stroke(lambda c: (c.save(), c.translate(*P(-0.14, 0.62)), c.scale(1.0, 0.36), c.new_sub_path(), c.arc(0, 0, 0.84 * U, 0, math.tau), c.restore()), 0.08, PALE)
    g.layer()
    meteor(g, 0.10, -0.12, 0.84)


def g_star_frost(g):
    snowflake(g, -0.10, -0.08, 0.84)
    badge(g, "clock")


def g_star_ward(g):
    g.fill(lambda c: circle(c, 0, 0, 0.94), PALE)
    g.fill(lambda c: circle(c, 0, 0, 0.70), SUB)
    g.layer()
    crystal(g, 0, 0.02, 0.56)
    g.light(lambda c: arc(c, 0, 0, 0.82, 200, 270), 0.09, 0.9)


def g_star_quick(g):
    g.stroke(lambda c: arc(c, 0, 0, 0.88, -60, 230), 0.11, PALE, cairo.LINE_CAP_BUTT)
    a = math.radians(-60)
    tip = (math.cos(a) * 0.88, math.sin(a) * 0.88)
    g.fill(lambda c: poly(c, [(tip[0] + 0.02, tip[1] - 0.26), (tip[0] + 0.26, tip[1] + 0.16), (tip[0] - 0.22, tip[1] + 0.08)]), PALE)
    g.layer()
    g.fill(lambda c: poly(c, star_pts(0, 0.04, 0.58, 0.45)))


def g_star_more_blast(g):
    meteor(g, -0.04, 0.0, 0.92)
    badge(g, "+1")


def g_star_more_freeze(g):
    snowflake(g, -0.10, -0.08, 0.84)
    badge(g, "+1")


def g_star_more_ward(g):
    g.fill(lambda c: circle(c, -0.08, -0.08, 0.86), PALE)
    g.fill(lambda c: circle(c, -0.08, -0.08, 0.64), SUB)
    g.layer()
    crystal(g, -0.08, -0.06, 0.50)
    g.light(lambda c: arc(c, -0.08, -0.08, 0.75, 200, 270), 0.09, 0.9)
    badge(g, "+1")

def g_star_bless(g):
    burst(g, 0, 0.08, 1.0, 12, 0.72, PALE)
    g.layer()
    for (x, y, r) in [(0, -0.36, 0.40), (-0.42, 0.34, 0.34), (0.42, 0.34, 0.34)]:
        g.fill(lambda c, x=x, y=y, r=r: poly(c, star_pts(x, y, r, 0.45)))


def g_fate_gold(g):
    coin(g, 0, 0, 1.0, "star")


def g_fate_midas(g):
    for k, y in enumerate([0.64, 0.38, 0.12]):
        g.fill(lambda c, y=y: (c.save(), c.translate(*P(-0.18, y)), c.scale(1.0, 0.42), c.new_sub_path(), c.arc(0, 0, 0.72 * U, 0, math.tau), c.restore()), SUB if k < 2 else MAIN)
        g.layer()
    coin(g, 0.40, -0.40, 0.56, "star")


def g_fate_insight(g):
    g.fill(lambda c: poly(c, [(0, 0.88), (-0.96, 0.66), (-0.96, -0.30), (0, -0.10)]))
    g.fill(lambda c: poly(c, [(0, 0.88), (0.96, 0.66), (0.96, -0.30), (0, -0.10)]), PALE)
    g.ink(lambda c: poly(c, [(0, -0.10), (0, 0.88)], False), 0.05)
    for k in range(3):
        g.ink(lambda c, k=k: (poly(c, [(-0.78, 0.04 + k * 0.20), (-0.18, 0.16 + k * 0.20)], False), poly(c, [(0.18, 0.16 + k * 0.20), (0.78, 0.04 + k * 0.20)], False)), 0.04)
    g.layer()
    g.fill(lambda c: poly(c, star_pts(0, -0.62, 0.36, 0.42)))


def g_fate_bond(g):
    g.stroke(lambda c: circle(c, -0.34, 0.06, 0.52), 0.15)
    g.layer()
    g.stroke(lambda c: circle(c, 0.34, 0.06, 0.52), 0.15, PALE)
    g.layer()
    g.stroke(lambda c: arc(c, -0.34, 0.06, 0.52, -40, 20), 0.15, MAIN, cairo.LINE_CAP_BUTT)


def g_fate_growth(g):
    g.fill(lambda c: poly(c, star_pts(-0.36, 0.30, 0.46, 0.45)), PALE)
    g.fill(lambda c: poly(c, star_pts(0.30, -0.10, 0.60, 0.45)))
    g.layer()
    arrow(g, (0.66, 0.96), (0.66, 0.30), 0.10, 0.26, False)


def reroll(g, s=1.0):
    for k in (0, 1):
        a0, a1 = (200, 330) if k == 0 else (20, 150)
        g.stroke(lambda c, a0=a0, a1=a1: arc(c, 0, 0, 0.74 * s, a0, a1), 0.15 * s, MAIN, cairo.LINE_CAP_BUTT)
        a = math.radians(a1)
        tip = (math.cos(a) * 0.74 * s, math.sin(a) * 0.74 * s)
        tang = (-math.sin(a), math.cos(a))
        nrm = (math.cos(a), math.sin(a))
        g.fill(lambda c, tip=tip, tang=tang, nrm=nrm: poly(c, [(tip[0] + tang[0] * 0.32 * s, tip[1] + tang[1] * 0.32 * s),
                                                                (tip[0] + nrm[0] * 0.26 * s, tip[1] + nrm[1] * 0.26 * s),
                                                                (tip[0] - nrm[0] * 0.26 * s, tip[1] - nrm[1] * 0.26 * s)]))


def g_fate_reroll(g):
    reroll(g, 1.05)


def g_fate_deal(g):
    g.layer()
    reroll(g, 0.86)
    badge(g, "+2")


def g_fate_eye(g):
    d = rotated([(-0.70, -0.70), (0.70, -0.70), (0.70, 0.70), (-0.70, 0.70)], 12)
    g.fill(lambda c: rrect(c, -0.76, -0.76, 0.76, 0.76, 0.22))
    g.ink(lambda c: (circle(c, -0.40, -0.40, 0.11), circle(c, 0.40, 0.40, 0.11), circle(c, 0.40, -0.40, 0.11), circle(c, -0.40, 0.40, 0.11)))
    g.layer()
    eye(g, 0.0, 0.0, 0.46)


def g_fate_joker(g):
    for k, (tx, ty) in enumerate([(-0.86, -0.52), (0.0, -0.98), (0.86, -0.52)]):
        g.fill(lambda c, tx=tx, ty=ty: (c.move_to(*P(-0.60 if tx <= 0 else -0.10, 0.34)), curve(c, (tx * 0.6, -0.10), (tx * 0.8, ty * 0.6), (tx, ty)),
                                        curve(c, (tx * 0.5, ty * 0.3 + 0.10), (0.20 * (1 if tx >= 0 else -1), 0.0), (0.60 if tx >= 0 else 0.10, 0.34)),
                                        c.close_path()), MAIN if k == 1 else SUB)
    g.layer()
    g.fill(lambda c: rrect(c, -0.80, 0.30, 0.80, 0.62, 0.10))
    g.fill(lambda c: (circle(c, -0.86, -0.52, 0.13), circle(c, 0.0, -0.98, 0.13), circle(c, 0.86, -0.52, 0.13)), PALE)
    g.ink(lambda c: (poly(c, star_pts(-0.40, 0.46, 0.10, 0.45, 4)), poly(c, star_pts(0.0, 0.46, 0.10, 0.45, 4)), poly(c, star_pts(0.40, 0.46, 0.10, 0.45, 4))))


def g_fate_treasure(g):
    g.fill(lambda c: rrect(c, -0.92, -0.06, 0.92, 0.86, 0.08))
    g.fill(lambda c: (c.move_to(*P(-0.92, -0.02)), c.line_to(*P(-0.92, -0.40)), curve(c, (-0.92, -0.86), (0.92, -0.86), (0.92, -0.40)),
                      c.line_to(*P(0.92, -0.02)), c.close_path()), PALE)
    g.ink(lambda c: (poly(c, [(-0.92, -0.04), (0.92, -0.04)], False)), 0.05)
    g.layer()
    g.fill(lambda c: (rrect(c, -0.60, -0.70, -0.40, 0.86, 0.03), rrect(c, 0.40, -0.70, 0.60, 0.86, 0.03)), SUB)
    g.fill(lambda c: rrect(c, -0.20, -0.20, 0.20, 0.24, 0.06), SUB)
    g.ink(lambda c: circle(c, 0, 0.0, 0.07))


def g_fate_ascend(g):
    g.fill(lambda c: poly(c, [(-0.40, 0.98), (-0.40, 0.20), (-0.76, 0.20), (0, -0.40), (0.76, 0.20), (0.40, 0.20), (0.40, 0.98)]), PALE)
    g.layer()
    g.fill(lambda c: poly(c, star_pts(0, -0.50, 0.50, 0.45)))


GLYPHS = {name[2:]: fn for name, fn in globals().items() if name.startswith("g_") and callable(fn)}


def build(node_id: str) -> Glyph | None:
    fn = GLYPHS.get(node_id)
    if fn is None:
        return None
    g = Glyph()
    fn(g)
    return g
