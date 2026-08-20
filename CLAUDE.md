# CLAUDE.md — 이 저장소에서 작업할 때

**두리의 모험** — 아이 둘(나이 차 있음)을 위한 놀이 모음. Godot 4.7.1, 안드로이드/iOS.
게임 여섯이 하나의 앱에 들어 있고, 앞으로 더 늘어난다.
주인공은 **두리**(만 4세) — 이야기가 아니라 **안내자**다 ([`docs/look-rules.md`](docs/look-rules.md)).

- **공룡 찾기** (`games/dino/`) — 방에 숨은 공룡을 콕 눌러 찾는다
- **손전등 찾기** (`games/torch/`) — 깜깜한 방을 좁은 손전등으로 비춰 공룡을 찾는다
- **셈놀이** (`games/math/`) — 블록으로 왜 그런지 보여 주는 사칙연산
- **블록 채우기** (`games/kanoodle/`) — 조각을 기둥에 떨어뜨려 가이드 모양대로 쌓는다
- **참참참** (`games/cham/`) — 친구가 어느 쪽으로 뛸지 손으로 가리켜 잡는다
- **가위바위보** (`games/rps/`) — 친구 손을 보고 이기는(비기는·지는) 손을 낸다

★ **세계관이 없다.** 예전에는 "집 안 / 집 밖"이라는 이야기로 묶었는데, 게임들의 결이
너무 달라서 이야기가 오히려 이질감을 키웠다. 허브는 그냥 **게임 목록 + 아무거나(랜덤)** 다.
새 게임의 title 이 "방향"이 되지 않아도 된다.

전체 설명은 [`README.md`](README.md). 갈무리 절차는 [`WRAPUP.md`](WRAPUP.md).
게임별 규칙은 [`docs/dino-rules.md`](docs/dino-rules.md) · [`docs/math-rules.md`](docs/math-rules.md)
— **둘 다 여전히 유효하다. 고치기 전에 반드시 읽어라.**
손전등 찾기는 [`docs/torch-rules.md`](docs/torch-rules.md), 참참참은 [`docs/cham-rules.md`](docs/cham-rules.md),
가위바위보는 [`docs/rps-rules.md`](docs/rps-rules.md).
룩앤필(주인공·색·아이콘)은 [`docs/look-rules.md`](docs/look-rules.md).

---

## 이 앱의 뼈대

```
shell/            앱 셸 — 게임 목록 말고는 게임을 모른다
  shell.gd          오토로드 Shell: 저장 파일 · 기기 설정 · 프로필 · 공용 도감 · 뷰포트
  router.gd         오토로드 Router: 화면 전환 (페이드가 덮은 순간 뷰포트를 갈아 끼운다)
  game_registry.gd  ★ 게임이 등록되는 유일한 곳 (「섬 한 바퀴」 가중치도 여기)
  migrate.gd        옛 저장 파일 -> v3 (순수 함수라 헤드리스로 테스트된다)
  boot.gd / hub.gd  진입점 / 둥지방
core/look.gd      ★ 앱 전체의 색 · 주인공 두리 · 손 그리기 (게임이 색·손을 짓지 않게)
core/art/         두리 네 포즈 (tools/theme/gen_theme.py 가 만든다)
core/fonts/       DinoKR.ttf (프로젝트 fallback) · Jua-Regular.ttf (셈놀이 전용)
games/dino/       공룡 찾기
games/torch/      손전등 찾기 (공룡 찾기의 방·가구·공룡을 빌려 쓴다)
games/math/       셈놀이 (오토로드 MathGame / Audio 포함)
games/kanoodle/   블록 채우기
games/cham/       참참참 (공룡 그림·도감만 빌려 쓴다)
games/rps/        가위바위보 (손은 core/look.gd 의 draw_hand — 허브 카드와 같은 손)
tools/            verify.sh · check_font.py · screenshot.py · dino/ · theme/
tests/            test_runner · shot · dino_dump · ns_check
                  journey_check (게임 사이) · battle_check (시연 켠 전탄)
                  kanoodle_check (퍼즐 생성기) · torch_check (어둠·빛·찾기 규칙)
                  cham_check (버릇 읽기) · rps_check (규칙·안내·찍기 상한)
                  session_check (「많이 놀았다」가 쉼표인가 자물쇠인가)
```

**새 게임을 넣을 때 손대는 것은 `shell/game_registry.gd` 의 배열 한 줄과 씬 하나뿐이다.**
셸(`shell.gd` / `router.gd` / `hub.gd`)은 절대 게임 이름을 알아서는 안 된다.

