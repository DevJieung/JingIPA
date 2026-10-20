#!/usr/bin/env python3
"""Constellation node art (2026-10-19, feedback F3 "a striking node design").

    python3 tools/talent_art.py                 # art/ui/talents/seal_atlas.png + <id>.png
    python3 tools/talent_art.py --sheet build/feedback-2026-10-19/D2/art_sheet.png

Drawn with cairo (vector, anti-aliased) and numpy/scipy (soft glows); no GPU is needed.
Everything except the gold parts is neutral (white, silver, ivory) so the game tints it
while drawing: a seal's face takes its constellation's colour, a locked node greys its
frame and glyph, a glow takes the colour of what it lights. The layout of the atlas is
mirrored by Constellation.CELL in game/constellation.gd (cell index -> what it holds);
change both together.

Atlas: 4 x 6 cells of 192 px. A seal sprite is centred in its cell and drawn for a face
radius of R_FACE px; the game scales it by (face radius on screen / R_FACE).
"""
from __future__ import annotations

import argparse
import math
from pathlib import Path

import cairo
import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "art/ui/talents"
CELL = 192
COLS, ROWS = 4, 7
R_FACE = 52.0          # face radius of every seal sprite (cells 0-6, 10-12)
R_SOFT = 40.0          # unit of the soft sprites (halo, rays, sparkle, dot)
R_RING = 64.0          # radius of the soft ring
R_EMBLEM = 74.0        # emblems fill this radius
R_THIN = 80.0          # radius of the crisp thin ring and the selection brackets
INK = (0.043, 0.075, 0.106)          # outline ink, the game's BG_DEEP family
SILVER = [(0.0, (1.0, 1.0, 1.0)), (0.42, (0.80, 0.85, 0.89)), (0.72, (0.52, 0.61, 0.68)), (1.0, (0.27, 0.34, 0.40))]
GOLD = [(0.0, (1.0, 0.97, 0.80)), (0.38, (0.98, 0.80, 0.38)), (0.70, (0.80, 0.53, 0.15)), (1.0, (0.45, 0.27, 0.05))]
GOLD_INK = (0.20, 0.11, 0.02)
LIGHT = (-0.55, -0.83)               # towards the light: up and a little left


# --------------------------------------------------------------------------- #
# Surfaces
# --------------------------------------------------------------------------- #
def surface(w: int = CELL, h: int = CELL):
    s = cairo.ImageSurface(cairo.FORMAT_ARGB32, w, h)
    c = cairo.Context(s)
    c.set_line_join(cairo.LINE_JOIN_ROUND)
    c.set_line_cap(cairo.LINE_CAP_ROUND)
    return s, c


