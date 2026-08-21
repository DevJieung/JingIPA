# CLAUDE.md — 이 저장소에서 작업할 때

**포커 디펜스** — 트럼프 다섯 장으로 영웅을 뽑아 몬스터를 막는 디펜스. Godot 4.7.1, 안드로이드.

한 탄의 흐름은 이렇다:

1. **카드 다섯 장을 받는다.** 맘에 안 드는 카드는 **한 번 공짜로** 다시 뽑을 수 있고,
   이미 바꾼 카드는 **골드를 내야** 또 바꿀 수 있다 (15 → 30 → 60 … 두 배씩).
2. **결정하면 족보를 판정**하고, 그 등급의 캐릭터 중 **하나가 무작위로** 나와 투기장에 선다.
   원페어면 원페어급 넷 중 하나, 로열이면 로열급 둘 중 하나.
3. **몬스터가 바깥에서 나타나 빙글빙글 돌면서 안쪽으로 조여 온다.** 영웅들이 자동으로 쏜다.
4. **제한 시간이 끝나면 남아 있는 마릿수만큼 목숨이 깎인다.** 한 마리 잡을 때마다 골드.
5. **상점**에서 골드로 전체 능력치를 올리거나, 패시브를 사거나, 공짜 리롤을 늘린다.
6. 40탄까지. 목숨이 0 이 되면 끝.

**풀하우스 이상**(풀하우스 · 포카드 · 스트레이트 플러시 · 로열)이 나오면 연출이 화려해진다 —
섬광 · 빛살 · 고리 · 카드가 깨져 흩어짐 · 화면 흔들림. 등급이 높을수록 전부 세진다.

갈무리 절차는 [`WRAPUP.md`](WRAPUP.md). 전체 설명은 [`README.md`](README.md).

---

## 뼈대

```
core/
  poker.gd     ★순수. 카드 52장과 족보 판정. 화면도 저장도 모른다.
  balance.gd   ★순수. 게임의 숫자가 전부 여기 있다 (투기장·등급·상점·탄 편성).
  roster.gd    ★자동 생성. 캐릭터 36명 · 몬스터 14종 표. 손으로 고치지 마라.
  look.gd      색 · 글꼴 · 카드와 무늬 그리기
  art.gd       그림 캐시. 그림이 없으면 색 도형으로 대신 그린다.
  ui.gd        그리면서 동시에 누를 자리를 등록하는 아주 작은 버튼 도우미
  save.gd      (오토로드 Save) 저장 파일 하나
  run.gd       (오토로드 Run) 한 판의 상태 전부 — 목숨·골드·영웅·카드·상점
game/
  main.gd          화면 갈아 끼우기. 게임의 진행 순서가 여기 한 줄로 보인다.
  title_screen.gd  타이틀
  draw_screen.gd   카드 다섯 장 고르기 + 족보 확정 연출 ★화려한 곳
  battle_sim.gd    ★전투 계산. **그리기를 전혀 모른다.**
  battle_screen.gd 전투 그리기 (BattleSim 을 하나 들고 그린다)
  shop_screen.gd   상점
  over_screen.gd   끝
  fx.gd            이펙트 (뒤 layer / 앞 layer 로 나뉜다)
tools/
  roster.json      ★캐릭터·몬스터의 원본. 여기만 고친다.
  gen_art.py       로컬 Krea 2 Turbo 로 도트 그림 58장
  gen_roster.py    roster.json → core/roster.gd
  screenshot.py    Xvfb 로 실제 화면 촬영
  check_font.py    폰트에 없는 글자 찾기
  verify.sh        검증 한 곳
tests/
  poker_check      족보 전수 검사 (2,598,960판)
  ns_check         표끼리 어긋나지 않는가 (이름·등급·사거리·투기장·그림)
  play_check       화면을 실제로 눌러서 한 바퀴
  balance_check    자동 플레이로 40탄까지 (policy.gd 가 "기준 실력")
  shot             촬영 전용 진입점 (★커맨드라인을 읽는 곳은 여기뿐)
```

---

## 작업을 마칠 때 (매번, 빠짐없이)

