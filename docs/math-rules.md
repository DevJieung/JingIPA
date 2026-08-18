# 개구리 용사 — 설계 규칙 (합치기 전의 CLAUDE.md)

> **이 문서는 합치기 전 `mathgame` 저장소의 CLAUDE.md 다.**
> **21개 규칙은 여전히 전부 유효하다** — 고치기 전에 반드시 읽을 것.
> 다만 아래는 통합하면서 바뀌었으니 같이 기억할 것:
>
> | 이 문서에 적힌 것 | 지금은 |
> |---|---|
> | `src/core`, `src/game`, `src/ui`, `src/autoload` | `games/frog/core`, `game`, `ui`, `autoload` |
> | `assets/fonts/Jua-Regular.ttf` | `core/fonts/Jua-Regular.ttf` |
> | `assets/art/`, `assets/audio/` | `games/frog/art/`, `games/frog/audio/` |
> | 오토로드 `Game` | `FrogGame` (오토로드 `Game` 은 씬 루트를 조용히 개명시킨다) |
> | 저장 `user://save.json` | `Shell` 이 소유하는 `user://rogame_save.json` 의 프로필별 칸 |
> | **규칙 1의 전제** "gl_compatibility 라 MSAA 가 없다" | 통합 project.godot 에 `msaa_2d=2` 가 있다. **규칙 자체(`DrawUtil.fill_aa` 로만 채우기)는 유지**하고 주석만 고칠 것 |
> | 별 판정 (오답 0/≤2/그 외) | 문항 수 비례로 완화. 더 엄격해진 항목은 없다 |
> | 타이틀의 "설명 건너뛰기"·"언어" 버튼 | 없앴다 (프로필별 값이라 부모 화면에서만) |
> | `begin_session()` 을 타이틀이 호출 | `Shell` 이 앱 부팅에서 한 번만 (허브 왕복으로 상한이 사라지던 문제) |
>
> 전체 설명은 저장소 뿌리의 [`../CLAUDE.md`](../CLAUDE.md) 와
> [`architecture.md`](architecture.md).

---

**개구리 용사** — 초등 1~2학년(만 7~8세)용 사칙연산 게임. Godot 4.7.1, 안드로이드/iOS.
전체 설명은 [`README.md`](README.md), 설계 근거는 [`docs/architecture.md`](docs/architecture.md).

## 자주 쓰는 명령

```bash
~/.local/bin/godot --path .                                   # 게임 실행
~/.local/bin/godot -e --path .                                # 편집기
~/.local/bin/godot --headless --path . --import               # 임포트만
~/.local/bin/godot --headless --path . res://tests/test_runner.tscn   # 전체 검증 (약 3~5분)
python3 tools/gen_audio.py                                    # 사운드 재생성
python3 tools/gen_icons.py                                    # 아이콘/스플래시 재생성
python3 tools/check_font.py                                   # 한글 글리프 누락 검사
python3 tools/gen_art.py                                      # Krea 2 로 그림 재생성 (GPU, ~20분)
python3 tools/make_zip.py                                     # 내려받을 프로젝트 zip (-> ~/frogwarrior.zip)
python3 tools/setup_android_arm64.py --check                  # APK 빌드 도구 상태 (없으면 --check 빼고 한 번)
python3 tools/screenshot.py map:0 battle:8                     # 화면을 PNG 로 (-> build/shots/)
python3 tools/screenshot.py --portrait map:1                   # 세로 화면으로
mkdir -p build/android && ~/.local/bin/godot --headless --path . \
    --export-debug "Android Test APK" "$PWD/build/android/frogwarrior-test.apk"   # 테스트 APK
```

**이 머신(aarch64)에서도 테스트 APK 는 만들어집니다.** `use_gradle_build=false` 라
미리 구운 템플릿에 프로젝트만 밀어 넣고 `zipalign`/`apksigner` 만 돌리므로 x86_64 전용인
`aapt2` 를 안 씁니다. **AAB(스토어용)만** 여전히 Mac 이 필요합니다 — 자세한 건
[`docs/build-android.md`](docs/build-android.md) 0장.

