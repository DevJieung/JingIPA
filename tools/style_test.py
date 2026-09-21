#!/usr/bin/env python3
"""픽셀아트 화풍 후보를 몇 장 뽑아 눈으로 고르기 위한 시험용 스크립트.

로컬 Krea 2 Turbo 를 한 번만 올려서 후보 화풍 × 표본 캐릭터를 전부 뽑는다.
결과: build/styletest/<화풍>_<표본>.png  (원본 1024 + 픽셀화 결과 둘 다)
"""
from __future__ import annotations
import os, sys, time

KREA_ROOT = "/home/dgxmaruta/pjt/krea2"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "build", "styletest")
sys.path.insert(0, KREA_ROOT)

# 후보 화풍 앵커 넷
STYLES = {
    # 1) 정통 16비트 스프라이트
    "a": ("16-bit pixel art sprite, retro SNES japanese role playing game character sprite, "
          "crisp clean pixels, limited 24 color palette, black outline, "
          "strong readable silhouette, flat cel shading with dithering, "
          "front three-quarter view, full body, centered, "
          "on a pure flat white background, no text, no watermark, no grid"),
    # 2) 좀 더 굵고 아기자기한 도트
    "b": ("cute chunky pixel art game sprite, 32x32 style low resolution dot art, "
          "thick dark outline, bold saturated colors, simple shapes, big head chibi proportions, "
          "front view, full body, centered, standing pose, "
          "on a pure flat white background, no text, no watermark, no grid"),
    # 3) 화려한 판타지 도트 (상위 등급용)
    "c": ("detailed pixel art sprite of a fantasy hero, 16-bit arcade beat em up style, "
          "rich shading, glowing magic accents, ornate armor, dramatic pose, "
          "crisp square pixels, limited palette, black outline, "
          "full body, centered, on a pure flat white background, no text, no grid"),
}
SAMPLES = {
    "slime": "a small round green slime monster with two black dot eyes",
    "knight": "a young knight girl in blue plate armor holding a short sword and round shield",
    "dragon": "a majestic golden dragon knight with huge feathered wings and a flaming greatsword",
}


def pixelize(img, target_h=96, colors=32):
    """1024px 생성물을 진짜 도트처럼 만든다: 축소 -> 팔레트 축약."""
    from PIL import Image
    w, h = img.size
    tw = max(1, round(w * target_h / h))
    small = img.resize((tw, target_h), Image.BOX)
    if img.mode == "RGBA":
        rgb = small.convert("RGB").quantize(colors=colors, method=Image.MEDIANCUT).convert("RGB")
        rgb.putalpha(small.getchannel("A").point(lambda a: 255 if a > 128 else 0))
        return rgb
    return small.convert("RGB").quantize(colors=colors, method=Image.MEDIANCUT).convert("RGB")


def cut_white(img, thresh=26):
    """흰 배경을 지운다 (gen_dinos.py 의 방식을 옮겨 옴)."""
    from PIL import Image, ImageDraw
    import numpy as np
    rgb = img.convert("RGB"); w, h = rgb.size
    arr = np.array(rgb).astype("int16")
    sat = arr.max(axis=2) - arr.min(axis=2)
    val = arr.max(axis=2)
    protect = (sat > 22) | (val < 205)
    work = np.array(rgb); work[protect] = 0
    wimg = Image.fromarray(work); key = (255, 0, 255)
    for xy in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1),
               (w // 2, 0), (w // 2, h - 1), (0, h // 2), (w - 1, h // 2)]:
        try: ImageDraw.floodfill(wimg, xy, key, thresh=thresh)
        except Exception: pass
    warr = np.array(wimg)
    bg = (warr[:, :, 0] == key[0]) & (warr[:, :, 1] == key[1]) & (warr[:, :, 2] == key[2])
    out = img.convert("RGBA")
    out.putalpha(Image.fromarray(((~bg) * 255).astype("uint8"), mode="L"))
    bb = out.getbbox()
    return out.crop(bb) if bb else out


def main() -> int:
    os.makedirs(OUT, exist_ok=True)
    # ★ Krea2 와 MiniMax H3 는 같은 순간에 못 뜬다 — 올리기 전에 문지기를 부른다 (tools/gpu_guard.py)
    import gpu_guard
    gpu_guard.claim("krea2")
    from krea2.pipelines.image import Krea2ImagePipeline
    t0 = time.time()
    print("[style] 모델 올리는 중...", flush=True)
    pipe = Krea2ImagePipeline("turbo").load()
    print(f"[style] 준비 완료 ({time.time()-t0:.0f}초)", flush=True)
    n = 0
    for sk, sv in STYLES.items():
        for mk, mv in SAMPLES.items():
            t1 = time.time()
            prompt = f"{mv}, {sv}"
            res = pipe.generate(prompt, width=1024, height=1024, seed=7000 + n)[0]
            res.image.save(os.path.join(OUT, f"{sk}_{mk}_raw.png"))
            cut = cut_white(res.image)
            px = pixelize(cut, 96, 32)
            px.save(os.path.join(OUT, f"{sk}_{mk}_dot.png"))
            px.resize((px.size[0] * 4, px.size[1] * 4), 0).save(
                os.path.join(OUT, f"{sk}_{mk}_dot4x.png"))
            n += 1
            print(f"[style] {sk}/{mk} {px.size[0]}x{px.size[1]} {time.time()-t1:.0f}초", flush=True)
    print(f"[style] 완료 {n}장, {OUT}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