---

## 작업을 마칠 때 (매번, 빠짐없이)

```bash
tools/verify.sh              # 전부 (약 17분)
tools/verify.sh quick        # 느린 둘(시연 전탄·개구리 전체)만 빼고 (약 5분)
```

그리고 **APK 를 새로 굽고 어디에 만들어졌는지 답변에 적어라.** 고친 걸 아이가
바로 폰에서 눌러 볼 수 있어야 한다.

```bash
mkdir -p build/android && ~/.local/bin/godot --headless --path . \
    --export-debug "Android Test APK" "$PWD/build/android/rogame-test.apk"
cp build/android/rogame-test.apk ~/rogame-test.apk
```

```bash
scp dgxmaruta@<호스트>:~/rogame-test.apk .
adb install -r rogame-test.apk
```

- 화면에 보이는 걸 고쳤으면 **미리보기 그림도 새로 뽑아라**
  (`godot --headless --path . res://tests/dino_dump.tscn -- --dump && python3 tools/dino/render_preview.py`).
- 익스포트 끝의 `cannot connect to daemon at tcp:5037` 은 폰이 안 붙어 있어서 나는 것이라
  오류가 아니다. `[ DONE ] export` 와 `Signed` 가 보이면 성공이다.
- **APK 가 안 나오면 조용히 넘어가지 말고 왜 실패했는지 말해라.**

그리고 **커밋하고 push 해라.** 원격은 <https://github.com/DevJieung/JingIPA> (`origin`) 하나고,
자격증명은 `~/.ghtoken` + 전역 credential 헬퍼로 이미 걸려 있다 — 그냥 `git push` 하면 된다.
검증이 하나라도 깨졌으면 push 하지 말고 보고해라. ⚠ **토큰을 화면에 찍지 마라**
(`... 2>&1 | sed 's/github_pat_[A-Za-z0-9_]*/<토큰>/g'`).

**아이폰용이 필요하면 IPA 는 GitHub Actions 가 굽는다** (이 머신은 aarch64 라 못 굽는다).
푸시한 뒤 워크플로를 걸고, 초록불만 보지 말고 **IPA 를 받아서 안까지 열어 확인해라** —
화면이 없는 이 머신에서 결과를 볼 수 있는 방법이 그것뿐이다. 약 2분 걸린다.

```bash
# ⚠ 토큰을 -H 로 넘기면 프로세스 인자에 올라가 ps/pgrep 으로 새어 나간다. stdin 으로 준다.
gh_api() { local u="$1"; shift; printf 'header = "Authorization: Bearer %s"\n' \
  "$(cat "$HOME/.ghtoken")" | curl -sS --config - "$@" "$u"; }
API=https://api.github.com/repos/DevJieung/JingIPA
gh_api "$API/actions/workflows/ios.yml/dispatches" -X POST \
  -H "Accept: application/vnd.github+json" -d '{"ref":"main","inputs":{"build_type":"release"}}'
```

전체 절차(실행 찾기·기다리기·실패 원인 보기·IPA 열어 보기·토큰 권한 셋)는
[`WRAPUP.md`](WRAPUP.md) 4~5번에 있다. 서명 재료는 [`docs/ios-signing.md`](docs/ios-signing.md).

---

## 절대 깨면 안 되는 것

### 아이용 기본값 (두 게임 공통)
1. **타이머·카운트다운·재촉 연출을 넣지 않는다.** 이 나이대 학습 불안의 주 원인이다.
2. **실패·목숨·게임오버를 넣지 않는다.** 틀려도 벌 대신 귀여운 반응.
3. **조작은 단일 탭만.** 드래그·스와이프·더블탭 금지.
4. **화면에 나가는 글자는 크게, 읽기를 요구하지 않게.** 어린 쪽은 글을 못 읽는다.
5. **누적 카운터를 아이 화면 첫 페이지에 두지 않는다.** 총 별·최고 탄·총 마리수는
   전부 부모 화면으로. 아이 화면에는 "지금 이 판"만. — 이 규칙 하나가 형제 비교 문제와
   과잉정당화를 동시에 막는다.
6. **보상을 미리 예고하지 않는다.** "이거 다 하면 ○○을 줘요"를 화면 어디에도 쓰지 않는다.
   보상은 놀이가 끝난 뒤 그냥 나타나고, **활동의 연장**이어야 한다(새 공룡·새 방·새 색).
   스티커·코인 같은 놀이 밖 화폐와 무작위 보상(가챠)은 넣지 않는다.
