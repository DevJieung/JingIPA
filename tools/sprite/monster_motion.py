#!/usr/bin/env python3
"""Krea monster reference poses -> MiniMax H3 locomotion -> game sprite loops.

Run concepts and motion in separate processes; gpu_guard prevents overlapping models.
Generation is resumable, with prompts, seeds and original frames retained for review.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage as ndi

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
import gen_art
import gpu_guard
import h3_i2v as h3

SOURCE = ROOT / 'art/concepts/monsters'
TAKES = ROOT / 'build/monster-motion'
GAME = ROOT / 'art/anim/monsters'
FRAMES = 124
SIZE = 768
CELL = 192
QUADS = {'blaze_fox', 'magma_brute', 'vine_lynx', 'crystal_skink', 'blizzard_wolf'}
WINGS = {'flame_dragon', 'glacier_dragon', 'rapid_ray', 'abyss_leviathan'}
FLOAT = {'jelly_seer', 'runestone_idol'}
MOTION_SEEDS = {'wave_giant': 37, 'ember_imp': 37, 'pyre_priest': 37, 'vine_lynx': 37, 'abyss_leviathan': 37, 'flame_dragon': 37}


def savejson(p, data):
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_suffix('.tmp.json')
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
    tmp.replace(p)


def movement(m):
    uid = m['id']
    if uid in WINGS:
        return 'fly'
    if uid in FLOAT:
        return 'float'
    if uid == 'drop_slime':
        return 'flow'
    return 'walk'


def concept_prompt(m):
    uid = m['id']
    pose = ('Both arms extend straight horizontally to the sides in a clear T-pose, '
            'palms open, both feet separated and planted, all joints clearly visible. ')
    if uid in QUADS:
        pose = 'Natural four-legged reference stance, all four legs separated and clearly visible, tail extended. '
    elif uid in WINGS:
        pose = ('Symmetrical fully spread wings or broad wing-shaped fins, both tips visible, '
                'limbs separated and relaxed, entire tail visible. ')
    elif uid in FLOAT or uid == 'drop_slime':
        pose = 'Natural open reference pose, all existing fins or tentacles spread apart, preserve its original anatomy. '
    elif uid == 'titan_bloom':
        pose = 'Open reference pose, root legs separated, vine arms spread sideways, every flower head visible. '
    return ('A single full body fantasy monster concept for a 2D pixel art game, '
            'crisp chunky pixel clusters, confident dark outlines, vivid elemental colors, '
            'three cel-shaded tones per material, detailed readable silhouette, upper-left lighting. '
            + m['prompt'] + '. ' + pose +
            'Front-facing reference with a slight right-facing three-quarter angle. '
            'All of the creature fits in the middle 65 percent of the canvas with generous clear margins. '
            'Perfectly flat pure white background, crisp isolated silhouette, no cast shadow, '
            'no ground, no detached particles, no typography or labels. '
            'The brightest body colors are tinted cream or pale cyan, distinct from the white backdrop.')


def concepts(monsters):
    SOURCE.mkdir(parents=True, exist_ok=True)
    pending = []
    for m in monsters:
        prompt = concept_prompt(m)
        seed = gen_art._seed('monster_tpose_' + m['id'])
        fingerprint = hashlib.sha256(f'{prompt}|{seed}|1024|8'.encode()).hexdigest()
        meta = SOURCE / (m['id'] + '.json')
        if meta.exists() and (SOURCE / (m['id'] + '.png')).exists():
            if json.loads(meta.read_text()).get('fingerprint') == fingerprint:
                continue
        pending.append((m, prompt, seed, fingerprint))
    if not pending:
        print('CONCEPTS already complete', flush=True)
        return
    gpu_guard.claim('krea2')
    from krea2.pipelines.image import Krea2ImagePipeline
    pipe = Krea2ImagePipeline('turbo').load()
    pipe.pipe.set_progress_bar_config(disable=True)
    for i, (m, prompt, seed, fingerprint) in enumerate(pending):
        print(f'KREA START {i+1}/{len(pending)} {m["id"]}', flush=True)
        start = time.monotonic()
        result = pipe.generate(prompt, width=1024, height=1024, steps=8, seed=seed)[0]
        dst = SOURCE / (m['id'] + '.png')
        tmp = dst.with_suffix('.tmp.png')
        result.image.save(tmp)
        tmp.replace(dst)
        savejson(dst.with_suffix('.json'), dict(id=m['id'], name=m['ko'], model='Krea 2 Turbo',
                 seed=seed, steps=8, prompt=prompt, fingerprint=fingerprint,
                 seconds=round(time.monotonic()-start, 2)))
        print(f'KREA SAVED {m["id"]} {time.monotonic()-start:.1f}s', flush=True)


def prepare(m):
    dst = TAKES / m['id']
    dst.mkdir(parents=True, exist_ok=True)
    source = Image.open(SOURCE / (m['id'] + '.png')).convert('RGBA')
    cut, kept, _holes = gen_art.cut_white(source, holes=bool(m.get('holes', False)))
    if kept < 0.05:
        raise RuntimeError('Reference background removal lost the creature: ' + m['id'])
    # Remove detached smoke/embers; preserve the idol's deliberately separate crown crystal.
    if m['id'] != 'runestone_idol':
        a = np.array(cut)
        labels, _ = ndi.label(a[:, :, 3] > 127)
        sizes = np.bincount(labels.ravel())
        sizes[0] = 0
        a[labels != int(np.argmax(sizes))] = 0
        cut = Image.fromarray(a)
    cut = cut.crop(cut.getbbox())
    max_w, max_h = (340, 360) if m['id'] in {'abyss_leviathan', 'flame_dragon', 'glacier_dragon'} else (450, 480)
    scale = min(max_w / cut.width, max_h / cut.height)
    cut = cut.resize((round(cut.width*scale), round(cut.height*scale)), Image.Resampling.NEAREST)
    canvas = Image.new('RGBA', (SIZE, SIZE))
    canvas.alpha_composite(cut, ((SIZE-cut.width)//2, 620-cut.height))
    canvas.save(dst / 'input_transparent.png')
    # Green avoids magenta flower petals and purple crystals; woody creatures use magenta.
    key = (255, 0, 255) if m['body'] == 'wood' else (0, 255, 0)
    bg = Image.new('RGB', (SIZE, SIZE), key)
    bg.paste(canvas, mask=canvas.getchannel('A'))
    bg.save(dst / 'input.png')
    return dst / 'input.png'


def motion_prompt(m):
    mode = movement(m)
    action = ('Walk in place facing FRAME RIGHT with a natural alternating left-right step cycle. '
              'One foot plants while the other lifts, swings forward and plants. '
              'Arms counter-swing opposite the legs, knees and ankles articulate. ')
    if m['id'] in QUADS:
        action = ('Walk in place facing FRAME RIGHT in a steady natural quadruped gait. '
                  'All four legs articulate in a coordinated alternating cycle with clear foot contacts. '
                  'The spine stays level and the tail follows softly. ')
    elif mode == 'fly':
        action = ('Fly in place facing FRAME RIGHT with continuous smooth powerful wingbeats. '
                  'Both wings or broad fins articulate at their roots: a strong downstroke, '
                  'then a folded recovery upstroke. The wing tips trace broad vertical arcs. '
                  'The torso holds a stable hovering height, the tail follows softly, legs tuck underneath. ')
    elif m['id'] == 'jelly_seer':
        action = ('Hover in place facing FRAME RIGHT, hold the main body upright and stable. '
                  'The existing tentacles undulate in a flowing repeated wave beneath the bell. '
                  'Use small organic appendage motions, keeping the main body centered. ')
    elif m['id'] == 'runestone_idol':
        action = ('Hover in place facing FRAME RIGHT. The rigid stone pillar remains upright and centered, '
                  'while the existing overhead crystal makes a small slow repeated orbit above its crown. '
                  'Keep the original limbless stone anatomy intact. ')
    elif mode == 'flow':
        action = ('Flow in place toward FRAME RIGHT like a living water slime, small traveling ripples '
                  'along the base pull the body forward in a continuous cycle. '
                  'The eyes and upper body remain stable while the lower edge rolls smoothly. ')
    elif m['id'] == 'titan_bloom':
        action = ('Walk in place facing FRAME RIGHT on its root legs. Roots alternately lift and plant '
                  'like feet, vine arms counter-swing softly, flower heads hold stable upright poses. ')
    key = 'magenta' if m['body'] == 'wood' else 'green'
    settle = 'lower the T-pose arms into a natural walking stance'
    if m['id'] in QUADS:
        settle = 'settle into a natural four-legged stance with all four paws visible'
    elif mode == 'fly':
        settle = 'ease the spread wings or fins into the first gentle downstroke'
    elif mode in {'float', 'flow'}:
        settle = 'settle the original creature into its natural relaxed shape, preserving its original anatomy'
    elif m['id'] == 'titan_bloom':
        settle = 'relax the vine arms and plant the existing root legs'
    articulated = 'The two existing legs and two existing arms articulate naturally; the shoulders keep their original outline. '
    if m['id'] in QUADS:
        articulated = 'The four existing legs and the tail articulate naturally; the spine stays level. '
    elif mode == 'fly':
        articulated = 'The existing wings or fins flap smoothly while the torso stays stable and the tail follows. '
    elif m['id'] == 'jelly_seer':
        articulated = 'The existing tentacles ripple while the bell stays centered. '
    elif m['id'] == 'runestone_idol':
        articulated = 'The existing crown crystal moves gently while the rigid stone pillar stays centered. '
    elif mode == 'flow':
        articulated = 'Small waves travel along the original lower edge; the eyes and upper body stay stable. '
    elif m['id'] == 'titan_bloom':
        articulated = 'The existing root legs step and the vine arms counter-swing; the flower heads stay stable. '
    return ('How the reference pictures align with the target video — Picture 1 (from Shot 1) '
            'aligns with the 0.00-second mark; Picture 2 (from Shot 1) aligns with the 5.17-second mark.\n\n'
            'integrated_multimodal_description: [Shot 1] One uninterrupted pixel-art monster animation. '
            'Use the reference creature, retaining its exact anatomy, colors, outline and equipment. '
            'Subject identity: ' + m['prompt'] + '. '
            + h3.CAMERA.format(S='5.17') +
            '0.00-0.80 seconds: ' + settle +
            ', settling into a clear three-quarter view facing FRAME RIGHT. '
            '0.80-4.50 seconds: ' + action +
            'Repeat this same rhythmic cycle at an even speed. '
            '4.50-5.17 seconds: ease back into the exact original reference pose in Picture 2. '
            'This is a treadmill animation: the torso stays at exactly the same canvas position and size. '
            'Torso position, width and height remain fixed. '
            'The original species, anatomy, silhouette, equipment and elemental colors remain unchanged. '
            + articulated + 'The head holds its orientation. '
            'Generous margins keep the entire creature inside the frame at all times. '
            f'Perfectly uniform flat solid {key} background, no shadows, scenery, particles or effects. '
            'Fixed pixel grid and constant lighting.\n\noverall_soundscape: Silent.\n\nnon_diegetic_music: None.')


def motion(monsters):
    # CUDA may briefly report the already-exited Krea process after its lock releases.
    # Wait only for dead process entries; never bypass a live model's guard.
    for attempt in range(6):
        try:
            gpu_guard.claim('h3')
            break
        except SystemExit:
            bad = gpu_guard.others(exclude={p for p in (gpu_guard.h3_pid(),) if p})
            if attempt == 5 or any(Path(f'/proc/{pid}').exists() for pid, _, _ in bad):
                raise
            time.sleep(2)
    for m in monsters:
        dst = TAKES / m['id']
        raw = dst / 'raw'
        if (dst / 'generation.json').exists() and len(list(raw.glob('f_*.png'))) == FRAMES:
            print('H3 EXISTS', m['id'], flush=True)
            continue
        print('H3 START', m['id'], flush=True)
        resume = dst / 'resume.json'
        if resume.exists():
            state = json.loads(resume.read_text())
        else:
            src = prepare(m)
            prompt = motion_prompt(m)
            if movement(m) != 'fly' and re.search(r'\bwing(?:s|tips|beats)?\b', prompt, re.I):
                raise ValueError('Flying anatomy leaked into locomotion prompt: ' + m['id'])
            name = h3.upload(str(src), 'monster_' + m['id'] + '.png')
            graph = h3.graph(name, prompt, seed=MOTION_SEEDS.get(m['id'], 7), frames=FRAMES, size=SIZE,
                             steps=4, turbo=4, pin_last=True, prefix='pocker_monsters/' + m['id'])
            pid = h3._post('/prompt', {'prompt': graph})['prompt_id']
            state = dict(prompt_id=pid, workflow=graph, started=time.time())
            savejson(resume, state)
        pid = state['prompt_id']
        while True:
            history = h3._get('/history/' + pid)
            if pid in history:
                break
            if time.time()-state['started'] > 3600:
                raise RuntimeError('H3 timeout: ' + m['id'])
            time.sleep(3)
        result = history[pid]
        if result.get('status', {}).get('status_str') == 'error':
            raise RuntimeError(str(result['status']))
        items = [it for node in result['outputs'].values() for it in node.get('images', [])]
        if len(items) != FRAMES:
            raise RuntimeError(f'{m["id"]}: expected {FRAMES} frames, got {len(items)}')
        raw.mkdir(exist_ok=True)
        for i, it in enumerate(sorted(items, key=lambda x: x['filename'])):
            q = urllib.parse.urlencode(it)
            with urllib.request.urlopen('http://' + h3.HOST + '/view?' + q, timeout=120) as r:
                (raw / f'f_{i:04d}.png').write_bytes(r.read())
        savejson(dst / 'generation.json', dict(model=h3.UNET, turbo=h3.TURBO[4],
                 seed=state['workflow']['noise']['inputs']['noise_seed'],
                 pin_last='last_frame' in state['workflow']['cond']['inputs'],
                 frames=FRAMES, fps=24, movement=movement(m),
                 seconds=round(time.time()-state['started'], 2),
                 source_sha256=hashlib.sha256((SOURCE/(m['id']+'.png')).read_bytes()).hexdigest(),
                 prompt=state['workflow']['cond']['inputs']['prompt']))
        print('H3 SAVED', m['id'], flush=True)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('stage', choices=['concepts', 'prepare', 'motion'])
    ap.add_argument('--only', default='')
    args = ap.parse_args()
    monsters = json.loads((ROOT / 'tools/roster.json').read_text())['monsters']
    if args.only:
        monsters = [m for m in monsters if m['id'] in args.only.split(',')]
    if args.stage == 'concepts':
        concepts(monsters)
    elif args.stage == 'prepare':
        for m in monsters:
            prepare(m)
    else:
        motion(monsters)


if __name__ == '__main__':
    main()
