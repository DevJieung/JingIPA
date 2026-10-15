#!/usr/bin/env python3
"""Before/after review sheets for the 2026-10-15 mobile LOD pass.

    python3 tools/3d/lod_review.py capture --out build/character-3d/lod-2026-10-15/review/after
    python3 tools/3d/lod_review.py compose --before .../review/before --after .../review/after \
        --out .../review/compare

`capture` runs tests/3d/lod_roster_preview.tscn (real factory, adapters and shading) on the
login session's GPU display when it is there (DISPLAY=:1, NVIDIA), else on Xvfb.
`compose` pairs every picture of the two runs:
    pairs/<id>.jpg           close-ups before (top) / after (bottom): idle, attack, walk, front
    grid_<set>_<pose>.jpg    the whole roster at the arena camera, before | after, plus a 3x
                             nearest crop so single pixels can be compared
    seq_<id>.gif             continuous idle -> attack -> walk, before | after side by side
    mosaic_NN.jpg            every model, three views, before | after (quick full scan)
    scores.json              mean absolute pixel difference per model and view (outliers first)
`deform` runs tools/3d/check_native_(monster_)deformation.py on game.blend and game-lod.blend
of every model and writes summary.json (overstretched short edges, edge extension, soles).
"""
import argparse, contextlib, json, os, subprocess, sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from godot_env import ROOT, GODOT, xvfb  # noqa: E402


def display():
    auth = Path(f'/run/user/{os.getuid()}/gdm/Xauthority')
    if os.environ.get('REVIEW_DISPLAY', 'auto') != 'xvfb' and auth.exists():
        env = dict(os.environ, DISPLAY=':1', XAUTHORITY=str(auth), STELLARDEFENSE_NO_SAVE='1')
        probe = subprocess.run(['xdpyinfo', '-queryExtensions'], env=env, capture_output=True, text=True)
        if probe.returncode == 0 and 'NV-GLX' in probe.stdout:
            return contextlib.nullcontext(env)
    return xvfb(131, '1280x800')


def capture(a):
    a.out.mkdir(parents=True, exist_ok=True)
    with display() as env:
        cmd = [str(GODOT), '--path', str(ROOT), '--disable-vsync', '--resolution', '96x60',
               'res://tests/3d/lod_roster_preview.tscn', '--', '--out', str(a.out)]
        if a.only: cmd += ['--only', a.only]
        log = subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=3600)
    text = log.stdout + log.stderr
    (a.out / 'render.log').write_text(text)
    # Exit-time leak reports ("resources still in use at exit") are not render errors.
    errors = [l for l in text.splitlines() if 'ERROR' in l and 'still in use at exit' not in l]
    if log.returncode or errors or '판정: 정상' not in text:
        print(text[-3000:]); raise SystemExit(1)
    print('captured', len(list(a.out.glob('*.png'))), 'pictures into', a.out)


def label(im, text):
    d = ImageDraw.Draw(im)
    d.rectangle((0, 0, 8 + 7 * len(text), 16), fill=(8, 12, 18))
    d.text((4, 2), text, fill=(235, 240, 245))
    return im


def score(b, a):
    x = np.asarray(Image.open(b).convert('RGB')).astype(np.float32)
    y = np.asarray(Image.open(a).convert('RGB')).astype(np.float32)
    ref = np.median(x.reshape(-1, 3), axis=0)
    mask = (np.abs(x - ref).sum(2) > 40) | (np.abs(y - ref).sum(2) > 40)
    if mask.sum() == 0: return 0.0, 0
    return float(np.abs(x - y).mean(2)[mask].mean()), int(mask.sum())