7. **칭찬은 사람이 아니라 사건을 말한다.** "잘했어요"는 능력 귀인을 만들고,
   그 귀인은 실패할 때 정확히 반대로 뒤집힌다.

### 난이도
8. **올리는 축은 셋뿐이다** — 볼 것이 늘거나(A) · 잘 안 보이거나(B) · 고를 것이 는다(C).
   **기다림(E)은 내려가기만 한다.** 줄여 주는 것이 곧 보상이다.
   평가받는 느낌(F)과 시간 압박(G)은 절대 올리지 않는다.
9. **적응형 난이도의 신호로 시간을 재지 않는다.**
   공룡 찾기는 **힌트 발동 횟수**만, 개구리 용사는 **누적 첫시도 정답 횟수**만 본다.
   초시계는 (a) 화면에 안 보이는 타이머이고, (b) 아이가 자리를 비우면 무너지고,
   (c) 4지선다 찍기를 숙련으로 오독한다(2연속 확률 1/16).
9-1. **한 판을 두 번 세지 마라.** 끝난 판을 저장할 때 `_done` 같은 **아직 안 꺼진 깃발**로
    "깼는가"를 판단하면, 끝낸 순간과 "다음 판" 버튼에서 두 번 세어진다. 블록 채우기가
    그랬다 — 숨은 손잡이(skill)가 판마다 +2 씩 올라 **다섯 판 만에 상한**에 붙었고,
    아이 눈에는 이유 없이 갑자기 어려워지는 것으로만 보였다(규칙 11 위반).
    부모 화면의 "오늘 몇 판"도 두 배였다. **세는 일과 저장하는 일을 갈라 둬라**
    (`kanoodle.gd` 의 `_save(score)`).
9-2. **새 게임의 축은 "찍어도 통과하는가"를 먼저 재고 정한다.** 규칙 9 는 초시계를
    금지하는 데서 끝나지 않는다 — **선택지가 적고 판이 짧으면 찍기가 숙련으로 읽힌다.**
    가위바위보는 그래서 라운드 하한이 5다 (4로 내리면 카드 2장에서 찍기 통과율이
    9.8% 로 규칙 9 의 문턱 6.25% 를 넘는다). 공식과 상한은
    `RpsGen.guess_pass()` 에 있고 `tests/rps_check.gd` 가 강제한다.
10. **새 축은 한 번에 하나씩, 그것도 한 마리/한 문제에만 먼저.** 축 도입 간격 최소 3방.
    어려운 판 뒤에는 쉬운 판. 10탄 배수(축하 방)는 항상 조금 쉽게.
11. **아이에게 "너 못한다"는 신호를 절대 보이지 않는다.** 난이도가 내려가도
    아이 눈에는 "설명이 다시 친절해진 것"으로만 보여야 한다.

### 형제
12. **두 프로필의 별·정답률·최고 탄을 나란히 그리는 화면을 아이 화면에 만들지 않는다.**
    격차가 실력차가 아니라 발달 단계차라, 순위는 매번 고정되고 그건 낙인이다.
    비교는 부모 화면에만 존재한다.
13. **도감은 집 공용이다.** 누가 찾았든 같은 칸이 찬다. 칸에 "누가 찾았는지"를
    표시하지 않는다 — 그 격자가 곧 점수판이 된다.
14. **단조 갱신을 깨지 않는다.** 별과 최고 탄은 내려가지 않는다. 동생이 형 프로필로
    놀아도 기록이 상하지 않게 하는 마지막 방어선이다.

### 기술
15. **셸은 게임을 모른다.** 새 게임은 `shell/game_registry.gd` 한 줄로 붙는다.
16. **화면 전환 잠금(`Router._busy`)은 씬이 바뀐 순간 푼다.** 마지막 페이드 트윈이
    끝날 때까지 잡고 있으면, 그 트윈이 한 번이라도 `finished` 를 안 내는 순간
    잠금이 영영 안 풀리고 **그 뒤 모든 화면 전환이 오류 한 줄 없이 무시된다** —
    아이가 문을 눌러도 아무 일이 안 일어난다. 실제로 물렸다.
    페이드 대기도 트윈과 타이머 중 먼저 오는 쪽을 받는다(`Router._first_of`).
17. **게임 코드는 커맨드라인을 읽지 않는다.** `--dump`/`--selftest` 는
    `tests/dino_dump.tscn` 전용 진입점이 들고 있다. 게임이 읽으면 두 게임의 개발 도구가
    인자를 섞고 `get_tree().quit()` 이 촬영 도중 앱을 죽인다. (`verify.sh` 가 강제한다)