## 작업을 마칠 때 (매번, 빠짐없이)

**프로젝트 zip 과 안드로이드 테스트 APK 를 **둘 다** 새로 만들고, 내려받는 방법까지 알려주세요.**
고친 걸 폰에서 바로 눌러 볼 수 있어야 합니다 — zip 만 주면 사용자가 직접 빌드해야 합니다.

```bash
python3 tools/make_zip.py                                     # -> ~/frogwarrior.zip
mkdir -p build/android && ~/.local/bin/godot --headless --path . \
    --export-debug "Android Test APK" "$PWD/build/android/frogwarrior-test.apk"
cp build/android/frogwarrior-test.apk ~/frogwarrior-test.apk  # -> ~/frogwarrior-test.apk
```

그리고 답변 끝에 이 두 줄을 그대로 알려주세요:

```bash
scp dgxmaruta@<호스트>:~/frogwarrior.zip .
scp dgxmaruta@<호스트>:~/frogwarrior-test.apk .    # adb install -r frogwarrior-test.apk
```

- **APK 익스포트가 실패하면** `python3 tools/setup_android_arm64.py` 를 한 번 돌리세요
  (도구가 없거나 편집기 설정이 비었을 때). 그래도 안 되면 zip 만이라도 만들고 **왜 APK 가
  안 나왔는지 말해 주세요** — 조용히 건너뛰지 마세요.
- 익스포트 끝의 `cannot connect to daemon at tcp:5037` 은 폰이 안 붙어 있어서 나는 것이라 오류가 아닙니다.
- zip 의 제외 목록을 손으로 쓰지 마세요 — `.godot/`(서명 비밀번호)과 `.certs/`(개인 키)가
  같이 나가면 키를 새로 만들어야 합니다. 스크립트가 묶은 뒤 한 번 더 훑어서 걸리면 zip 을 아예 안 만듭니다.
- 화면에 보이는 걸 고쳤다면 웹 빌드도 같이 갱신하세요 (아래).

**이 머신은 화면이 없는 SSH 전용 서버입니다.** `godot --path .` 로 창을 띄울 수 없습니다
(`Unable to create DisplayServer`).

**그래도 화면은 볼 수 있습니다 — `python3 tools/screenshot.py` 를 쓰세요.**
가상 프레임버퍼(Xvfb)를 띄워 실제로 그린 뒤 PNG 로 떨굽니다 (처음 한 번은 자동으로 받아 풉니다, sudo 불필요).
**화면 배치를 고쳤으면 반드시 한 번 찍어서 눈으로 확인하세요** — 무언가가 가려지거나
겹치는 문제는 테스트로 안 잡힙니다 (실제로 "세로 화면에서 배경이 지도를 통째로 덮는"
버그를 이걸로 찾았습니다).

아이가 직접 만져 볼 때는 웹으로 빌드해 브라우저로 접속하세요:

```bash
mkdir -p build/web
godot --headless --path . --export-release "Web" "$PWD/build/web/index.html"
python3 tools/serve_web.py     # http://<tailscale-ip>:8060/
```

`--check-only --script <파일>` 은 오토로드(`Game`, `Audio`, `Router`)를 못 찾아
`Identifier not found: Game` 을 냅니다. **이건 진짜 오류가 아닙니다.** 실제 검증은 위 test_runner 로 하세요.

## 절대 깨면 안 되는 규칙

1. **채워진 도형은 `DrawUtil.fill_aa()` 로만 그린다.**
   `gl_compatibility` 렌더러라 MSAA가 없고, `draw_colored_polygon()` 에는 `antialiased` 인자가 없습니다.
   직접 호출하면 계단 현상이 그대로 보입니다. 원은 `DrawUtil.circle_aa()`.
2. **타이머·카운트다운·재촉 연출을 넣지 않는다.** 이 나이대 수학 불안의 주 원인입니다.
3. **오답 시 보기를 제거하거나 재배치하지 않는다.** 제거는 찍기를 학습시키고,
   재배치는 "계산 다시 하기"를 "위치 다시 찾기"로 바꿉니다.
   그리고 **목숨(하트)·시도 제한·게임 오버를 다시 넣지 않는다.**
