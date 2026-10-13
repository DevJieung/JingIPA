#!/usr/bin/env python3
"""Tileable pattern texture for the arena battlefield shaders.

    python3 tools/3d/gen_terrain_noise.py

Output (deterministic, no external art):
  art/models/terrain_noise.png  512x512 RGBA, every channel tiles and is a smooth field
  that the shaders threshold themselves, so one small texture gives crisp plates, cracks,
  pools and drifts at any scale (art/models/arena_*.gdshader):
    R  cloud      five octaves of gradient noise (patches, pools, colour drift)
    G  crack      distance to the nearest cell border, 0 on the border (plates, cracks)
    B  cell       one flat random value per cell (plate tone, scattered marks)
    A  ridge      ridged noise, bright along thin winding lines (ripples, roots, veins)

After writing a new file run `bash tools/godot_import.sh` once; the import settings in
terrain_noise.png.import (lossless, mipmaps, repeat is set by the samplers) are kept.
"""
from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "art/models/terrain_noise.png"
SIZE = 512
CELLS = 20


def fade(t):
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)


def gradient_noise(size: int, period: int, rng) -> np.ndarray:
    """Tileable 2D gradient noise in roughly [-1, 1] with `period` cells per side."""
    angles = rng.random((period, period)) * np.pi * 2.0
    gx, gy = np.cos(angles), np.sin(angles)
    y, x = np.mgrid[0:size, 0:size].astype(np.float64)
    fx, fy = x / size * period, y / size * period
    x0, y0 = np.floor(fx).astype(int), np.floor(fy).astype(int)
    tx, ty = fx - x0, fy - y0
    x1, y1 = (x0 + 1) % period, (y0 + 1) % period
    x0, y0 = x0 % period, y0 % period

    def corner(ix, iy, dx, dy):
        return gx[iy, ix] * dx + gy[iy, ix] * dy

    n00 = corner(x0, y0, tx, ty)
    n10 = corner(x1, y0, tx - 1.0, ty)
    n01 = corner(x0, y1, tx, ty - 1.0)
    n11 = corner(x1, y1, tx - 1.0, ty - 1.0)
    u, v = fade(tx), fade(ty)
    return (n00 * (1 - u) + n10 * u) * (1 - v) + (n01 * (1 - u) + n11 * u) * v


def fbm(size: int, period: int, octaves: int, rng, ridged: bool = False) -> np.ndarray:
    total = np.zeros((size, size))
    weight, norm = 1.0, 0.0
    for octave in range(octaves):
        layer = gradient_noise(size, period * 2 ** octave, rng) * 1.5
        if ridged:
            layer = 1.0 - np.abs(layer)
            layer = layer * layer
        total += layer * weight
        norm += weight
        weight *= 0.5
    return total / norm


def cells(size: int, count: int, rng):
    """Tileable Worley cells: (distance to the nearest border, random value of the cell)."""
    jitter = rng.random((count, count, 2)) * 0.84 + 0.08
    value = rng.random((count, count))
    y, x = np.mgrid[0:size, 0:size].astype(np.float64)
    fx, fy = x / size * count, y / size * count
    cx, cy = np.floor(fx).astype(int), np.floor(fy).astype(int)
    first = np.full((size, size), 9.0)
    second = np.full((size, size), 9.0)
    first_dx = np.zeros((size, size))
    first_dy = np.zeros((size, size))
    second_dx = np.zeros((size, size))
    second_dy = np.zeros((size, size))
    ident = np.zeros((size, size))
    for oy in (-1, 0, 1):
        for ox in (-1, 0, 1):
            nx, ny = (cx + ox) % count, (cy + oy) % count
            dx = cx + ox + jitter[ny, nx, 0] - fx
            dy = cy + oy + jitter[ny, nx, 1] - fy
            dist = dx * dx + dy * dy
            closer = dist < first
            between = (~closer) & (dist < second)
            second = np.where(closer, first, np.where(between, dist, second))
            second_dx = np.where(closer, first_dx, np.where(between, dx, second_dx))
            second_dy = np.where(closer, first_dy, np.where(between, dy, second_dy))
            first = np.where(closer, dist, first)
            first_dx = np.where(closer, dx, first_dx)
            first_dy = np.where(closer, dy, first_dy)
            ident = np.where(closer, value[ny, nx], ident)
    # Exact distance to the bisector between the two nearest sites (even line width).
    mx, my = (first_dx + second_dx) * 0.5, (first_dy + second_dy) * 0.5
    ex, ey = second_dx - first_dx, second_dy - first_dy
    length = np.sqrt(ex * ex + ey * ey) + 1e-9
    border = np.abs(mx * ex + my * ey) / length
    return border, ident


def main() -> None:
    rng = np.random.default_rng(20261013)
    cloud = fbm(SIZE, 4, 5, rng)
    cloud = (cloud - cloud.min()) / (cloud.max() - cloud.min())
    border, ident = cells(SIZE, CELLS, rng)
    # 0 on a border, 1 from 0.42 of a cell inward: wide enough for thick glowing seams.
    crack = np.clip(border / 0.42, 0.0, 1.0)
    ridge = fbm(SIZE, 5, 4, rng, ridged=True)
    ridge = (ridge - ridge.min()) / (ridge.max() - ridge.min())
    rgba = np.stack([cloud, crack, ident, ridge], axis=-1)
    Image.fromarray(np.clip(rgba * 255.0 + 0.5, 0, 255).astype(np.uint8), "RGBA").save(OUT)
    print(f"wrote {OUT.relative_to(ROOT)} {SIZE}x{SIZE}  cloud mean {cloud.mean():.3f}  crack mean {crack.mean():.3f}  ridge mean {ridge.mean():.3f}")


if __name__ == "__main__":
    main()
