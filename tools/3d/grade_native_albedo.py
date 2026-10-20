#!/usr/bin/env python3
"""Painted-skin grade for the native character atlases (2026-10-18 casual overhaul, WP-A).

The TRELLIS albedos carry the reconstruction's lighting, near-black shadow, chart speckle and
grey mid-tones (all-49 mean L* 32.6, p10 luminance 0.07-0.10, micro-contrast 18/255). This
module turns the exact-colour EMIT bake of tools/3d/optimize_native_lod.py --retexture into a
painted atlas that carries its own light, inside the chart mask only, in this order:

  1. de-speckle: 3x3 median per channel, then a 2-texel bilateral
  2. chart-flatten (partial delight) only on charts >= 48 texels wide:
     L' = L / blur24(L) * median(L), blended 0.6 (judge_art_director.md W16)
  3. light posterise: 6 levels per channel, blended 0.30
  4. levels: v' = 0.06 + 0.88 * v^0.9, then a per-model gamma lift toward mean luminance 0.47
     (L* 50, capped) and a floor so p10 >= 0.14 (acceptance p10 >= 0.12)
  5. saturation: OKLab chroma x1.20 (monsters x1.15), skin x1.05 with HSV S capped at 0.45
  6. painted light (linear space): rgb *= (0.55 + 0.45 ao)^0.8 * mix(0.82, 1.12, smoothstep(0.05, 0.70, h)),
     cool shade rgb = mix(rgb, rgb * (0.85, 0.90, 1.12), (1 - ao) * 0.5),
     edge light rgb *= 1 + 0.06 * smoothstep(0.92, 1.0, ao)
  7. face paint-back (heroes): above head_start * H raise local contrast x1.3 and push the darkest
     4 % of head texels to L* <= 15

`ao` is a Cycles AO bake of the reduced mesh alone (1 = open), `h` an EMIT bake of clamp(z / H).
Everything runs in numpy + scipy.ndimage (both exist in Blender 4.0's Python). Per-id overrides
live in OVERRIDES and are recorded in the model's report.json / provenance.

CLI (system python, PIL):
    python3 tools/3d/grade_native_albedo.py stats <albedo.png> --cover <cover.png> [--skin <skin.png>]
    python3 tools/3d/grade_native_albedo.py table --work build/character-3d/lod-2026-10-18 --ids a,b \
        --out build/casual-overhaul/after/wp-a/atlas_stats.json
"""
import json, math, sys
from pathlib import Path

import numpy as np
from scipy import ndimage

VERSION = '2026-10-18.7'

PARAMS = {
    # 1. de-speckle
    'median': 3, 'bilateral_radius': 3, 'bilateral_sigma_s': 1.6, 'bilateral_sigma_r': 0.10, 'bilateral_passes': 2,
    # 1b. seam equalisation (per-chart gains solved from UV-seam colour ratios)
    'seam_lambda': 0.3, 'seam_gain_min': 0.7, 'seam_gain_max': 1.4, 'seam_floor': 0.02,
    'seam_chroma_sigma': 0.08, 'seam_small_chart': 96.0, 'seam_ratio_sigma': 0.6,
    # 2. chart-flatten
    'flatten_min_width': 48, 'flatten_blur': 24, 'flatten_blend': 0.4,
    # 3. posterise
    'posterize_levels': 6, 'posterize_blend': 0.30,
    # 4. levels
    'levels_lift': 0.06, 'levels_gain': 0.88, 'levels_gamma': 0.9,
    'p10_floor': 0.17, 'p50_target': 0.42, 'p50_pull': 0.5, 'p50_gain_max': 1.5,
    'dark_additive_lo': 0.04, 'dark_additive_hi': 0.16,
    'lift_saturation_damp': 0.5, 'knee_start': 0.78, 'knee_slope': 0.45, 'knee_saturated_drop': 0.10,
    # 5. saturation
    'chroma_hero': 1.20, 'chroma_monster': 1.15, 'chroma_skin': 1.0, 'skin_s_cap': 0.50, 's_cap': 0.86,
    # 6. painted light
    'ao_floor': 0.55, 'ao_gamma': 0.8, 'ao_smooth': 1.5,
    'height_low': 0.82, 'height_high': 1.12, 'height_lo': 0.05, 'height_hi': 0.70,
    'cool_shade': (0.85, 0.90, 1.12), 'cool_amount': 0.5, 'edge_light': 0.06, 'edge_lo': 0.92,
    # skin detection (sRGB HSV window per texel, then per chart)
    'skin_hue': (8.0, 38.0), 'skin_s': (0.15, 0.60), 'skin_v': (0.35, 0.98),
    'skin_chart_fraction': 0.6, 'skin_chart_mixed': 0.3, 'skin_chart_s_median_max': 0.55, 'skin_chart_s_p90_max': 0.72,
    # 7. face paint-back
    'face_contrast': 1.3, 'face_dark_fraction': 0.04, 'face_dark_lstar': 15.0, 'face_blur': 4.0, 'face_mark_desaturate': 0.8,
    'face_mark_lum': 0.35,
}
# Hero-only overlay (2026-10-18 second follow-up): the hero torso must sit >= +10 L* above the
# showcase roads (tests/arena_visual_review.py contrast rule); monsters keep PARAMS as published.
PARAMS_HERO = {'p50_pull': 0.8, 'p50_gain_max': 2.2, 'p50_target': 0.50, 'lift_saturation_damp': 0.15,
               'ao_floor': 0.65, 'levels_lift': 0.09}
