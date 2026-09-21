#!/usr/bin/env python3
"""Extract forward-only H3 locomotion loops, preserving articulated legs and wings."""
from __future__ import annotations
import argparse
import html
import json
import subprocess
import time
from pathlib import Path
import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage as ndi
from monster_motion import ROOT, SOURCE, TAKES, GAME, CELL, gen_art, movement, savejson
from world_h3_post import cutout, checker


def color_safe_cutout(image, separate_crystal=False):
    """Preserve dark burgundy caps/petals and the idol's separate crown crystal.

    A broad hue flood can cross a purple outline and erase a mushroom cap.
    These references use a uniform key, so compare normalized RGB proportions.
    """
    rgb = np.array(image.convert('RGB').resize((256, 256), Image.Resampling.NEAREST))
    f = rgb.astype('float32')
    corner = np.median(np.concatenate([f[:6, :6].reshape(-1, 3),
                       f[:6, -6:].reshape(-1, 3), f[-6:, :6].reshape(-1, 3),
                       f[-6:, -6:].reshape(-1, 3)]), axis=0)
    high = f.max(axis=2)
    normalized = f / np.maximum(high[:, :, None], 1)
    distance = np.linalg.norm(normalized-corner/max(corner.max(), 1), axis=2)
    # H3 can turn the key pink; dark wine petals then share its hue but retain
    # very different brightness. Only exact chroma proportions tolerate shade.
    residual = np.max(abs(f-corner), axis=2)
    background = ((distance < .27) & (residual < 50) | (distance < .065)) & (high > 80)
    labels, _ = ndi.label(~background)
    sizes = np.bincount(labels.ravel())
    sizes[0] = 0
    keep = np.argsort(sizes)[-(2 if separate_crystal else 1):]
    foreground = np.isin(labels, keep) & (labels > 0)
    out = np.dstack([rgb, np.where(foreground, 255, 0).astype('uint8')])
    out[~foreground] = 0
    return Image.fromarray(out)