18. **폰트를 통일하지 않는다.** 프로젝트 fallback 은 DinoKR(한글 100%),
    개구리 용사는 Jua 를 직접 preload 해서 `draw_string` 에 넘긴다.
    ⚠ **Theme 는 CanvasLayer 경계를 넘지 못한다** — 공룡 찾기의 HUD·타이틀·배너·카드는
    `ui: CanvasLayer` 의 직속 자식이라 우연히 동작하는 구조다. 사이에 CanvasLayer 를
    한 겹 더 끼우면 조용히 fallback 으로 돌아간다.
    ⚠ 두 `.import` 다 `allow_system_fallback=true` 라 실기기에서는 OS 폰트가 메워 준다 —
    **눈으로는 절대 안 잡힌다.** `tools/check_font.py` 를 반드시 돌려라.
19. **퍼즐은 거꾸로 만든다.** 무작위로 놓고 "풀리나?" 검사하면 못 푸는 판이 나온다.
    먼저 판을 조각으로 빈틈없이 덮고(=해답) 그중 일부를 빼서 문제로 준다.
    그러면 풀 수 있다는 것이 **생성 방식 자체로 보장**되고 힌트·검증이 공짜다.
    ⚠ **블록 채우기는 조각이 떨어져서 쌓인다(중력).** 그래서 덮은 것을 아무렇게나
    빼면 안 된다 — 위에 뭔가 얹힌 조각은 떨어뜨려도 제자리까지 못 내려간다.
    빼는 조각은 반드시 **위쪽이 뚫린 덩어리**여야 한다 (`NoodGen.pick_top`).
    ⚠ 다만 이 해답은 **아이가 맞춰야 할 정답이 아니다.** 첫 계획일 뿐이다 — 아래 19-1 참고.
19-1. **블록 채우기는 모양만 맞으면 어디든 들어간다.** 예전에는 해답에 적힌 그 자리에
    앉아야만 들어갔고, 그래서 모양이 딱 맞는 빈 자리에 제대로 넣어도 튕겨 나왔다
    (같은 모양 조각이 둘일 때 특히). 아이 눈에는 "맞는데 안 되는" 것이라 제일 나쁘다.
    지금 판정은 자리가 아니라 **가능성**이다 — **"여기 앉혀도 남은 조각으로 판을
    끝까지 채울 수 있는가"** (`NoodGen.fits`). 그래서 자유롭게 넣으면서도 막다른 판이
    안 생긴다.
    - 해답은 계약이 아니라 **지금 계획**(`kanoodle.gd` 의 `_plan`)이다. 아이가 다른
      자리에 넣으면 `_refresh()` 가 다시 세운다. **안내 점·경계선·힌트는 전부 이
      계획을 그린다** — 생성기 해답을 그리면 그 순간 안내가 거짓말이 된다.
    - 힌트는 반드시 **계획의 첫 수**(`_plan_next`)만 가리켜라. `_plan[i]` 는 "다 놓고
      났을 때 있을 자리"라, 차례가 뒤인 조각을 가리키면 아이는 시킨 대로 떨어뜨렸는데
      더 아래로 가서 튕기는 것을 본다.
    - **"제자리에 앉는가"로 놓을 차례를 판단하지 마라**는 옛 교훈은 그대로다 — 옆 기둥에
      얹혀 제자리에 잘 앉으면서 아래 조각의 길을 막는 경우가 있다(여행 검사 10번째에서
      물렸다). 지금은 그것까지 포함해 "끝까지 채울 수 있는가"로 본다
      (`NoodGen.survey` -> `kanoodle.gd` 의 `_can_place` / `_ready_now`).
    - 탐색은 격자가 아니라 **기둥 높이**만 본다. 조각이 위에서만 내려오므로 지나갈 수
      있는 판은 전부 "기둥마다 아래부터 빈틈없이 찬" 모양이기 때문이다. 낙하 자리는
      `NoodGen.land_at()` **한 곳에서만** 계산한다 (격자 쪽 `drop_dy()` 와 같은 답을
      내야 하고, `tests/kanoodle_check.gd` 의 `_equiv_check` 가 둘을 맞대어 본다).
      ⚠ **ㄷ 자처럼 기둥이 끊긴 조각을 `pieces.gd` 에 넣지 마라** — 기둥 표가 거짓말이
      된다 (`_contig_check` 가 막는다).
    - **막힌 판 기억(`_bag`)은 한 판 내내 이어 쓴다.** 같은 판을 자리마다 수십 번
      물어보기 때문에, 판마다 새로 파면 어려운 판에서 탐색 한도(`PLAN_CAP`)에 걸린다.
      한 번 물렸다: 계획 다시 세우기가 4.6ms(417판) → **0.9ms(20판)** 로 줄었고
      한도 초과가 사라졌다. 한도에 걸리면 **너그러운 쪽**(놓게 해 준다)으로 답하고,
      혹시 못 채우는 자리가 들어가면 다음 `_refresh` 가 잡아서 힌트가 들어낼 조각을
      가리킨다. `tests/kanoodle_check.gd` 가 "탐색포기 0건"을 강제한다.
    - 되돌리기(판 위의 조각 도로 들기)로는 **여전히 갇힐 수 있다** — 위에 얹힌 조각을
      들어내면 그 자리가 묻힌 구멍이 된다. 그때는 힌트가 **들어낼 조각**을 가리킨다
      (`_lift_hint`). 이 셋(생성·판정·탈출)이 다 있어야 판이 막다르게 안 끝난다.
      ⚠ 갇힌 동안에는 힌트를 **기다림 없이 바로** 띄우고, 탭이 그걸 지우지 않게 한다
      (`_stuck`). 답답해서 자꾸 두드리는 아이는 탭마다 기다림이 0으로 돌아가서
      유일한 탈출 안내를 영영 못 본다.
    - 힌트 색에 **흰색·금색을 쓰지 마라.** 빈 칸이 이미 밝은 베이지(e2ded6)라 대비가
      1.1:1 밖에 안 나온다 — 눈으로는 "힌트가 안 뜬다"로만 보인다.
      `python3 tools/screenshot.py kanoodlehint:1` 로 직접 찍어서 확인해라.