def compose(a):
    out = a.out; (out / 'pairs').mkdir(parents=True, exist_ok=True)
    B, A = a.before, a.after
    ids = sorted({p.name[len('front_'):-4] for p in B.glob('front_*.png')})
    scores = {}
    for cid in ids:
        views = [f'zoom_{cid}_idle', f'zoom_{cid}_attack', f'zoom_{cid}_walk', f'front_{cid}']
        views = [v for v in views if (B / f'{v}.png').exists() and (A / f'{v}.png').exists()]
        if not views: continue
        tiles = []
        for v in views:
            b = Image.open(B / f'{v}.png').convert('RGB'); x = Image.open(A / f'{v}.png').convert('RGB')
            w, h = b.size
            col = Image.new('RGB', (w, h * 2), (0, 0, 0))
            col.paste(label(b, 'before ' + v.split('_')[-1] if v.startswith('zoom') else 'before front'), (0, 0))
            col.paste(label(x, 'after'), (0, h))
            tiles.append(col)
            scores.setdefault(cid, {})[v] = round(score(B / f'{v}.png', A / f'{v}.png')[0], 2)
        sheet = Image.new('RGB', (sum(t.width for t in tiles), tiles[0].height))
        xo = 0
        for t in tiles: sheet.paste(t, (xo, 0)); xo += t.width
        sheet = sheet.resize((sheet.width // 2, sheet.height // 2), Image.LANCZOS)
        sheet.save(out / 'pairs' / f'{cid}.jpg', quality=90)
    for grid in sorted(B.glob('grid_*.png')):
        after = A / grid.name
        if not after.exists(): continue
        b = Image.open(grid).convert('RGB'); x = Image.open(after).convert('RGB')
        sheet = Image.new('RGB', (b.width * 2 + 8, b.height), (8, 12, 18))
        sheet.paste(label(b, 'before'), (0, 0)); sheet.paste(label(x, 'after'), (b.width + 8, 0))
        sheet.save(out / (grid.stem + '.jpg'), quality=92)
        # 3x nearest crop of the busiest part so single pixels can be compared at game scale.
        box = (300, 230, 700, 480) if 'heroes' in grid.name and '_x' not in grid.name else None
        if box:
            crops = [im.crop(box).resize(((box[2] - box[0]) * 3, (box[3] - box[1]) * 3), Image.NEAREST) for im in (b, x)]
            pair = Image.new('RGB', (crops[0].width * 2 + 8, crops[0].height), (8, 12, 18))
            pair.paste(label(crops[0], 'before (3x nearest)'), (0, 0)); pair.paste(label(crops[1], 'after (3x nearest)'), (crops[0].width + 8, 0))
            pair.save(out / (grid.stem + '_crop3x.png'))
        scores.setdefault('_grids', {})[grid.stem] = round(score(grid, after)[0], 2)
    for cid in sorted({p.name[4:-7] for p in B.glob('seq_*_00.png')}):
        frames = []
        n = 0
        while (B / f'seq_{cid}_{n:02d}.png').exists() and (A / f'seq_{cid}_{n:02d}.png').exists():
            b = Image.open(B / f'seq_{cid}_{n:02d}.png').convert('RGB'); x = Image.open(A / f'seq_{cid}_{n:02d}.png').convert('RGB')
            f = Image.new('RGB', (b.width * 2 + 6, b.height), (8, 12, 18))
            f.paste(label(b, 'before'), (0, 0)); f.paste(label(x, 'after'), (b.width + 6, 0))
            frames.append(f.resize((f.width // 2, f.height // 2), Image.LANCZOS).quantize(colors=160, method=Image.Quantize.FASTOCTREE))
            n += 1
        if frames:
            frames[0].save(out / f'seq_{cid}.gif', save_all=True, append_images=frames[1:], duration=67, loop=0)
            strip = [Image.open(A / f'seq_{cid}_{k:02d}.png').convert('RGB') for k in range(0, n, max(1, n // 12))][:12]
            sb = [Image.open(B / f'seq_{cid}_{k:02d}.png').convert('RGB') for k in range(0, n, max(1, n // 12))][:12]
            w, h = strip[0].size
            contact = Image.new('RGB', (w * len(strip) // 2, h), (8, 12, 18))
            for k, (pb, pa) in enumerate(zip(sb, strip)):
                contact.paste(pb.resize((w // 2, h // 2)), (k * w // 2, 0)); contact.paste(pa.resize((w // 2, h // 2)), (k * w // 2, h // 2))
            contact.save(out / f'seq_{cid}_contact.jpg', quality=90)
    for name in sorted(B.glob('legacy_*.png')):
        after = A / name.name
        if not after.exists(): continue
        b = Image.open(name).convert('RGB'); x = Image.open(after).convert('RGB')
        sheet = Image.new('RGB', (b.width, b.height * 2 + 8), (8, 12, 18))
        sheet.paste(label(b, 'before'), (0, 0)); sheet.paste(label(x, 'after'), (0, b.height + 8))
        sheet.save(out / (name.stem + '.jpg'), quality=92)
    # One mosaic of every model: front and arena-angle idle, before | after, for a quick full scan.
    tiles = []
    for cid in ids:
        views = [f'front_{cid}', f'zoom_{cid}_idle', f'zoom_{cid}_attack']
        if not all((B / f'{v}.png').exists() and (A / f'{v}.png').exists() for v in views): continue
        cell = Image.new('RGB', (6 * 150, 200), (8, 12, 18))
        for k, v in enumerate(views):
            for j, root in enumerate((B, A)):
                im = Image.open(root / f'{v}.png').convert('RGB')
                im = im.crop((60, 40, im.width - 60, im.height - 40)) if v.startswith('front') else im.crop((80, 60, im.width - 80, im.height - 60))
                im.thumbnail((150, 186), Image.LANCZOS)
                cell.paste(im, ((k * 2 + j) * 150, 14))
        ImageDraw.Draw(cell).text((4, 1), f'{cid}  (before | after) x3 views', fill=(235, 240, 245))
        tiles.append(cell)
    for page in range(0, len(tiles), 12):
        chunk = tiles[page:page + 12]
        sheet = Image.new('RGB', (900 * 2 + 6, ((len(chunk) + 1) // 2) * 206), (30, 34, 40))
        for n, t in enumerate(chunk):
            sheet.paste(t, ((n % 2) * 906, (n // 2) * 206))
        sheet.save(out / f'mosaic_{page // 12:02d}.jpg', quality=88)
    ranked = sorted(((max(v.values()), k) for k, v in scores.items() if not k.startswith('_')), reverse=True)
    (out / 'scores.json').write_text(json.dumps({'ranked_by_max_view_difference': ranked, 'scores': scores}, indent=1) + '\n')
    print('composed', len(ids), 'models into', out)


def deform(a):
    """tools/3d/check_native_(monster_)deformation.py on the reviewed game.blend and on the
    reduced game-lod.blend of every model (same clips, same rig), side by side."""
    import concurrent.futures
    heroes = json.loads((ROOT / 'art/models/native_heroes.json').read_text())['ready_ids']
    monsters = json.loads((ROOT / 'art/models/native_monsters.json').read_text())['ready_ids']
    jobs = []
    for cid in heroes:
        src = ROOT / 'build/character-3d/source' / cid
        jobs += [(cid, 'hero', tag, src / name) for tag, name in [('before', 'game.blend'), ('after', 'game-lod.blend')]]
    for cid in monsters:
        src = ROOT / 'build/character-3d/monster-source' / cid
        jobs += [(cid, 'monster', tag, src / name) for tag, name in [('before', 'game.blend'), ('after', 'game-lod.blend')]]
    a.out.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ); env.pop('DISPLAY', None)

    def run(job):
        cid, kind, tag, blend = job
        tool = ROOT / 'tools/3d' / ('check_native_deformation.py' if kind == 'hero' else 'check_native_monster_deformation.py')
        out = a.out / f'{cid}-{tag}.json'
        if out.exists(): return job, True
        r = subprocess.run([str(Path.home() / '.local/bin/bl'), '-b', '--factory-startup', '--python', str(tool), '--',
                            '--input', str(blend), '--output', str(out)], env=env, capture_output=True, text=True, timeout=1800)
        return job, r.returncode == 0 and out.exists()

    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        for job, ok in pool.map(run, jobs):
            if not ok: print('FAIL', job)
    table = {}
    for cid in heroes + monsters:
        row = {}
        for tag in ['before', 'after']:
            path = a.out / f'{cid}-{tag}.json'
            if not path.exists(): continue
            data = json.loads(path.read_text())
            samples = data['samples']
            row[tag] = {'overstretch_edges': sum(s['short_edge_overstretch_count'] for s in samples),
                        'max_edge_extension_m': round(max(s['maximum_edge_extension_m'] for s in samples), 4),
                        'sole_movement_m': round(max((s.get('sole_movement_m', 0) for s in samples), default=0), 5),
                        'min_ground_z_m': round(min((s.get('minimum_ground_z_m', 0) for s in samples), default=0), 4),
                        'loop_error': data.get('loop_matrix_max_error'), 'review_required': data['review_required']}
        table[cid] = row
    (a.out / 'summary.json').write_text(json.dumps(table, indent=1) + '\n')
    flagged = [cid for cid, row in table.items() if row.get('after', {}).get('overstretch_edges', 0) > row.get('before', {}).get('overstretch_edges', 0)]
    print('deformation summary:', a.out / 'summary.json', 'more overstretched edges after:', flagged)


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('mode', choices=['capture', 'compose', 'deform'])
    p.add_argument('--out', type=Path, required=True)
    p.add_argument('--only', default='')
    p.add_argument('--before', type=Path)
    p.add_argument('--after', type=Path)
    a = p.parse_args()
    {'capture': capture, 'compose': compose, 'deform': deform}[a.mode](a)


if __name__ == '__main__':
    main()
