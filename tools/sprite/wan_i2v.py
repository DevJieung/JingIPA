#!/usr/bin/env python3
"""Step 2 — Wan 2.2 I2V 로 마스터 한 장에서 동작 클립을 뽑는다.

`sprite_pipeline.md` §3 Step 2 를 ComfyUI API 로 옮긴 것.

★★ **동영상을 거치지 않는다.** 지침의 후처리는 mp4 를 ffmpeg 로 뜯는데, H.264 는
   하드 엣지를 갈아 뭉개고 색을 4:2:0 으로 반씩 버린다 — 도트 그림에서 그것은
   테두리 한 도트(sprite_design.md §3)와 마젠타 크로마키를 **동시에** 망친다.
   여기서는 `VAEDecode` 뒤에 곧장 `SaveImage` 를 물려 **프레임을 PNG 로** 받는다.
   지침 §3 의 `extract()` 가 하던 일(안쪽에서 균등 샘플링)은 Step 3 이 그대로 한다.

★ 두 전문가(high/low noise)를 쌍으로 돌린다. LoRA 도 반드시 쌍으로 — 한쪽만
  얹으면 픽셀 화풍이 무너진다(지침 §6).
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
import uuid

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)

import units as U                                # noqa: E402

PIXELFORGE = "/home/dgxmaruta/pjt/pixelforge"
COMFY = os.path.join(PIXELFORGE, "ComfyUI")
# ★ 8188 을 쓰지 마라 — 이 머신에는 **남의 ComfyUI 가 이미** 거기 떠 있다
#   (pixelforge 것이거나 사람이 띄운 것). 그 자리에 붙으면 우리 가중치 경로를
#   모르는 인스턴스에 그래프를 던지게 되고, 「그 이름의 모델이 없다」로 튕긴다
#   (실제로 그렇게 튕겼다). 죽이지 말고 **옆에** 띄운다.
# ★★ 8199 도 이제 못 쓴다 — MiniMax H3 서버(`~/pjt/h3/serve.sh`)가 거기 **상주**한다
#   (`h3_i2v.py` 머리말). alive() 가 참이라 안 띄우고 그리로 Wan 그래프를 던지는데,
#   그 서버는 Wan 가중치를 몰라서 위와 똑같이 튕긴다. 그래서 8198 이다.
HOST = os.environ.get("POCKER_COMFY", "127.0.0.1:8198")
OUT = os.path.join(ROOT, "build", "sprite")

DEF_SEED = 7            # `units.SEED` 에 없는 캐릭터가 쓰는 값
HIGH = "wan2.2_i2v_high_noise_14B_fp8_scaled.safetensors"
LOW = "wan2.2_i2v_low_noise_14B_fp8_scaled.safetensors"
UMT5 = "umt5_xxl_fp8_e4m3fn_scaled.safetensors"
VAE = "wan_2.1_vae.safetensors"

LORA = {
    "speed":  ("wan2.2_i2v_lightx2v_4steps_lora_v1_high_noise.safetensors",
               "wan2.2_i2v_lightx2v_4steps_lora_v1_low_noise.safetensors"),
    "attack": ("pixel_attack_lora_v2_000000750_high_noise.safetensors",
               "pixel_attack_lora_v2_000000750_low_noise.safetensors"),
    "walk":   ("pixel_walk_lora_v1_high_noise.safetensors",
               "pixel_walk_lora_v1_low_noise.safetensors"),
}

# 지침 §Step 2 의 문구. `no camera movement / static camera` 를 빼면 카메라가 움직여서
# 프레임 정렬이 전부 어긋난다 — 공통 크롭(Step 3)이 그 순간 뜻을 잃는다.
NEG = ("camera pan, zoom, blurry, motion blur, background change, "
       "extra limbs, text, watermark, 3d render, smooth shading")


def _post(path: str, payload: dict) -> dict:
    req = urllib.request.Request(f"http://{HOST}{path}",
                                 data=json.dumps(payload).encode(),
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        # ★ 400 의 **본문**을 반드시 보여 준다. 그래프가 검증에서 튕기는 까닭은
        #   거의 언제나 「그 이름의 가중치가 없다」인데, 그 이름은 본문에만 적힌다.
        body = e.read().decode("utf-8", "replace")[:2000]
        raise SystemExit(f"ComfyUI 가 {e.code} 로 거절했다:\n{body}") from None


def _get(path: str) -> dict:
    with urllib.request.urlopen(f"http://{HOST}{path}", timeout=60) as r:
        return json.loads(r.read())


def alive() -> bool:
    try:
        _get("/system_stats")
        return True
    except Exception:
        return False


def serve() -> subprocess.Popen | None:
    """ComfyUI 가 안 떠 있으면 띄운다. 우리 가중치 경로를 **얹어서** 준다."""
    # ★ Wan 도 MiniMax H3 와 같은 순간에 못 뜬다 — 문지기가 H3 의 메모리를 비우고 락을 잡는다.
    #   서버가 이미 떠 있어도 부른다: 모델은 첫 그래프에서 올라오므로 그때 H3 가 물고 있으면 터진다.
    sys.path.insert(0, os.path.join(ROOT, "tools"))
    import gpu_guard
    gpu_guard.claim("wan")
    if alive():
        print("[comfy] 이미 떠 있다")
        return None
    py = os.path.join(PIXELFORGE, ".venv-comfy", "bin", "python")
    host, port = HOST.split(":")
    cmd = [py, "main.py", "--listen", host, "--port", port,
           "--extra-model-paths-config",
           os.path.join(COMFY, "extra_model_paths.yaml"),
           os.path.join(HERE, "comfy_paths.yaml")]
    # ★ 지침 §2 의 `--disable-smart-memory` 는 **안 쓴다.** 그 권고는 「워크플로를
    #   갈아 끼울 때」의 이야기인데 여기서는 같은 그래프를 열 번 돌린다. 그리고
    #   GB10 은 통합메모리라 「VRAM 에서 일반 RAM 으로 내린다」가 같은 램 안에서의
    #   복사일 뿐이다 — 켜면 클립마다 28GB 짜리 전문가 둘을 다시 읽는다.
    #   대신 **애니메이션 종류별로 묶어서** 돌려 LoRA 갈아 끼우기를 한 번으로 줄인다.
    log = open(os.path.join(OUT, "comfy.log"), "w")
    os.makedirs(OUT, exist_ok=True)
    p = subprocess.Popen(cmd, cwd=COMFY, stdout=log, stderr=subprocess.STDOUT)
    print("[comfy] 띄우는 중 …")
    for _ in range(180):
        if alive():
            print("[comfy] 준비됨")
            return p
        if p.poll() is not None:
            raise SystemExit(f"ComfyUI 가 죽었다 — {OUT}/comfy.log 를 봐라")
        time.sleep(2)
    raise SystemExit("ComfyUI 가 6분 안에 안 떴다")


def upload(png: str) -> str:
    """LoadImage 가 볼 수 있게 input/ 에 넣는다."""
    dst_dir = os.path.join(COMFY, "input")
    os.makedirs(dst_dir, exist_ok=True)
    name = os.path.basename(png)
    shutil.copyfile(png, os.path.join(dst_dir, name))
    return name


def graph(image: str, pos: str, *, seed: int, length: int, size: int,
          loras: list[tuple[str, float]], steps: int, split: int) -> dict:
    """Wan 2.2 I2V 두 전문가 그래프. LoRA 는 언제나 high/low 쌍으로 얹는다."""
    g: dict[str, dict] = {
        "1": {"class_type": "UNETLoader",
              "inputs": {"unet_name": HIGH, "weight_dtype": "default"}},
        "2": {"class_type": "UNETLoader",
              "inputs": {"unet_name": LOW, "weight_dtype": "default"}},
        "3": {"class_type": "CLIPLoader",
              "inputs": {"clip_name": UMT5, "type": "wan"}},
        "4": {"class_type": "VAELoader", "inputs": {"vae_name": VAE}},
    }
    hi, lo = "1", "2"                            # 지금 사슬의 끝
    nid = 20
    for key, w in loras:
        h, l = LORA[key]
        g[str(nid)] = {"class_type": "LoraLoaderModelOnly",
                       "inputs": {"model": [hi, 0], "lora_name": h,
                                  "strength_model": w}}
        hi = str(nid); nid += 1
        g[str(nid)] = {"class_type": "LoraLoaderModelOnly",
                       "inputs": {"model": [lo, 0], "lora_name": l,
                                  "strength_model": w}}
        lo = str(nid); nid += 1

    g.update({
        "9":  {"class_type": "CLIPTextEncode", "inputs": {"clip": ["3", 0], "text": pos}},
        "10": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["3", 0], "text": NEG}},
        "11": {"class_type": "LoadImage", "inputs": {"image": image}},
        "12": {"class_type": "WanImageToVideo",
               "inputs": {"positive": ["9", 0], "negative": ["10", 0], "vae": ["4", 0],
                          "start_image": ["11", 0], "width": size, "height": size,
                          "length": length, "batch_size": 1}},
        # 앞쪽 절반 = high noise 전문가. 뒤에 노이즈를 남겨 낮은 쪽에 넘긴다.
        "13": {"class_type": "KSamplerAdvanced",
               "inputs": {"model": [hi, 0], "positive": ["12", 0], "negative": ["12", 1],
                          "latent_image": ["12", 2], "add_noise": "enable",
                          "noise_seed": seed, "steps": steps, "cfg": 1.0,
                          "sampler_name": "euler", "scheduler": "simple",
                          "start_at_step": 0, "end_at_step": split,
                          "return_with_leftover_noise": "enable"}},
        "14": {"class_type": "KSamplerAdvanced",
               "inputs": {"model": [lo, 0], "positive": ["12", 0], "negative": ["12", 1],
                          "latent_image": ["13", 0], "add_noise": "disable",
                          "noise_seed": 0, "steps": steps, "cfg": 1.0,
                          "sampler_name": "euler", "scheduler": "simple",
                          "start_at_step": split, "end_at_step": 10000,
                          "return_with_leftover_noise": "disable"}},
        "15": {"class_type": "VAEDecode", "inputs": {"samples": ["14", 0], "vae": ["4", 0]}},
        # ★ 동영상이 아니라 **프레임 PNG** 로 받는다 (위 주석)
        "16": {"class_type": "SaveImage",
               "inputs": {"images": ["15", 0], "filename_prefix": "pocker/" + image[:-4]}},
    })
    return g


def run(g: dict, tag: str) -> list[str]:
    cid = str(uuid.uuid4())
    pid = _post("/prompt", {"prompt": g, "client_id": cid})["prompt_id"]
    t0 = time.time()
    while True:
        h = _get(f"/history/{pid}")
        if pid in h:
            st = h[pid].get("status", {})
            if st.get("status_str") == "error" or st.get("completed") is False:
                msgs = json.dumps(st.get("messages", []), ensure_ascii=False)[:1500]
                raise SystemExit(f"{tag}: ComfyUI 오류\n{msgs}")
            outs = []
            for node in h[pid]["outputs"].values():
                for im in node.get("images", []):
                    outs.append(os.path.join(COMFY, "output", im.get("subfolder", ""),
                                             im["filename"]))
            print(f"  {tag}: {len(outs)}프레임 {time.time() - t0:.0f}초")
            return sorted(outs)
        if time.time() - t0 > 3600:
            raise SystemExit(f"{tag}: 한 시간이 지났다")
        time.sleep(3)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--route", default="sdxl", choices=("sdxl", "krea"))
    ap.add_argument("--only", default="")
    ap.add_argument("--anim", default="", help="idle,attack 중 몇 개만")
    ap.add_argument("--length", type=int, default=33)
    ap.add_argument("--size", type=int, default=512)
    ap.add_argument("--steps", type=int, default=4)
    ap.add_argument("--split", type=int, default=2)
    ap.add_argument("--seed", type=int, default=DEF_SEED)
    ap.add_argument("--view", default="front", help="마스터의 시점과 같게 적는다")
    ap.add_argument("--speed-w", type=float, default=1.0, help="lightx2v 4스텝 LoRA 세기")
    # ★ 기본이 `auto` 다 — **무리마다 다른 세기**(`units.PIX_W`)를 쓴다. 숫자를 주면
    #   여든 명 전부에 그 값을 똑같이 건다(비교 팔을 돌릴 때만 그렇게 한다).
    ap.add_argument("--pix-w", default="auto",
                    help="픽셀 LoRA 세기. auto=무리마다 (units.PIX_W) · 숫자=전부 그 값 · 0=안 씀")
    ap.add_argument("--idle-lora", default="", choices=("", "walk", "attack"),
                    help="idle 에도 픽셀 LoRA 를 얹는다 (기본: 안 얹음)")
    # ★ 비교 팔(arm)을 나란히 두려고 있는 것이다. 손잡이 하나만 바꿔 두 번 돌린 뒤
    #   나란히 놓고 봐야 「그 손잡이가 무엇을 했나」가 보인다 — 덮어쓰면 앞의 것이
    #   없어져서 매번 기억으로 비교하게 된다(docs/SPRITE.md 4-3 이 그 자리다).
    ap.add_argument("--tag", default="", help="클립 폴더에 붙일 꼬리표 (비교 팔)")
    ap.add_argument("--force", action="store_true")
    a = ap.parse_args()

    ids = [s for s in a.only.split(",") if s] or U.PILOT
    anims = [s for s in a.anim.split(",") if s] or U.ANIMS
    us = U.load(ids)
    os.makedirs(OUT, exist_ok=True)
    serve()

    # ★ 바깥이 애니메이션이다. LoRA 가 애니메이션마다 다르므로 이 차례여야
    #   28GB 짜리 전문가를 다시 읽는 일이 열 번이 아니라 두 번으로 준다.
    for anim in anims:
        # ★★ **LoRA 세기가 같은 것끼리 붙여 돌린다.** 세기가 바뀔 때마다 ComfyUI 가
        #   28GB 짜리 전문가에 LoRA 를 다시 얹는데, 무리마다 세기가 다르므로
        #   (`units.PIX_W` — 활·총 0.5 · 검 1.0 · 채찍 0.5 · 광역 0) 로스터 차례로
        #   돌면 쉰 번 가까이 다시 얹는다. 세기로 묶으면 **세 번**이다.
        #   ☆ 묶음 안의 차례는 그대로 두므로 결과는 한 톨도 안 달라진다.
        order = sorted(us, key=lambda x: (U.PIX_W[x["family"]] if a.pix_w == "auto"
                                          else 0.0)) if anim == "attack" else us
        for u in order:
            dst = os.path.join(OUT, a.route, "clips" + a.tag, f"{u['id']}_{anim}")
            if os.path.isdir(dst) and os.listdir(dst) and not a.force:
                print(f"  {u['id']}_{anim}: 있음 — 건너뜀")
                continue
            src = os.path.join(OUT, a.route, "wan_in", f"{u['id']}.png")
            if not os.path.exists(src):
                raise SystemExit(f"Wan 입력이 없다: {src} (먼저 make_ref → refine)")
            name = upload(src)
            act = (U.ATTACK_ACTION if anim == "attack" else U.IDLE_ACTION)[u["family"]]
            loras = [("speed", a.speed_w)]
            # ★ 픽셀 LoRA 는 **쌍으로** 얹는다(지침 §6: 한쪽만 얹으면 픽셀 화풍이
            #   무너진다). idle 은 지침에 트리거가 없어서 기본은 안 얹지만,
            #   화풍이 무너지면 `--idle-lora walk` 로 픽셀 모션 LoRA 를 빌려 쓴다.
            key = "attack" if anim == "attack" else (a.idle_lora or "")
            pw = U.PIX_W[u["family"]] if a.pix_w == "auto" else float(a.pix_w)
            on = bool(key) and pw > 0
            if on:
                loras.append((key, pw))
            # ★★ 트리거 낱말은 **그 LoRA 를 실제로 얹을 때만** 적는다. `--pix-w 0`
            #   으로 빼 놓고도 `pix3lattack,` 을 맨 앞에 두면, 그 자리는 프롬프트에서
            #   가장 센 자리라 베이스 모델이 그 말을 「칼 휘두르기」로 읽는다 —
            #   LoRA 를 뺀 팔이 뺀 것처럼 안 보이게 되어 비교가 통째로 거짓이 된다.
            trig = "pix3lattack, " if (anim == "attack" and on) else ""
            # ★ 시점을 **마스터와 같게** 말한다. 지침의 문구는 "side view" 인데
            #   원화가 정면이라(units.SD_HEAD 주석) 그대로 넣으면 Wan 이 클립 도중에
            #   몸을 옆으로 돌린다 — 그 순간 프레임마다 다른 사람이 된다.
            pos = (f"{trig}{a.view} view pixel art sprite of a character, {act}, "
                   f"solid magenta background, "
                   f"no camera movement, static camera, full body, "
                   f"the character stays in the same place and keeps the same design")
            # ★ 손으로 고른 씨앗이 있으면 그것을 쓴다 (`units.SEED` 머리말).
            #   `--seed` 를 명시로 준 재굴림 때는 그쪽이 이긴다.
            seed = a.seed if a.seed != DEF_SEED else U.SEED.get(u["id"], a.seed)
            g = graph(name, pos, seed=seed, length=a.length, size=a.size,
                      loras=loras, steps=a.steps, split=a.split)
            outs = run(g, f"{u['id']}_{anim} (pix-w {pw:g} · seed {seed})")
            os.makedirs(dst, exist_ok=True)
            for f in os.listdir(dst):
                os.remove(os.path.join(dst, f))
            for i, f in enumerate(outs):
                shutil.copyfile(f, os.path.join(dst, "f_%04d.png" % i))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
