#!/usr/bin/env python3
"""Rebake retained H3 mattes once, with clean edges and separate UI portraits.

python3 tools/sprite/readability.py --only niamh
python3 tools/sprite/readability.py --install

Sources in art/animation are immutable. Every unit is staged and validated before
installation; build/readability/baseline holds the first runtime backup. Running
again always samples the source mattes, never a previously processed sheet.
"""
from __future__ import annotations

import argparse
import hashlib
import html
import json
import shutil
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage as ndi

from world_h3_post import anchor

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "art/animation/last_refuge_v3_pixel_h3"
OUT = ROOT / "build/readability"
SIZE = 256
COLORS = 96


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def savejson(path, obj):
    path.write_text(json.dumps(obj, ensure_ascii=False, indent=2) + "\n")


def source_frame(path, selection, neutral=False):
    """Replay approved per-character repairs before any new processing."""
    a = np.array(Image.open(path).convert("RGBA"))
    for rule in selection.get("cleanup_colors", []):
        match = (np.max(abs(a[:, :, :3].astype("int16") - np.array(rule["rgb"])), axis=2)
                 <= rule["tolerance"]) & (a[:, :, 3] > 0)
        labs, _ = ndi.label(match)
        sizes = np.bincount(labs.ravel())
        sizes[0] = 0
        a[np.isin(labs, np.flatnonzero(sizes >= rule["min_area"]))] = 0
    if neutral:
        edge = (a[:, :, 3] > 0) & ~ndi.binary_erosion(a[:, :, 3] > 0, iterations=3)
        spill = edge & (a[:, :, 1].astype("int16") > np.maximum(a[:, :, 0], a[:, :, 2]).astype("int16") + 18)
        grey = ((a[:, :, 0].astype("int16") + a[:, :, 2]) / 2).astype("uint8")
        a[spill, :3] = grey[spill, None]
    return Image.fromarray(a)


def clean_matte(im):
    """Remove tiny detached dust and replace just the contaminated edge colors.

    Two source pixels are less than one combat pixel. Alpha is not eroded: thin
    weapons retain their width. Interior costume colors are never desaturated.
    """
    a = np.array(im)
    fg = a[:, :, 3] >= 128
    labels, _ = ndi.label(fg, structure=np.ones((3, 3)))
    areas = np.bincount(labels.ravel())
    areas[0] = 0
    # H3's detached particles are exported separately as shot/effect sheets.
    # Retain the connected actor/equipment, as the reviewed source pipeline does.
    fg &= labels == int(np.argmax(areas))
    core = ndi.binary_erosion(fg, iterations=2)
    if not core.any():
        raise ValueError("No solid character core")
    distance, nearest = ndi.distance_transform_edt(~core, return_indices=True)
    boundary = fg & ~core & (distance <= 3)
    a[boundary, :3] = a[nearest[0][boundary], nearest[1][boundary], :3]
    a[:, :, 3] = np.where(fg, 255, 0)
    a[~fg, :3] = 0
    return Image.fromarray(a)


def sample(im, size):
    # Pillow's RGBa mode averages premultiplied color, so transparent black does
    # not contaminate the visible border. Exactly one resize from the source.
    z = im.convert("RGBa").resize(size, Image.Resampling.BOX).convert("RGBA")
    a = np.array(z)
    fg = a[:, :, 3] >= 96
    a[:, :, 3] = np.where(fg, 255, 0)
    a[~fg, :3] = 0
    return Image.fromarray(a)


def palette_for(frames):
    visible = np.concatenate([np.array(f)[:, :, :3][np.array(f)[:, :, 3] > 0] for f in frames])
    # Quantize foreground samples only: transparent backdrop never gets a vote.
    return Image.fromarray(visible.reshape(1, -1, 3)).quantize(colors=COLORS, method=Image.Quantize.MEDIANCUT)


def outlined(frame):
    a = np.array(frame)
    fg = a[:, :, 3] > 0
    # A four-connected, one-pixel contour adds a readable edge without growing
    # every interior detail or making a square halo around diagonal hair tips.
    outer = ndi.binary_dilation(fg) & ~fg
    _, nearest = ndi.distance_transform_edt(~fg, return_indices=True)
    a[outer, :3] = np.rint(a[nearest[0][outer], nearest[1][outer], :3] * .48).astype("uint8")
    a[outer, 3] = 255
    return Image.fromarray(a)


