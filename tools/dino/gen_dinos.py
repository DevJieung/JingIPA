#!/usr/bin/env python3
"""공룡을 찾아라! — 공룡 그림 50종을 로컬 Krea 2 로 생성한다.

이 컴퓨터(DGX Spark GB10)에 설치된 Krea 2 Turbo 를 직접 부른다.
모델 올리는 데만 몇 분 걸리므로 한 번 올려서 전부 이어서 뽑는다.

사용법:
    python3 tools/gen_dinos.py                    # 없는 것만 생성 (종당 약 1분)
    python3 tools/gen_dinos.py --list             # 목록만 보기
    python3 tools/gen_dinos.py --only trex,stego --force   # 특정 공룡만 다시

결과: games/dino/dinos/<이름>.png  (흰 배경을 지운 투명 PNG, 높이 420 이하)
      게임 안에서는 오른쪽을 보는 그림을 좌우 뒤집어 쓴다.
"""

from __future__ import annotations

import argparse
import os
import sys
import time

KREA_ROOT = "/home/dgxmaruta/pjt/krea2"
# tools/dino/ 에 있으므로 저장소 뿌리는 세 번 올라가야 한다.
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "games", "dino", "dinos")

sys.path.insert(0, KREA_ROOT)

# --------------------------------------------------------------------------- #
# 화풍 앵커 — "진짜 공룡을 피규어로 만든 것" 처럼. 종끼리 구별이 잘 되는 게 제일 중요하다.
# (만화체로 뽑으면 다 비슷비슷해져서 아이가 종을 구분하지 못한다)
# --------------------------------------------------------------------------- #
STYLE = ("a realistic collectible dinosaur figurine, hand painted plastic model toy like a "
         "museum quality Schleich figure, matte finish, paleontologically accurate anatomy, "
         "detailed scaly skin texture, rich colors, clean studio product photograph, "
         "soft even lighting, sharp focus, no text")

POSE = (", strict full body side view facing right, standing on its feet, the whole tail "
        "and the whole head inside the frame, centered, cut out on a pure flat white "
        "background, no base, no stand, no ground, no shadow, no scenery, no hands, "
        "no people, no text")

POSE_FLY = (", strict full body side view facing right, wings spread wide, the whole body "
            "inside the frame, centered, cut out on a pure flat white background, no base, "
            "no stand, no sky, no clouds, no ground, no shadow, no scenery, no text")

POSE_SWIM = (", strict full body side view facing right, flippers out as if swimming, the "
             "whole tail and head inside the frame, centered, cut out on a pure flat white "
             "background, no base, no stand, no water, no waves, no ground, no shadow, "
             "no scenery, no text")

ONE = "a single figurine, only one creature in the picture, "


def P(body: str, pose: str = POSE) -> str:
    return f"{ONE}{body}, {STYLE}{pose}"


def PS(body: str, pose: str = POSE) -> str:
    """주인공이 하나뿐임을 한 번 더 못 박는 형태.

    새·익룡처럼 '공룡이 아닌 이름'이 들어가면 모델이 공룡 + 그 동물, 이렇게 **둘**을
    그리는 일이 있다. 그럴 때 쓸 것.
    """
    return (f"a single dinosaur figurine of one {body}, only one creature in the picture, "
            f"nothing else, {STYLE}{pose}")


