# tools/blender3d — Blender 3D → 도트 스프라이트 (**테스트용 길**)

> ★★ **이것은 공식 파이프라인이 아니다.** 게임이 쓰는 길은 `tools/sprite/`
> (Wan 2.2 I2V 영상 → 도트 시트, `docs/SPRITE.md`)이고 이 디렉터리는 그것을 **한 줄도
> 안 건드린다.** 여기는 「3D 로 만들면 어떤가」를 캐릭터 한 명으로 0→7단계 끝까지 돌려
> 보고 **무엇이 낫고 무엇이 못한가**를 재려고 지은 자다.

## 0. 왜 이 길을 재 보는가

지금 길이 잘 하는 것과 비싸게 치르는 것이 뚜렷하다(`docs/SPRITE.md`).
잘 하는 것 — 원화 한 장에서 **디자인이 그대로 살아 있는** 동작이 나온다.
비싸게 치르는 것 — 클립 한 장에 21~27초 GPU · 쉰 명에 약 100분 · **씨앗을 눈으로 골라야**
하고(`units.SEED`) 무리마다 LoRA 세기를 실측으로 정해야 하며(`units.PIX_W`),
클립 둘의 크롭 상자를 억지로 맞춰야 하고(`sprite_post`), 루프 이음매를 따로 재야 한다.
그 비용의 뿌리가 하나다 — **영상 모델은 캐릭터를 「기억」하지 못한다.**

3D 는 정반대다. 모델이 곧 캐릭터라 프레임마다 같은 사람이고, 발 높이·루프·방향·
놓는 칸이 **산수로** 정해진다. 대신 **모델을 사람이 만들어야 한다.**
이 테스트는 그 맞바꿈이 이 게임에서 어느 쪽으로 기우는지를 숫자로 보려는 것이다.

## 1. 이 머신에서 확인된 것 (실측)

| 항목 | 결과 |
|---|---|
| Blender | **4.0.2** (우분투 noble arm64 deb 71개를 `dpkg-deb -x` 로 홈에 풀었다 · sudo 불필요 · 362MB) |
| 실행 | `bl` = `$HOME/.local/bin/bl` · prefix `$HOME/.local/opt/blender-root` |
| EEVEE 헤드리스 | ★**된다. DISPLAY 도 Xvfb 도 필요 없다** — 배경 모드에서 EGL 로 GB10 을 직접 잡는다 (`/dev/nvidia0` 이 열린다) |
| 96x96 한 장 | **0.106초** (첫 렌더에만 GPU 컨텍스트 +1.0초 · 프로세스 시작 0.21초) |
| Xvfb 경로 | 된다. 그러나 **2.6배 느리다**(llvmpipe 로 떨어진다). 쓰지 마라 |
| Cycles | CPU 로만 된다. `use_denoising=False` 필수(빌드에 OIDN 이 없다). GPU 는 GB10(sm_121) 커널 컴파일이 죽는다 |
| Shader to RGB | ★EEVEE 에서 **된다**(툰 하드 밴딩). **Cycles 에서는 경고 없이 조용히 무시된다** — 로그로는 못 잡는다 |
| Freestyle | EEVEE·Cycles 둘 다 된다. 다만 **`filter_size=0` 을 무시하고 반투명 픽셀을 되살린다** |
| `filter_size=0` | 반투명 픽셀이 **정확히 0개**가 된다(1.5 일 때 472개). 크로마키가 통째로 필요 없어진다 |
| `dither_intensity=0` | 안 끄면 같은 툰 밴드가 ±1 로 흩어져 고유색이 **24 → 57** 로 는다 |
| `view_transform` | ★**'Standard' 로 두어야 한다.** 기본 AgX 면 넣은 색과 찍히는 색이 다르다 |

## 2. 단계와 파일

| 단계 | 파일 | 하는 일 |
|---|---|---|
| 0 스펙 | `spec.py` | ★**규격 한 곳.** 셀·프레임·방향·카메라·팔레트·경로. 다른 단계는 여기만 본다 |
| 1 캐릭터 디자인 | (Krea 2 Turbo) | 턴어라운드 — `build/b3d/<id>/1_turnaround/` |
| 2·3·4 모델·리그·액션 | `cand_*/build.py` | bpy 로 로우폴리 + 뼈 + 액션 → `.blend` |
| 5 렌더 | `cand_*/render.py` | 직교 툰 렌더 → `5_frames/<동작>/<방향>/*.png` |
| 6 후처리 | `post.py` | **공식 `tools/sprite/pixels.py` 를 그대로 불러** 팔레트 양자화 + 1도트 테두리 |
| 7 패킹 | `pack.py` | 스트립 PNG + `anim.json`(게임 꼴) + `sheet.json`(일반 꼴) + `atlas.png` |
| 검사 | `qc.py` | 공식 품질검사 **8가지 + 새로 넷** |
| 엔진 확인 | `engine_check.py` · `godot/b3d_shot.gd` | Godot 안에서 실제로 돌려 사진으로 남긴다 |
| 보고 | `embed.py` | 결과 그림을 data URI 로 박아 보고서 HTML 을 굽는다 |

