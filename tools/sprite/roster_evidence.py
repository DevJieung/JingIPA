#!/usr/bin/env python3
"""Assemble native sprite review and actual Godot playback evidence, without changing assets."""
from pathlib import Path
import json
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "build/all-hero-sprites"
work = ROOT / "art/animation/roster_v1"
roster = json.loads((ROOT / "tools/roster.json").read_text())
units = [u for tier in roster["tiers"] for u in tier["units"]]
font_path = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
font = ImageFont.truetype(font_path, 14) if Path(font_path).exists() else ImageFont.load_default()

def frame(uid, kind, index):
    path = ROOT / "art/anim" / uid
    meta = json.loads((path / "anim.json").read_text())
    clip = meta["clips"][kind]
    cw, ch = clip.get("cell", meta["cell"]).values()
    atlas = Image.open(path / (meta["name"] + "_" + kind + ".png")).convert("RGBA")
    return atlas.crop((cw * index, 0, cw * (index + 1), ch)), meta

def board(weapon_units, target):
    canvas = Image.new("RGB", (1600, 350 * ((len(weapon_units) + 4) // 5)), (20, 25, 36))
    d = ImageDraw.Draw(canvas)
    for i, u in enumerate(weapon_units):
        uid = u["id"]
        ox, oy = i % 5 * 320, i // 5 * 350
        idle, meta = frame(uid, "idle", 0)
        attack, _ = frame(uid, "attack", meta["clips"]["attack"]["hit_frame"])
        shot, _ = frame(uid, "shot", 2)
        d.text((ox + 8, oy + 5), uid + " / " + u["elem"], font=font, fill="white")
        for source, px in [(idle, 82), (attack, 215)]:
            scale = .70
            sprite = source.resize((round(source.width * scale), round(source.height * scale)), Image.Resampling.NEAREST)
            canvas.paste(sprite, (ox + px - round(meta["anchor"]["x"] * scale), oy + 205 - round(meta["anchor"]["y"] * scale)), sprite)
        canvas.paste(shot, (ox + 96, oy + 192), shot)
        d.text((ox + 8, oy + 330), "Idle / release / Shot  " + u["bullet"], font=font, fill=(180, 195, 210))
    canvas.save(target)

if all((ROOT / "art/anim" / u["id"] / "anim.json").exists() for u in units):
    board(units, OUT / "all_50_comparison.png")
    for weapon in ["deck", "gun", "bow", "sword", "whip"]:
        selected = [u for u in units if u["weapon"] == weapon]
        board(selected, OUT / (weapon + "_comparison.png"))

for directory in OUT.glob("*/*x*"):
    frames = [Image.open(p).convert("RGB") for p in sorted(directory.glob("animation_*.png"))]
    if len(frames) != 12:
        continue
    frames[0].save(directory / "playback.gif", save_all=True, append_images=frames[1:], duration=83, loop=0, optimize=False)
    scale = frames[0].width / 1280
    top, bottom = round(378 * scale), round(549 * scale)
    height = bottom - top
    attack = Image.new("RGB", (frames[0].width, 12 * (height + 20)), (20, 25, 36))
    d = ImageDraw.Draw(attack)
    for i, source in enumerate(frames):
        d.text((8, i * (height + 20) + 2), "frame %02d" % i, font=font, fill="white")
        attack.paste(source.crop((0, top, source.width, bottom)), (0, i * (height + 20) + 20))
    attack.save(directory / "attack_sequence.png")
    for name in ["animation", "battle"]:
        paths = sorted(directory.glob(name + "_*.png"))
        tiles = [Image.open(p).convert("RGB").resize((512, 320), Image.Resampling.NEAREST) for p in paths]
        contact = Image.new("RGB", (512 * 3, 342 * ((len(tiles) + 2) // 3)), (20, 25, 36))
        d = ImageDraw.Draw(contact)
        for i, (tile, p) in enumerate(zip(tiles, paths)):
            x, y = i % 3 * 512, i // 3 * 342
            d.text((x + 5, y + 4), p.stem, font=font, fill="white")
            contact.paste(tile, (x, y + 22))
        contact.save(directory / (name + "_sequence.jpg"), quality=93)
print(OUT / "all_50_comparison.png")