4. **보상(개구리 공격)은 반드시 블록 시연 뒤에 온다.** 앞에 두면 보상이 '탭'에 연합됩니다.
   그리고 **결과를 다시 세지 않는다** — 쏟는 동안 이미 숫자가 올라갔으므로 또 세면 헷갈립니다.
   **다시 보기(새로고침) 버튼도 두지 않습니다.**
5. **곱셈 `a × b` 는 "a씩 b묶음"** — a가 한 묶음의 크기입니다 (한국 교과서 표기).
   화면은 b행 × a열. 영어권의 "a groups of b" 로 바꾸면 아이 교과서와 반대가 됩니다.
6. **문제에는 한글이 한 어절도 들어가지 않는다.** 숫자와 기호만.
   그리고 **화면에 나가는 글자는 반드시 `Loc.t("키")` 로 꺼낸다** — 코드에 직접 박으면
   영어 모드에서 한글이 그대로 나옵니다. 새 문자열은 `src/core/loc.gd` 에 ko/en 둘 다 채우세요
   (테스트 [9]가 빠진 언어와 서식 개수 불일치를 잡습니다).
7. **답 버튼은 200×200 디자인 px 이상, 간격 36 이상.** 상호작용은 단일 탭만
   (드래그·스와이프·더블탭 금지). 답 판은 **2×2 고정**입니다 — 1×4 나 4×1 로 바꾸면
   손가락이 큰 아이가 옆 보기를 누릅니다.
8. **`*.uid` 와 `*.import` 를 gitignore 하지 않는다.** Godot 4.4+ 가 리소스 참조에 씁니다.
9. **`.godot/` 는 커밋하지 않는다.** 서명 비밀번호가 담긴 `export_credentials.cfg` 가 그 안에 있습니다.
10. **덧셈·뺄셈은 20을 넘지 않는다** (최대 10 + 10). 합산판이 20칸 고정이라 이걸 어기면 표현이 깨집니다.
11. **격자 칸 수를 문제에 따라 바꾸지 않는다.** 항 격자 10칸, 합산판 20칸 고정.
12. **그림이 없어도 돌아가야 한다.** `Art.has()` 로 확인하고 없으면 코드 드로잉으로 대체하세요
    (헤드리스 테스트는 그림 없이도 돕니다).
13. **화면 배치는 가로/세로 두 가지뿐이고, 판정은 `Layout.is_wide()` 한 곳에서만 한다.**
    기준 해상도는 **가로 태블릿 1280×800** (`project.godot` 의 viewport = `Layout.BASE`).
    각 화면이 저마다 `size.x > size.y` 같은 기준을 들면 4:3 태블릿처럼 애매한 비율에서
    화면마다 배치가 갈립니다. 그리고 가로에서 **왼쪽이 '보는 곳'(문제·블록),
    오른쪽이 '고르는 곳'(답)** 입니다 — 읽는 방향과 같아야 아이가 순서를 따로 배우지
    않습니다. 좌우를 뒤집지 마세요.
14. **초록은 뜻이 하나다 — "내가 찾아야 할 것".** `?` 가 나타나는 격자만 초록입니다
    (`_draw_answer_frame`). `a + b = ?` 면 합산판이, `a + □ = b` 면 □ 항 격자가 초록이고,
    **이미 아는 수가 놓이는 격자는 절대 초록이 아닙니다.** 보기 버튼·카드의 물음표 상자와
    같은 색이라, 아이가 "저 초록을 채우면 된다"를 화면마다 다시 배우지 않습니다.
15. **캐릭터 크기는 `_bg.size.y` 가 아니라 `_character_room()` 으로 잡는다.**
    배경 띠 위쪽을 HUD 가 덮고 있어서, 띠 높이로 크기를 잡으면 특히 보스
    (`Snake.BOSS_SCALE` 1.7배)의 얼굴과 왕관이 화면 밖으로 나갑니다. 그리고 크기는
    `_place_characters()` 에서 **매 배치마다 다시** 줘야 합니다 — `_ready()` 의 첫 배치
    때는 자기 size 가 0이라 그때 정한 크기가 실제 화면과 안 맞습니다.
    (테스트 [7]이 "뱀·개구리 머리가 HUD 아래에 있는가"를 지킵니다.)