`probe_*.py` 와 `smoke/` 는 위 1절을 실측한 탐침이다. 도는 코드이니 참고용으로 남긴다.

## 3. 규격을 왜 그렇게 잡았나 (`spec.py` 머리말이 본체)

* **셀 96x96** — 사용자 스펙의 예시는 64였지만 게임이 96을 읽는다. 64로 뽑으면 결과가
  나쁠 때 그게 파이프라인 탓인지 해상도 탓인지 갈리지 않는다.
* **팔레트 15색이 기본** — 스펙은 「16~32색」이었는데 내렸다. 공식 품질검사 2번이
  「팔레트 이탈 0」을 요구하고 그 팔레트가 15색이라, 24색으로 뽑으면 **설계상 반드시
  실패**한다. 게다가 정지 일러스트 50장이 그 15색의 결이다. (`--palette ext24` 로 24색도 굽는다)
* **8방향** — 게임은 한 방향(좌우 뒤집기)만 쓴다. 그래도 8을 뽑는 까닭은 그것이
  **3D 길에만 있는 이점**이라서다. 공짜로 나오는 것을 안 뽑으면 견주는 뜻이 없다.
* **1m = 40px** — `ORTHO_SCALE 2.40` / 96px. 캐릭터 1.70m 가 68px 이고 위로 28px 이 남아
  검을 치켜들어도 칸 밖으로 안 나간다.

## 4. 게임에 꽂으려면 (계약)

`core/anim.gd` 가 읽는 것은 세 파일뿐이다 — `<name>_idle.png` · `<name>_attack.png` ·
`anim.json`. 지켜야 할 것 중 조용히 틀리는 것들:

* `anim.json` 의 **`name` 이 PNG 파일명 앞머리**다. 틀리면 로그 한 줄 없이 정지 그림으로 되돌아간다.
* 칸 크기는 JSON 이 아니라 **그림 폭 ÷ 칸수**로 잰다 → `width % frames == 0` 이어야 한다.
* `anchor` 는 **idle 0번 칸**의 (발 가로 가운데, 알파 bbox 아래끝).
* `scale = unit_h(tier) / H_body`, `H_body` = 그 idle 0번 칸의 알파 bbox 높이.
  **`roster.json` 의 `sc` 를 넣지 마라** — 엔진이 따로 곱한다.
* `static.h` 는 그 `H_body` 와 **같아야** 한다. 다르면 **총구만** 조용히 어긋나고 `ns_check` 도 못 잡는다.
* `muzzle_at.x` 는 **양수**여야 한다. 음수면 `Balance.art_aim` 이 스프라이트를 통째로 좌우 반전한다
  (지금 `brasa` 가 실제로 그렇다 — `muzzle_at.x = -1`).
* `hit_ms == sum(ms[0:hit_frame])` 정확히(±2ms). `ns_check._check_muzzle` 이 세 파일을 대조한다.

## 5. 돌리는 법

```bash
python3 tools/blender3d/spec.py --unit jokull            # 0단계 — 스펙 + 팔레트 PNG
# 1단계 (선택) — 턴어라운드. ★GPU 는 반드시 gpujob 으로
gpujob run b3d-turn python3 -m krea2 image "<턴어라운드 프롬프트>" --size 1536x512 -n 4 -o …

cd /home/dgxmaruta/pjt/pocker
env -u DISPLAY bl -b --factory-startup --python tools/blender3d/<후보>/build.py  -- --unit jokull
env -u DISPLAY bl -b --factory-startup --python tools/blender3d/<후보>/render.py -- --unit jokull
python3 tools/blender3d/post.py --unit jokull            # 6단계
python3 tools/blender3d/pack.py --unit jokull            # 7단계
python3 tools/blender3d/qc.py   --dir build/b3d/jokull/7_sheet --elem ice
python3 tools/blender3d/engine_check.py --unit jokull    # 엔진 실기 (Xvfb 는 Godot 때문에만 쓴다)
```

★ `art/anim/` 에 **복사하지 마라.** 게임에 실제로 반입하는 것은 사용자가 정할 일이다.