# --------------------------------------------------------------------------- #
# 공룡 50종
#   id        : 파일 이름 / 게임 안 식별자
#   ko        : 아이에게 보여줄 풀네임
#   h         : 게임 안 키 (px). 화면 1280x720 기준, 기본 150
# --------------------------------------------------------------------------- #
DINOS: list[dict] = [
    dict(id="trex", ko="티라노사우루스", h=168, seed=1101,
         prompt=P("a green Tyrannosaurus rex with a big head, rows of small sharp teeth, "
                  "tiny short arms, thick strong legs and a long thick tail")),
    dict(id="triceratops", ko="트리케라톱스", h=146, seed=1202,
         prompt=P("an orange Triceratops with a wide neck frill, three short blunt horns "
                  "on its face, a parrot-like beak, four sturdy legs")),
    dict(id="stegosaurus", ko="스테고사우루스", h=150, seed=1303,
         prompt=P("a teal Stegosaurus with a row of big cream diamond plates along its "
                  "back, a small head, four legs, long spikes on its tail")),
    dict(id="brachiosaurus", ko="브라키오사우루스", h=178, seed=1404,
         prompt=P("a light green Brachiosaurus with a very long neck reaching up, a tiny "
                  "head, a round body and four thick legs, long tail")),
    dict(id="diplodocus", ko="디플로도쿠스", h=152, seed=5511,
         prompt=P("a blue Diplodocus, its long straight neck stretched forward and low in "
                  "front of the body with a small head at the tip, a separate very long "
                  "thin tail stretched out behind, four thick legs, neck and tail clearly "
                  "apart from the body, not curled, not touching")),
    dict(id="ankylosaurus", ko="안킬로사우루스", h=132, seed=1606,
         prompt=P("a brown Ankylosaurus with an armored back covered in small bony plates, "
                  "a big round club at the end of its tail, short legs, low body")),
    dict(id="parasaurolophus", ko="파라사우롤로푸스", h=160, seed=1707,
         prompt=P("a pink Parasaurolophus with one long tube-shaped crest curving back "
                  "from its head, a duck-like bill, standing on two legs")),
    dict(id="spinosaurus", ko="스피노사우루스", h=170, seed=1808,
         prompt=P("a purple Spinosaurus with a tall rounded sail on its back, a long "
                  "crocodile-like snout, standing on two legs, long tail")),
    dict(id="pteranodon", ko="프테라노돈", h=140, seed=1909,
         prompt=P("a sky blue Pteranodon flying dinosaur with wide spread wings, a long "
                  "pointed crest on the back of its head, a long beak, small legs")),
    dict(id="pachycephalosaurus", ko="파키케팔로사우루스", h=150, seed=6022,
         prompt=P("a yellow Pachycephalosaurus, the top of its skull is a very thick round "
                  "bony dome of the same yellow skin, a ring of small spiky bumps around "
                  "the edge of the dome and along the snout, standing on two legs")),
    dict(id="velociraptor", ko="벨로키랍토르", h=134, seed=2111,
         prompt=P("a small red-brown Velociraptor with soft feathers on its arms and tail, "
                  "a slim snout, standing on two legs, curved claw on each foot")),
    dict(id="dilophosaurus", ko="딜로포사우루스", h=148, seed=2212,
         prompt=P("a mint green Dilophosaurus with two thin round crests on top of its "
                  "head, a slim body, standing on two legs, long tail")),
    dict(id="oviraptor", ko="오비랍토르", h=130, seed=2313,
         prompt=P("a small cream and orange Oviraptor with a short parrot-like beak, a "
                  "small crest on its head, feathery arms, standing on two legs")),
    dict(id="iguanodon", ko="이구아노돈", h=158, seed=6433,
         prompt=P("a sandy beige Iguanodon standing on two strong legs, a wide flat "
                  "duck-like snout, one hand raised in front showing a big pointed cone "
                  "shaped thumb spike, striped back")),
    dict(id="carnotaurus", ko="카르노타우루스", h=162, seed=2515,
         prompt=P("a dark red Carnotaurus with two short bull-like horns above its eyes, "
                  "a deep short snout, very tiny arms, standing on two legs")),
    dict(id="allosaurus", ko="알로사우루스", h=160, seed=2616,
         prompt=P("a golden yellow Allosaurus with small ridges above its eyes, a long "
                  "head, three-fingered hands, standing on two legs, long tail")),

    # ---- 여기부터 2차 (17~50종) ----
    dict(id="giganotosaurus", ko="기가노토사우루스", h=172, seed=3101,
         prompt=P("a rust red Giganotosaurus with a very big head and long jaw, strong "
                  "back legs, tiny arms, long thick tail")),
    dict(id="maiasaura", ko="마이아사우라", h=156, seed=3202,
         prompt=P("a warm tan Maiasaura duck-billed dinosaur with a small bump between "
                  "its eyes and a wide flat bill, standing on four legs")),
    dict(id="ceratosaurus", ko="케라토사우루스", h=158, seed=3303,
         prompt=P("a violet Ceratosaurus with a small round horn on its nose and small "
                  "ridges above its eyes, standing on two legs")),
    dict(id="compsognathus", ko="콤프소그나투스", h=118, seed=7404,
         prompt=P("a tiny lime green Compsognathus, a long thin "
                  "tail, standing on two skinny legs, only one creature in the picture")),
    dict(id="gallimimus", ko="갈리미무스", h=150, seed=3505,
         prompt=P("a sandy Gallimimus shaped like an ostrich, small beaked head "
                  "on a long neck, long slim legs, no teeth")),
    dict(id="deinonychus", ko="데이노니쿠스", h=138, seed=3606,
         prompt=P("an orange Deinonychus raptor with feathered arms and tail and a big "
                  "curved claw on each foot, standing on two legs")),
    dict(id="utahraptor", ko="유타랍토르", h=150, seed=3707,
         prompt=P("a deep red Utahraptor, a large raptor with thick feathered arms and a "
                  "big sickle claw on each foot")),
    dict(id="microraptor", ko="미크로랍토르", h=122, seed=3808,
         prompt=P("a small glossy blue black Microraptor with long feathers on both its "
                  "arms and its legs, four feathered wings, long feathered tail")),
    dict(id="archaeopteryx", ko="시조새", h=124, seed=9109,
         prompt=PS("Archaeopteryx with golden and cream feathers, small clawed feathered "
                   "wings folded at its sides, a long feathered tail, standing on two "
                   "small legs, one creature only, nothing else in the picture")),
    dict(id="quetzalcoatlus", ko="케찰코아틀루스", h=168, seed=4010,
         prompt=P("a pale blue Quetzalcoatlus, a giant pterosaur standing on folded wings "
                  "with a very long beak and a long neck")),
    dict(id="rhamphorhynchus", ko="람포링쿠스", h=126, seed=9111,
         prompt=PS("Rhamphorhynchus pterosaur with tan leathery wings spread wide, a "
                   "pointed beak, a long thin tail with a small diamond flap at the end, "
                   "one creature only, nothing else in the picture", POSE_FLY)),
    dict(id="dimorphodon", ko="디모르포돈", h=130, seed=9212,
         prompt=PS("Dimorphodon pterosaur, a reptile with a tall deep short skull and a "
                   "wide jaw full of small sharp teeth, leathery bat-like wings spread, "
                   "four clawed fingers, a long thin tail, dusty pink and brown scaly "
                   "skin, not a bird, no feathers, no beak", POSE_FLY)),
    dict(id="mosasaurus", ko="모사사우루스", h=120, seed=4313,
         prompt=P("a deep blue Mosasaurus sea reptile with four flippers, a long "
                  "crocodile-like snout and a paddle tail", POSE_SWIM)),
    dict(id="plesiosaurus", ko="플레시오사우루스", h=132, seed=4414,
         prompt=P("a teal Plesiosaurus sea reptile with a long neck, a small head, a "
                  "round body and four big flippers", POSE_SWIM)),
    dict(id="elasmosaurus", ko="엘라스모사우루스", h=140, seed=4515,
         prompt=P("a mint green Elasmosaurus with an extremely long neck curving up, a "
                  "tiny head, a round body and four flippers", POSE_SWIM)),
    dict(id="ichthyosaurus", ko="이크티오사우루스", h=116, seed=4616,
         prompt=P("a silver blue Ichthyosaurus shaped like a dolphin "
                  "with a pointed snout, a back fin and a fish tail", POSE_SWIM)),
    dict(id="dimetrodon", ko="디메트로돈", h=132, seed=4717,
         prompt=P("a rose pink Dimetrodon with a tall wide sail on its back held up by "
                  "thin spines, short legs, walking low")),
    dict(id="apatosaurus", ko="아파토사우루스", h=172, seed=4818,
         prompt=P("a soft blue Apatosaurus with a long thick neck held level, a huge "
                  "round body and a long tapering tail")),
    dict(id="camarasaurus", ko="카마라사우루스", h=166, seed=4919,
         prompt=P("an olive green Camarasaurus with a boxy short snout, a medium long "
                  "neck, a chunky body and four thick legs")),
    dict(id="mamenchisaurus", ko="마멘키사우루스", h=182, seed=5020,
         prompt=P("a yellow green Mamenchisaurus with an extremely long neck stretched "
                  "forward, a tiny head and a long tail")),
    dict(id="argentinosaurus", ko="아르젠티노사우루스", h=184, seed=5121,
         prompt=P("a lavender Argentinosaurus, a giant long-necked dinosaur with a very "
                  "round heavy body and four tree-trunk legs")),
    dict(id="brontosaurus", ko="브론토사우루스", h=176, seed=5222,
         prompt=P("a sea green Brontosaurus with a thick long neck, a very round body "
                  "and a long thin whip tail")),
    dict(id="kentrosaurus", ko="켄트로사우루스", h=142, seed=5323,
         prompt=P("a caramel Kentrosaurus with small plates on its neck and long sharp "
                  "spikes down its back and tail")),
    dict(id="nodosaurus", ko="노도사우루스", h=126, seed=8424,
         prompt=P("a grey brown Nodosaurus, back covered in "
                  "bony plates with spikes along its sides, a plain tail with no club, "
                  "only one creature in the picture")),
    dict(id="protoceratops", ko="프로토케라톱스", h=128, seed=5525,
         prompt=P("a beige Protoceratops, a small four-legged dinosaur with a round neck "
                  "frill and a parrot beak, no horns")),
    dict(id="styracosaurus", ko="스티라코사우루스", h=150, seed=5626,
         prompt=P("a coral Styracosaurus with a big frill ringed by long spikes and one "
                  "long horn on its nose")),
    dict(id="pachyrhinosaurus", ko="파키리노사우루스", h=148, seed=5727,
         prompt=P("a bronze Pachyrhinosaurus with a thick flat bony pad instead of a nose "
                  "horn and a wide frill with small horns")),
    dict(id="torosaurus", ko="토로사우루스", h=152, seed=5828,
         prompt=P("a mustard yellow Torosaurus with a very large long neck frill and two "
                  "long brow horns")),
    dict(id="corythosaurus", ko="코리토사우루스", h=160, seed=5929,
         prompt=P("a periwinkle blue Corythosaurus with a tall round fan-shaped crest on "
                  "its head like a helmet and a duck bill")),
    dict(id="lambeosaurus", ko="람베오사우루스", h=158, seed=6030,
         prompt=P("a magenta Lambeosaurus with a hatchet-shaped crest on its head that "
                  "points forward and a duck bill")),
    dict(id="edmontosaurus", ko="에드몬토사우루스", h=162, seed=6131,
         prompt=P("a sage green Edmontosaurus with a wide flat duck bill and no crest, "
                  "standing on two strong legs")),
    dict(id="therizinosaurus", ko="테리지노사우루스", h=168, seed=6232,
         prompt=P("a lilac Therizinosaurus with a small head on a long neck, a round "
                  "belly, and very long curved claws on its hands")),
    dict(id="ornithomimus", ko="오르니토미무스", h=148, seed=6333,
         prompt=P("a wheat colored Ornithomimus, a slim ostrich-like dinosaur with a "
                  "small beak and feathery arms")),
    dict(id="troodon", ko="트로오돈", h=134, seed=8434,
         prompt=P("a leaf green Troodon, a slim raptor, feathered "
                  "arms and a long tail, only one creature in the picture")),
]