16. **10이 찰 때 묶는 연출을 넣지 않는다.** 예전에는 합산판 앞 10칸이 차는 순간 금색으로
    잠그고 "10" 배지를 붙였다가 뺄 때 다시 푸는 장면이 있었습니다. 설명은 옳았지만
    한 문제마다 2초 가까이 잡아먹어 **기다리는 시간이 계산하는 시간보다 길어져서** 걷어냈습니다.
    자릿값은 십틀 두 개(5칸씩 두 줄)의 모양으로 충분합니다 — 앞 틀이 차고 뒤 틀로 넘어가는
    것이 곧 받아올림입니다. 테스트 [4]가 `bundle`/`borrow` 장면이 되살아나면 실패시킵니다.
17. **격자와 연산 기호는 답을 고르기 전부터 깔려 있다 — `=` 도 포함.**
    아래 그림이 위의 식과 같은 모양이어야 아이가 둘을 잇습니다:
    위 줄이 `[격자] + [격자]`, 아래 줄이 `= [합산판]` — 식을 두 줄로 옮겨 적은 그림입니다.
    등호는 합산판 바로 왼쪽에 있고(`BlockStage._eq_center`, 자리 폭은 `EQ_GAP`),
    `= [합산판]` 이 **한 덩어리로** 가운데에 놓입니다. 곱셈(배열 표시)은 합산판이 없어
    등호도 그리지 않습니다. 기호를 시연 도중에 등장시키지 마세요 — 정작 답을 고르는
    순간의 화면에서 무슨 계산인지가 사라집니다. (테스트 [8]이 등호 유무와 가운데 정렬을 지킵니다.)
18. **뱀은 뒤 월드로 갈수록 세 보이되, 진짜 무섭게는 만들지 않는다.**
    색·굵기·뿔·등가시·눈썹이 `Snake.WORLD_LOOK` 한 곳에서 함께 올라갑니다.
    피·사실적인 송곳니·붉게 빛나는 눈·해골은 금지 — 눈은 끝까지 크고 동그랗게 둡니다.
19. **빈칸 문제(`a + □ = b`)는 격자를 셋 다 깐다** — `a` 격자, `□` 격자(초록·아래에 `?`),
    합산판. 그리고 답을 고른 뒤에는 **`□` 격자와 합산판이 같은 순간에 한 칸씩 움직인다**
    (`_fill_blank_coupled()`, 한 트윈 안에서). 따로 움직이면 아이가 '다음 단계'로 읽지
    '같은 사건'으로 읽지 않습니다. 이 대응이 이 문제 유형이 가르치는 전부입니다.
20. **개구리 혀는 화면과 나란히(수평으로) 나간다.** 뱀 노드의 원점은 **발밑**이라
    `snake.position` 을 그대로 겨누면 혀가 땅으로 처져 "뱀이 아니라 땅을 핥는" 그림이 됩니다.
    `_tongue_points()` 는 x 만 목표를 따라가고 높이는 입높이로 고정하며, 공격 중 몸이
    앞으로 기울므로(tilt) **몸 변형의 역행렬을 태워** 화면 기준으로 수평을 맞춥니다.
    먹는 연출에서 뱀이 순간이동하지 않도록, 물릴 때의 높이 차이는 끌려오는 동안
    서서히 줄입니다 (`swallow()` 의 `y_off`). 테스트 [7b]가 자세 세 가지에서 이걸 지킵니다.