20. **뷰포트를 통일하지 않는다.** 기본 1280x800 expand, 공룡 찾기 진입 시에만
    런타임으로 1280x720 keep 으로 전환한다(`Shell.enter_game`).
    720 으로 통일하면 노치 있는 아이폰에서 개구리 답 버튼이 24px 화면 밖으로 나가고,
    800 으로 통일하면 공룡 찾기의 소품 y 좌표 42개를 다시 맞춰야 한다.
    → 개구리 테스트 [7]의 `sizes` 배열에 `Vector2(1280,720)` 를 **추가하지 마라.**
21. **`Game` 이라는 오토로드 이름을 쓰지 않는다.** 오토로드 `Game` 이 있으면
    같은 이름의 씬 루트가 **경고 한 줄 없이** `@Node2D@N` 으로 개명된다.
22. **`class_name` 규칙** — 접두사 없는 이름은 `core/`·`shell/` 만. `games/<id>/` 는
    그 게임 접두사로 시작한다. 접두사 없는 이름을 쓰고 싶으면 `core/` 로 승격하라.
    유예 목록은 `tests/ns_check.gd` 에 동결돼 있다.
23. **검증이 저장 파일을 덮지 않게 한다.** `verify.sh` 가 `ROGAME_NO_SAVE=1` 로 돌린다.
    이걸 안 하면 "아이 기록"이라 믿는 값이 사실은 테스트가 만든 값이 된다
    (실제로 물렸다 — `found=254` 는 `--selftest` 를 두 번 돌린 값이었다).
24. **`use_custom_user_dir=true` 를 지우지 마라.** 이름만 넣으면 조용히 무시되고
    `config/name` 이 저장 폴더 이름이 된다. 앱 이름을 바꾸는 순간 기록이 사라진 것처럼 보인다.
25. **어둠은 완전한 검정이 아니다.** 손전등 찾기의 어둠에는 상한이 있고
    (`TorchGen.DARK_CEIL`), 놀이 중에는 **내려가기만** 한다. 방은 밝게 시작해서 해가 지고,
    창의 달빛은 절대 안 꺼지며, 다 찾으면 불이 켜진다. 이 넷 중 하나라도 빼면
    이 나이대에게는 놀이가 아니라 공포다. 어둠 x 가림 x 좁은 빛은 **곱해진다** —
    셋을 따로 올리면 각각은 온건한데 합쳐서 "안 보이는 방"이 된다
    (`TorchGen.hardness()` 가 그 곱을 재고 `tests/torch_check.gd` 가 상한을 강제한다).
    자세한 것은 [`docs/torch-rules.md`](docs/torch-rules.md).
26. **공룡 그림을 좌우로 뒤집어서 "방향"을 말하지 마라.** 50종 PNG 는 바라보는 방향이
    종마다 달라서, 뒤집기로 무언가를 알리면 종에 따라 아이에게 거짓말이 된다.
    (공룡 찾기는 그냥 모양이라 무해했고, 그래서 여태 안 드러났다. 참참참에서 드러났다.)