def rgba(s) -> np.ndarray:
    """Straight-alpha float RGBA of a cairo surface."""
    w, h, stride = s.get_width(), s.get_height(), s.get_stride()
    raw = np.ndarray((h, stride // 4, 4), np.uint8, buffer=s.get_data())[:, :w, :].astype(np.float32) / 255.0
    a = raw[..., 3]
    out = np.zeros((h, w, 4), np.float32)
    safe = np.maximum(a, 1e-6)
    out[..., 0] = np.where(a > 0, raw[..., 2] / safe, 0)
    out[..., 1] = np.where(a > 0, raw[..., 1] / safe, 0)
    out[..., 2] = np.where(a > 0, raw[..., 0] / safe, 0)
    out[..., 3] = a
    return np.clip(out, 0, 1)


def over(dst: np.ndarray, src: np.ndarray) -> np.ndarray:
    sa = src[..., 3:4]
    da = dst[..., 3:4]
    oa = sa + da * (1 - sa)
    rgb = (src[..., :3] * sa + dst[..., :3] * da * (1 - sa)) / np.maximum(oa, 1e-6)
    return np.concatenate([np.where(oa > 0, rgb, 0), oa], axis=-1)


def soft(alpha: np.ndarray, rgb=(1.0, 1.0, 1.0)) -> np.ndarray:
    out = np.zeros(alpha.shape + (4,), np.float32)
    out[..., 0], out[..., 1], out[..., 2] = rgb
    out[..., 3] = np.clip(alpha, 0, 1)
    return out


def grid(size: int = CELL):
    y, x = np.mgrid[0:size, 0:size].astype(np.float32)
    return x + 0.5 - size / 2, y + 0.5 - size / 2


def ramp(stops, t: float):
    t = min(1.0, max(0.0, t))
    for (a, ca), (b, cb) in zip(stops, stops[1:]):
        if t <= b:
            k = (t - a) / max(1e-6, b - a)
            return tuple(ca[i] + (cb[i] - ca[i]) * k for i in range(3))
    return stops[-1][1]


def metal_gradient(stops, cx, cy, r):
    """Linear gradient across a disc of radius r, lit from LIGHT."""
    g = cairo.LinearGradient(cx + LIGHT[0] * r, cy + LIGHT[1] * r, cx - LIGHT[0] * r, cy - LIGHT[1] * r)
    for t, col in stops:
        g.add_color_stop_rgb(t, *col)
    return g


def lit(nx: float, ny: float) -> float:
    """Brightness of a facet whose outward normal is (nx, ny): 0 dark .. 1 bright."""
    n = math.hypot(nx, ny) or 1.0
    d = (nx * LIGHT[0] + ny * LIGHT[1]) / n
    return 0.5 + 0.5 * d


# --------------------------------------------------------------------------- #
# Seal sprites
# --------------------------------------------------------------------------- #
C0 = CELL / 2


def cell_face():
    s, c = surface()
    R = R_FACE
    g = cairo.RadialGradient(C0 - 0.30 * R, C0 - 0.34 * R, 0.0, C0, C0, R)
    g.add_color_stop_rgb(0.00, 1.00, 1.00, 1.00)
    g.add_color_stop_rgb(0.50, 0.90, 0.90, 0.90)
    g.add_color_stop_rgb(0.86, 0.70, 0.70, 0.70)
    g.add_color_stop_rgb(1.00, 0.52, 0.52, 0.52)
    c.arc(C0, C0, R, 0, math.tau)
    c.set_source(g)
    c.fill()
    # A lighter crescent low on the face: light coming back through the gem.
    c.save()
    c.arc(C0, C0, R - 1.0, 0, math.tau)
    c.clip()
    b = cairo.RadialGradient(C0 + 0.12 * R, C0 + 0.95 * R, 0.0, C0 + 0.12 * R, C0 + 0.95 * R, 0.75 * R)
    b.add_color_stop_rgba(0.0, 1, 1, 1, 0.42)
    b.add_color_stop_rgba(1.0, 1, 1, 1, 0.0)
    c.set_source(b)
    c.paint()
    c.restore()
    # The dark rim that parts the face from its frame.
    c.arc(C0, C0, R - 1.2, 0, math.tau)
    c.set_source_rgba(0.0, 0.0, 0.0, 0.42)
    c.set_line_width(2.4)
    c.stroke()
    return rgba(s)


def cell_gloss():
    s, c = surface()
    R = R_FACE
    c.save()
    c.arc(C0, C0, R - 3.0, 0, math.tau)
    c.clip()
    c.save()
    c.translate(C0 - 0.10 * R, C0 - 0.47 * R)
    c.scale(0.80 * R, 0.46 * R)
    c.arc(0, 0, 1, 0, math.tau)
    c.restore()
    g = cairo.LinearGradient(0, C0 - 0.95 * R, 0, C0 - 0.02 * R)
    g.add_color_stop_rgba(0.0, 1, 1, 1, 0.78)
    g.add_color_stop_rgba(0.55, 1, 1, 1, 0.22)
    g.add_color_stop_rgba(1.0, 1, 1, 1, 0.0)
    c.set_source(g)
    c.fill()
    c.restore()
    c.arc(C0 - 0.46 * R, C0 - 0.40 * R, 0.085 * R, 0, math.tau)
    c.set_source_rgba(1, 1, 1, 0.95)
    c.fill()
    return rgba(s)


def cell_ring(stops, ink):
    s, c = surface()
    R = R_FACE
    outer = 1.17 * R
    c.set_fill_rule(cairo.FILL_RULE_EVEN_ODD)
    c.arc(C0, C0, outer, 0, math.tau)
    c.new_sub_path()
    c.arc(C0, C0, R, 0, math.tau)
    c.set_source(metal_gradient(stops, C0, C0, outer))
    c.fill()
    c.set_fill_rule(cairo.FILL_RULE_WINDING)
    # A highlight running round the lit side and a dark lip on both edges.
    c.arc(C0, C0, 1.085 * R, math.radians(195), math.radians(300))
    c.set_source_rgba(1, 1, 1, 0.75)
    c.set_line_width(1.6)
    c.stroke()
    c.arc(C0, C0, outer, 0, math.tau)
    c.set_source_rgba(*ink, 0.88)
    c.set_line_width(2.6)
    c.stroke()
    c.arc(C0, C0, R + 0.4, 0, math.tau)
    c.set_source_rgba(*ink, 0.55)
    c.set_line_width(1.4)
    c.stroke()
    return rgba(s)


def hexagon(r: float, cx: float = C0, cy: float = C0):
    return [(cx + r * math.cos(math.radians(-90 + 60 * k)), cy + r * math.sin(math.radians(-90 + 60 * k))) for k in range(6)]


def poly(c, pts):
    c.move_to(*pts[0])
    for p in pts[1:]:
        c.line_to(*p)
    c.close_path()


def cell_hex(stops, ink):
    """Tier 2: the face set in a faceted hexagon (point up), lit from the top left."""
    s, c = surface()
    R = R_FACE
    out_pts, in_pts = hexagon(1.42 * R), hexagon(1.20 * R)
    # The inner flat between the hexagon and the face.
    c.set_fill_rule(cairo.FILL_RULE_EVEN_ODD)
    poly(c, in_pts)
    c.new_sub_path()
    c.arc(C0, C0, R, 0, math.tau)
    g = metal_gradient(stops, C0, C0, 1.2 * R)
    c.set_source(g)
    c.fill()
    c.set_fill_rule(cairo.FILL_RULE_WINDING)
    poly(c, in_pts)
    c.new_sub_path()
    c.arc(C0, C0, R, 0, math.tau)
    c.set_source_rgba(0, 0, 0, 0.30)
    c.set_fill_rule(cairo.FILL_RULE_EVEN_ODD)
    c.fill()
    c.set_fill_rule(cairo.FILL_RULE_WINDING)
    # Six bevel facets.
    for k in range(6):
        a, b = out_pts[k], out_pts[(k + 1) % 6]
        d, e = in_pts[k], in_pts[(k + 1) % 6]
        mx, my = (a[0] + b[0]) / 2 - C0, (a[1] + b[1]) / 2 - C0
        poly(c, [a, b, e, d])
        c.set_source_rgb(*ramp(stops, 1.0 - lit(mx, my)))
        c.fill()
    # Ridges between facets, the outer outline, the lip and the face's seat.
    for k in range(6):
        c.move_to(*in_pts[k])
        c.line_to(*out_pts[k])
    c.set_source_rgba(1, 1, 1, 0.30)
    c.set_line_width(1.0)
    c.stroke()
    poly(c, in_pts)
    c.set_source_rgba(1, 1, 1, 0.45)
    c.set_line_width(1.2)
    c.stroke()
    poly(c, out_pts)
    c.set_source_rgba(*ink, 0.90)
    c.set_line_width(2.8)
    c.stroke()
    c.arc(C0, C0, R + 0.4, 0, math.tau)
    c.set_source_rgba(*ink, 0.60)
    c.set_line_width(1.6)
    c.stroke()
    return rgba(s)


def star_tips(long_r: float, short_r: float, valley_r: float, points: int = 8):
    tips, valleys = [], []
    for k in range(points):
        a = math.radians(-90 + 360 / points * k)
        r = long_r if k % 2 == 0 else short_r
        tips.append((C0 + r * math.cos(a), C0 + r * math.sin(a)))
        av = a + math.radians(180 / points)
        valleys.append((C0 + valley_r * math.cos(av), C0 + valley_r * math.sin(av)))
    return tips, valleys


def cell_star():
    """Tier 3 (the capstone): an eight-point faceted gold star behind a gold ring."""
    s, c = surface()
    R = R_FACE
    tips, valleys = star_tips(1.86 * R, 1.50 * R, 1.00 * R)
    n = len(tips)
    for k in range(n):
        tip, left, right = tips[k], valleys[k - 1], valleys[k]
        for side in (left, right):
            ex, ey = tip[0] - side[0], tip[1] - side[1]
            nx, ny = ey, -ex                      # perpendicular of the outer edge
            mx, my = (tip[0] + side[0]) / 2 - C0, (tip[1] + side[1]) / 2 - C0
            if nx * mx + ny * my < 0:
                nx, ny = -nx, -ny
            poly(c, [(C0, C0), side, tip])
            c.set_source_rgb(*ramp(GOLD, 1.0 - lit(nx * 0.7 + mx * 0.3 / R, ny * 0.7 + my * 0.3 / R)))
            c.fill()
    for k in range(n):
        c.move_to(C0, C0)
        c.line_to(*tips[k])
    c.set_source_rgba(1, 0.98, 0.85, 0.45)
    c.set_line_width(1.1)
    c.stroke()
    outline = []
    for k in range(n):
        outline += [tips[k], valleys[k]]
    poly(c, outline)
    c.set_source_rgba(*GOLD_INK, 0.92)
    c.set_line_width(2.6)
    c.stroke()
    ring = rgba(s)
    return over(ring, cell_ring(GOLD, GOLD_INK))


def cell_halo():
    x, y = grid()
    d = np.hypot(x, y) / R_SOFT
    return soft(np.exp(-0.8 * d * d))


def cell_rays():
    s, c = surface()
    for k in range(8):
        a = math.radians(-90 + 45 * k)
        length = (2.30 if k % 2 == 0 else 1.55) * R_SOFT
        w0 = (0.20 if k % 2 == 0 else 0.13) * R_SOFT
        dx, dy = math.cos(a), math.sin(a)
        px, py = -dy, dx
        poly(c, [(C0 + px * w0, C0 + py * w0), (C0 + dx * length, C0 + dy * length), (C0 - px * w0, C0 - py * w0)])
        c.set_source_rgba(1, 1, 1, 1)
        c.fill()
    a = rgba(s)[..., 3]
    a = gaussian_filter(a, 2.2)
    x, y = grid()
    d = np.hypot(x, y) / (2.35 * R_SOFT)
    a = a * np.clip(1.0 - d, 0, 1) ** 1.1
    a = np.maximum(a, 0.85 * np.exp(-((np.hypot(x, y) / (0.42 * R_SOFT)) ** 2)))
    return soft(a)


def cell_sparkle():
    s, c = surface()
    R = R_SOFT
    pts = []
    for k in range(8):
        a = math.radians(-90 + 45 * k)
        r = (2.2 if k % 4 == 0 else 0.62 if k % 2 == 0 else 0.16) * R
        if k % 2 == 1:
            r = 0.16 * R
        elif k % 4 == 2:
            r = 0.95 * R
        pts.append((C0 + r * math.cos(a), C0 + r * math.sin(a)))
    poly(c, pts)
    c.set_source_rgba(1, 1, 1, 1)
    c.fill()
    a = gaussian_filter(rgba(s)[..., 3], 0.9)
    x, y = grid()
    a = np.maximum(a, np.exp(-((np.hypot(x, y) / (0.38 * R)) ** 2)))
    return soft(a)


def cell_crown():
    s, c = surface()
    R = R_FACE
    w, h = 1.50 * R, 0.30 * R
    top = C0 - 0.10 * R
    base_y = C0 + 0.30 * R
    pts = [(C0 - w / 2, base_y), (C0 - w / 2 - 0.05 * R, top - 0.42 * R), (C0 - 0.38 * R, top + 0.02 * R),
           (C0, top - 0.62 * R), (C0 + 0.38 * R, top + 0.02 * R), (C0 + w / 2 + 0.05 * R, top - 0.42 * R),
           (C0 + w / 2, base_y)]
    band = [(C0 - w / 2 - 0.02 * R, base_y - 0.02 * R), (C0 + w / 2 + 0.02 * R, base_y - 0.02 * R),
            (C0 + w / 2, base_y + h), (C0 - w / 2, base_y + h)]
    for shape in (pts, band):
        poly(c, shape)
        c.set_source_rgba(*GOLD_INK, 1)
        c.set_line_width(5.0)
        c.stroke()
    poly(c, pts)
    c.set_source(metal_gradient(GOLD, C0, C0, 0.9 * R))
    c.fill()
    poly(c, band)
    g = cairo.LinearGradient(0, base_y, 0, base_y + h)
    g.add_color_stop_rgb(0, *GOLD[1][1])
    g.add_color_stop_rgb(1, *GOLD[2][1])
    c.set_source(g)
    c.fill()
    for (gx, gy, gr) in [(C0 - w / 2 - 0.05 * R, top - 0.42 * R, 0.11), (C0, top - 0.62 * R, 0.13), (C0 + w / 2 + 0.05 * R, top - 0.42 * R, 0.11)]:
        c.arc(gx, gy, gr * R, 0, math.tau)
        c.set_source_rgba(*GOLD_INK, 1)
        c.fill_preserve()
        c.set_source_rgb(1.0, 0.98, 0.88)
        c.arc(gx, gy, gr * R - 2.0, 0, math.tau)
        c.fill()
    for k, gx in enumerate([-0.42, 0.0, 0.42]):
        c.arc(C0 + gx * R, base_y + h / 2, 0.075 * R, 0, math.tau)
        c.set_source_rgb(0.95, 0.33, 0.42) if k != 1 else c.set_source_rgb(0.40, 0.85, 1.0)
        c.fill()
    c.move_to(C0 - w / 2 + 3, base_y + 2)
    c.line_to(C0 + w / 2 - 3, base_y + 2)
    c.set_source_rgba(1, 1, 0.9, 0.7)
    c.set_line_width(1.4)
    c.stroke()
    return rgba(s)


def cell_lock():
    s, c = surface()
    R = R_FACE
    bw, bh = 0.92 * R, 0.70 * R
    bx, by = C0 - bw / 2, C0 - 0.05 * R
    c.arc(C0, by, 0.30 * R, math.pi, 0)
    c.set_source_rgba(*INK, 1)
    c.set_line_width(0.24 * R)
    c.stroke()
    c.arc(C0, by, 0.30 * R, math.pi, 0)
    c.set_source_rgb(0.80, 0.86, 0.90)
    c.set_line_width(0.13 * R)
    c.stroke()

    def body(grow):
        r = 0.14 * R
        x0, y0, x1, y1 = bx - grow, by - grow, bx + bw + grow, by + bh + grow
        c.new_sub_path()
        c.arc(x1 - r, y0 + r, r, -math.pi / 2, 0)
        c.arc(x1 - r, y1 - r, r, 0, math.pi / 2)
        c.arc(x0 + r, y1 - r, r, math.pi / 2, math.pi)
        c.arc(x0 + r, y0 + r, r, math.pi, 1.5 * math.pi)
        c.close_path()
    body(3.0)
    c.set_source_rgba(*INK, 1)
    c.fill()
    body(0.0)
    c.set_source(metal_gradient(SILVER, C0, by + bh / 2, 0.6 * R))
    c.fill()
    c.arc(C0, by + bh * 0.42, 0.10 * R, 0, math.tau)
    c.set_source_rgba(*INK, 1)
    c.fill()
    poly(c, [(C0 - 0.05 * R, by + bh * 0.45), (C0 + 0.05 * R, by + bh * 0.45), (C0 + 0.07 * R, by + bh * 0.78), (C0 - 0.07 * R, by + bh * 0.78)])
    c.fill()
    return rgba(s)


def cell_shadow():
    x, y = grid()
    d = np.hypot(x, y)
    a = (d < 1.06 * R_FACE).astype(np.float32)
    a = gaussian_filter(a, 0.16 * R_FACE) * 0.9
    return soft(a, (0, 0, 0))


def cell_ring_soft():
    x, y = grid()
    d = np.hypot(x, y)
    return soft(np.exp(-(((d - R_RING) / (0.075 * R_RING)) ** 2)))


def cell_pip():
    s, c = surface()
    pts = []
    for k in range(10):
        a = math.radians(-90 + 36 * k)
        r = (0.80 if k % 2 == 0 else 0.38) * R_SOFT
        pts.append((C0 + r * math.cos(a), C0 + r * math.sin(a)))
    poly(c, pts)
    c.set_source_rgba(*INK, 1)
    c.set_line_width(0.30 * R_SOFT)
    c.stroke_preserve()
    c.set_source_rgba(1, 1, 1, 1)
    c.fill()
    return rgba(s)


def cell_thin_ring():
    s, c = surface()
    c.arc(C0, C0, R_THIN, 0, math.tau)
    c.set_source_rgba(1, 1, 1, 1)
    c.set_line_width(5.0)
    c.stroke()
    return rgba(s)


def cell_brackets():
    s, c = surface()
    c.set_line_cap(cairo.LINE_CAP_ROUND)
    for k in range(4):
        mid = math.radians(45 + 90 * k)
        c.new_sub_path()
        c.arc(C0, C0, R_THIN, mid - math.radians(23), mid + math.radians(23))
    c.set_source_rgba(1, 1, 1, 1)
    c.set_line_width(7.0)
    c.stroke()
    return rgba(s)


def cell_dot():
    x, y = grid()
    d = np.hypot(x, y)
    return soft(np.exp(-((d / (0.45 * R_SOFT)) ** 2)))


# --------------------------------------------------------------------------- #
# Emblems: one per constellation, white with a soft emboss, outlined in ink.
# --------------------------------------------------------------------------- #
def emboss(build, outline: float = 5.0, inner=None):
    """Draw a silhouette built by `build(c, u)` (u = emblem unit): ink outline under a
    white-to-grey fill, plus optional inner detail strokes `inner(c, u)`."""
    s, c = surface()
    u = R_EMBLEM
    c.translate(C0, C0)
    stroke = build(c, u)
    g = cairo.LinearGradient(0, -u, 0, u)
    g.add_color_stop_rgb(0.0, 1.0, 1.0, 1.0)
    g.add_color_stop_rgb(0.55, 0.90, 0.90, 0.90)
    g.add_color_stop_rgb(1.0, 0.70, 0.70, 0.70)
    c.set_source_rgba(*INK, 1)
    if stroke:
        c.set_line_width(stroke * u + outline * 2)
        c.stroke_preserve()
        c.set_source(g)
        c.set_line_width(stroke * u)
        c.stroke()
    else:
        c.set_line_width(outline * 2)
        c.stroke_preserve()
        c.set_source(g)
        c.fill()
    if inner:
        inner(c, u)
    return rgba(s)


def _blade(c, u, x0, y0, x1, y1, w):
    """A straight blade from hilt (x0,y0) to tip (x1,y1), half width w."""
    dx, dy = x1 - x0, y1 - y0
    n = math.hypot(dx, dy)
    dx, dy = dx / n, dy / n
    px, py = -dy * w, dx * w
    tipb = (x1 - dx * w * 2.2, y1 - dy * w * 2.2)
    poly(c, [(x0 + px, y0 + py), (tipb[0] + px, tipb[1] + py), (x1, y1), (tipb[0] - px, tipb[1] - py), (x0 - px, y0 - py)])


def emblem_fury(c, u):
    # Two-tongued flames rising either side of an upright sword.
    for k in (-1, 1):
        def p(x, y):
            return (k * x * u, y * u)
        c.move_to(*p(0.13, 0.30))
        c.curve_to(*p(0.50, 0.26), *p(0.68, 0.02), *p(0.50, -0.26))
        c.curve_to(*p(0.60, -0.40), *p(0.62, -0.58), *p(0.55, -0.78))
        c.curve_to(*p(0.46, -0.58), *p(0.40, -0.47), *p(0.31, -0.40))
        c.curve_to(*p(0.33, -0.52), *p(0.29, -0.64), *p(0.22, -0.72))
        c.curve_to(*p(0.19, -0.52), *p(0.14, -0.30), *p(0.13, -0.10))
        c.close_path()
        c.new_sub_path()
    _blade(c, u, 0, 0.40 * u, 0, -1.0 * u, 0.12 * u)
    c.new_sub_path()
    c.move_to(-0.52 * u, 0.30 * u)
    c.curve_to(-0.30 * u, 0.44 * u, 0.30 * u, 0.44 * u, 0.52 * u, 0.30 * u)
    c.line_to(0.50 * u, 0.46 * u)
    c.curve_to(0.30 * u, 0.58 * u, -0.30 * u, 0.58 * u, -0.50 * u, 0.46 * u)
    c.close_path()
    c.rectangle(-0.075 * u, 0.50 * u, 0.15 * u, 0.32 * u)
    c.new_sub_path()
    c.arc(0, 0.90 * u, 0.12 * u, 0, math.tau)


def emblem_fury_inner(c, u):
    c.move_to(0, 0.36 * u)
    c.line_to(0, -0.80 * u)
    c.set_source_rgba(*INK, 0.55)
    c.set_line_width(2.4)
    c.stroke()


def emblem_tempo(c, u):
    # A gust: three streaks; the upper two curl over at their ends. Drawn as a stroke.
    c.move_to(-0.80 * u, -0.40 * u)
    c.line_to(0.26 * u, -0.40 * u)
    c.arc_negative(0.26 * u, -0.62 * u, 0.22 * u, math.pi / 2, -math.pi * 0.95)
    c.new_sub_path()
    c.move_to(-0.96 * u, 0.04 * u)
    c.line_to(0.50 * u, 0.04 * u)
    c.arc(0.50 * u, 0.30 * u, 0.26 * u, -math.pi / 2, math.pi * 0.92)
    c.new_sub_path()
    c.move_to(-0.62 * u, 0.48 * u)
    c.line_to(0.06 * u, 0.48 * u)
    return 0.16


def emblem_precision(c, u):
    # A reticle: a ring (its hole wound the other way), four ticks and a diamond.
    c.arc(0, 0, 0.84 * u, 0, math.tau)
    c.close_path()
    c.new_sub_path()
    c.arc_negative(0, 0, 0.64 * u, 0, -math.tau)
    c.close_path()
    for a in range(4):
        ang = a * math.pi / 2
        ca, sa = math.cos(ang), math.sin(ang)
        pts = [(-0.085, -1.02), (0.085, -1.02), (0.05, -0.40), (-0.05, -0.40)]
        c.new_sub_path()
        poly(c, [((x * ca - y * sa) * u, (x * sa + y * ca) * u) for x, y in pts])
    c.new_sub_path()
    poly(c, [(0, -0.22 * u), (0.22 * u, 0), (0, 0.22 * u), (-0.22 * u, 0)])


def emblem_element(c, u):
    # A prism: a triangle with a four-point star in its heart and sparks at its corners.
    tri = [(0, -0.88 * u), (0.80 * u, 0.56 * u), (-0.80 * u, 0.56 * u)]
    poly(c, tri)
    for (x, y) in tri:
        c.new_sub_path()
        d = math.hypot(x, y) or 1
        ox, oy = x / d * 0.22 * u, y / d * 0.22 * u
        c.arc(x + ox, y + oy, 0.10 * u, 0, math.tau)


def emblem_element_inner(c, u):
    tri = [(0, -0.50 * u), (0.46 * u, 0.32 * u), (-0.46 * u, 0.32 * u)]
    poly(c, tri)
    c.set_source_rgba(*INK, 0.55)
    c.set_line_width(2.6)
    c.stroke()
    pts = []
    for k in range(8):
        a = math.radians(-90 + 45 * k)
        r = (0.28 if k % 2 == 0 else 0.07) * u
        pts.append((r * math.cos(a), 0.06 * u + r * math.sin(a)))
    poly(c, pts)
    c.set_source_rgba(*INK, 0.75)
    c.fill()


def emblem_arms(c, u):
    _blade(c, u, -0.62 * u, 0.62 * u, 0.80 * u, -0.80 * u, 0.10 * u)
    c.new_sub_path()
    poly(c, [(-0.78 * u, 0.34 * u), (-0.34 * u, 0.78 * u), (-0.26 * u, 0.70 * u), (-0.70 * u, 0.26 * u)])
    c.new_sub_path()
    # arrow, the other diagonal
    w = 0.05 * u
    poly(c, [(0.70 * u + w, 0.70 * u - w), (-0.52 * u + w, -0.52 * u - w), (-0.52 * u - w, -0.52 * u + w), (0.70 * u - w, 0.70 * u + w)])
    c.new_sub_path()
    poly(c, [(-0.84 * u, -0.84 * u), (-0.36 * u, -0.66 * u), (-0.66 * u, -0.36 * u)])
    for k in range(2):
        o = 0.12 * u * k
        c.new_sub_path()
        poly(c, [(0.56 * u - o, 0.56 * u - o), (0.86 * u - o, 0.60 * u - o), (0.74 * u - o, 0.74 * u - o), (0.60 * u - o, 0.86 * u - o)])


def shield_path(c, u, s=1.0, dy=0.0):
    c.move_to(0, (-0.92 + dy) * u * s)
    c.curve_to(0.30 * u * s, (-0.78 + dy) * u * s, 0.60 * u * s, (-0.80 + dy) * u * s, 0.80 * u * s, (-0.74 + dy) * u * s)
    c.curve_to(0.82 * u * s, (-0.10 + dy) * u * s, 0.62 * u * s, (0.52 + dy) * u * s, 0, (0.96 + dy) * u * s)
    c.curve_to(-0.62 * u * s, (0.52 + dy) * u * s, -0.82 * u * s, (-0.10 + dy) * u * s, -0.80 * u * s, (-0.74 + dy) * u * s)
    c.curve_to(-0.60 * u * s, (-0.80 + dy) * u * s, -0.30 * u * s, (-0.78 + dy) * u * s, 0, (-0.92 + dy) * u * s)
    c.close_path()


def emblem_guardian(c, u):
    shield_path(c, u)


def emblem_guardian_inner(c, u):
    gem = [(0, -0.52 * u), (0.30 * u, -0.24 * u), (0.30 * u, 0.20 * u), (0, 0.56 * u), (-0.30 * u, 0.20 * u), (-0.30 * u, -0.24 * u)]
    poly(c, gem)
    c.set_source_rgba(*INK, 0.70)
    c.fill()
    poly(c, [(0, -0.40 * u), (0.18 * u, -0.20 * u), (0, 0.04 * u), (-0.18 * u, -0.20 * u)])
    c.set_source_rgba(1, 1, 1, 0.85)
    c.fill()


def five_star(c, cx, cy, r, inner=0.42, rot=-90.0):
    pts = []
    for k in range(10):
        a = math.radians(rot + 36 * k)
        rr = r if k % 2 == 0 else r * inner
        pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    poly(c, pts)


def emblem_starlight(c, u):
    for (o, w, ln) in [(-0.20, 0.07, 1.05), (0.0, 0.10, 1.25), (0.20, 0.07, 0.95)]:
        # tail streaks towards the lower left, tapering
        ang = math.radians(135)
        dx, dy = math.cos(ang), math.sin(ang)
        px, py = -dy, dx
        sx, sy = 0.26 * u + px * o * u, -0.26 * u + py * o * u
        c.new_sub_path()
        poly(c, [(sx + px * w * u, sy + py * w * u), (sx + dx * ln * u, sy + dy * ln * u), (sx - px * w * u, sy - py * w * u)])
    c.new_sub_path()
    five_star(c, 0.30 * u, -0.30 * u, 0.56 * u, 0.45, -90 + 8)


def emblem_fortune(c, u):
    c.arc(0, 0.06 * u, 0.80 * u, 0, math.tau)
    c.new_sub_path()
    sp = []
    for k in range(8):
        a = math.radians(-90 + 45 * k)
        r = (0.30 if k % 2 == 0 else 0.07) * u
        sp.append((0.70 * u + r * math.cos(a), -0.66 * u + r * math.sin(a)))
    poly(c, sp)


def emblem_fortune_inner(c, u):
    c.arc(0, 0.06 * u, 0.62 * u, 0, math.tau)
    c.set_source_rgba(*INK, 0.50)
    c.set_line_width(2.6)
    c.stroke()
    five_star(c, 0, 0.08 * u, 0.42 * u, 0.44)
    c.set_source_rgba(*INK, 0.70)
    c.fill()


EMBLEMS = [
    ("fury", emblem_fury, emblem_fury_inner),
    ("tempo", emblem_tempo, None),
    ("precision", emblem_precision, None),
    ("element", emblem_element, emblem_element_inner),
    ("arms", emblem_arms, None),
    ("guardian", emblem_guardian, emblem_guardian_inner),
    ("starlight", emblem_starlight, None),
    ("fortune", emblem_fortune, emblem_fortune_inner),
]


# --------------------------------------------------------------------------- #
# The atlas
# --------------------------------------------------------------------------- #
def atlas() -> np.ndarray:
    cells = [
        cell_face(),                    # 0 face (tinted by the constellation colour)
        cell_gloss(),                   # 1 gloss over the face (white, untinted)
        cell_ring(SILVER, INK),         # 2 tier 1 ring, silver
        cell_ring(GOLD, GOLD_INK),      # 3 tier 1 ring, gold (a full node)
        cell_hex(SILVER, INK),          # 4 tier 2 hexagon, silver
        cell_hex(GOLD, GOLD_INK),       # 5 tier 2 hexagon, gold
        cell_star(),                    # 6 tier 3 star, gold
        cell_halo(),                    # 7 soft halo
        cell_rays(),                    # 8 eight soft rays
        cell_sparkle(),                 # 9 four-point sparkle
        cell_crown(),                   # 10 crown (a full node)
        cell_lock(),                    # 11 lock (a locked node)
        cell_shadow(),                  # 12 drop shadow under a seal
        cell_ring_soft(),               # 13 soft ring (offer / pulse)
        cell_dot(),                     # 14 soft dot (dust, particles)
        cell_pip(),                     # 15 pip: a white five-point star in an ink rim (tinted)
    ]
    for _, build, inner in EMBLEMS:     # 16..23 emblems in TALENT_GROUP_ORDER
        cells.append(emboss(build, 5.0, inner))
    cells.append(cell_thin_ring())      # 24 crisp thin ring (open rim, offer ring)
    cells.append(cell_brackets())       # 25 four selection brackets
    cells.append(np.zeros((CELL, CELL, 4), np.float32))  # 26 spare
    cells.append(np.zeros((CELL, CELL, 4), np.float32))  # 27 spare
    sheet = np.zeros((ROWS * CELL, COLS * CELL, 4), np.float32)
    for i, cell in enumerate(cells):
        r, c = divmod(i, COLS)
        sheet[r * CELL:(r + 1) * CELL, c * CELL:(c + 1) * CELL] = cell
    return sheet


def save(arr: np.ndarray, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    img = (np.clip(arr, 0, 1) * 255 + 0.5).astype(np.uint8)
    Image.fromarray(img, "RGBA").save(path, optimize=True)


def talent_nodes() -> list[tuple[str, str, int]]:
    """(id, constellation, tier) of every node, read from core/balance.gd (the DB's copy)."""
    import re
    text = (ROOT / "core/balance.gd").read_text()
    block = text[text.index("const TALENTS := ["):]
    block = block[:block.index("\n]\n")]
    out = []
    for m in re.finditer(r'\{"id": "([a-z_]+)".*?"group": "([a-z]+)", "tier": (\d)', block):
        out.append((m.group(1), m.group(2), int(m.group(3))))
    return out


GROUP_COLOR = {"fury": "#E2415A", "tempo": "#F6C445", "precision": "#5AD07A", "element": "#A56CF0",
               "arms": "#FF9A3C", "guardian": "#5FE6FF", "starlight": "#EDC879", "fortune": "#FF7AC0"}


def icons(sheet: str = "") -> None:
    import talent_glyphs as tg
    nodes = talent_nodes()
    missing = [n for n, _, _ in nodes if n not in tg.GLYPHS]
    extra = [n for n in tg.GLYPHS if n not in {i for i, _, _ in nodes}]
    if missing or extra:
        print("glyphs missing:", missing, "unused:", extra)
    cells = []
    for node_id, group, tier in nodes:
        glyph = tg.build(node_id)
        if glyph is None:
            continue
        arr = tg.render(glyph, rgba)
        save(arr, OUT / f"{node_id}.png")
        cells.append((node_id, group, arr))
    print("icons", len(cells), "->", OUT)
    if not sheet:
        return
    # Review sheet: each glyph on a lit face (constellation colour) and on an open face.
    cols = 12
    cw, ch = 150, 84
    rows = (len(cells) + cols - 1) // cols
    canvas = np.zeros((rows * ch, cols * cw, 4), np.float32)
    canvas[..., :3] = (0.04, 0.08, 0.11)
    canvas[..., 3] = 1.0
    yy, xx = np.mgrid[0:64, 0:64].astype(np.float32)
    disc = (np.hypot(xx - 31.5, yy - 31.5) <= 30).astype(np.float32)
    for i, (node_id, group, arr) in enumerate(cells):
        r, c = divmod(i, cols)
        col = np.array([int(GROUP_COLOR[group][k:k + 2], 16) / 255 for k in (1, 3, 5)], np.float32)
        small = np.array(Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8), "RGBA").resize((56, 56), Image.LANCZOS)).astype(np.float32) / 255
        for k, (face, ink) in enumerate([(col, np.ones(3, np.float32)), (np.array([0.06, 0.10, 0.13]) * 0.7 + col * 0.3, np.clip(col * 1.3 + 0.15, 0, 1))]):
            x0, y0 = c * cw + 6 + k * 70, r * ch + 10
            tile = np.zeros((64, 64, 4), np.float32)
            tile[..., :3] = face
            tile[..., 3] = disc
            g = small.copy()
            g[..., :3] = g[..., :3] * ink
            pad = np.zeros((64, 64, 4), np.float32)
            pad[4:60, 4:60] = g
            tile = over(tile, pad)
            canvas[y0:y0 + 64, x0:x0 + 64] = over(canvas[y0:y0 + 64, x0:x0 + 64], tile)
    img = Image.fromarray((np.clip(canvas, 0, 1) * 255).astype(np.uint8), "RGBA").convert("RGB")
    from PIL import ImageDraw
    d = ImageDraw.Draw(img)
    for i, (node_id, _, _) in enumerate(cells):
        r, c = divmod(i, cols)
        d.text((c * cw + 6, r * ch + 74 - 2), node_id, fill=(200, 210, 215))
    (ROOT / sheet).parent.mkdir(parents=True, exist_ok=True)
    img.save(ROOT / sheet)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--sheet", default="")
    ap.add_argument("--icon-sheet", default="")
    ap.add_argument("--only", default="", help="atlas | icons (default both)")
    args = ap.parse_args()
    if args.only in ("", "icons"):
        icons(args.icon_sheet)
    if args.only in ("", "atlas"):
        sheet = atlas()
        save(sheet, OUT / "seal_atlas.png")
        print("atlas", OUT / "seal_atlas.png", sheet.shape)
        if args.sheet:
            bg = np.zeros_like(sheet)
            bg[..., :3] = (0.08, 0.13, 0.18)
            bg[..., 3] = 1.0
            save(over(bg, sheet), ROOT / args.sheet)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