21. **상단 진행 칩은 마지막 칸까지 다 찬 뒤에 탄이 끝난다.** 칩의 '차오름'과 '통통 튐'은
    **서로 다른 트윈**이어야 합니다 — 한 문제를 풀 때마다 `set_progress()` 와
    `pulse_progress()` 가 같은 프레임에 불리는데, 다 풀었을 때는 둘이 **같은 칩**을
    가리킵니다. 하나로 묶으면 강조가 차오름을 죽여서 마지막 칸이 영영 안 찬 채로
    결과 판이 덮습니다 (아이 눈에는 "다 잡았는데 한 마리 남았다"). 마무리 직전에는
    `Hud.progress_settled()` 로 한 번 더 기다립니다. 테스트 [5b]/[5c]가 지킵니다.

## Godot 4.7 함정 (여기서 이미 물린 것들)

- 엔진 기본 폰트에 **한글 글리프가 없습니다.** `gui/theme/custom_font` 로 Jua 지정 필수.
  오류가 안 나고 화면에서만 두부(□)로 깨집니다.
- **`.godot/` 가 없는 상태(새로 받은 프로젝트)의 첫 임포트에서는 폰트 로드 오류 4줄이 납니다.**
  `Error loading custom project font 'res://assets/fonts/Jua-Regular.ttf'` — 테마가 폰트를
  굽기 전에 먼저 찾아서 나는 순서 문제입니다. **두 번째 실행부터는 안 납니다.**
  진짜 오류로 착각해 `custom_font` 를 지우지 마세요. 그러면 한글이 전부 두부가 됩니다.
- Jua 폰트에 **`×`, `−`, `÷` 글리프가 없습니다.** 연산 기호는 `Glyphs` 로 직접 그립니다.
- **JSON은 정수를 float으로 돌려줍니다.** 저장 파일을 읽을 때 `int()` 로 다시 조이세요.
- **`draw_string()` 의 `pos` 는 베이스라인 좌하단**입니다. `Fonts.draw_centered()` 를 쓰세요.
- **`Tween.kill()` 은 `finished` 를 내지 않습니다.** `await tw.finished` 가 영원히 멈춥니다.
  건너뛰기는 `set_speed_scale(60.0)` 으로 하세요.
- **트위너 없는 Tween** 도 `finished` 를 안 냅니다. `has_tweeners()` 로 거르세요.
- **GDScript 람다는 지역 변수를 값으로 캡처합니다.** 콜백에서 바깥 값을 바꾸려면 배열로 감싸세요.
- **`handheld/orientation` 은 정수**입니다 (Godot 3의 `"portrait"` 문자열 아님).
  `0`=가로 `1`=세로 `2`=역가로 `3`=역세로 `4`=센서가로 `5`=센서세로 `6`=센서.
  이 게임은 **`4`(센서 가로)** — 태블릿을 어느 쪽으로 돌려 들어도 가로로 섭니다.
- **`stretch/aspect="expand"` 에서 뷰포트는 기준 해상도보다 절대 작아지지 않습니다.**
  1280×800 기준이면 어떤 기기에서도 뷰포트는 최소 1280×800 이고 한쪽만 늘어납니다.
  그래서 **1280×800 이 가로 배치에서 가장 빡빡한 경우**이고, 여기서 답 버튼 200px 이
  들어가면 다른 어떤 가로 기기에서도 들어갑니다 (테스트 [7]이 이 크기를 꼭 넣습니다).
- **`import_etc2_astc=true`** 가 없으면 안드로이드 익스포트가 아예 막힙니다.
- **iOS 는 `targeted_device_family=2`(아이폰+아이패드) 여야 합니다.** `0`(아이폰 전용)이면
  오류 없이 익스포트되지만, 아이패드가 앱을 **아이폰 호환 모드**로 띄워서 폰 크기 창 하나만
  가운데 뜨고 나머지가 전부 여백이 됩니다. 기준 해상도가 가로 태블릿인 게임에서 특히 치명적입니다.
  배치 코드로는 못 고칩니다 — `export_presets.cfg` 값입니다.
  확인: `grep -a TARGETED_DEVICE_FAMILY build/ios/*.xcodeproj/project.pbxproj` 가 `"1,2"`.
- **iOS 앱 이름은 `config/name.ios` 로 영문을 따로 줍니다.** 애플이 App ID 이름에 영문·숫자만
  받아서, 한글 이름 그대로면 무료 서명(AltStore/Sideloadly)이 App ID 를 못 만듭니다.
