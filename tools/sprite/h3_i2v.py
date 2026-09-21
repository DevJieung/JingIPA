#!/usr/bin/env python3
"""Step 2-H3 — MiniMax H3(Hailuo 3, 로컬 ComfyUI)로 마스터 한 장에서 동작 클립을 뽑는다.

`wan_i2v.py` 와 **같은 자리**(Step 2)에 서고 **같은 꼴로 내놓는다**:
    build/sprite/<route>/clips<tag>/<id>_<anim>/f_%04d.png
그래서 Step 3(`sprite_post`)부터는 한 줄도 안 바뀐다 — 시트·검사·반입이 그대로다.
두 길을 나란히 두고 보는 것은 `--tag` 로 한다(docs/SPRITE.md 4-3 의 규칙). 기본 꼬리표가
`_h3` 라 Wan 클립(`clips/`)을 덮어쓰는 일이 없다.

Wan 길과 다른 것 다섯:
  1. **모델이 다른 ComfyUI 에 떠 있다** — `~/pjt/h3/` 의 서버(`serve.sh`, 127.0.0.1:8199).
     가중치 43GB 가 상주하므로 여기서는 띄우지 않고 **있는 것에 붙기만** 한다.
     ★ 그래서 `wan_i2v.HOST` 는 8199 를 더 못 쓴다 — 거기 붙으면 Wan 가중치를 모르는
       H3 서버에 Wan 그래프를 던지게 된다(docs/SPRITE.md 4-6 이 8188 에서 겪은 그것).
  2. **픽셀 LoRA 가 없다.** Wan 의 `pix_attack` 은 「melee attack」으로 학습돼 있어 무리마다
     세기를 달리 주고(`units.PIX_W`) 씨앗까지 골라야 칼을 안 쥐었다. H3 는 그 손잡이가
     통째로 없다 — 동작은 **프롬프트의 스토리보드**가 정한다(`prompt_for`).
     프롬프트 꼴은 MiniMax 의 공식 지침(`~/pjt/h3/docs/VIDEO_PROMPT_WRITING_GUIDE_base_en.md`)
     그대로다 — 정렬 지시 한 줄 · 빈 줄 · 세 필드.
  3. **끝 프레임도 못 박는다**(`--pin last`, 기본). 첫 칸과 끝 칸에 같은 마스터를 걸면
     공격이 쉬는 자세로 **되돌아오고** 숨쉬기는 한 바퀴가 닫힌다. Wan 의 FLF 는 같은
     그림을 양끝에 걸면 「가만히 있기」가 나왔는데(docs/PIXELLAB.md 3-2), H3 는 텍스트
     인코더가 Qwen3-VL 32B 라 스토리보드가 그것을 이긴다 — `--pin first` 가 그 대조군이다.
  4. **768x768 · 124칸 · 24fps**(5.17초). 모델의 격자가 「각 축 32의 배수 · 칸 수 17k+5」다.
     512x512 x 33칸이던 Wan 보다 칸이 넉 배라 `sprite_post.pick` 이 고를 자세 극점이 많다.
     ★ 첫 칸은 `_resize(..., "disabled")` 라 **비율을 안 지키고 늘린다** — 입력을 반드시
       캔버스와 같은 정사각으로 만든다(`h3_input`).
  5. **동영상을 안 거친다** — Wan 과 같은 까닭(docs/SPRITE.md 1-1). H3 그래프의 끝을
     `SaveVideo` 가 아니라 `SaveImage` 로 둬서 프레임을 PNG 로 받고, 오디오는 아예 안 푼다.

돌리는 법:
    gpujob fg pd-h3 python3 tools/sprite/h3_i2v.py --route krea --only estoque,limne
    python3 tools/sprite/h3_i2v.py --dry --only estoque          # 프롬프트만 본다
    python3 tools/sprite/sprite_post.py --route krea --tag _h3   # 그다음은 그대로
    python3 tools/sprite/preview.py     --route krea --tag _h3
"""

from __future__ import annotations

import argparse
import json
import mimetypes
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)

import pixels                                    # noqa: E402
import units as U                                # noqa: E402
from make_ref import to_wan_input                # noqa: E402  — 마스터 → 마젠타 캔버스