```bash
tools/verify.sh          # 전부 (약 3분)
tools/verify.sh quick    # 빠르게 (약 1분)
```

그리고 **화면을 고쳤으면 사진을 새로 찍고 눈으로 봐라**, **APK 를 새로 굽고 어디에
만들어졌는지 답변에 적어라.** 자세한 것은 [`WRAPUP.md`](WRAPUP.md).

---

## 절대 깨면 안 되는 것

### 판정과 표

1. **`core/poker.gd` 는 순수 함수만 둔다.** 화면·저장·난수를 넣지 마라.
   전수 검사(2,598,960판)가 이 파일 하나에 기대고 있다.
2. **A 는 스트레이트의 양쪽 끝에 다 선다.** A-2-3-4-5(휠)와 10-J-Q-K-A 둘 다 스트레이트다.
   이걸 빼먹는 것이 족보 판정에서 제일 흔한 실수다.
3. **`Poker.Hand` 의 숫자를 바꾸지 마라.** 그 값이 곧 캐릭터 등급 인덱스이고
   저장 파일에도 그 숫자가 들어간다.
4. **`core/roster.gd` 는 자동 생성이다.** 원본은 `tools/roster.json`.
   `verify.sh` 1번이 둘이 어긋나면 잡는다.
5. **캐릭터 id 는 게임 전체에서 유일해야 한다.** 겹치면 그림 파일이 조용히 덮어써진다.
   실제로 `bolt_ranger` 가 투페어와 트리플에 둘 다 있었다 (`ns_check` 가 잡는다).

### 그리기

6. **`♠ ♦ ♣` 를 글자로 그리지 마라.** 번들 폰트에 없다. `Look.draw_suit()` 이 도형으로 그린다.
   `×`(U+00D7) 도 없다 — "2배" 처럼 한글로 써라. (`tools/check_font.py`)
7. **버튼은 그리면서 동시에 `Ui` 에 등록한다.** 그리기와 누를 자리를 따로 적으면
   "버튼은 옮겼는데 눌리는 자리는 그대로"인 버그가 반드시 생긴다.
8. **빛살·고리는 `Fx.draw_back()`, 나머지는 `Fx.draw()`.** 전부 앞에 그리면
   로열 연출에서 빛살이 족보 이름을 덮어 무슨 족보인지 안 보인다. 실제로 그랬다.
9. **연출은 언제든 탭으로 넘길 수 있어야 한다.** 40탄을 도는 게임에서 못 넘기는 연출은 고문이다.
10. **도형이 0 으로 줄어들 때 `draw_colored_polygon` 을 부르지 마라.** 점이 한 곳에 뭉쳐
    `triangulation failed` 오류가 프레임마다 쏟아진다. 안 보일 만큼 작으면 건너뛴다.

### 전투와 숫자

11. **`BattleSim` 은 그리기를 모른다.** 이 머신에는 화면이 없어서, 시뮬레이터가 따로 있어야
    헤드리스로 40탄을 수백 번 돌려 볼 수 있다. 화면에 붙일 것은 `events` 배열로 흘린다.
12. **몬스터 좌표는 한 걸음에 한 번만 계산한다**(`_cache_positions`). 사거리를 잴 때마다
    cos/sin 을 다시 돌리면 영웅 40 × 몬스터 60 = 한 프레임에 2,400번이고,
    자동 플레이 검사가 몇 분씩 걸린다.
13. **몬스터가 죽어 배열이 당겨지면 탄이 들고 있는 목표 번호도 같이 고쳐야 한다**(`_reap`).
    안 그러면 탄이 엉뚱한 놈을 쫓아가고 마지막 한 마리가 안 잡힌다.
14. **가장 짧은 사거리는 `INNER_R` 보다 길어야 한다.** 아니면 가운데 선 영웅이
    **아무도 못 때린다.** `ns_check` 가 이걸 지킨다.
15. **둔화는 곱하지 말고 센 쪽으로 덮어쓴다.** 곱하면 둘만 겹쳐도 몬스터가 멈춘다.
16. **밸런스 숫자를 감으로 고치지 마라.** `tests/balance_check` 를 돌려라. 기대값은
    중간값 35~39탄, 12판 중 2~4판 클리어, **1~6탄은 목숨을 잃지 않음**.