- Control에 **비대칭 앵커**가 걸려 있으면 `size` 를 직접 대입해도 덮어써집니다 (`Hud` 가 그렇습니다).

## 어디를 고칠 것인가

| 하고 싶은 것 | 파일 |
|---|---|
| 탄 추가/순서 변경/난이도 조정 | `src/core/curriculum.gd` |
| 문제 생성 규칙 | `src/core/problem_gen.gd` (`make_one` 의 match 에 규칙 추가) |
| 오답(오류 모델) | `src/core/problem_gen.gd` 의 `_errors_*` |
| 오답 유형의 한국어 설명 | `src/ui/parent.gd` 의 `TAG_LABEL` |
| 블록 시연 연출 | `src/game/block_stage.gd` (`_demo_add` / `_demo_sub` / `_demo_mul` / `_demo_missing`) |
| 오답 사다리 규칙 | `src/game/battle.gd` (`_resolve_wrong`) |
| 시연 속도 | `src/game/block_stage.gd` 의 `PACE` (크면 느림) |
| 문제↔설명 기호 정렬 | `ProblemCard.op_centers()` → `BlockStage.set_op_anchors()` (테스트 [8]이 지킴) |
| 색 | `src/core/palette.gd` |
| 캐릭터 그림 | `tools/gen_art.py` 의 프롬프트 → 재생성. 코드 대체본은 `src/game/frog.gd`, `snake.gd` |
| 월드별 뱀·보스 생김새 | `src/game/snake.gd` 의 `WORLD_LOOK` + `tools/gen_art.py` 의 `snake_w*`/`boss_w*` |
| 지도 그림 | `tools/gen_art.py` 의 `map_w*` (1280×800 가로, **길은 왼쪽→오른쪽**). 세로 화면에서는 안 쓰고 코드 배경으로 대체합니다 |
| 지도 화면 | `src/ui/map.gd` (`NODE_SPOTS` 세로 / `NODE_SPOTS_WIDE` 가로 가 탄 위치) |
| 지도 월드별 테마·탄 받침 | `src/ui/map.gd` 의 `WORLD_THEME` / `_draw_pedestal()` |
| 블록 놓는·옮기는 속도 | `src/game/block_stage.gd` 의 `FILL_GAP` / `POUR_GAP` (개수와 무관하게 일정) |
| 로딩 화면 | `src/ui/splash.gd` |
| 화면 배치 | 각 화면의 `_layout()` → 가로는 `_layout_wide()`, 세로는 `_layout_tall()` |
| 개구리·뱀 크기 (보스 포함) | `src/game/battle.gd` 의 `_character_room()` / `_place_characters()` |
| 개구리 혀 (방향·길이) | `src/game/frog.gd` 의 `_tongue_points()` / `_aim_point()` |
| 상단 진행 칩 | `src/ui/hud.gd` 의 `set_progress()` / `pulse_progress()` / `progress_settled()` |
| 가로/세로 판정 기준 | `src/core/layout.gd` (`WIDE_RATIO`, `BASE`) |
| 가로에서 답 열 폭·전투 띠 높이 | `src/game/battle.gd` 의 `WIDE_*` 상수 |
| 화면 글자 (한/영) | `src/core/loc.gd` |

**규칙이나 탄을 추가하면 `tests/test_runner.gd` 에 조건 검사도 함께 추가하세요.**
`_check_tier_specifics()` 가 "5탄에 받아올림이 섞이지 않는가" 같은 것을 지키는 안전망입니다.

## 코드 스타일

- 들여쓰기는 **탭**. 주석과 사용자 문구는 **한국어**.
- `class_name` 은 PascalCase, 파일명은 snake_case.
- 공개 함수에는 `##` 문서 주석. **왜** 그렇게 했는지가 중요한 곳에는 근거를 남기세요
  (특히 교육적 이유 — 나중에 "최적화"하다가 되돌리기 쉬운 것들입니다).
- 이미지 에셋을 추가하지 마세요. 모든 그래픽은 코드로 그립니다.