#: H3 서버. `~/pjt/h3/serve.sh` 가 띄우는 그것이다 — 여기서는 안 띄운다.
HOST = os.environ.get("POCKER_H3", "127.0.0.1:8199")
#: 서버가 결과를 떨구는 자리(`serve.sh --output-directory ./out`). 가져온 뒤 지우는 데만 쓴다.
H3_ROOT = os.environ.get("POCKER_H3_ROOT", os.path.expanduser("~/pjt/h3"))
OUT = os.path.join(ROOT, "build", "sprite")

FPS = 24
DEF_SEED = 7            # `units.SEED` 에 없는 캐릭터가 쓰는 값 (wan_i2v 와 같다)
DEF_SIZE = 768          # 터보 LoRA 이름이 `768p` 다 — 그 크기에서 학습된 것이다
DEF_FRAMES = 124        # 17k+5 · 5.17초. 학습 구간의 아래끝

UNET = "minimax_h3_fl2va_pruned_fp8_scaled.safetensors"
CLIP = "qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors"
VAE = "minimax_h3_video_vae_fp16.safetensors"
TURBO = {4: "minimax_h3_fl2v_turbo_4step_v1.0_768p_comfyui_bf16.safetensors",
         8: "minimax_h3_fl2v_turbo_8step_v1.0_comfyui_bf16.safetensors"}

#: 놓는 순간에 무기 끝에서 한 번 튀는 빛 — **무기에 붙어 있고 날아가지 않는다.**
#: 탄은 게임이 그린다(CLAUDE.md 18-7). 클립 안에서 무엇이 날아가면 공통 크롭 상자가
#: 그만큼 넓어져 사람이 작아지고(docs/SPRITE.md 1-10), 그 탄이 시트에 구워진다.
ELEM_FX = {
    "fire":  "orange flame",
    "ice":   "pale blue frost",
    "elec":  "yellow-violet lightning",
    "water": "teal water",
    "none":  "white light",
}
PROP = {"bow": "bow", "gun": "gun", "sword": "blade", "whip": "chain whip", "deck": "cards"}
ELEM_WORD = {"fire": "fire", "ice": "ice", "elec": "lightning", "water": "water", "none": "card"}


# --------------------------------------------------------------------------
# 프롬프트 — MiniMax 지침의 꼴 그대로 (정렬 지시 · 빈 줄 · 세 필드)
# --------------------------------------------------------------------------
#: ★ 카메라 고정 문단은 사용자가 손으로 돌려 본 프롬프트(`~/pjt/h3/prompts/card_burn.txt`)
#:   에서 그대로 가져왔다 — 그 문단으로 카메라가 실제로 멎었다. 줄이지 마라.
CAMERA = ("The camera holds a completely static shot, locked on a tripod for the entire video - "
          "no zoom, no push in, no pull out, no pan, no tilt, no truck, no pedestal, no arc, "
          "no roll, no handheld drift, no shake and no reframing; the framing, the focal length, "
          "the camera height and the field of view are exactly identical at 0.00 seconds and "
          "at {S} seconds. ")

#: 몸의 규칙 — 이 게임에는 점프도 걷기도 없다. 발이 움직이면 공통 크롭 안에서 캐릭터가
#: 흘러서 칸마다 키가 달라진다(docs/SPRITE.md 1-11).
FEET = ("The feet stay planted on the same invisible ground line at the same spot on the floor "
        "for the entire video; the character never walks, steps, hops, slides, turns around or "
        "travels across the frame, and keeps facing frame right throughout. ")

TAIL = ("Exactly one character is in frame, completely alone, with no second figure and no "
        "duplicate at any time. Nothing else ever enters the frame; no projectile, no arrow, "
        "no bullet, no card and no object separates from the character and flies away; the "
        "background stays a perfectly flat uniform solid magenta with no gradient, no cast "
        "shadow, no ground line and no scenery; and everything that is not described here "
        "stays completely static. No on-screen text, no caption, no subtitle, no watermark, "
        "no logo, no interface element, no letterboxing, no film grain, no vignette, "
        "no lens flare and no motion blur.")

