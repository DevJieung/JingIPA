#!/usr/bin/env python3
"""Side-by-side before/after sheets for the hero motion overhaul.

    python3 tools/3d/motion_overhaul_compare.py --ids echo,kari

Before: build/motion-overhaul/before/<id>_motion.gif (old stage motion, when kept)
        and the old review frames under build/motion-overhaul/before-review/<id>/ if present.
After:  build/character-3d/review/<id>/<res>/{motion,locomotion}.gif and frame PNGs.
Output: build/motion-overhaul/heroes/<id>_attack_before_after.jpg, <id>_locomotion.jpg,
        <id>_before_after.gif (left old / right new attack frames).
"""
import argparse
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageSequence

ROOT = Path(__file__).resolve().parents[2]
BEFORE = ROOT / 'build/motion-overhaul/before'
BEFORE_REVIEW = ROOT / 'build/motion-overhaul/before-review'
OUT = ROOT / 'build/motion-overhaul/heroes'
FONT = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', 16)


def gif_frames(path: Path, limit: int = 80) -> list:
    im = Image.open(path)
    frames = []
    for n, frame in enumerate(ImageSequence.Iterator(im)):
        if n >= limit: break
        frames.append(frame.convert('RGB').copy())
    return frames


def strip(frames: list, label: str, cell=(200, 250), count=12) -> Image.Image:
    if not frames: return Image.new('RGB', (cell[0] * count, cell[1]), (15, 27, 40))
    picks = [frames[int(i * (len(frames) - 1) / max(1, count - 1))] for i in range(count)]
    sheet = Image.new('RGB', (cell[0] * count, cell[1] + 28), (15, 27, 40))
    draw = ImageDraw.Draw(sheet)
    draw.text((8, 6), label, font=FONT, fill=(235, 243, 247))
    for i, frame in enumerate(picks):
        f = frame.copy(); f.thumbnail((cell[0] - 8, cell[1] - 8))
        sheet.paste(f, (i * cell[0] + 4, 28 + 4))
    return sheet


def arena(after_root: Path) -> None:
    """In-game before/after: the parent's HUD review GIFs (long walk, echo attack)."""
    for name in ['en_long_walk', 'en_echo_attack', 'ko_road_pass']:
        before = BEFORE / f'{name}.gif'
        after = next(iter(sorted(after_root.glob(f'1280x800/{name}.gif'))), None)
        if not before.exists() or after is None: continue
        old = gif_frames(before, 40); new = gif_frames(after, 40)
        n = max(len(old), len(new))
        frames = []
        for i in range(n):
            left = old[min(i, len(old) - 1)].copy(); right = new[min(i, len(new) - 1)].copy()
            left.thumbnail((640, 400)); right.thumbnail((640, 400))
            canvas = Image.new('RGB', (1300, 430), (15, 27, 40))
            canvas.paste(left, (5, 25)); canvas.paste(right, (655, 25))
            d = ImageDraw.Draw(canvas); d.text((8, 4), name + ' before', font=FONT, fill=(235, 243, 247)); d.text((658, 4), name + ' after', font=FONT, fill=(235, 243, 247))
            frames.append(canvas)
        frames[0].save(OUT / f'arena_{name}_before_after.gif', save_all=True, append_images=frames[1:], duration=100, loop=0)
        picks = [frames[int(i * (len(frames) - 1) / 5)] for i in range(6)]
        sheet = Image.new('RGB', (1300, 430 * 6), (15, 27, 40))
        for i, f in enumerate(picks): sheet.paste(f, (0, i * 430))
        sheet.save(OUT / f'arena_{name}_before_after.jpg', quality=85)
        print('ARENA', name, OUT / f'arena_{name}_before_after.gif')


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument('--ids', default='echo,kari,jokull,brasa,triton,pip,carmen,limne')
    p.add_argument('--res', default='1280x800')
    p.add_argument('--arena', default='', help='after root of tests/arena_visual_review.py --only hud')
    a = p.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    if a.arena:
        arena(ROOT / a.arena); return
    for cid in a.ids.split(','):
        review = ROOT / 'build/character-3d/review' / cid / a.res
        rows = []
        before_gif = BEFORE / f'{cid}_motion.gif'
        if not before_gif.exists(): before_gif = BEFORE_REVIEW / cid / 'motion.gif'
        if before_gif.exists():
            rows.append(strip(gif_frames(before_gif), f'{cid} BEFORE: old stage idle+attack (motion.gif)'))
        old_frames = sorted((BEFORE_REVIEW / cid).glob('attack_*.png')) if (BEFORE_REVIEW / cid).exists() else []
        if old_frames:
            rows.append(strip([Image.open(f).convert('RGB') for f in old_frames], f'{cid} BEFORE: old attack frames'))
        after_attack = sorted(review.glob('attack_[0-9][0-9].png'))
        if after_attack:
            rows.append(strip([Image.open(f).convert('RGB') for f in after_attack], f'{cid} AFTER: attack 40 frames (fire at 20)'))
        for state, label in [('walk', 'AFTER: run cycle'), ('walk_stop', 'AFTER: run then stop'), ('walk_curve', 'AFTER: curved run'),
                             ('turn', 'AFTER: 90/180 degree turns'), ('aim', 'AFTER: aim twist then fire'), ('walk_attack', 'AFTER: walking while attacking')]:
            frames = sorted(review.glob(f'{state}_[0-9][0-9].png'))
            if frames: rows.append(strip([Image.open(f).convert('RGB') for f in frames], f'{cid} {label}'))
        if not rows: continue
        width = max(r.width for r in rows)
        sheet = Image.new('RGB', (width, sum(r.height for r in rows)), (15, 27, 40))
        y = 0
        for r in rows:
            sheet.paste(r, (0, y)); y += r.height
        sheet.save(OUT / f'{cid}_before_after.jpg', quality=88)
        # Animated side by side: old motion.gif (if any) next to the new motion.gif.
        new_gif = review / 'motion.gif'
        if before_gif.exists() and new_gif.exists():
            old = gif_frames(before_gif, 60); new = gif_frames(new_gif, 60)
            n = max(len(old), len(new))
            frames = []
            for i in range(n):
                left = old[min(i, len(old) - 1)].copy(); right = new[min(i, len(new) - 1)].copy()
                left.thumbnail((320, 400)); right.thumbnail((320, 400))
                canvas = Image.new('RGB', (660, 430), (15, 27, 40))
                canvas.paste(left, (5, 25)); canvas.paste(right, (335, 25))
                d = ImageDraw.Draw(canvas); d.text((8, 4), 'before', font=FONT, fill=(235, 243, 247)); d.text((338, 4), 'after', font=FONT, fill=(235, 243, 247))
                frames.append(canvas)
            frames[0].save(OUT / f'{cid}_before_after.gif', save_all=True, append_images=frames[1:], duration=90, loop=0)
        print('COMPARE', cid, OUT / f'{cid}_before_after.jpg')


main()