# Per-id overrides (RECORD.md lists every entry with its reason).
OVERRIDES = {
    # charcoal lava rock with glowing cracks: the default mid-tone pull turned the rock light grey
    'magma_brute': {'p50_pull': 0.2, 'p10_floor': 0.15},
    # crowd bodies that sat inside the road's L* band on the showcase fields (WP-C contrast.json,
    # bramble dE 7.6-8.8, ember 10.6): lift the mid-tones and the leaf/ember colour
    # (the bramble atlas has no green: it is a brown twig body, so the lever is lightness + chroma, not hue)
    'bramble_imp': {'p50_pull': 0.9, 'p50_target': 0.52, 'p50_gain_max': 2.6, 'lift_saturation_damp': 0.1, 'p10_floor': 0.16,
                    'chroma_monster': 1.9, 's_cap': 0.92, 'levels_lift': 0.08},
    # ash-grey body with ember spots: lift toward a light figure on the dark volcano floor (chroma <= 1.4, more turns the embers red)
    'ember_imp': {'p50_pull': 0.9, 'p50_target': 0.62, 'p50_gain_max': 2.6, 'lift_saturation_damp': 0.15, 'p10_floor': 0.22,
                  'chroma_monster': 1.4, 's_cap': 0.9, 'levels_lift': 0.12},
}

SKIN_RATIO = 1.05            # r > 1.05 g > 1.05^2 b: skin is always warm-ordered, pale skin only just


# ----------------------------------------------------------------------------- colour maths
def srgb_to_linear(x):
    x = np.asarray(x, np.float32)
    return np.where(x <= 0.04045, x / 12.92, ((x + 0.055) / 1.055) ** 2.4).astype(np.float32)


def linear_to_srgb(x):
    x = np.clip(np.asarray(x, np.float32), 0.0, 1.0)
    return np.where(x <= 0.0031308, x * 12.92, 1.055 * np.power(x, 1 / 2.4) - 0.055).astype(np.float32)


def luminance_srgb(rgb):
    """Rec.709 weights on sRGB-encoded values (the analysis' 'luminance', 0-1)."""
    return (0.2126 * rgb[..., 0] + 0.7152 * rgb[..., 1] + 0.0722 * rgb[..., 2]).astype(np.float32)


def lstar(rgb):
    y = luminance_srgb(srgb_to_linear(rgb)) if rgb.ndim == 3 else srgb_to_linear(rgb)
    y = np.clip(y, 0, 1)
    f = np.where(y > 216 / 24389, np.cbrt(y), (24389 / 27 * y + 16) / 116)
    return (116 * f - 16).astype(np.float32)


def rgb_to_hsv(rgb):
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mx = np.max(rgb, axis=-1); mn = np.min(rgb, axis=-1)
    d = mx - mn
    s = np.where(mx > 1e-6, d / np.maximum(mx, 1e-6), 0.0)
    h = np.zeros_like(mx)
    nz = d > 1e-6
    rc = np.where(nz, (mx - r) / np.maximum(d, 1e-6), 0); gc = np.where(nz, (mx - g) / np.maximum(d, 1e-6), 0)
    bc = np.where(nz, (mx - b) / np.maximum(d, 1e-6), 0)
    h = np.where(mx == r, bc - gc, np.where(mx == g, 2.0 + rc - bc, 4.0 + gc - rc))
    h = np.where(nz, (h / 6.0) % 1.0, 0.0)
    return h.astype(np.float32), s.astype(np.float32), mx.astype(np.float32)


def hsv_to_rgb(h, s, v):
    i = np.floor(h * 6.0); f = h * 6.0 - i
    p = v * (1 - s); q = v * (1 - s * f); t = v * (1 - s * (1 - f))
    i = i.astype(np.int32) % 6
    r = np.choose(i, [v, q, p, p, t, v]); g = np.choose(i, [t, v, v, q, p, p]); b = np.choose(i, [p, p, t, v, v, q])
    return np.stack([r, g, b], axis=-1).astype(np.float32)


_M1 = np.array([[0.4122214708, 0.5363325363, 0.0514459929],
                [0.2119034982, 0.6806995451, 0.1073969566],
                [0.0883024619, 0.2817188376, 0.6299787005]], np.float32)
_M2 = np.array([[0.2104542553, 0.7936177850, -0.0040720468],
                [1.9779984951, -2.4285922050, 0.4505937099],
                [0.0259040371, 0.7827717662, -0.8086757660]], np.float32)