#: 무리마다의 공격 스토리보드. 시각은 5.17초짜리 한 컷 기준이고 `{S}` 가 끝이다.
#: ★★ **이펙트를 「작게」「없이」로 고쳐 적지 마라 — 더 커진다.** 세 판을 돌려 봤다
#:   (docs/SPRITE.md 6-3): v1 「thin crescent」→ 틀 끝까지 닿는 불꽃 호 · v2 「손 크기 이하의
#:   글린트, 입자 없음」→ 같은 호에 불덩이 하나 더 · v3 「plain and unlit, no glow, no crescent,
#:   no sparks, no light of any kind」→ **더 큰 호 + 별 모양 타격 섬광**. 림네도 「no cards leave
#:   the hands」를 더 적었더니 카드가 통째로 터져 나왔다. H3 에는 부정 프롬프트가 없어서(CFG 없음)
#:   금지어 목록이 곧 **그 낱말을 그리라는 말**이 된다. 그래서 글은 **있어야 할 것만** 적고,
#:   이펙트가 큰 캐릭터는 씨앗을 굴려 고른다(`units.SEED` — Wan 에서 칼을 쥔 캐릭터에 한 것과 같다).
#: ★ 반대로 **어디로**를 적은 것은 들었다 — 「엉덩이 옆으로 낮게 당긴다」(v2·v3 둘 다 낮게 당겼다).
#:   그것만 v1 에 더했다.
ATTACK = {
    "aim":   ("From about 0.5 seconds the character raises the {prop} and draws it up to aim "
              "toward frame right, both arms extending forward at shoulder height and the weight "
              "shifting onto the front foot, reaching full draw at about 1.8 seconds. At about "
              "2.0 seconds the shot is released: the {prop} snaps and a brief bright burst of "
              "{fx} flares at the tip of the {prop} for a fraction of a second and fades, staying "
              "attached to the weapon, while the shoulders recoil slightly. From about 2.6 seconds "
              "the character lowers the {prop} and relaxes, "),
    "slash": ("From about 0.5 seconds the character draws the {prop} back low beside the hip, the "
              "tip pointing down and back, never above the shoulders, the torso coiling. At about "
              "1.8 seconds the character cuts forward and across in one clean fast stroke toward "
              "frame right, the weight driving onto the front foot, and a thin bright crescent arc "
              "of {fx} trails the edge of the {prop} for a fraction of a second and fades; the "
              "{prop} stops extended toward frame right at chest height at about 2.2 seconds. "
              "From about 2.8 seconds the character recovers and draws the {prop} back in, "),
    "lash":  ("From about 0.5 seconds the character draws the whip arm back and the {prop} gathers "
              "behind the body. At about 1.8 seconds the character lashes the {prop} out low and "
              "wide toward frame right in one fast swing, the torso turning with it, the {prop} "
              "extending about one body length and cracking at full extension at about 2.2 seconds "
              "with a brief flicker of {fx} along its length that fades at once; then the {prop} "
              "recoils back and hangs coiled again. From about 2.8 seconds the character settles, "),
    "raise": ("From about 0.5 seconds the character sinks slightly at the knees, gathering, then from "
              "about 1.2 seconds lifts both arms up beside the head with the elbows bent and the open "
              "hands at head height, never straight above the head, the sleeves and robes swinging "
              "with the motion; the raised pose is reached at about 2.0 seconds and held, the hands "
              "trembling faintly, until about 3.4 seconds. No cards, no light and no effect leave "
              "the hands. Then the arms come back down, "),
    "cast":  ("From about 0.5 seconds the character draws one arm back, then at about 1.8 seconds "
              "thrusts it forward toward frame right in a casting strike, the weight shifting onto "
              "the front foot, a brief burst of {fx} flaring at the open hand for a fraction of a "
              "second and fading. From about 2.8 seconds the arm comes back, "),
    "throw": ("From about 0.5 seconds the character pulls the throwing arm back, the torso twisting, "
              "then at about 1.8 seconds whips it forward toward frame right in a throwing motion "
              "that stops short, a brief burst of {fx} flaring at the hand for a fraction of a second "
              "and fading; nothing leaves the hand. From about 2.8 seconds the arm comes back, "),
}

IDLE = ("Over the whole take the character only breathes slowly in place: from about 0.4 seconds "
        "the chest and shoulders rise gently through one slow inhale until about 2.6 seconds, the "
        "head lifting a fraction and the hair and loose cloth swaying slightly, then sink back "
        "through one slow exhale. The arms, the {prop} and the hovering cards stay exactly where "
        "they are in <Picture 1> the whole time; nothing is raised, swung, thrown, drawn, loosed "
        "or fired, and no arrow, card, spark or effect appears, ")