17. **`Run.total_dps()` 는 단일 대상 기준이다.** 광역·연쇄·장판이 여럿을 동시에 때리는
    몫은 안 들어 있다. 어림수로만 써라.

### 도구

18. **커맨드라인은 `tests/` 만 읽는다.** 게임 코드가 인자를 읽으면 촬영 도구와 검사기가
    서로의 인자를 삼키고 `get_tree().quit()` 이 촬영 도중 앱을 죽인다.
19. **검사에는 반드시 `timeout` 과 `stdbuf -oL`.** 멈춤은 조용한 대기가 아니라 실패다.
20. **`POCKER_NO_SAVE=1`** 로 검사를 돌린다. 안 그러면 검사가 만든 값이 "내 기록"이 된다.

---

## 자주 쓰는 명령

```bash
~/.local/bin/godot -e --path .                                   # 편집기
~/.local/bin/godot --headless --path . --import                  # 임포트만 (새 PNG 를 넣은 뒤)
~/.local/bin/godot --headless --path . --quit-after 200          # 부팅 확인

tools/verify.sh                                                  # 검증 전부
tools/verify.sh quick

POCKER_NO_SAVE=1 stdbuf -oL ~/.local/bin/godot --headless --path . res://tests/poker_check.tscn
POCKER_NO_SAVE=1 stdbuf -oL ~/.local/bin/godot --headless --path . res://tests/ns_check.tscn -- --strict
POCKER_NO_SAVE=1 stdbuf -oL ~/.local/bin/godot --headless --path . res://tests/play_check.tscn
POCKER_NO_SAVE=1 stdbuf -oL ~/.local/bin/godot --headless --path . res://tests/balance_check.tscn -- --runs 12 --verbose

python3 tools/screenshot.py                       # 기본 아홉 장
python3 tools/screenshot.py reveal:9 battle:14    # 로열 연출 · 14탄 전투
python3 tools/gen_art.py --list                   # 그림 58장 목록
python3 tools/gen_art.py --only 용기사 --force
python3 tools/gen_roster.py                       # roster.json → core/roster.gd
python3 tools/check_font.py

mkdir -p build/android && ~/.local/bin/godot --headless --path . \
    --export-debug "Android Test APK" "$PWD/build/android/pokerdefense-test.apk"
```

---

## 이 머신(aarch64, 화면 없음)에서 알아둘 것

- **화면이 없다.** `tools/screenshot.py` 가 Xvfb 를 띄워 소프트웨어 OpenGL 로 실제로 그린다.
  느리다 — 전투 한 장에 1~2분. 여러 장을 한 번에 넘기면 Godot 을 한 번만 띄운다.
- **그림은 로컬 Krea 2 Turbo(`/home/dgxmaruta/pjt/krea2`)로 만든다.** 모델 올리는 데 3~4분,
  한 장에 65초. 58장이면 약 65분이다.
- **APK 는 `use_gradle_build=false` 라서 만들어진다.** x86_64 전용인 `aapt2` 를 안 탄다.
  스토어용 **AAB 는 이 머신에서 안 된다.** iOS 는 Xcode 프로젝트까지만.
- **`import_etc2_astc=true` 를 지우지 마라.** 없으면 x86_64 러너에서 오류 메시지도 없이
  익스포트가 거부된다.
- `pkill -f "..."` 는 **그 문자열이 지금 셸의 명령줄에도 있으면 셸 자신을 죽인다.**
  PID 를 먼저 찾아 `kill` 하라.

---

## 코드 스타일

- 들여쓰기는 **탭**. 주석과 사용자 문구는 **한국어**.
- `class_name` 은 PascalCase, 파일명은 snake_case.
- 공개 함수에는 `##` 문서 주석. **왜** 그렇게 했는지가 중요한 곳에는 근거를 남겨라 —
  특히 나중에 "최적화"하다가 되돌리기 쉬운 것들(위의 8·12·13·15번이 전부 그런 것이다).