27. **놀이에 쓰이는 그래픽은 코드로 그린다.** 이미지 파일은 공룡 50종 PNG 와
    주인공 두리 네 장뿐이다. 방·가구·블록 조각·손은 전부 코드다 — (a) 판정이 그 도형에서
    나오고(가림%·클릭·낙하), (b) 화면 없는 이 머신에서 그리기 명령을 재현해 검증하기
    때문이다. **새 게임의 놀이 화면은 이미지 0장이 원칙이다.**
    두리·아이콘·부팅 화면 같은 **장식만** 그림을 쓴다 ([`docs/look-rules.md`](docs/look-rules.md)).
28. **색을 짓지 마라.** `core/look.gd` 의 `Look` 에서 가져와라. 게임마다 제 색을 지어내면
    다섯 개가 다섯 앱처럼 보인다. 게임의 정체성 색만 `game_registry.gd` 의 `color` 에 둔다.
29. **`config/name.ios` 와 번들 ID 는 절대 바꾸지 마라.** 표시 이름(`config/name`)만 바꾼다.
    바꾸는 순간 아이 폰의 기존 저장 데이터가 남남이 된다.
30. **놀이 단위 상한은 벽이 아니라 쉼표다.** 상한에 닿아 허브로 돌려보낼 때 반드시
    세션을 새로 연다 (`Shell.round_done` -> `take_session_break`).
    ⚠ `session_units` 를 0 으로 되돌리는 곳이 앱 부팅(`shell/boot.gd`) 하나뿐이면,
    한 번 넘긴 뒤로는 **방을 깰 때마다 예외 없이 허브로 튕긴다** — 다시 들어가서 한 방,
    또 허브, 또 한 방. 아이 눈에는 "다 찾았는데 다음 방이 안 나온다"로만 보인다(규칙 11).
    안드로이드는 홈 버튼으로 나가도 프로세스가 살아 있어 `boot.gd` 가 다시 안 돌고,
    그 상태가 **며칠씩** 이어진다. 제한이 없는 것보다 나쁘다 — 실제로 물렸고,
    부모가 "다음 스테이지로 안 넘어간다"로 신고했다.
    ⚠ 그리고 **말없이 화면만 바꾸지 마라.** 두리가 한 번 인사하고 나간다
    (`Router.goto_rest`). 축하 배너를 보고 기뻐한 직후에 갑자기 게임 목록에 서 있으면,
    이 나이대는 그걸 "내가 뭘 잘못 눌러서 놀이가 끊겼다"로 읽는다.
    ⚠ 허브로 보내는 일은 **셸이 한다.** 게임이 제 페이드로 덮은 뒤 `Router.goto_hub()`
    를 부르면 [덮임 -> 방이 다시 보임 -> 다시 덮임] 으로 한 번 깜빡이고,
    아이 눈에는 "넘어가려다 실패한 것"으로 보인다.
    `tests/session_check.gd` 가 강제한다 (게임별 검사기는 `dev_mode` 라 이 분기를
    통째로 건너뛰고, 여행 검사는 상한을 꺼 버려서 여태 아무도 안 봤다).

---

## 자주 쓰는 명령