def finish(frame, palette):
    a = np.array(frame)
    z = Image.fromarray(a[:, :, :3]).quantize(palette=palette, dither=Image.Dither.NONE).convert("RGBA")
    z.putalpha(Image.fromarray(a[:, :, 3]))
    a = np.array(z)
    a[a[:, :, 3] == 0, :3] = 0
    return Image.fromarray(a)


def validate(frames, pin):
    first = frames[0].crop(pin).tobytes()
    for f in frames:
        box = f.getbbox()
        if not box or box[0] <= 0 or box[1] <= 0 or box[2] >= SIZE or box[3] >= SIZE:
            raise ValueError(f"Empty/clipped actor: {box}")
        if f.crop(pin).tobytes() != first:
            raise ValueError("Foot patch differs between frames")
        if not set(f.getchannel("A").getdata()) <= {0, 255}:
            raise ValueError("Non-binary sprite alpha")


def bake(uid):
    src = SOURCE / uid
    dst = OUT / "staged" / uid
    dst.mkdir(parents=True, exist_ok=True)
    info = json.loads((src / "animation.json").read_text())
    selection = info["selection"]
    ref = selection["reference"]
    pin_ref = selection.get("foot_pin_reference", ref)
    indices = sorted(set(info["idle_source_indices"] + info["attack_source_indices"] + [ref, pin_ref]))
    source = {i: source_frame(src / "matte" / f"f_{i:04}.png", selection, info["element"] == "none") for i in indices}
    clean = {i: clean_matte(im) for i, im in source.items()}
    scale = info["constant_character_scale"]
    n = round(SIZE * scale)
    reviewed = {}
    for name in ("idle", "attack"):
        for frame_no, i in enumerate(info[name + "_source_indices"]):
            if name == "attack" and frame_no == len(info["attack_source_indices"]) - 1:
                continue  # The reviewed last frame is the ready pose.
            reviewed[i] = np.array(Image.open(src / name / f"{name}_{frame_no:02}.png"))[:, :, 3] > 0
    reviewed[ref] = np.array(Image.open(src / "ready.png"))[:, :, 3] > 0
    rendered = {}
    for i, im in source.items():
        # Preserve the reviewed registration and shared idle/attack transform.
        # Re-measuring cleaned edges would move the feet or weapon origins.
        old = np.array(im.resize((SIZE, SIZE), Image.Resampling.NEAREST))
        labels, _ = ndi.label(old[:, :, 3] > 0)
        areas = np.bincount(labels.ravel()); areas[0] = 0
        old[labels != np.argmax(areas)] = 0
        x, y = anchor(Image.fromarray(old), info["qc"]["source_foot_x_hint"])
        z = sample(clean[i], (n, n))
        canvas = Image.new("RGBA", (SIZE, SIZE))
        canvas.paste(z, (128 - round(x * scale), 224 - round(y * scale)))
        if i in reviewed:
            # Fine connections can attach an unwanted projectile to the native
            # matte. The reviewed silhouette supplies a permissive 2px guard;
            # source pixels inside it still get recovered with area sampling.
            a = np.array(canvas)
            a[~ndi.binary_dilation(reviewed[i], iterations=2)] = 0
            canvas = Image.fromarray(a)
        rendered[i] = canvas
    # Include the future contour in the common palette, so outlines retain dark
    # colors even when the costume itself is mostly white or bright yellow.
    rendered = {i: outlined(f) for i, f in rendered.items()}
    palette = palette_for(list(rendered.values()))
    rendered = {i: finish(f, palette) for i, f in rendered.items()}
    # Enlarge the patch by the one-pixel contour to avoid a seam below the sole.
    p = info["qc"]["foot_pin_box"]
    pin = (p[0] - 1, p[1] - 1, p[2] + 1, p[3] + 1)
    sole = rendered[pin_ref].crop(pin)
    for f in rendered.values():
        f.paste(sole, pin[:2])
    sequences = {name: [rendered[i].copy() for i in info[name + "_source_indices"]] for name in ("idle", "attack")}
    sequences["attack"][-1] = rendered[ref].copy()
    all_frames = sequences["idle"] + sequences["attack"]
    validate(all_frames, pin)

    runtime = ROOT / "art/anim" / uid
    meta = json.loads((runtime / "anim.json").read_text())
    meta["foot_pin_box"] = list(pin)
    meta["palette_colors"] = COLORS
    meta["readability"] = {"version": 1, "source": str(src.relative_to(ROOT)),
        "method": "native matte > edge color repair > premultiplied area sample > shared palette > 1px contour > fixed feet",
        "source_hashes": {str(i): digest(src / "matte" / f"f_{i:04}.png") for i in indices}}
    for name, frames in sequences.items():
        sheet = Image.new("RGBA", (SIZE * len(frames), SIZE))
        for i, f in enumerate(frames):
            sheet.paste(f, (i * SIZE, 0))
        path = dst / f"{uid}_{name}.png"
        sheet.save(path)
        meta["clips"][name]["sha256"] = digest(path)
    savejson(dst / "anim.json", meta)
    # A high-resolution portrait is separate from combat's 256px atlas. Niamh
    # has an explicitly authored ToBe portrait; everyone else uses the retained
    # full-resolution ready pose, avoiding a destructive two-stage shrink.
    override = ROOT / "art/portraits/sources" / f"{uid}.png"
    portrait = Image.open(override).convert("RGBA") if override.exists() else clean[ref]
    portrait = portrait.crop(portrait.getbbox())
    if portrait.height > 512:
        portrait = portrait.convert("RGBa").resize((round(portrait.width * 512 / portrait.height), 512), Image.Resampling.BOX).convert("RGBA")
    canvas = Image.new("RGBA", (portrait.width + 8, portrait.height + 8))
    canvas.paste(portrait, (4, 4))
    canvas.save(dst / "portrait.png")
    base = Image.open(src / "idle/idle_00.png").convert("RGBA")
    current = sequences["idle"][0]
    report = {"id": uid, "frames": len(all_frames), "source_height": clean[ref].getbbox()[3] - clean[ref].getbbox()[1],
        "portrait_size": list(canvas.size), "portrait_source": "authored transparent override" if override.exists() else "full-resolution H3 ready matte",
        "old_opaque_pixels": int(np.count_nonzero(np.array(base)[:, :, 3])),
        "new_opaque_pixels": int(np.count_nonzero(np.array(current)[:, :, 3])),
        "feet_identical": True, "clipped": False}
    base.save(dst / "before.png"); current.save(dst / "after.png")
    return report


