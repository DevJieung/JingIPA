#!/usr/bin/env python3
"""Generate the new world's individual T-pose concept art with local Krea 2.

Uses the project's GPU guard and resumes from matching provenance sidecars.
The manifest can grow while generation runs; --watch waits for all 50 designs.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'art/concepts/last_refuge_v3'
MANIFEST = OUT / 'characters.json'
STYLE = ('Professional hand-painted fantasy game character concept illustration, '
         'crisp confident contour drawing, polished cel-painted materials, colorful readable '
         'heroic adventure art, consistent stylized adult six-head body proportions. '
         'Single character full body FRONT VIEW in a strict symmetrical T-POSE, '
         'standing upright facing viewer, BOTH arms extended straight horizontally sideways '
         'at shoulder height, straight elbows, feet planted shoulder-width apart. '
         'Entire head, fingertips, feet and equipment inside frame with generous margins. '
         'Plain warm light gray studio background, soft upper-left light, clear facial features. '
         'One character only, one view, clean presentation without lettering. ')
POSE = (' All handheld weapons are SECURELY HOLSTERED or strapped vertically beside the '
        'outer leg or on the back, visible outside the torso silhouette. Both hands EMPTY, '
        'fingers relaxed and visible, arms horizontal. Body-mounted equipment stays attached. '
        'All equipment inactive, show physical construction clearly. '
        'Grounded standing feet, exposed elbow and knee articulation, compact costume panels. '
        'Front-facing T-pose model reference, elegant detailed illustration rather than pixel art.')


def prompt_for(c):
    return STYLE + c['prompt_en'] + c.get('pose_en', POSE)


def digest(prompt, seed):
    return hashlib.sha256(f'{prompt}|{seed}|1024|1024|turbo|8'.encode()).hexdigest()


def fingerprint_for(c):
    base = digest(prompt_for(c), c['seed'])
    if c.get('init_image'):
        sha = hashlib.sha256((ROOT / c['init_image']).read_bytes()).hexdigest()
        return hashlib.sha256(f"{base}|{sha}|{c['strength']}".encode()).hexdigest()
    return base


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--watch', action='store_true')
    ap.add_argument('--only', default='')
    ap.add_argument('--dry-run', action='store_true')
    args = ap.parse_args()
    only = set(args.only.split(',')) if args.only else None
    if args.dry_run:
        chars = json.loads(MANIFEST.read_text())
        for c in chars:
            if not only or c['id'] in only:
                print(c['id'], len(prompt_for(c)), fingerprint_for(c)[:12])
        return
    import gpu_guard
    gpu_guard.claim('krea2')
    sys.path.insert(0, '/home/dgxmaruta/pjt/krea2')
    from krea2.pipelines.image import Krea2ImagePipeline
    from PIL.PngImagePlugin import PngInfo
    pipe = Krea2ImagePipeline('turbo').load()
    pipe.pipe.set_progress_bar_config(disable=True)
    print('[concept] MODEL READY', flush=True)
    completed = set()
    while True:
        chars = json.loads(MANIFEST.read_text())
        pending = []
        for c in chars:
            if only and c['id'] not in only:
                continue
            p = prompt_for(c)
            sha = fingerprint_for(c)
            path = OUT / f"{c['id']}.png"
            meta = path.with_suffix('.json')
            if path.exists() and meta.exists() and json.loads(meta.read_text()).get('fingerprint') == sha:
                completed.add(c['id'])
                continue
            pending.append((c, p, sha, path, meta))
        for c, p, sha, path, meta in pending:
            t = time.monotonic()
            print(f"[concept] START {c['id']} tier={c['tier']} {len(completed)}/50", flush=True)
            if c.get('init_image'):
                result = pipe.generate_img2img(p, str(ROOT / c['init_image']),
                    strength=c['strength'], width=1024, height=1024, steps=8, seed=c['seed'])[0]
            else:
                result = pipe.generate(p, width=1024, height=1024, steps=8, seed=c['seed'])[0]
            info = dict(id=c['id'], name=c['name'], model='Krea 2 Turbo', model_key=result.model,
                        seed=result.seed, steps=result.steps, guidance=result.guidance,
                        width=result.width, height=result.height, prompt=p, fingerprint=sha,
                        generated_at=time.strftime('%Y-%m-%dT%H:%M:%S%z'),
                        seconds=round(time.monotonic()-t, 2))
            if c.get('init_image'):
                info.update(method='Krea2 img2img', input_image=c['init_image'],
                    input_sha256=hashlib.sha256((ROOT/c['init_image']).read_bytes()).hexdigest(),
                    strength=c['strength'])
            pnginfo = PngInfo()
            pnginfo.add_text('generation', json.dumps(info, ensure_ascii=False))
            tmp = path.with_suffix('.tmp.png')
            result.image.save(tmp, pnginfo=pnginfo)
            # Retain earlier candidates when a changed design/seed is regenerated.
            if path.exists():
                import shutil
                archive = OUT / 'variants'
                archive.mkdir(exist_ok=True)
                stamp = time.strftime('%Y%m%dT%H%M%S')
                shutil.copy2(path, archive / f"{c['id']}_{stamp}.png")
                if meta.exists():
                    shutil.copy2(meta, archive / f"{c['id']}_{stamp}.json")
            os.replace(tmp, path)
            meta.write_text(json.dumps(info, ensure_ascii=False, indent=2)+'\n')
            completed.add(c['id'])
            print(f"[concept] SAVED {path.name} {info['seconds']}s ({len(completed)}/50)", flush=True)
        if only or not args.watch or (len(chars) == 50 and len(completed) == 50):
            break
        print(f'[concept] Waiting for remaining designs ({len(chars)}/50)', flush=True)
        time.sleep(10)
    print(f'[concept] COMPLETE {len(completed)} individual images', flush=True)


if __name__ == '__main__':
    main()
