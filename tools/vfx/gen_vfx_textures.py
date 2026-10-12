#!/usr/bin/env python3
"""Procedurally generate the battle VFX sprite atlas and tileable noise.

    python3 tools/vfx/gen_vfx_textures.py

Outputs (deterministic, no external art):
  art/vfx/sprites.png  1024x1024 RGBA, 4x4 cells of 256px. Cell index = row*4+col.
    0 soft glow        1 four-point star   2 six-point sparkle   3 soft ring
    4 smoke puff       5 flame tongue      6 ice shard           7 lightning
    8 water droplet    9 arrow            10 tracer bolt        11 crescent slash
   12 rune disc       13 hex shield       14 ember mote         15 shock arc
  art/vfx/noise.png    256x256 RGB tileable noise (R low, G mid, B high frequency).
  art/vfx/skill_sprites.png  1024x1024 RGBA, 4x4 cells of 256px, for the big one-shot
    sequences (vfx_skill*.gdshader: Starlight Burst, boss gate warning / arrival):
    0 star sigil (lock-on)  1 light pillar      2 ground cracks      3 crack glow (blurred)
    4 comet tail            5 eight-ray flare   6 debris chunk       7 fog wisp
    8 boss rune circle      9 thorn portal ring 10 ground glow disc  11 star streak
   12..15 reserved (transparent)

Sprites are white with alpha; shaders tint them. The cell layout is read by
art/vfx/*.gdshader (`cell()`); keep indices stable when adding sprites.
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "art/vfx"
CELL = 256
GRID = 4
RNG = np.random.default_rng(20261010)


def grid():
    y, x = np.mgrid[0:CELL, 0:CELL].astype(np.float32)
    u = (x + 0.5) / CELL * 2.0 - 1.0
    v = 1.0 - (y + 0.5) / CELL * 2.0
    return u, v


def smooth(a, b, x):
    t = np.clip((x - a) / (b - a + 1e-9), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def value_noise(size, freq, seed):
    rng = np.random.default_rng(seed)
    lattice = rng.random((freq + 1, freq + 1)).astype(np.float32)
    lattice[-1, :] = lattice[0, :]
    lattice[:, -1] = lattice[:, 0]
    y, x = np.mgrid[0:size, 0:size].astype(np.float32)
    fx = x / size * freq
    fy = y / size * freq
    ix = np.floor(fx).astype(int)
    iy = np.floor(fy).astype(int)
    tx = fx - ix
    ty = fy - iy
    tx = tx * tx * (3 - 2 * tx)
    ty = ty * ty * (3 - 2 * ty)
    a = lattice[iy, ix]
    b = lattice[iy, ix + 1]
    c = lattice[iy + 1, ix]
    d = lattice[iy + 1, ix + 1]
    return (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty


def fbm(size, base, octaves, seed):
    total = np.zeros((size, size), np.float32)
    amp = 1.0
    norm = 0.0
    for o in range(octaves):
        total += value_noise(size, base * 2 ** o, seed + o * 17) * amp
        norm += amp
        amp *= 0.5
    return total / norm


def soft_glow():
    u, v = grid()
    r = np.sqrt(u * u + v * v)
    core = np.exp(-(r / 0.22) ** 2)
    halo = np.exp(-(r / 0.62) ** 2) * 0.55
    return np.clip(core + halo, 0, 1) * (1.0 - smooth(0.9, 1.0, r))


def star(points, sharp=10.0, core=0.18):
    u, v = grid()
    r = np.sqrt(u * u + v * v) + 1e-6
    a = np.arctan2(v, u)
    spikes = np.abs(np.cos(a * points / 2.0)) ** sharp
    rays = np.exp(-r / 0.42) * spikes
    cen = np.exp(-(r / core) ** 2)
    return np.clip(cen + rays, 0, 1) * (1.0 - smooth(0.9, 1.0, r))


def soft_ring():
    u, v = grid()
    r = np.sqrt(u * u + v * v)
    band = np.exp(-((r - 0.72) / 0.10) ** 2)
    inner = np.exp(-((r - 0.72) / 0.26) ** 2) * 0.35
    return np.clip(band + inner, 0, 1) * (1.0 - smooth(0.92, 1.0, r))


def smoke_puff():
    u, v = grid()
    r = np.sqrt(u * u + v * v)
    n = fbm(CELL, 3, 4, 101)
    n2 = fbm(CELL, 6, 3, 202)
    shape = (1.0 - smooth(0.15, 0.92, r + (n - 0.5) * 0.45))
    body = shape * (0.62 + 0.38 * n2)
    body = np.clip(body, 0, 1) * (1.0 - smooth(0.85, 1.0, r))
    # Soft, lit-from-nowhere mass: blur so it never reads as cotton on bright snow.
    img = Image.fromarray((body * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(7))
    return np.asarray(img).astype(np.float32) / 255.0 * 0.92


def flame():
    u, v = grid()
    # Teardrop pointing up, with wisps.
    y = (v + 0.75) / 1.55
    width = 0.42 * np.sqrt(np.clip(1.0 - y, 0, 1)) * (1.0 - 0.35 * y) + 0.02
    n = fbm(CELL, 5, 3, 303)
    d = np.abs(u + (n - 0.5) * 0.25 * y) / np.maximum(width, 1e-3)
    body = (1.0 - smooth(0.55, 1.0, d)) * smooth(-0.05, 0.08, y) * (1.0 - smooth(0.92, 1.08, y))
    core = (1.0 - smooth(0.1, 0.55, d)) * smooth(0.0, 0.2, y) * (1.0 - smooth(0.5, 0.85, y))
    return np.clip(body * 0.8 + core, 0, 1)


def ice_shard():
    u, v = grid()
    # Elongated hexagonal crystal with a bright facet line.
    L = 0.86
    W = 0.26
    y = v / L
    taper = np.where(np.abs(y) > 0.55, 1.0 - (np.abs(y) - 0.55) / 0.45, 1.0)
    half = W * np.clip(taper, 0, 1)
    body = (np.abs(u) <= half) & (np.abs(y) <= 1.0)
    edge = 1.0 - smooth(half - 0.03, half + 0.005, np.abs(u))
    facet = np.exp(-(np.abs(u - 0.06) / 0.035) ** 2) * (np.abs(y) < 0.8)
    a = body.astype(np.float32) * (0.55 + 0.45 * edge)
    a = np.clip(a * 0.85 + facet * 0.6, 0, 1)
    # Small satellite crystals.
    for cx, cy, s in [(-0.42, -0.25, 0.3), (0.40, 0.18, 0.26)]:
        ry = (v - cy) / (L * s)
        half2 = W * s * np.clip(np.where(np.abs(ry) > 0.5, 1 - (np.abs(ry) - 0.5) / 0.5, 1), 0, 1)
        sat = ((np.abs(u - cx) <= half2) & (np.abs(ry) <= 1.0)).astype(np.float32)
        a = np.clip(a + sat * 0.7, 0, 1)
    return a


def lightning():
    u, v = grid()
    rng = np.random.default_rng(404)
    a = np.zeros((CELL, CELL), np.float32)
    # Main zigzag from top to bottom.
    pts = []
    x = 0.0
    for i in range(9):
        y = 0.92 - i * 0.23
        x = np.clip(x + rng.uniform(-0.28, 0.28), -0.5, 0.5)
        pts.append((x, y))

    def seg(p, q, w, amp):
        nonlocal a
        px, py = p
        qx, qy = q
        dx, dy = qx - px, qy - py
        ll = dx * dx + dy * dy + 1e-9
        t = np.clip(((u - px) * dx + (v - py) * dy) / ll, 0, 1)
        d = np.sqrt((u - (px + t * dx)) ** 2 + (v - (py + t * dy)) ** 2)
        a = np.maximum(a, (1.0 - smooth(w * 0.4, w, d)) * amp)

    for i in range(len(pts) - 1):
        seg(pts[i], pts[i + 1], 0.07, 1.0)
    # Branches.
    for i in [1, 3, 5]:
        bx, by = pts[i]
        ex = np.clip(bx + rng.choice([-1, 1]) * rng.uniform(0.2, 0.4), -0.9, 0.9)
        ey = by - rng.uniform(0.15, 0.3)
        seg((bx, by), (ex, ey), 0.045, 0.7)
    glow = Image.fromarray((a * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(9))
    g = np.asarray(glow).astype(np.float32) / 255.0
    return np.clip(a + g * 0.6, 0, 1)


def droplet():
    u, v = grid()
    y = v
    w = 0.34 * np.sqrt(np.clip(1.0 - ((y + 0.15) / 0.65) ** 2, 0, 1))
    w = np.where(y > 0.5, 0.0, w)
    tail = np.clip(1.0 - (y - 0.3) / 0.55, 0, 1) * 0.22 * (y > 0.3)
    half = np.maximum(w, tail * (y > 0.3))
    body = 1.0 - smooth(half - 0.04, half + 0.01, np.abs(u))
    body = body * (y > -0.85) * (y < 0.88)
    hi = np.exp(-(((u + 0.12) / 0.09) ** 2 + ((v + 0.05) / 0.14) ** 2)) * 0.9
    return np.clip(body * 0.75 + hi, 0, 1)


def arrow():
    u, v = grid()
    shaft = (np.abs(u) < 0.055) & (v > -0.9) & (v < 0.42)
    head = (v >= 0.42) & (v < 0.95) & (np.abs(u) < (0.95 - v) * 0.42)
    fl = ((np.abs(u) < 0.26 - (v + 0.9) * 0.6) & (v > -0.9) & (v < -0.55))
    a = (shaft | head | fl).astype(np.float32)
    hot = np.exp(-(np.abs(u) / 0.03) ** 2) * (v > -0.9) * (v < 0.9)
    img = Image.fromarray((a * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2))
    a = np.asarray(img).astype(np.float32) / 255.0
    return np.clip(a + hot * 0.5, 0, 1)


def tracer():
    u, v = grid()
    y = v
    width = 0.17 * np.sqrt(np.clip(1.0 - ((y - 0.25) / 0.72) ** 2, 0, 1))
    width = np.where(y < -0.47, 0.17 * np.clip(1.0 + (y + 0.47) / 0.5, 0, 1) * 0.6, width)
    body = 1.0 - smooth(width * 0.7, width + 0.02, np.abs(u))
    body *= (y > -0.97) & (y < 0.97)
    core = np.exp(-(u / 0.05) ** 2) * (1.0 - smooth(0.5, 0.97, np.abs(y - 0.2)))
    glow = np.exp(-((u / 0.35) ** 2 + ((y - 0.2) / 0.8) ** 2)) * 0.35
    return np.clip(body * 0.8 + core + glow, 0, 1)


def crescent():
    u, v = grid()
    r = np.sqrt(u * u + v * v)
    a = np.arctan2(v, u)
    # Arc from -70deg to +70deg around +x, thick in the middle, sharp ends.
    ang = np.abs(a) / math.radians(72)
    thick = 0.16 * np.clip(1.0 - ang ** 2.2, 0, 1)
    band = 1.0 - smooth(thick * 0.5, thick + 0.01, np.abs(r - 0.72))
    band *= (ang < 1.0)
    edge = np.exp(-((r - 0.80) / 0.05) ** 2) * (ang < 0.95) * 0.9
    return np.clip(band * 0.85 + edge, 0, 1)


def rune_disc():
    u, v = grid()
    r = np.sqrt(u * u + v * v)
    a = np.arctan2(v, u)
    outer = np.exp(-((r - 0.93) / 0.025) ** 2)
    inner = np.exp(-((r - 0.70) / 0.018) ** 2) * 0.8
    ticks = (np.abs(np.sin(a * 12)) ** 40) * (r > 0.72) * (r < 0.90) * 0.8
    runes = ((np.abs(np.sin(a * 24 + r * 30)) > 0.93) & (r > 0.74) & (r < 0.88)).astype(np.float32) * 0.9
    tri = np.zeros_like(r)
    for k in range(3):
        ang0 = k * 2 * math.pi / 3 + math.pi / 2
        ang1 = ang0 + 2 * math.pi / 3
        p0 = np.array([math.cos(ang0), math.sin(ang0)]) * 0.66
        p1 = np.array([math.cos(ang1), math.sin(ang1)]) * 0.66
        d = p1 - p0
        t = np.clip(((u - p0[0]) * d[0] + (v - p0[1]) * d[1]) / (d @ d), 0, 1)
        dist = np.sqrt((u - (p0[0] + t * d[0])) ** 2 + (v - (p0[1] + t * d[1])) ** 2)
        tri = np.maximum(tri, np.exp(-(dist / 0.014) ** 2) * 0.8)
    centre = np.exp(-(r / 0.16) ** 2) * 0.7 + np.exp(-((r - 0.3) / 0.015) ** 2) * 0.6
    return np.clip(outer + inner + ticks + runes + tri + centre, 0, 1) * (r < 0.99)


def hex_shield():
    u, v = grid()
    # Flat-top hexagons, circumradius 1 in lattice units; two offset rectangular lattices.
    s = 4.0
    x = (u + 1.0) * s * 0.75 * 2.0 / 1.5
    y = (v + 1.0) * s
    best = np.full_like(u, 9.0)
    for ox, oy in [(0.0, 0.0), (0.75, 0.8660254)]:
        cx = np.round((x - ox) / 1.5) * 1.5 + ox
        cy = np.round((y - oy) / 1.7320508) * 1.7320508 + oy
        dx = np.abs(x - cx)
        dy = np.abs(y - cy)
        hexd = np.maximum(dx * 0.8660254 + dy * 0.5, dy) / 0.8660254
        best = np.minimum(best, hexd)
    line = smooth(0.80, 0.9, best)
    glow = 1.0 - smooth(0.25, 0.85, best)
    return np.clip(line * 0.95 + glow * 0.22, 0, 1)


def ember_mote():
    u, v = grid()
    r = np.sqrt(u * u + (v * 0.7) ** 2)
    core = np.exp(-(r / 0.18) ** 2)
    tail = np.exp(-(u / 0.1) ** 2) * np.clip(-v, 0, 1) * np.exp(-((-v) / 0.6)) * 0.7
    return np.clip(core + tail, 0, 1)


def shock_arc():
    u, v = grid()
    r = np.sqrt(u * u + v * v)
    a = np.arctan2(v, u)
    ang = np.abs(a) / math.radians(80)
    band = np.exp(-((r - 0.8) / 0.08) ** 2) * np.clip(1.0 - ang ** 3, 0, 1)
    wake = np.exp(-((r - 0.62) / 0.14) ** 2) * np.clip(1.0 - ang ** 2, 0, 1) * 0.35
    return np.clip(band + wake, 0, 1)


# --------------------------------------------------------------------------- #
# Skill / boss gate atlas (art/vfx/skill_sprites.png)
# --------------------------------------------------------------------------- #
def _seg(a, u, v, p, q, w, amp):
    """Max-blend a soft line segment p->q of half-width w into alpha plane `a`."""
    px, py = p
    qx, qy = q
    dx, dy = qx - px, qy - py
    ll = dx * dx + dy * dy + 1e-9
    t = np.clip(((u - px) * dx + (v - py) * dy) / ll, 0, 1)
    d = np.sqrt((u - (px + t * dx)) ** 2 + (v - (py + t * dy)) ** 2)
    np.maximum(a, (1.0 - smooth(w * 0.45, w, d)) * amp, out=a)


def star_sigil():
    """Lock-on marker of the Starlight Burst: rings, eight ticks and an eight-point star outline.
    The outer ring sits at r 0.95 of the cell so the shader can scale it to the damage radius."""
    u, v = grid()
    r = np.sqrt(u * u + v * v)
    ang = np.arctan2(v, u)
    a = np.zeros((CELL, CELL), np.float32)
    a = np.maximum(a, np.exp(-((r - 0.95) / 0.016) ** 2))
    a = np.maximum(a, np.exp(-((r - 0.76) / 0.012) ** 2) * 0.8)
    for k in range(8):
        th = k * math.pi / 4.0
        p = (math.cos(th) * 0.78, math.sin(th) * 0.78)
        q = (math.cos(th) * 0.93, math.sin(th) * 0.93)
        _seg(a, u, v, p, q, 0.022, 1.0)
    pts = []
    for k in range(16):
        th = k * math.pi / 8.0 + math.pi / 2.0
        rad = 0.64 if k % 2 == 0 else 0.27
        pts.append((math.cos(th) * rad, math.sin(th) * rad))
    for k in range(16):
        _seg(a, u, v, pts[k], pts[(k + 1) % 16], 0.014, 0.95)
    a = np.maximum(a, np.exp(-(r / 0.05) ** 2) * 0.9)
    # Four short chevrons just inside the outer ring, pointing at the centre.
    for k in range(4):
        th = k * math.pi / 2.0
        tip = (math.cos(th) * 0.84, math.sin(th) * 0.84)
        for side in (-1, 1):
            base = (math.cos(th) * 0.92 + math.cos(th + math.pi / 2) * side * 0.05,
                    math.sin(th) * 0.92 + math.sin(th + math.pi / 2) * side * 0.05)
            _seg(a, u, v, tip, base, 0.014, 0.9)
    return np.clip(a, 0, 1) * (r < 0.995)


def light_pillar():
    """Vertical column of light: hot core, soft halo, bright foot, feathered top."""
    u, v = grid()
    core = np.exp(-(u / 0.15) ** 2)
    halo = np.exp(-(u / 0.46) ** 2) * 0.5
    vert = smooth(-1.0, -0.84, v) * (1.0 - smooth(0.30, 0.98, v))
    foot = np.exp(-((v + 0.88) / 0.11) ** 2) * np.exp(-(u / 0.38) ** 2) * 0.55
    return np.clip((core + halo) * vert + foot, 0, 1)


def _cracks_plane(seed=505):
    u, v = grid()
    rng = np.random.default_rng(seed)
    a = np.zeros((CELL, CELL), np.float32)
    rays = 7
    for k in range(rays):
        th = k * 2 * math.pi / rays + rng.uniform(-0.25, 0.25)
        p = (0.0, 0.0)
        length = rng.uniform(0.80, 0.97)
        steps = 5
        for i in range(steps):
            f0 = i / steps
            f1 = (i + 1) / steps
            th1 = th + rng.uniform(-0.28, 0.28)
            q = (p[0] + math.cos(th1) * length * (f1 - f0), p[1] + math.sin(th1) * length * (f1 - f0))
            w = 0.052 * (1.0 - f0) + 0.014
            _seg(a, u, v, p, q, w, 1.0 - 0.25 * f0)
            if i in (1, 3):
                bth = th1 + rng.choice([-1, 1]) * rng.uniform(0.55, 1.0)
                blen = rng.uniform(0.14, 0.30)
                b = (p[0] + math.cos(bth) * blen, p[1] + math.sin(bth) * blen)
                _seg(a, u, v, p, b, 0.022, 0.75)
            p = q
    return np.clip(a, 0, 1)


def ground_cracks():
    """Radial fracture pattern that the mix layer paints dark on the ground."""
    a = _cracks_plane()
    img = Image.fromarray((a * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8))
    return np.asarray(img).astype(np.float32) / 255.0


def crack_glow():
    """The same fractures blurred, for the additive light that seeps out of them."""
    u, v = grid()
    r = np.sqrt(u * u + v * v)
    a = _cracks_plane()
    img = Image.fromarray((a * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(6))
    g = np.asarray(img).astype(np.float32) / 255.0
    return np.clip(a * 0.9 + g * 1.1 + np.exp(-(r / 0.22) ** 2) * 0.6, 0, 1) * (1.0 - smooth(0.9, 1.0, r))


def comet_tail():
    """Falling-star streak, head at the top of the cell, tapering to nothing at the bottom."""
    u, v = grid()
    y = np.clip((0.86 - v) / 1.80, 0, 1)   # 0 head .. 1 tail end
    width = 0.30 * (1.0 - y) ** 0.75 + 0.02
    env = np.exp(-(u / width) ** 2) * (1.0 - y) ** 1.5
    core = np.exp(-(u / (0.05 + 0.05 * (1.0 - y))) ** 2) * (1.0 - y) ** 1.1
    head = np.exp(-((u / 0.16) ** 2 + ((v - 0.84) / 0.13) ** 2)) * 0.9
    a = env * 0.85 + core + head
    return np.clip(a, 0, 1) * (v < 0.985) * (v > -0.98)


def flare8():
    """Eight-ray impact flare: four long spikes, four short, hot core."""
    u, v = grid()
    r = np.sqrt(u * u + v * v) + 1e-6
    ang = np.arctan2(v, u)
    long_rays = np.exp(-r / 0.40) * np.abs(np.cos(ang * 2.0)) ** 22
    short_rays = np.exp(-r / 0.24) * np.abs(np.sin(ang * 2.0)) ** 22 * 0.85
    core = np.exp(-(r / 0.13) ** 2)
    disc = np.exp(-(r / 0.42) ** 2) * 0.28
    return np.clip(long_rays + short_rays + core + disc, 0, 1) * (1.0 - smooth(0.92, 1.0, r))


def debris_chunk():
    """Irregular rock chunk silhouette (mix layer paints it dark)."""
    u, v = grid()
    rng = np.random.default_rng(606)
    ang = np.arctan2(v, u)
    r = np.sqrt(u * u + v * v)
    n = 9
    radii = rng.uniform(0.45, 0.82, n)
    edge = np.zeros_like(r)
    for k in range(n):
        a0 = k * 2 * math.pi / n
        a1 = (k + 1) * 2 * math.pi / n
        d = ((ang - a0) % (2 * math.pi))
        t = np.clip(d / (a1 - a0), 0, 1)
        seg_r = radii[k] * (1 - t) + radii[(k + 1) % n] * t
        edge = np.where((d >= 0) & (d < (a1 - a0) + 1e-6), seg_r, edge)
    body = 1.0 - smooth(edge - 0.03, edge + 0.01, r)
    return np.clip(body, 0, 1)


def fog_wisp():
    """Ragged elongated fog wisp, lighter than the smoke puff."""
    u, v = grid()
    rr = np.sqrt((u / 1.0) ** 2 + (v / 0.55) ** 2)
    n = fbm(CELL, 3, 4, 707)
    n2 = fbm(CELL, 7, 3, 808)
    shape = 1.0 - smooth(0.25, 1.0, rr + (n - 0.5) * 0.9)
    body = shape * (0.45 + 0.55 * n2)
    body = np.clip(body, 0, 1) * (1.0 - smooth(0.85, 1.0, np.sqrt(u * u + v * v)))
    img = Image.fromarray((body * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(5))
    return np.asarray(img).astype(np.float32) / 255.0 * 0.85


def boss_rune():
    """Summoning circle of the boss gate: heavy outer ring, thorns, runic strokes, an eye."""
    u, v = grid()
    r = np.sqrt(u * u + v * v)
    ang = np.arctan2(v, u)
    rng = np.random.default_rng(909)
    a = np.zeros((CELL, CELL), np.float32)
    a = np.maximum(a, np.exp(-((r - 0.90) / 0.030) ** 2))
    a = np.maximum(a, np.exp(-((r - 0.77) / 0.014) ** 2) * 0.85)
    a = np.maximum(a, np.exp(-((r - 0.46) / 0.014) ** 2) * 0.8)
    for k in range(6):
        th = k * math.pi / 3.0 + math.pi / 6.0
        d = np.abs(((ang - th) + math.pi) % (2 * math.pi) - math.pi)
        spike = (r > 0.80) & (r < 0.995) & (d < 0.11 * np.clip(1.0 - (r - 0.80) / 0.195, 0, 1))
        a = np.maximum(a, spike.astype(np.float32))
    for k in range(14):
        th = rng.uniform(0, 2 * math.pi)
        r0 = rng.uniform(0.52, 0.70)
        r1 = np.clip(r0 + rng.uniform(-0.12, 0.12), 0.50, 0.74)
        dth = rng.uniform(-0.25, 0.25)
        _seg(a, u, v, (math.cos(th) * r0, math.sin(th) * r0), (math.cos(th + dth) * r1, math.sin(th + dth) * r1), 0.013, 0.9)
    # Twelve ticks between the two inner rings.
    for k in range(12):
        th = k * math.pi / 6.0
        _seg(a, u, v, (math.cos(th) * 0.47, math.sin(th) * 0.47), (math.cos(th) * 0.55, math.sin(th) * 0.55), 0.012, 0.7)
    lid = 0.17 * np.sqrt(np.clip(1.0 - (u / 0.30) ** 2, 0, 1))
    eye = np.exp(-((np.abs(v) - lid) / 0.014) ** 2) * (np.abs(u) < 0.30)
    a = np.maximum(a, eye)
    a = np.maximum(a, np.exp(-(r / 0.06) ** 2) * 0.95)
    return np.clip(a, 0, 1) * (r < 0.998)


def thorn_ring():
    """Jagged portal mouth: a wobbling ring with twelve outward thorns and an inner glow."""
    u, v = grid()
    r = np.sqrt(u * u + v * v)
    ang = np.arctan2(v, u)
    r0 = 0.78 + 0.04 * np.sin(ang * 12.0) + 0.025 * np.sin(ang * 5.0 + 1.0)
    band = np.exp(-((r - r0) / 0.045) ** 2)
    thorns = np.zeros_like(r)
    for k in range(12):
        th = k * math.pi / 6.0 + 0.15
        d = np.abs(((ang - th) + math.pi) % (2 * math.pi) - math.pi)
        spike = (r > 0.72) & (r < 0.985) & (d < 0.085 * np.clip(1.0 - (r - 0.72) / 0.265, 0, 1))
        thorns = np.maximum(thorns, spike.astype(np.float32))
    inner = (1.0 - smooth(0.25, 0.78, r)) * 0.28
    return np.clip(band + thorns * 0.95 + inner, 0, 1) * (r < 0.995)


def glow_disc():
    """Soft plateau disc for ground afterglow."""
    u, v = grid()
    r = np.sqrt(u * u + v * v)
    return np.clip(1.0 - smooth(0.42, 1.0, r), 0, 1)


def star_streak():
    """Short bright streak with a hot head: flying star fragments."""
    u, v = grid()
    core = np.exp(-(u / 0.05) ** 2) * (1.0 - smooth(0.55, 0.98, np.abs(v)))
    glow = np.exp(-(u / 0.20) ** 2) * 0.35 * (1.0 - smooth(0.3, 0.9, np.abs(v)))
    head = np.exp(-((u / 0.10) ** 2 + ((v - 0.52) / 0.16) ** 2)) * 0.95
    return np.clip(core + glow + head, 0, 1)


def empty_cell():
    return np.zeros((CELL, CELL), np.float32)


SKILL_SPRITES = [star_sigil, light_pillar, ground_cracks, crack_glow,
                 comet_tail, flare8, debris_chunk, fog_wisp,
                 boss_rune, thorn_ring, glow_disc, star_streak,
                 empty_cell, empty_cell, empty_cell, empty_cell]


SPRITES = [soft_glow, lambda: star(4, 14.0, 0.16), lambda: star(6, 30.0, 0.10), soft_ring,
           smoke_puff, flame, ice_shard, lightning,
           droplet, arrow, tracer, crescent,
           rune_disc, hex_shield, ember_mote, shock_arc]


def build_atlas(sprites=SPRITES) -> Image.Image:
    atlas = np.zeros((CELL * GRID, CELL * GRID, 4), np.float32)
    for index, fn in enumerate(sprites):
        alpha = np.clip(fn(), 0, 1).astype(np.float32)
        row, col = divmod(index, GRID)
        y0, x0 = row * CELL, col * CELL
        atlas[y0:y0 + CELL, x0:x0 + CELL, 0:3] = 1.0
        atlas[y0:y0 + CELL, x0:x0 + CELL, 3] = alpha
    # A one-texel transparent gutter keeps linear sampling from bleeding across cells.
    for k in range(1, GRID):
        atlas[k * CELL - 1:k * CELL + 1, :, 3] = 0.0
        atlas[:, k * CELL - 1:k * CELL + 1, 3] = 0.0
    return Image.fromarray((atlas * 255.0 + 0.5).astype(np.uint8), "RGBA")


def build_noise() -> Image.Image:
    size = 256
    r = fbm(size, 4, 4, 11)
    g = fbm(size, 8, 4, 23)
    b = fbm(size, 16, 3, 37)
    rgb = np.stack([r, g, b], axis=-1)
    rgb = (rgb - rgb.min(axis=(0, 1))) / (rgb.max(axis=(0, 1)) - rgb.min(axis=(0, 1)))
    return Image.fromarray((rgb * 255.0 + 0.5).astype(np.uint8), "RGB")


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    build_atlas().save(OUT / "sprites.png", optimize=True)
    build_atlas(SKILL_SPRITES).save(OUT / "skill_sprites.png", optimize=True)
    build_noise().save(OUT / "noise.png", optimize=True)
    print("wrote", OUT / "sprites.png", OUT / "skill_sprites.png", OUT / "noise.png")
    return 0


if __name__ == "__main__":
    sys.exit(main())