def contact_sheet(rows, path):
    font = ImageFont.truetype(str(ROOT / "core/fonts/RefugeSans-Bold.otf"), 18)
    contact = Image.new("RGB", (1000, len(rows) * 290), "#172127")
    d = ImageDraw.Draw(contact)
    for i, row in enumerate(rows):
        uid = row["id"]; dst = OUT / "staged" / uid; y = i * 290
        for x, name in [(0, "before"), (260, "after")]:
            im = Image.open(dst / f"{name}.png").convert("RGBA")
            contact.paste(im, (x, y + 26), im)
            d.text((x + 12, y + 4), uid + " / " + name, fill="white", font=font)
        im = Image.open(dst / "portrait.png").convert("RGBA")
        im.thumbnail((440, 246), Image.Resampling.LANCZOS)
        contact.paste(im, (520 + (480 - im.width) // 2, y + 282 - im.height), im)
        d.text((532, y + 4), "UI portrait", fill="white", font=font)
    contact.save(path)


def gallery(rows):
    featured = [r for uid in ("niamh", "solana", "zero") for r in rows if r["id"] == uid]
    contact_sheet(featured or rows[:3], OUT / "comparison.png")
    for start in range(0, len(rows), 10):
        contact_sheet(rows[start:start + 10], OUT / f"contact_{start // 10 + 1}.png")
    options = "".join(f'<option>{html.escape(r["id"])}</option>' for r in rows)
    page = '''<!doctype html><html lang="ko"><meta charset="utf-8">
<title>캐릭터 가독성 비교</title><style>
body{margin:24px;background:#10191f;color:#f3eee3;font:16px system-ui}h1{font-size:24px}
select,button{font:inherit;padding:8px;margin:6px}main{display:flex;gap:16px;flex-wrap:wrap}
section{background:#203038;padding:12px;border-radius:10px}canvas{max-width:100%;width:384px}
.portrait{width:384px;height:384px;display:flex;align-items:center;justify-content:center}
.portrait img{max-height:95%;max-width:95%}label{display:block}p{line-height:1.6}
</style><h1>원본 / 후처리 / 상세창 원화</h1>
<p>전투: 원본에서 한 번 축소 · 공통 팔레트 · 1px 외곽선 · 발 고정<br>
상세창: 작은 전투 프레임 대신 전용 원화. Niamh에는 ToBe.png의 투명 추출본 사용.</p>
<select id="unit">OPTIONS</select><select id="motion"><option>idle</option><option>attack</option></select>
<button id="pause">일시정지</button><button id="background">배경 변경</button>
<main><section><label>기존 전투</label><canvas id="before" width="512" height="512"></canvas></section>
<section><label>후처리 전투</label><canvas id="after" width="512" height="512"></canvas></section>
<section><label>상세창 원화</label><div class="portrait"><img id="portrait"></div></section></main>
<script>
const unit=document.querySelector('#unit'),motion=document.querySelector('#motion');
const old=new Image(),fresh=new Image(),portrait=document.querySelector('#portrait');
let tick=0,paused=false,bg=0;const backgrounds=['#172127','#eee5d4','#567456'];
function load(){tick=0;old.src='../../art/animation/last_refuge_v3_pixel_h3/'+unit.value+'/'+motion.value+'_sheet.png';
fresh.src='staged/'+unit.value+'/'+unit.value+'_'+motion.value+'.png';portrait.src='staged/'+unit.value+'/portrait.png';}
unit.onchange=motion.onchange=load;
document.querySelector('#pause').onclick=e=>{paused=!paused;e.target.textContent=paused?'재생':'일시정지'};
document.querySelector('#background').onclick=()=>{bg=(bg+1)%backgrounds.length};
if([...unit.options].some(o=>o.value==='niamh'))unit.value='niamh';load();
setInterval(()=>{const n=motion.value==='idle'?8:12;
for(const [id,img] of [['before',old],['after',fresh]]){const ctx=document.querySelector('#'+id).getContext('2d');
ctx.fillStyle=backgrounds[bg];ctx.fillRect(0,0,512,512);ctx.imageSmoothingEnabled=false;
if(img.complete&&img.naturalWidth)ctx.drawImage(img,(tick%n)*256,0,256,256,0,0,512,512);}
document.querySelector('.portrait').style.background=backgrounds[bg];if(!paused)tick++;},1000/12);
</script></html>'''
    (OUT / "index.html").write_text(page.replace("OPTIONS", options))


def install(rows):
    # All images have already passed validation. Keep the first original files
    # and use atomic file replacement so an interrupted copy cannot corrupt PNG.
    for row in rows:
        uid = row["id"]; stage = OUT / "staged" / uid
        runtime = ROOT / "art/anim" / uid
        backup = OUT / "baseline" / uid
        backup.mkdir(parents=True, exist_ok=True)
        for name in ["anim.json", f"{uid}_idle.png", f"{uid}_attack.png"]:
            if not (backup / name).exists():
                shutil.copyfile(runtime / name, backup / name)
            tmp = runtime / (name + ".tmp")
            shutil.copyfile(stage / name, tmp); tmp.replace(runtime / name)
        target = ROOT / "art/portraits" / f"{uid}.png"
        target.parent.mkdir(parents=True, exist_ok=True)
        tmp = target.with_suffix(".tmp.png")
        shutil.copyfile(stage / "portrait.png", tmp); tmp.replace(target)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--only", default="")
    ap.add_argument("--install", action="store_true")
    a = ap.parse_args()
    roster = json.loads((ROOT / "tools/roster.json").read_text())
    units = [u["id"] for t in roster["tiers"] for u in t["units"]]
    if a.only:
        wanted = set(a.only.split(","))
        if not wanted <= set(units):
            raise ValueError("Unknown character IDs: " + ",".join(wanted - set(units)))
        units = [u for u in units if u in wanted]
    rows = []
    for uid in units:
        row = bake(uid); rows.append(row)
        print(uid, "portrait", row["portrait_size"], "opaque", row["old_opaque_pixels"], "->", row["new_opaque_pixels"], flush=True)
    gallery(rows)
    savejson(OUT / "report.json", {"characters": rows, "installed": a.install})
    if a.install:
        install(rows)
    print(f"{'Installed' if a.install else 'Staged'} {len(rows)} characters; {OUT}")


if __name__ == "__main__":
    main()