```bash
~/.local/bin/godot -e --path .                                  # 편집기
~/.local/bin/godot --headless --path . --import                 # 임포트만
~/.local/bin/godot --headless --path . --quit-after 300         # 부팅 확인 (헤드리스는 SIGTERM 시 출력이 날아간다)

tools/verify.sh                                                  # 검증 전부
tools/verify.sh quick                                            # 빠르게

~/.local/bin/godot --headless --path . res://tests/dino_dump.tscn -- --dump
~/.local/bin/godot --headless --path . res://tests/dino_dump.tscn -- --dump --pre
~/.local/bin/godot --headless --path . res://tests/dino_dump.tscn -- --dump --boxes
~/.local/bin/godot --headless --path . res://tests/dino_dump.tscn -- --selftest
stdbuf -oL ~/.local/bin/godot --headless --path . res://tests/journey_check.tscn   # 섬 한 바퀴
stdbuf -oL ~/.local/bin/godot --headless --path . res://tests/battle_check.tscn    # 시연 켠 전탄
stdbuf -oL ~/.local/bin/godot --headless --path . res://tests/kanoodle_check.tscn  # 퍼즐 생성기
stdbuf -oL ~/.local/bin/godot --headless --path . res://tests/torch_check.tscn     # 어둠·빛·찾기 규칙
stdbuf -oL ~/.local/bin/godot --headless --path . res://tests/cham_check.tscn      # 참참참 버릇 읽기
stdbuf -oL ~/.local/bin/godot --headless --path . res://tests/session_check.tscn   # 「많이 놀았다」 쉼표
python3 tools/screenshot.py kanoodle:0 kanoodlehint:14 torch:1 cham:1 rps:1 rpsmeet:1 hub:0
python3 tools/dino/render_preview.py                             # 위 JSON 을 PNG 로
python3 tools/screenshot.py map:0 battle:8                       # Xvfb 로 실제 촬영
python3 tools/theme/gen_theme.py --list            # 두리 자산 목록
python3 tools/theme/gen_theme.py --only duri --tries 6  # 주인공 후보 뽑아 보기
python3 tools/theme/gen_theme.py --icons          # 두리 얼굴로 아이콘·부팅화면 다시
python3 tools/check_font.py
python3 tools/dino/gen_dinos.py --list                           # 공룡 50종

git push                                                         # ~/.ghtoken 으로 그냥 된다
# 아이폰용 IPA — 절차·gh_api 정의는 WRAPUP.md 5번 (토큰을 -H 로 넘기지 마라)
gh_api "$API/actions/workflows/ios.yml/dispatches" -X POST \
     -d '{"ref":"main","inputs":{"build_type":"release"}}'
gh_api "$API/actions/runs?per_page=3"                            # 결과 보기
ROGAME_DEBUG=1 ~/.local/bin/godot --headless --path . --quit-after 200   # 이관 진단
```

---

## 이 머신(aarch64, 화면 없음)에서 알아둘 것

- **화면이 없다.** 게임 창을 띄울 수 없다. 대신 두 가지로 본다:
  공룡 찾기는 `--dump` + `tools/dino/render_preview.py`(그리기 명령을 JSON 으로 기록해
  Pillow 로 재현), 개구리 용사·허브는 `tools/screenshot.py`(Xvfb 로 실제 렌더).
  그래서 공룡 찾기의 그리기 코드는 `_draw()` 안에 두지 말고 `_paint(ci)` 로 빼라.
- **헤드리스 stdout 은 블록 버퍼링이다.** 죽이거나 멈추면 여태 찍은 게 통째로 날아가서
  **"실행이 아예 안 된다"로 오해하게 된다.** 파스 에러 한 줄 때문에 한참을 헤맸다.
  → 검사를 돌릴 때는 항상 `stdbuf -oL` 을 앞에 붙여라:
  `timeout 200 stdbuf -oL ~/.local/bin/godot --headless --path . res://tests/....tscn`
  오래 도는 검사기는 진행 상황을 `user://` 파일에도 흘려 두면(`tests/journey_runner.gd`)
  멈춰도 어디까지 갔는지가 남는다.
- **APK 는 `use_gradle_build=false` 라서 만들어진다.** x86_64 전용인 `aapt2` 를 안 탄다.
  스토어용 **AAB 는 이 머신에서 안 된다.**
- **iOS 는 Xcode 프로젝트까지만 나온다.** `.ipa 는 macOS 에서만` 경고가 뜨는 게 정상이고
  종료 코드는 0 이다. IPA 는 GitHub Actions 의 맥이 굽는다.
- **`import_etc2_astc=true` 를 지우지 마라.** 없으면 x86_64 러너에서 **오류 메시지도 없이**
  익스포트가 거부된다.

---

## 어디를 고칠 것인가