SOUND = {
    "idle":   "Quiet room tone with one slow soft breath and a faint rustle of cloth.",
    "attack": ("Quiet room tone with a rustle of cloth as the character moves and one short sharp "
               "snap at the moment of release."),
}


def prompt_for(u: dict, anim: str, *, frames: int, pin_last: bool) -> str:
    """H3 프롬프트 한 덩어리. 지침의 꼴: 정렬 지시 한 줄 · 빈 줄 · 세 필드."""
    S = f"{frames / FPS:.2f}"
    fam = u["family"]
    prop = PROP.get(u["weapon"], "weapon")
    fx = ELEM_FX[u["elem"]]
    if pin_last:
        head = ("How the reference pictures align with the target video — Picture 1 (from Shot 1) "
                "aligns with the 0.00-second mark of the target video; Picture 2 (from Shot 1) "
                f"aligns with the {S}-second mark of the target video.")
        back = ("and by {S} seconds the character has settled back into exactly the pose, position "
                "and framing of <Picture 2>, which is identical to <Picture 1>. ")
    else:
        head = ("For the target video, at 0.00 seconds into the target video, <Picture 1> "
                "(from [Shot 1]) is fully referenced.")
        back = "and by {S} seconds the character has settled back into exactly the pose of <Picture 1>. "

    style = (f"[Shot 1] 2D pixel-art sprite animation, one single continuous {S}-second take from "
             "beginning to end, with no cut, no dissolve, no fade, no wipe and no scene change of "
             "any kind. ")
    # ★ 로스터의 몸통 묘사(`u["prompt"]`)는 **안 넣는다.** 그 줄에는 「loosing three arrows」
    #   「lunging with a rapier」 같은 동작 분사가 박혀 있어서, 첫 시범에서 니브의 **숨쉬기**
    #   클립이 화살 세 대를 쏘았다. 정체성은 <Picture 1> 이 못 박고, 글은 무기와 속성만 말한다.
    subject = (f"A full-body shot frames {u['en']}, the character shown in <Picture 1> - "
               f"a {ELEM_WORD[u['elem']]} fighter who wields a {prop} - standing centred against "
               "a perfectly flat uniform solid magenta background, and the appearance stays exactly "
               "as in <Picture 1> for the whole video: the same face, hair, costume, colours, "
               "weapon and hovering cards, with nothing added and nothing removed. The chunky "
               "visible pixels, the hard aliased pixel edges, the bold dark outlines and the flat "
               "colour fills of <Picture 1> are preserved in every frame at a constant pixel scale, "
               "and the body proportions, the hand size and the foot size never change. ")
    open_ = ("The character begins in exactly the pose of <Picture 1> and holds it for the first "
             "half second. ")
    act = (IDLE if anim == "idle" else ATTACK[fam]).format(prop=prop, fx=fx)
    desc = (style + CAMERA.format(S=S) + subject + FEET + open_ + act + back.format(S=S) + TAIL)
    return (f"{head}\n\n"
            f"integrated_multimodal_description: {desc}\n\n"
            f"overall_soundscape: {SOUND[anim]}\n\n"
            "non_diegetic_music: N/A")