# --------------------------------------------------------------------------- #
# 배경 제거 — 흰 배경에서 바깥쪽만 지운다 (공룡 안쪽 흰색은 남긴다).
# --------------------------------------------------------------------------- #
def cut_out(img, thresh: int = 90, feather: int = 2):
    """흰 배경을 지운다.

    스튜디오 사진처럼 발밑에 옅은 회색 그림자가 깔리면, 단순히 흰색만 지워서는
    그림자가 흰 얼룩으로 남는다. 그래서 먼저 "색이 있거나 어두운" 픽셀을 피규어로
    보고 까맣게 칠해 벽을 세운 뒤, 넉넉한 기준으로 바깥에서 채워 들어온다.
    회색 그림자는 색이 없으니 같이 지워지고, 피규어는 벽에 막혀 살아남는다.
    """
    from PIL import Image, ImageDraw, ImageFilter
    import numpy as np

    rgb = img.convert("RGB")
    w, h = rgb.size
    arr = np.array(rgb).astype("int16")
    sat = arr.max(axis=2) - arr.min(axis=2)
    val = arr.max(axis=2)
    protect = (sat > 22) | (val < 205)      # 색이 있거나 어두우면 피규어

    work = np.array(rgb)
    work[protect] = 0                        # 피규어 자리를 막아 둔다
    wimg = Image.fromarray(work)
    key = (255, 0, 255)
    for xy in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1),
               (w // 2, 0), (w // 2, h - 1), (0, h // 2), (w - 1, h // 2)]:
        try:
            ImageDraw.floodfill(wimg, xy, key, thresh=thresh)
        except Exception:
            pass

    warr = np.array(wimg)
    bg = ((warr[:, :, 0] == key[0]) & (warr[:, :, 1] == key[1]) & (warr[:, :, 2] == key[2]))
    alpha = Image.fromarray(((~bg) * 255).astype("uint8"), mode="L")
    if feather > 0:
        alpha = alpha.filter(ImageFilter.GaussianBlur(feather))
        a = np.array(alpha).astype("float32")
        a = np.clip((a - 110.0) * 3.2 + 128.0, 0, 255)
        alpha = Image.fromarray(a.astype("uint8"), mode="L")

    out = img.convert("RGBA")
    out.putalpha(alpha)
    bbox = out.getbbox()
    if bbox:
        pad = 6
        bbox = (max(0, bbox[0] - pad), max(0, bbox[1] - pad),
                min(w, bbox[2] + pad), min(h, bbox[3] + pad))
        out = out.crop(bbox)
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="", help="이름에 이 문자열이 들어간 것만 (쉼표로 여러 개)")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--force", action="store_true", help="이미 있어도 다시 생성")
    ap.add_argument("--max-h", type=int, default=420, help="저장할 그림의 최대 높이")
    args = ap.parse_args()

    pats = [p.strip() for p in args.only.split(",") if p.strip()]
    jobs = [d for d in DINOS if not pats or any(p in d["id"] for p in pats)]
    if args.list:
        for d in jobs:
            print(f"  {d['id']:<20} {d['ko']:<12} 키 {d['h']}px")
        print(f"\n총 {len(jobs)}종")
        return 0

    os.makedirs(OUT, exist_ok=True)
    todo = [d for d in jobs
            if args.force or not os.path.exists(os.path.join(OUT, d["id"] + ".png"))]
    if not todo:
        print("모두 이미 있습니다. 다시 만들려면 --force")
        return 0

    from krea2.pipelines.image import Krea2ImagePipeline
    from PIL import Image

    print(f"[dino] {len(todo)}종 생성 시작 — 모델을 한 번만 올립니다", flush=True)
    t0 = time.time()
    pipe = Krea2ImagePipeline("turbo").load()
    print(f"[dino] 모델 준비 완료 ({time.time() - t0:.0f}초)", flush=True)

    for i, d in enumerate(todo, 1):
        t1 = time.time()
        path = os.path.join(OUT, d["id"] + ".png")
        res = pipe.generate(d["prompt"], width=1024, height=1024, seed=d["seed"])[0]
        img = cut_out(res.image)
        if img.size[1] > args.max_h:
            w2 = max(1, int(img.size[0] * args.max_h / img.size[1]))
            img = img.resize((w2, args.max_h), Image.LANCZOS)
        img.save(path, optimize=True)
        print(f"[dino] ({i}/{len(todo)}) {d['id']:<20} {img.size[0]}x{img.size[1]} "
              f"{os.path.getsize(path) / 1024:.0f}KB  {time.time() - t1:.0f}초", flush=True)

    print(f"[dino] 완료 — 총 {time.time() - t0:.0f}초, {OUT}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