| 하고 싶은 것 | 파일 |
|---|---|
| **새 게임 추가** | `shell/game_registry.gd` (배열 한 줄) + 씬 하나 |
| 허브 (게임 목록) | `shell/hub.gd` — 게임이 늘어도 안 고친다 |
| **블록 채우기 조각 세트** | `games/kanoodle/pieces.gd` 의 `LIST` |
| 블록 채우기 퍼즐 생성 | `games/kanoodle/nood_gen.gd` 의 `tile()` / `make()` / `pick_top()` |
| 블록 채우기 낙하 규칙 | `games/kanoodle/nood_gen.gd` 의 `drop_dy()` — 게임·생성기·검사기가 같은 함수를 본다 |
| **블록 채우기 자리 판정** | `games/kanoodle/nood_gen.gd` 의 `fits()` / `plan()` / `survey()` |
| 블록 채우기 놓을 차례 · 안내 | `games/kanoodle/kanoodle.gd` 의 `_refresh()` + `_plan` / `_plan_next` |
| 블록 채우기 난이도 | `games/kanoodle/nood_gen.gd` 의 `axes()` |
| **「섬 한 바퀴」 (게임 섞기)** | `shell/shell.gd` 의 `journey_*` + `pick_journey_game()` |
| 여행에서 게임이 나올 확률 | `shell/game_registry.gd` 의 `journey` (나이대별 가중치) |
| 여행 한 판의 놀이 단위 | `shell/game_registry.gd` 의 `journey_units` (셸은 게임 이름을 모른다) |
| **놀이 단위 상한 · 쉼표** | `shell/shell.gd` 의 `round_done()` / `take_session_break()` — 게임은 이 한 줄만 부른다 |
| 쉬러 갈 때 두리 인사 | `shell/router.gd` 의 `goto_rest()` / `_show_caption()` |
| **앱 색 · 주인공 두리** | `core/look.gd` 의 `Look` — 색을 게임에서 짓지 않는다 |
| 두리 그림 · 아이콘 | `tools/theme/gen_theme.py` (로컬 Krea 2, 화풍 앵커가 여기 있다) |
| 여행 개구리 구간의 탄 고르기 | `shell/router.gd` 의 `_pick_journey_tier()` |
| 저장 스키마 · 프로필 · 도감 | `shell/shell.gd` |
| 옛 저장 이관 | `shell/migrate.gd` (순수 함수) |
| 화면 전환 · 뷰포트 | `shell/router.gd` + `Shell.enter_game()` |
| **가위바위보 난이도·규칙** | `games/rps/scripts/rps_gen.gd` 의 `axes()` / `answer()` — **단일 진실 소스** |
| 가위바위보 흐름·그리기 | `games/rps/scripts/rps_game.gd` |
| 손 그리기 (가위·바위·보) | `core/look.gd` 의 `draw_hand()` — 허브 카드와 게임이 같은 함수를 본다 |
| **참참참 난이도·버릇** | `games/cham/scripts/cham_gen.gd` 의 `axes()` / `pattern()` — **단일 진실 소스** |
| 참참참 흐름·그리기 | `games/cham/scripts/cham_game.gd` |
| **손전등 찾기 난이도** | `games/torch/scripts/torch_gen.gd` 의 `axes()` — **단일 진실 소스** |
| 손전등 빛·어둠 그리기 | `games/torch/scripts/torch_beam.gd` (판정 `lit()` 도 같은 파일) |
| 손전등 찾기 흐름·힌트 | `games/torch/scripts/torch_game.gd` |
| **공룡 찾기 난이도** | `games/dino/scripts/room_gen.gd` 의 `axes()` — **단일 진실 소스** |
| 가림 정도(파고듦) | `games/dino/scripts/room_gen.gd` 의 `solve_u()` / `rooms.gd` 의 `spot_transform` |
| 가림 밴드 | `games/dino/scripts/rooms.gd` 의 `band()` — 생성기와 검사기가 같은 함수를 본다 |
| 공룡 적응형 | `games/dino/scripts/game.gd` 의 `_update_skill()` |
| 방 이름 / 가구 | `games/dino/scripts/room_gen.gd` 의 `THEMES` / `CATALOG` |
| 공룡 50종 | `games/dino/scripts/dino_species.gd` 의 `LIST` (+ `tools/dino/gen_dinos.py` 의 `DINOS`) |
| **개구리 난이도 변형** | `games/frog/core/curriculum.gd` 의 `mods_for()` |
| 문제 생성 규칙 | `games/frog/core/problem_gen.gd` |
| 시연 속도 사다리 | `games/frog/game/block_stage.gd` 의 `DEMO_SCALE` |
| 개구리 적응형 | `games/frog/game/battle.gd` 의 `_update_adapt()` |
| 나이대별 손잡이 | `shell/shell.gd` 의 `default_tuning()` |
| 부모 화면 | `games/frog/ui/parent.gd` |
| **아이폰용 IPA** | `.github/workflows/ios.yml` — 절차는 `WRAPUP.md` 5번, 서명은 `docs/ios-signing.md` |
| 화면 글자 (개구리) | `games/frog/core/loc.gd` |

**규칙이나 탄을 추가하면 `tests/` 에 조건 검사도 함께 추가하라.**

---

## 코드 스타일

- 들여쓰기는 **탭**. 주석과 사용자 문구는 **한국어**.
- `class_name` 은 PascalCase, 파일명은 snake_case.
- 공개 함수에는 `##` 문서 주석. **왜** 그렇게 했는지가 중요한 곳에는 근거를 남겨라 —
  특히 교육적·심리적 이유. 나중에 "최적화"하다가 되돌리기 쉬운 것들이다.