# --------------------------------------------------------------------------
# 입력 — 마젠타 정사각 캔버스. 마스터(도트 96)든 원화든 **캔버스와 같은 크기**로 만든다.
# --------------------------------------------------------------------------
def h3_input(u: dict, route: str, kind: str, canvas: int) -> str:
    """`build/sprite/<route>/h3_in/<id>[_raw].png` 를 만들고 그 경로를 준다.

    master  `wan_in` 과 같은 것을 canvas 크기로 — 도트 마스터를 **정수 배율** nearest 로
            키운다(`make_ref.to_wan_input`). 96px 마스터 x6 = 576px, 캔버스의 70%.
    raw     Krea2 원화(`raw/`) 그대로 — 사용자가 손으로 돌려 본 것이 이쪽에 가깝다
            (1250px 도트 일러스트를 흰 배경째 넣었다). 밝기는 마스터와 같은 자로 올린다
            (`pixels.lift`) — 안 올리면 Step 3 의 양자화에서 마스터보다 어둡게 앉는다.
            ★ 마젠타에 **먼저 얹고** 줄인다. 투명한 채로 줄이면 알파 밖의 색이 가장자리에
              섞여 든다.
    """
    d = os.path.join(OUT, route, "h3_in")
    os.makedirs(d, exist_ok=True)
    if kind == "master":
        src = os.path.join(OUT, route, "master", u["id"] + ".png")
        if not os.path.exists(src):
            raise SystemExit(f"마스터가 없다: {src} (먼저 make_ref → refine)")
        im = to_wan_input(Image.open(src).convert("RGBA"), canvas)
        dst = os.path.join(d, u["id"] + ".png")
    else:
        src = os.path.join(OUT, route, "raw", u["id"] + ".png")
        if not os.path.exists(src):
            raise SystemExit(f"원화가 없다: {src} (먼저 make_ref)")
        raw = pixels.lift(Image.open(src).convert("RGBA"))
        box = raw.getbbox() or (0, 0, raw.width, raw.height)
        raw = raw.crop(box)
        full = Image.new("RGBA", raw.size, pixels.CHROMA + (255,))
        full.alpha_composite(raw)
        room = int(canvas * 0.74)
        s = min(room / raw.width, room / raw.height)
        art = full.convert("RGB").resize((max(1, round(raw.width * s)),
                                          max(1, round(raw.height * s))), Image.LANCZOS)
        im = Image.new("RGB", (canvas, canvas), pixels.CHROMA)
        im.paste(art, ((canvas - art.width) // 2, (canvas - art.height) // 2))
        dst = os.path.join(d, u["id"] + "_raw.png")
    im.save(dst)
    return dst


# --------------------------------------------------------------------------
# ComfyUI 몰이 — 서버가 다른 폴더에 떠 있으므로 파일 경로를 가정하지 않고 HTTP 로만 오간다
# --------------------------------------------------------------------------
def _post(path: str, payload: dict) -> dict:
    req = urllib.request.Request(f"http://{HOST}{path}", data=json.dumps(payload).encode(),
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "replace")[:2000]
        raise SystemExit(f"H3 서버가 {e.code} 로 거절했다:\n{body}") from None


def _get(path: str) -> dict:
    with urllib.request.urlopen(f"http://{HOST}{path}", timeout=120) as r:
        return json.loads(r.read())


def alive() -> bool:
    try:
        _get("/system_stats")
        return True
    except Exception:
        return False


def upload(png: str, name: str, subfolder: str = "pocker") -> str:
    """`/upload/image` — 서버의 input 폴더가 어디든 상관없다. LoadImage 가 쓸 이름을 준다."""
    boundary = uuid.uuid4().hex
    ctype = mimetypes.guess_type(png)[0] or "application/octet-stream"
    blob = open(png, "rb").read()
    body = (f"--{boundary}\r\nContent-Disposition: form-data; name=\"image\"; "
            f"filename=\"{name}\"\r\nContent-Type: {ctype}\r\n\r\n").encode() + blob
    for k, v in (("overwrite", "true"), ("subfolder", subfolder)):
        body += f"\r\n--{boundary}\r\nContent-Disposition: form-data; name=\"{k}\"\r\n\r\n{v}".encode()
    body += f"\r\n--{boundary}--\r\n".encode()
    req = urllib.request.Request(f"http://{HOST}/upload/image", data=body,
                                 headers={"Content-Type": f"multipart/form-data; boundary={boundary}"})
    with urllib.request.urlopen(req, timeout=120) as r:
        info = json.loads(r.read())
    return f"{info['subfolder']}/{info['name']}" if info.get("subfolder") else info["name"]


def graph(image: str, pos: str, *, seed: int, frames: int, size: int, steps: int,
          turbo: int, pin_last: bool, prefix: str) -> dict:
    """`~/pjt/h3/generate.py` 의 fl2va 그래프에서 **끝만** 갈아 끼운 것 — SaveImage 로 PNG.

    ★ 오디오 VAE·VAEDecodeAudio·CreateVideo·SaveVideo 가 없다. 소리는 시트에 안 들어간다.
    """
    g: dict[str, dict] = {
        "unet": {"class_type": "UNETLoader",
                 "inputs": {"unet_name": UNET, "weight_dtype": "default"}},
        "clip": {"class_type": "CLIPLoader",
                 "inputs": {"clip_name": CLIP, "type": "minimax", "device": "default"}},
        "vae": {"class_type": "VAELoader", "inputs": {"vae_name": VAE}},
        "img": {"class_type": "LoadImage", "inputs": {"image": image}},
        "cond": {"class_type": "MiniMaxH3ImageToVideo",
                 "inputs": {"clip": ["clip", 0], "vae": ["vae", 0], "prompt": pos,
                            "width": size, "height": size, "length": frames,
                            "first_frame": ["img", 0],
                            **({"last_frame": ["img", 0]} if pin_last else {})}},
        "noise": {"class_type": "RandomNoise", "inputs": {"noise_seed": seed}},
        "sampler": {"class_type": "KSamplerSelect", "inputs": {"sampler_name": "res_multistep"}},
    }
    model = "unet"
    if turbo:
        g["lora"] = {"class_type": "LoraLoaderModelOnly",
                     "inputs": {"model": [model, 0], "lora_name": TURBO[turbo],
                                "strength_model": 1.0}}
        model = "lora"
    g.update({
        "guider": {"class_type": "BasicGuider",
                   "inputs": {"model": [model, 0], "conditioning": ["cond", 0]}},
        "sigmas": {"class_type": "BasicScheduler",
                   "inputs": {"model": [model, 0], "scheduler": "simple",
                              "steps": steps, "denoise": 1.0}},
        "sample": {"class_type": "SamplerCustomAdvanced",
                   "inputs": {"noise": ["noise", 0], "guider": ["guider", 0],
                              "sampler": ["sampler", 0], "sigmas": ["sigmas", 0],
                              "latent_image": ["cond", 1]}},
        "decode": {"class_type": "VAEDecode", "inputs": {"samples": ["sample", 0], "vae": ["vae", 0]}},
        # ★ 동영상이 아니라 **프레임 PNG** 로 받는다 (머리말 5번)
        "save": {"class_type": "SaveImage",
                 "inputs": {"images": ["decode", 0], "filename_prefix": prefix}},
    })
    return g


def run(g: dict, tag: str, dst: str, timeout: float = 1800.0) -> int:
    """그래프를 던지고 끝날 때까지 기다린 뒤 프레임을 `dst/f_%04d.png` 로 가져온다."""
    cid = str(uuid.uuid4())
    pid = _post("/prompt", {"prompt": g, "client_id": cid})["prompt_id"]
    t0 = time.time()
    while True:
        h = _get(f"/history/{urllib.parse.quote(pid)}")
        if pid in h:
            break
        if time.time() - t0 > timeout:
            raise RuntimeError(f"{tag}: {timeout:.0f}초가 지났다")
        time.sleep(3)
    st = h[pid].get("status", {})
    if st.get("status_str") == "error" or st.get("completed") is False:
        msgs = json.dumps(st.get("messages", []), ensure_ascii=False)[:1500]
        raise RuntimeError(f"{tag}: H3 오류\n{msgs}")
    items = []
    for node in h[pid]["outputs"].values():
        items += node.get("images", [])
    # 이름 끝의 번호가 곧 칸 차례 (SaveImage 는 `<prefix>_00001_.png` 부터 센다)
    items.sort(key=lambda it: it["filename"])
    os.makedirs(dst, exist_ok=True)
    for f in os.listdir(dst):
        os.remove(os.path.join(dst, f))
    for i, it in enumerate(items):
        q = urllib.parse.urlencode({"filename": it["filename"], "subfolder": it.get("subfolder", ""),
                                    "type": it.get("type", "output")})
        with urllib.request.urlopen(f"http://{HOST}/view?{q}", timeout=120) as r:
            open(os.path.join(dst, "f_%04d.png" % i), "wb").write(r.read())
        # 서버 쪽 사본은 지운다 — 백 장이면 4GB 가 남의 폴더에 쌓인다
        p = os.path.join(H3_ROOT, "out", it.get("subfolder", ""), it["filename"])
        if os.path.exists(p):
            os.remove(p)
    print(f"  {tag}: {len(items)}프레임 {time.time() - t0:.0f}초", flush=True)
    return len(items)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--route", default="krea", choices=("sdxl", "krea"))
    ap.add_argument("--only", default="")
    ap.add_argument("--anim", default="", help="idle,attack 중 몇 개만")
    ap.add_argument("--tag", default="_h3", help="클립 폴더의 꼬리표 (기본 _h3 — Wan 것과 안 섞인다)")
    ap.add_argument("--input", default="master", choices=("master", "raw"),
                    help="첫 칸에 거는 그림: 도트 마스터(기본) · Krea2 원화")
    ap.add_argument("--pin", default="last", choices=("last", "first"),
                    help="last = 첫·끝 칸에 같은 그림(기본) · first = 첫 칸만")
    ap.add_argument("--size", type=int, default=DEF_SIZE, help="정사각 캔버스. 32의 배수")
    ap.add_argument("--frames", type=int, default=DEF_FRAMES, help="칸 수. 17k+5 (124 = 5.17초)")
    ap.add_argument("--turbo", type=int, default=4, choices=(0, 4, 8), help="터보 LoRA. 0 = 안 씀(20스텝)")
    ap.add_argument("--steps", type=int, default=0, help="기본: 터보 스텝 수, 터보가 없으면 20")
    ap.add_argument("--seed", type=int, default=DEF_SEED)
    ap.add_argument("--dry", action="store_true", help="프롬프트만 찍고 서버에는 안 붙는다")
    ap.add_argument("--force", action="store_true")
    a = ap.parse_args()

    if a.size % 32:
        raise SystemExit(f"--size {a.size}: 32의 배수여야 한다")
    if a.frames % 17 != 5:
        raise SystemExit(f"--frames {a.frames}: 17k+5 여야 한다 (22 · 39 · 56 · 73 · … · 124)")
    steps = a.steps or (a.turbo or 20)

    ids = [s for s in a.only.split(",") if s] or U.PILOT
    anims = [s for s in a.anim.split(",") if s] or U.ANIMS
    us = U.load(ids)
    pin_last = a.pin == "last"

    if a.dry:
        for u in us:
            for anim in anims:
                print(f"===== {u['id']} {anim} ({u['family']} · {u['elem']}) =====")
                print(prompt_for(u, anim, frames=a.frames, pin_last=pin_last))
                print()
        return 0

    if not alive():
        raise SystemExit(f"H3 서버가 {HOST} 에 없다 — `~/pjt/h3/serve.sh` 를 먼저 띄워라")
    # ★ Krea2·Wan 이 GPU 를 물고 있으면 여기서 멈춘다 (tools/gpu_guard.py). 락도 여기서 잡는다.
    sys.path.insert(0, os.path.join(ROOT, "tools"))
    import gpu_guard
    gpu_guard.claim("h3")
    os.makedirs(OUT, exist_ok=True)
    failed: list[str] = []
    for anim in anims:
        for u in us:
            dst = os.path.join(OUT, a.route, "clips" + a.tag, f"{u['id']}_{anim}")
            if os.path.isdir(dst) and os.listdir(dst) and not a.force:
                print(f"  {u['id']}_{anim}: 있음 — 건너뜀")
                continue
            src = h3_input(u, a.route, a.input, a.size)
            name = upload(src, os.path.basename(src))
            pos = prompt_for(u, anim, frames=a.frames, pin_last=pin_last)
            seed = a.seed if a.seed != DEF_SEED else U.SEED.get(u["id"], a.seed)
            g = graph(name, pos, seed=seed, frames=a.frames, size=a.size, steps=steps,
                      turbo=a.turbo, pin_last=pin_last, prefix=f"pocker_h3/{u['id']}_{anim}")
            tag = f"{u['id']}_{anim} (h3 · {a.input} · pin {a.pin} · seed {seed})"
            t0 = time.time()
            try:
                n = run(g, tag, dst)
            except (RuntimeError, urllib.error.URLError) as e:
                print(f"!! {tag}: {e}", flush=True)
                failed.append(f"{u['id']}_{anim}")
                continue
            json.dump({"model": "MiniMax H3 fl2va fp8", "input": a.input, "pin": a.pin,
                       "size": a.size, "frames": n, "fps": FPS, "steps": steps, "turbo": a.turbo,
                       "seed": seed, "secs": round(time.time() - t0, 1), "prompt": pos},
                      open(os.path.join(dst, "meta.json"), "w", encoding="utf-8"),
                      ensure_ascii=False, indent=1)
    if failed:
        print(f"\n실패 {len(failed)}장: {', '.join(failed)}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