_M2i = np.array([[1.0, 0.3963377774, 0.2158037573],
                 [1.0, -0.1055613458, -0.0638541728],
                 [1.0, -0.0894841775, -1.2914855480]], np.float32)
_M1i = np.array([[4.0767416621, -3.3077115913, 0.2309699292],
                 [-1.2684380046, 2.6097574011, -0.3413193965],
                 [-0.0041960863, -0.7034186147, 1.7076147010]], np.float32)


def linear_to_oklab(lin):
    lms = np.cbrt(np.maximum(lin @ _M1.T, 0.0))
    return lms @ _M2.T


def oklab_to_linear(lab):
    lms = lab @ _M2i.T
    return (lms ** 3) @ _M1i.T


def smoothstep(lo, hi, x):
    t = np.clip((x - lo) / max(hi - lo, 1e-6), 0.0, 1.0)
    return t * t * (3 - 2 * t)


# ----------------------------------------------------------------------------- charts
def label_charts(cover):
    labels, n = ndimage.label(cover)
    slices = ndimage.find_objects(labels)
    return labels, n, slices


def chart_widths(slices):
    return [max(sl[0].stop - sl[0].start, sl[1].stop - sl[1].start) if sl is not None else 0 for sl in slices]


def fill_nearest(values, mask):
    """Every texel outside `mask` takes the value of the nearest texel inside it."""
    if mask.all():
        return values.copy()
    _, (iy, ix) = ndimage.distance_transform_edt(~mask, return_indices=True)
    return values[iy, ix]


def chart_filter(values, labels, slices, kind, size, only=None):
    """Normalised (chart-local) gaussian or box filter of a 2-D field: texels of other charts
    and the gutters never leak into a chart. `only` restricts the work to those labels."""
    out = np.zeros_like(values, dtype=np.float32)
    height, width = values.shape
    pad = int(3 * size) + 1 if kind == 'gaussian' else size
    for i, sl in enumerate(slices, start=1):
        if sl is None or (only is not None and i not in only):
            continue
        y0 = max(sl[0].start - pad, 0); y1 = min(sl[0].stop + pad, height)
        x0 = max(sl[1].start - pad, 0); x1 = min(sl[1].stop + pad, width)
        m = (labels[y0:y1, x0:x1] == i)
        mf = m.astype(np.float32)
        v = values[y0:y1, x0:x1] * mf
        if kind == 'gaussian':
            num = ndimage.gaussian_filter(v, size); den = ndimage.gaussian_filter(mf, size)
        else:
            num = ndimage.uniform_filter(v, size); den = ndimage.uniform_filter(mf, size)
        b = num / np.maximum(den, 1e-6)
        region = out[y0:y1, x0:x1]
        region[m] = b[m]
    return out


# ----------------------------------------------------------------------------- steps
def despeckle(rgb, p):
    out = np.empty_like(rgb)
    for c in range(3):
        out[..., c] = ndimage.median_filter(rgb[..., c], size=p['median'], mode='nearest')
    r = p['bilateral_radius']
    if r <= 0:
        return out
    ss, sr = p['bilateral_sigma_s'], p['bilateral_sigma_r']
    for _ in range(int(p.get('bilateral_passes', 1))):
        acc = np.zeros_like(out); wsum = np.zeros(out.shape[:2], np.float32)
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                shifted = np.roll(np.roll(out, dy, axis=0), dx, axis=1)
                spatial = math.exp(-(dx * dx + dy * dy) / (2 * ss * ss))
                diff = np.sum((shifted - out) ** 2, axis=-1)
                w = spatial * np.exp(-diff / (2 * sr * sr))
                acc += shifted * w[..., None]; wsum += w
        out = (acc / np.maximum(wsum, 1e-6)[..., None]).astype(np.float32)
    return out