def stabilize(frames, reference=60):
    """Register the torso by translation, with one fixed scale for the entire take.

    Never copy a foot patch or mirror the timeline: both destroy walking cycles.
    """
    ref = frames[reference]
    x0, y0, x1, y1 = ref.getbbox()
    cx = (x0+x1)//2
    cy = round(y0+(y1-y0)*0.44)
    tw = max(12, min(44, (x1-x0)//3))
    th = max(12, min(40, (y1-y0)//4))
    box = (cx-tw//2, cy-th//2, cx+tw//2, cy+th//2)
    template = np.asarray(ref.convert('RGB'))[box[1]:box[3], box[0]:box[2]].copy()
    out = {}
    shifts = []
    for i, frame in frames.items():
        searchbox = (max(0, box[0]-16), max(0, box[1]-16), min(256, box[2]+16), min(256, box[3]+16))
        pixels = np.asarray(frame.convert('RGB'))
        search = pixels[searchbox[1]:searchbox[3], searchbox[0]:searchbox[2]]
        scores = cv2.matchTemplate(search, template, cv2.TM_SQDIFF_NORMED)
        _, _, loc, _ = cv2.minMaxLoc(scores)
        dx, dy = box[0]-searchbox[0]-loc[0], box[1]-searchbox[1]-loc[1]
        canvas = Image.new('RGBA', (256, 256))
        canvas.paste(frame, (dx, dy))
        out[i] = canvas
        shifts.append((dx, dy))
    return out, shifts


def choose_loop(frames):
    arrays = {i: np.asarray(f.resize((64, 64), Image.Resampling.NEAREST)).astype('float32')/255 for i, f in frames.items()}
    candidates = []
    for start in range(30, 87, 2):
        # Up to 21 frames: 21 * 192 = 4032px, within a 4096px mobile texture.
        for length in range(18, 43, 2):
            end = start+length
            if end+2 not in arrays:
                continue
            a, b = arrays[start], arrays[end]
            union = (a[:, :, 3] > 0) | (b[:, :, 3] > 0)
            if union.sum() < 20:
                continue
            seam = float(np.abs(a-b)[union].mean())
            velocity = float(np.abs((arrays[start+2]-a)-(arrays[end+2]-b))[union].mean())
            middle = arrays[start+length//2]
            motion = float(np.abs(middle-a)[union].mean())
            # A still hold is not a walking cycle even if its endpoints match perfectly.
            score = seam + velocity*0.2 + max(0, .07-motion)*2
            candidates.append((score, start, end, seam, motion))
    score, start, end, seam, motion = min(candidates)
    return list(range(start, end, 2)), dict(start=start, end=end, seam=round(seam, 4),
            motion=round(motion, 4), selection_score=round(score, 4))


def post(m, force=False):
    src = TAKES / m['id']
    dst = GAME / m['id']
    if not (src/'generation.json').exists():
        return False
    if not (src/'source.mp4').exists():
        subprocess.run(['ffmpeg', '-v', 'error', '-y', '-framerate', '24', '-i',
                        str(src/'raw'/'f_%04d.png'), '-c:v', 'libx264', '-threads', '2',
                        '-crf', '18', '-pix_fmt', 'yuv420p', str(src/'source.mp4')], check=True)
    if (dst/'anim.json').exists() and not force:
        return True
    print('POST START', m['id'], flush=True)
    generation = json.loads((src/'generation.json').read_text())
    # Exclude the final return to the reference pose in pinned takes.
    end = 108 if generation.get('pin_last', False) else 124
    frames = {}
    for i in range(28, end):
        image = Image.open(src/'raw'/f'f_{i:04d}.png')
        frames[i] = (color_safe_cutout(image, m['id'] == 'runestone_idol')
                     if m['id'] in {'spore_cap', 'titan_bloom', 'runestone_idol'}
                     else cutout(image))
        if m['id'] == 'titan_bloom':
            # White openings trapped inside the Krea root/arm silhouette are
            # backdrop, distinct from the warm cream teeth and flower petals.
            pixels = np.array(frames[i])
            rgb = pixels[:, :, :3].astype('int16')
            white_hole = (rgb.min(axis=2) > 238) & (np.ptp(rgb, axis=2) < 20)
            pixels[white_hole] = 0
            frames[i] = Image.fromarray(pixels)
    if m['body'] != 'wood':
        # H3 darkens green trapped between tentacles; exterior color fitting alone
        # misses those holes. Cyan water/ice and pale foam remain below these limits.
        for i, frame in frames.items():
            a = np.array(frame)
            rgb = a[:, :, :3].astype('int16')
            green = ((rgb[:, :, 1] > rgb[:, :, 0] + 38) &
                     (rgb[:, :, 1] > rgb[:, :, 2] + 42) & (rgb[:, :, 1] > 90) &
                     ((rgb.max(axis=2)-rgb.min(axis=2)) > rgb.max(axis=2)*.45))
            a[green] = 0
            frames[i] = Image.fromarray(a)
    if any(f.getbbox() is None for f in frames.values()):
        raise RuntimeError('Missing foreground: '+m['id'])
    if any(not .01 < np.mean(np.asarray(f)[:, :, 3] > 0) < .65 for f in frames.values()):
        raise RuntimeError('Background matte needs review: '+m['id'])
    source_clipping = {}
    for i, f in frames.items():
        a = np.asarray(f)[:, :, 3]
        source_clipping[i] = bool(np.any(a[0]) or np.any(a[-1]) or np.any(a[:, 0]) or np.any(a[:, -1]))
    frames, shifts = stabilize(frames)
    selection_file = src/'selection.json'
    if selection_file.exists():
        selection = json.loads(selection_file.read_text())
        indices = list(range(selection['start'], selection['end'], selection.get('step', 2)))
    else:
        indices, selection = choose_loop(frames)
    if movement(m) in {'walk', 'fly'} and selection.get('motion', 1.0) < 0.025:
        raise RuntimeError('No readable locomotion cycle: ' + m['id'])
    if selection.get('seam', 0.0) > 0.24:
        raise RuntimeError('Loop needs manual review: ' + m['id'])
    if any(source_clipping[i] for i in indices):
        raise RuntimeError('H3 source clips an extremity: ' + m['id'])
    boxes = [frames[i].getbbox() for i in indices]
    box = (min(b[0] for b in boxes), min(b[1] for b in boxes), max(b[2] for b in boxes), max(b[3] for b in boxes))
    width, height = box[2]-box[0], box[3]-box[1]
    scale = min((CELL-16)/width, (CELL-20)/height)
    outsize = (round(width*scale), round(height*scale))
    anchor = (CELL//2, CELL-10)
    xy = (anchor[0]-outsize[0]//2, anchor[1]-outsize[1])
    palette = frames[indices[0]].convert('RGB').quantize(colors=64, method=Image.Quantize.MEDIANCUT)
    used = []
    for i in indices:
        frame = frames[i]
        rgb = frame.convert('RGB').quantize(palette=palette, dither=Image.Dither.NONE).convert('RGBA')
        rgb.putalpha(frame.getchannel('A'))
        rgb = rgb.crop(box).resize(outsize, Image.Resampling.NEAREST)
        canvas = Image.new('RGBA', (CELL, CELL))
        canvas.paste(rgb, xy)
        used.append(canvas)
    arrays = [np.asarray(f) for f in used]
    clipped = any(np.any(a[0, :, 3]) or np.any(a[-1, :, 3]) or np.any(a[:, 0, 3]) or np.any(a[:, -1, 3]) for a in arrays)
    unique = len({f.tobytes() for f in used})
    if clipped or unique < 5:
        raise RuntimeError(f'{m["id"]}: clipping={clipped}, unique poses={unique}')
    dst.mkdir(parents=True, exist_ok=True)
    sheet = Image.new('RGBA', (CELL*len(used), CELL))
    for i, f in enumerate(used):
        sheet.paste(f, (i*CELL, 0))
    tmp = dst/(m['id']+'_move.tmp.png')
    sheet.save(tmp)
    tmp.replace(dst/(m['id']+'_move.png'))
    used[0].save(src/'ready.png')
    # Preview icons and the animation fallback use the same new creature design.
    still = used[0].crop(used[0].getbbox())
    target_h = gen_art.MON_H[m['kind']]
    still = still.resize((max(1, round(still.width*target_h/still.height)), target_h), Image.Resampling.NEAREST)
    static_path = ROOT/'art/monsters'/(m['id']+'.png')
    still.save(static_path.with_suffix('.tmp.png'))
    static_path.with_suffix('.tmp.png').replace(static_path)
    used[0].save(src/'move.webp', save_all=True, append_images=used[1:], duration=83, loop=0, lossless=True, exact=True)
    contact = Image.new('RGB', (CELL*6, (CELL+22)*((len(used)+5)//6)), '#202936')
    draw = ImageDraw.Draw(contact)
    for i, f in enumerate(used):
        x, y = (i%6)*CELL, (i//6)*(CELL+22)
        contact.paste(f, (x, y), f)
        draw.text((x+6, y+CELL+4), f'{i} / H3 {indices[i]}', fill='white')
    contact.save(src/'contact.png')
    qc = dict(canvas_clipping=clipped, source_clipping=False, unique_poses=unique, forward_only=True,
              fixed_scale=True, foot_patches=False, translation_range=np.ptp(shifts, axis=0).tolist())
    savejson(src/'loop.json', dict(indices=indices, selection=selection, qc=qc))
    frame_ms = 1000*(indices[1]-indices[0])/24
    savejson(dst/'anim.json', dict(name=m['id'], cell=dict(w=CELL, h=CELL),
             anchor=dict(x=anchor[0], y=anchor[1]), scale=gen_art.MON_H[m['kind']]/outsize[1],
             movement=movement(m), source='Krea 2 Turbo + MiniMax H3',
             clips={'move': dict(frames=len(used), ms=[frame_ms]*len(used), loop=True)}, qc=qc))
    print('POST SAVED', m['id'], len(used), selection, flush=True)
    return True


def gallery(monsters):
    TAKES.mkdir(parents=True, exist_ok=True)
    cards = []
    for m in monsters:
        done = (GAME/m['id']/'anim.json').exists()
        if not done:
            continue
        cards.append(f'<article><h2>{html.escape(m["ko"])} <small>{movement(m)}</small></h2>'
                     f'<img src="{m["id"]}/move.webp"><p><a href="{m["id"]}/contact.png">프레임 확인</a> '
                     f'<a href="{m["id"]}/source.mp4">Minimax 원본 영상</a> '
                     f'<a href="../../art/concepts/monsters/{m["id"]}.png">Krea 원화</a></p></article>')
    (TAKES/'index.html').write_text('<!doctype html><html lang="ko"><meta charset="utf-8"><title>몬스터 모션 검토</title>'
        '<style>body{background:#141c28;color:#eee;font:15px system-ui;margin:24px}main{display:grid;grid-template-columns:repeat(5,1fr);gap:16px}'
        'article{background:#243040;padding:12px}h2{font-size:16px}small{color:#91adba}img{width:100%;image-rendering:pixelated}a{color:#8dd9ff}</style>'
        f'<h1>몬스터 {len(cards)} / {len(monsters)}종</h1><p>Krea 원화 → Minimax H3 보행·날개짓 · 실제 게임 프레임 · 일정한 배율</p><main>'+''.join(cards)+'</main></html>')


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--only', default='')
    ap.add_argument('--watch', action='store_true')
    ap.add_argument('--force', action='store_true')
    args = ap.parse_args()
    monsters = json.loads((ROOT/'tools/roster.json').read_text())['monsters']
    targets = [m for m in monsters if not args.only or m['id'] in args.only.split(',')]
    while True:
        done = []
        for m in targets:
            error = TAKES/m['id']/'post_error.json'
            if error.exists() and not args.force:
                done.append(False)
                continue
            try:
                done.append(post(m, args.force))
                if error.exists():
                    error.unlink()
            except Exception as exc:
                savejson(error, {'error': str(exc), 'time': time.time()})
                print('POST ERROR', m['id'], str(exc), flush=True)
                done.append(False)
        gallery(monsters)
        if not args.watch or all(done):
            break
        time.sleep(20)


if __name__ == '__main__':
    main()