def seam_equalize(rgb, labels, n, seams, p, exclude=None):
    """Between-chart delighting. `seams` (from the mesh, tools/3d/optimize_native_lod.py) holds
    texel pairs that sample the same surface line from the two charts meeting at a UV seam:
    a_rc / b_rc (N, 2) texel rows/cols and w (N,) edge-length weights. Any colour ratio across
    such a pair is baked-lighting error, so per-chart log gains x (3 channels) minimise
    sum w (x_i - x_j - log(c_a / c_b))^2 + lambda sum x_i^2 and multiply each chart."""
    if seams is None or n == 0 or len(seams.get('w', [])) == 0:
        return rgb, {'pairs': 0}
    a = np.asarray(seams['a_rc'], np.int64); b = np.asarray(seams['b_rc'], np.int64); w = np.asarray(seams['w'], np.float32)
    la = labels[a[:, 0], a[:, 1]]; lb = labels[b[:, 0], b[:, 1]]
    keep = (la > 0) & (lb > 0) & (la != lb)
    if exclude is not None:
        # Skin charts keep their painted shading and marks: no gain, no pairs.
        keep &= ~exclude[la] & ~exclude[lb]
    if keep.sum() < 4:
        return rgb, {'pairs': 0}
    la, lb, w = la[keep], lb[keep], w[keep]
    # Luminance only: a per-channel gain would tint a tiny dark chart (an eye) toward its
    # bright warm neighbours; one scalar per chart keeps every hue where it was.
    rgb_a = rgb[a[keep, 0], a[keep, 1]]; rgb_b = rgb[b[keep, 0], b[keep, 1]]
    ca = np.maximum(luminance_srgb(rgb_a), p['seam_floor'])
    cb = np.maximum(luminance_srgb(rgb_b), p['seam_floor'])
    ratio = np.log(ca) - np.log(cb)                       # (M,): chart la is brighter by ratio
    # A seam that also separates two colours (an eye against skin, a belt against cloth) is a
    # colour boundary, not lighting error: pairs whose OKLab chroma differs get little weight.
    lab_a = linear_to_oklab(srgb_to_linear(rgb_a)); lab_b = linear_to_oklab(srgb_to_linear(rgb_b))
    d_chroma = np.sqrt(((lab_a[:, 1:] - lab_b[:, 1:]) ** 2).sum(axis=1))
    w = w * np.exp(-(d_chroma / p['seam_chroma_sigma']) ** 2).astype(np.float32)
    # Baked-light steps between charts are tens of percent; a ratio of 2-3x is a colour edge.
    w = w * np.exp(-(ratio / p['seam_ratio_sigma']) ** 2).astype(np.float32)
    lo = np.minimum(la, lb); hi = np.maximum(la, lb)
    sign = np.where(la < lb, 1.0, -1.0)
    key = lo * (n + 1) + hi
    uniq, inv = np.unique(key, return_inverse=True)
    W = np.bincount(inv, weights=w, minlength=len(uniq)).astype(np.float64)
    R = np.bincount(inv, weights=w * ratio * sign, minlength=len(uniq)) / np.maximum(W, 1e-9)   # mean log ratio x_lo - x_hi
    i = (uniq // (n + 1)).astype(np.int64); j = (uniq % (n + 1)).astype(np.int64)
    Wn = W / max(float(W.mean()), 1e-9)
    A = np.zeros((n + 1, n + 1), np.float64)
    np.add.at(A, (i, i), Wn); np.add.at(A, (j, j), Wn); np.add.at(A, (i, j), -Wn); np.add.at(A, (j, i), -Wn)
    # Small charts (an eye, a buckle) have few seam texels and carry the marks: pull their
    # gain harder toward 1 the smaller they are.
    area = np.bincount(labels.ravel(), minlength=n + 1).astype(np.float64)
    A[np.diag_indices(n + 1)] += p['seam_lambda'] * (1.0 + p['seam_small_chart'] / np.maximum(area, 1.0))
    B = np.zeros(n + 1, np.float64)
    np.add.at(B, i, Wn * R); np.add.at(B, j, -Wn * R)
    x = np.linalg.solve(A, B)
    x[0] = 0.0
    gain = np.clip(np.exp(x), p['seam_gain_min'], p['seam_gain_max']).astype(np.float32)
    out = rgb * gain[labels][..., None]
    y = luminance_srgb(np.clip(out, 0, 1))
    out = gamut_fit(out, y)
    return out, {'pairs': int(len(uniq)), 'samples': int(keep.sum()), 'gain_min': round(float(gain[1:].min()), 3),
                 'gain_max': round(float(gain[1:].max()), 3), 'gain_std': round(float(np.log(gain[1:]).std()), 3)}


def flatten_charts(rgb, labels, slices, p, exclude=None):
    """Partial delight of the big charts: divide the luminance by its chart-local low-pass and
    re-scale to the chart median (keeps the texture, removes the baked light gradient)."""
    widths = chart_widths(slices)
    big = {i for i, w in enumerate(widths, start=1) if w >= p['flatten_min_width'] and not (exclude is not None and exclude[i])}
    if not big:
        return rgb, 0
    lum = np.maximum(luminance_srgb(rgb), 1e-4)
    blur = chart_filter(lum, labels, slices, 'gaussian', p['flatten_blur'] / 2.0, only=big)
    out = rgb.copy()
    for i in big:
        sl = slices[i - 1]
        m = labels[sl] == i
        l_chart = lum[sl]; b_chart = blur[sl]
        med = float(np.median(l_chart[m]))
        ratio = np.ones_like(l_chart)
        ratio[m] = (l_chart[m] / np.maximum(b_chart[m], 0.02)) * med / l_chart[m]
        ratio = np.clip(ratio, 0.5, 2.0)
        blended = 1.0 + (ratio - 1.0) * p['flatten_blend']
        region = out[sl]
        region[m] = np.clip(rgb[sl][m] * blended[m][:, None], 0, 1)
    return out, len(big)


def posterize(rgb, p, skip=None):
    """Light value quantisation (painted simplification); skin keeps its smooth gradient."""
    n = p['posterize_levels'] - 1
    q = np.round(rgb * n) / n
    blend = np.full(rgb.shape[:2], p['posterize_blend'], np.float32)
    if skip is not None:
        blend[skip] = 0.0
    return (rgb + (q - rgb) * blend[..., None]).astype(np.float32)


def gamut_fit(rgb, y):
    """Pull chroma toward the luminance `y` wherever a channel exceeds 1 (hue and luminance kept)."""
    out = rgb.copy()
    m = out.max(axis=-1)
    over = m > 1.0
    if over.any():
        yy = y[over][:, None]; o = out[over]
        scale = (1.0 - yy) / np.maximum(o.max(axis=-1, keepdims=True) - yy, 1e-4)
        out[over] = yy + (o - yy) * np.minimum(scale, 1.0)
    return np.clip(out, 0, 1).astype(np.float32)


def levels(rgb, cover, p):
    """Luminance levels that keep chroma: the tone curve, the per-model gamma lift and the p10
    floor act on Y; mid-tones take the lift as a multiplicative gain (a dark red stays red), the
    near-black range takes it additively (noisy blacks become neutral dark grey, not tinted)."""
    y = np.maximum(luminance_srgb(rgb), 1e-4)
    y1 = p['levels_lift'] + p['levels_gain'] * np.power(y, p['levels_gamma'])
    # Per-model remap through the luminance percentiles: p10 up to the floor, p50 pulled
    # halfway toward the painted mid-tone (never above 1.5x, never down), p90 kept. A dark
    # identity (black hair, charcoal trousers) keeps its darks at L* 15-25 instead of mid grey.
    q10, q50, q90 = (float(np.percentile(y1[cover], q)) for q in (10, 50, 90))
    t10 = max(q10, p['p10_floor'])
    t50 = q50 + max(0.0, p['p50_target'] - q50) * p['p50_pull']
    t50 = min(t50, q50 * p['p50_gain_max'])
    t50 = max(t50, t10 + 0.04)
    t90 = max(q90, t50 + 0.04)
    xs = [0.0, q10, q50, q90, 1.0]; ys = [0.0, t10, t50, t90, 1.0]
    for k_ in range(1, 5):
        xs[k_] = max(xs[k_], xs[k_ - 1] + 1e-4); ys[k_] = max(ys[k_], ys[k_ - 1] + 1e-4)
    y2 = np.interp(y1, xs, ys).astype(np.float32)
    # Saturated identity colours take less of the lift: a lift toward white is what turns a
    # deep red into pink under the tonemapper; painted reds sit at V 0.6-0.8 instead.
    _, sat, _ = rgb_to_hsv(rgb)
    y1 = y1 + (y2 - y1) * (1.0 - p['lift_saturation_damp'] * sat)
    y1 = np.clip(y1, 0, 1).astype(np.float32)
    mean, k, p10, lo = float(y1[cover].mean()), round(t50 / max(q50, 1e-4), 3), q10, t10 - q10
    mult = rgb * (y1 / y)[..., None]
    add = rgb + (y1 - y)[..., None]
    w = smoothstep(p['dark_additive_lo'], p['dark_additive_hi'], y)[..., None]
    out = gamut_fit(add + (mult - add) * w, y1)
    # Highlight knee on the strongest channel: painted colours never reach full intensity,
    # and saturated ones sit lower still (a V 0.8 red clips under the key, a V 0.7 red does not).
    m = out.max(axis=-1)
    _, sat2, _ = rgb_to_hsv(out)
    start = p['knee_start'] - p['knee_saturated_drop'] * sat2
    knee = np.where(m > start, start + (m - start) * p['knee_slope'], m)
    out = out * (knee / np.maximum(m, 1e-4))[..., None]
    return np.clip(out, 0, 1).astype(np.float32), {'lum_mean_after_remap': round(mean, 4), 'p50_gain': k, 'p10_before': round(p10, 4), 'p10_lift': round(lo, 4), 'remap': [[round(a_, 3), round(b_, 3)] for a_, b_ in zip(xs, ys)]}


def skin_mask(rgb, cover, labels, slices, p=None):
    """Skin texels: the finisher's warm ordering (finish_native_character.py:193 uses r > 1.18 g >
    1.18^2 b inside known skin regions; over a whole atlas that rejects pale skin, so the ratio is
    1.05 here) inside the skin-tone HSV window, decided per chart (>= 50 % of its texels), per
    texel in mixed charts (25-50 %)."""
    p = p or PARAMS
    h, s, v = rgb_to_hsv(rgb)
    deg = h * 360.0
    texel = (rgb[..., 0] > SKIN_RATIO * rgb[..., 1]) & (rgb[..., 1] > SKIN_RATIO * rgb[..., 2]) & (rgb[..., 0] > 0.12)
    texel &= (deg >= p['skin_hue'][0]) & (deg <= p['skin_hue'][1]) & (s >= p['skin_s'][0]) & (s <= p['skin_s'][1]) & (v >= p['skin_v'][0]) & (v <= p['skin_v'][1])
    texel &= cover
    n = len(slices)
    if n == 0:
        skin_mask.last_chart_fraction = np.zeros(1, np.float32)
        skin_mask.last_texel = texel
        return texel
    idx = np.arange(1, n + 1)
    frac = np.nan_to_num(np.asarray(ndimage.mean(texel.astype(np.float32), labels, index=idx), np.float32))
    # Red or gold armour has skin-like hues at higher saturation: a chart whose saturation
    # median or p90 is high is equipment, whatever its hue.
    s_med = np.nan_to_num(np.asarray(ndimage.median(s, labels, index=idx), np.float32))
    s_p90 = np.nan_to_num(np.asarray(ndimage.labeled_comprehension(s, labels, idx, lambda x: np.percentile(x, 90), np.float32, 0.0), np.float32))
    armour = (s_med > p['skin_chart_s_median_max']) | (s_p90 > p['skin_chart_s_p90_max'])
    frac = np.where(armour, 0.0, frac)
    chart_skin = np.zeros(n + 1, np.float32); chart_skin[1:] = frac
    per_chart = chart_skin[labels]
    out = (per_chart >= p['skin_chart_fraction']) | ((per_chart >= p['skin_chart_mixed']) & texel)
    skin_mask.last_chart_fraction = chart_skin
    skin_mask.last_texel = texel
    return out & cover


def saturate(rgb, cover, skin, kind, p):
    factor = np.full(rgb.shape[:2], p['chroma_monster'] if kind == 'monster' else p['chroma_hero'], np.float32)
    factor[skin] = p['chroma_skin']
    lin = srgb_to_linear(rgb)
    lab = linear_to_oklab(lin)
    lab[..., 1] *= factor; lab[..., 2] *= factor
    boosted = oklab_to_linear(lab)
    out = linear_to_srgb(gamut_fit(np.maximum(boosted, 0.0), luminance_srgb(lin)))
    # Painted colours never reach full saturation either: a 0.97 red clips under the key and
    # the tonemapper skews it toward orange; skin stays well below that.
    h, s, v = rgb_to_hsv(out)
    cap = np.where(skin, p['skin_s_cap'], p['s_cap']).astype(np.float32)
    s2 = np.minimum(s, cap)
    out = hsv_to_rgb(h, s2, v)
    return np.clip(out, 0, 1).astype(np.float32)


def painted_light(rgb, ao, height, p):
    lin = srgb_to_linear(rgb)
    shade = np.power(p['ao_floor'] + (1 - p['ao_floor']) * ao, p['ao_gamma'])
    shade *= p['height_low'] + (p['height_high'] - p['height_low']) * smoothstep(p['height_lo'], p['height_hi'], height)
    lin = lin * shade[..., None]
    cool = lin * np.asarray(p['cool_shade'], np.float32)
    lin = lin + (cool - lin) * ((1.0 - ao) * p['cool_amount'])[..., None]
    lin = lin * (1.0 + p['edge_light'] * smoothstep(p['edge_lo'], 1.0, ao))[..., None]
    return linear_to_srgb(np.clip(lin, 0, 1))


def face_paint_back(rgb, cover, labels, slices, height, head_start, p, skin=None, skin_chart_fraction=None, skin_texel=None):
    head = cover & (height > head_start)
    if head.sum() < 64:
        return rgb, {'head_texels': int(head.sum())}
    lum = np.maximum(luminance_srgb(rgb), 1e-4)
    n = len(slices)
    frac = np.nan_to_num(np.asarray(ndimage.mean(head.astype(np.float32), labels, index=np.arange(1, n + 1)), np.float32))
    head_charts = {i for i, f in enumerate(frac, start=1) if f >= 0.5}
    local = chart_filter(lum, labels, slices, 'gaussian', p['face_blur'], only=head_charts)
    out = rgb.copy()
    sel = head & (local > 0)
    new = local[sel] + (lum[sel] - local[sel]) * p['face_contrast']
    scale = np.clip(new / lum[sel], 0.5, 1.8)
    out[sel] = np.clip(rgb[sel] * scale[:, None], 0, 1)
    lum2 = luminance_srgb(out)
    thresh = float(np.percentile(lum2[head], p['face_dark_fraction'] * 100))
    dark = head & (lum2 <= thresh)
    if skin is not None and skin_chart_fraction is not None and len(skin_chart_fraction) == len(slices) + 1:
        # The marks (eyes, brows, mouth) are the dark, non-skin-coloured texels inside the
        # skin charts of the head; the darkest-4 % rule alone finds hair on a dark-haired hero.
        in_skin_chart = skin_chart_fraction[labels] >= p['skin_chart_mixed']
        not_skin = ~skin_texel if skin_texel is not None else ~skin
        marks = head & in_skin_chart & not_skin & (lum2 < p['face_mark_lum'])
        dark = dark | marks
    y_target = ((p['face_dark_lstar'] + 16) / 116) ** 3          # linear Y of L* 15 ~ 0.0197
    target = float(linear_to_srgb(np.float32(y_target)))         # sRGB-luminance equivalent ~ 0.145
    too_bright = dark & (lum2 > target)
    if too_bright.any():
        out[too_bright] = out[too_bright] * (target / lum2[too_bright])[:, None]
    # Eyes, brows and the mouth are ink, not tinted shadow: pull the marks toward neutral.
    gray = luminance_srgb(out[dark])[:, None]
    out[dark] = out[dark] + (gray - out[dark]) * p['face_mark_desaturate']
    return np.clip(out, 0, 1).astype(np.float32), {'head_texels': int(head.sum()), 'head_charts': len(head_charts), 'dark_threshold': round(thresh, 4), 'mark_texels': int(dark.sum())}


# ----------------------------------------------------------------------------- statistics
def dominant_hues(rgb, mask, min_mass=0.05):
    h, s, v = rgb_to_hsv(rgb)
    sel = mask & (s >= 0.25) & (v >= 0.15)
    if sel.sum() < 16:
        return []
    bins = 24
    hist, _ = np.histogram(h[sel], bins=bins, range=(0, 1))
    hist = hist.astype(np.float32)
    sm = (np.roll(hist, 1) + 2 * hist + np.roll(hist, -1)) / 4.0
    total = max(float(sm.sum()), 1.0)
    peaks = []
    for i in range(bins):
        if sm[i] >= sm[(i - 1) % bins] and sm[i] >= sm[(i + 1) % bins] and sm[i] / total >= min_mass:
            peaks.append((i, float(sm[i] / total)))
    merged = []
    for i, mass in sorted(peaks, key=lambda t: -t[1]):
        deg = (i + 0.5) * 360.0 / bins
        if all(min(abs(deg - d), 360 - abs(deg - d)) > 30 for d, _ in merged):
            merged.append((deg, mass))
    return [{'hue_deg': round(d, 1), 'mass': round(m, 3)} for d, m in merged]


def atlas_stats(rgb, cover, labels=None, slices=None, skin=None):
    """Numbers the plan judges: mean L*, luminance percentiles, near-black fraction, saturation,
    chart-aware micro-contrast (|texel - 13-texel chart box blur|, /255), dominant hues, skin."""
    rgb = np.asarray(rgb, np.float32)
    if rgb.max() > 1.5:
        rgb = rgb / 255.0
    if labels is None:
        labels, _, slices = label_charts(cover)
    used = cover
    lum = luminance_srgb(rgb)
    ls = lstar(rgb)
    h, s, v = rgb_to_hsv(rgb)
    blur = chart_filter(lum, labels, slices, 'box', 13)
    inner = ndimage.binary_erosion(cover, iterations=1)
    micro = float(np.abs(lum - blur)[inner].mean() * 255.0) if inner.any() else 0.0
    lap = np.abs(4 * lum - np.roll(lum, 1, 0) - np.roll(lum, -1, 0) - np.roll(lum, 1, 1) - np.roll(lum, -1, 1))
    inner2 = ndimage.binary_erosion(cover, iterations=2)
    out = {
        'used_texels': int(used.sum()), 'charts': int(labels.max()),
        'mean_lstar': round(float(ls[used].mean()), 2),
        'lum_mean': round(float(lum[used].mean()), 4),
        'lum_p10': round(float(np.percentile(lum[used], 10)), 4),
        'lum_p50': round(float(np.percentile(lum[used], 50)), 4),
        'lum_p90': round(float(np.percentile(lum[used], 90)), 4),
        'lstar_p10': round(float(np.percentile(ls[used], 10)), 2),
        'near_black_fraction': round(float((lum[used] < 0.15).mean()), 4),
        'sat_mean': round(float(s[used].mean()), 4),
        'sat_p90': round(float(np.percentile(s[used], 90)), 4),
        'micro_contrast_255': round(micro, 2),
        'laplacian_mean': round(float(lap[inner2].mean()), 4) if inner2.any() else 0.0,
        'dominant_hues': dominant_hues(rgb, used),
    }
    out['dominant_hue_count'] = len(out['dominant_hues'])
    if skin is not None and skin.any():
        out['skin'] = {'texels': int(skin.sum()), 'mean_lstar': round(float(ls[skin].mean()), 2),
                       'sat_mean': round(float(s[skin].mean()), 4), 'sat_p90': round(float(np.percentile(s[skin], 90)), 4),
                       'sat_max': round(float(s[skin].max()), 4)}
    return out


# ----------------------------------------------------------------------------- the grade
def params_for(cid, kind, overrides=None):
    p = dict(PARAMS)
    if kind != 'monster':
        p.update(PARAMS_HERO)
    table = OVERRIDES if overrides is None else overrides
    p.update(table.get(cid, {}))
    return p


def grade(rgb, cover, ao, height, kind, cid, head_start=0.675, overrides=None, seams=None):
    """rgb: (H, W, 3) sRGB floats 0-1 (every texel defined: nearest-filled bake); cover: bool chart
    mask; ao, height: (H, W) floats 0-1. Returns (graded rgb, info). Only texels inside `cover`
    are meaningful in the result."""
    p = params_for(cid, kind, overrides)
    labels, n, slices = label_charts(cover)
    info = {'version': VERSION, 'params': {k: (list(v) if isinstance(v, tuple) else v) for k, v in p.items()},
            'override': (OVERRIDES if overrides is None else overrides).get(cid, {}), 'charts': int(n)}
    work = np.clip(np.asarray(rgb, np.float32), 0, 1)
    work = despeckle(work, p)
    skin_mask(work, cover, labels, slices, p)
    skin_charts = getattr(skin_mask, 'last_chart_fraction', np.zeros(n + 1, np.float32)) >= p['skin_chart_mixed']
    info['skin_charts_excluded'] = int(skin_charts[1:].sum())
    work, info['seams'] = seam_equalize(work, labels, n, seams, p, exclude=skin_charts)
    work, info['flattened_charts'] = flatten_charts(work, labels, slices, p, exclude=skin_charts)
    work = posterize(work, p, skip=skin_charts[labels])
    work, info['levels'] = levels(work, cover, p)
    skin = skin_mask(work, cover, labels, slices, p)
    info['skin_texels'] = int(skin.sum())
    work = saturate(work, cover, skin, kind, p)
    ao_f = fill_nearest(np.clip(ao, 0, 1).astype(np.float32), cover)
    if p['ao_smooth'] > 0:
        ao_f = ndimage.gaussian_filter(ao_f, p['ao_smooth'])
    h_f = fill_nearest(np.clip(height, 0, 1).astype(np.float32), cover)
    info['ao_mean'] = round(float(ao_f[cover].mean()), 4)
    info['ao_p10'] = round(float(np.percentile(ao_f[cover], 10)), 4)
    work = painted_light(work, ao_f, h_f, p)
    if kind == 'hero':
        work, info['face'] = face_paint_back(work, cover, labels, slices, h_f, head_start, p, skin=skin,
                                             skin_chart_fraction=getattr(skin_mask, 'last_chart_fraction', None),
                                             skin_texel=getattr(skin_mask, 'last_texel', None))
    return np.clip(work, 0, 1).astype(np.float32), info, skin


# ----------------------------------------------------------------------------- CLI
def _load_png(path):
    from PIL import Image
    return np.asarray(Image.open(path).convert('RGB')).astype(np.float32) / 255.0


def _load_mask(path):
    from PIL import Image
    return np.asarray(Image.open(path).convert('L')) > 127


def _cli():
    import argparse
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('mode', choices=['stats', 'table'])
    ap.add_argument('albedo', nargs='?')
    ap.add_argument('--cover')
    ap.add_argument('--skin')
    ap.add_argument('--work')
    ap.add_argument('--ids', default='')
    ap.add_argument('--out')
    a = ap.parse_args()
    if a.mode == 'stats':
        rgb = _load_png(a.albedo)
        cover = _load_mask(a.cover) if a.cover else np.ones(rgb.shape[:2], bool)
        skin = _load_mask(a.skin) if a.skin else None
        print(json.dumps(atlas_stats(rgb, cover, skin=skin), indent=1))
        return
    work = Path(a.work)
    ids = [i for i in a.ids.split(',') if i] or sorted(p.parent.name for p in work.glob('*/report.json'))
    rows = {}
    for cid in ids:
        report = json.loads((work / cid / 'report.json').read_text())
        rt = report.get('retexture', {})
        rows[cid] = {'kind': report.get('kind'), 'before': rt.get('stats_before'), 'after': rt.get('stats_after'),
                     'override': rt.get('grade', {}).get('override', {}), 'geometry_bytes_preserved': rt.get('geometry_bytes_preserved'),
                     'glb_sha256': report.get('after', {}).get('glb_sha256')}
    if a.out:
        Path(a.out).write_text(json.dumps(rows, indent=1) + '\n')
    header = '| id | kind | mean L* b→a | p10 b→a | p50 b→a | micro b→a | hues b→a | skin L*/S | geometry |'
    lines = [header, '|---|---|---|---|---|---|---|---|---|']
    for cid, r in rows.items():
        b, x = r['before'] or {}, r['after'] or {}
        skin = x.get('skin') or {}
        lines.append('| %s | %s | %.1f → %.1f | %.3f → %.3f | %.3f → %.3f | %.1f → %.1f | %d → %d | %s | %s |' % (
            cid, r['kind'], b.get('mean_lstar', 0), x.get('mean_lstar', 0), b.get('lum_p10', 0), x.get('lum_p10', 0),
            b.get('lum_p50', 0), x.get('lum_p50', 0), b.get('micro_contrast_255', 0), x.get('micro_contrast_255', 0),
            b.get('dominant_hue_count', 0), x.get('dominant_hue_count', 0),
            ('%.0f / %.2f' % (skin.get('mean_lstar', 0), skin.get('sat_p90', 0))) if skin else '-',
            'kept' if r['geometry_bytes_preserved'] else 'CHANGED'))
    print('\n'.join(lines))


if __name__ == '__main__':
    _cli()
