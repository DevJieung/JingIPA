# WRAPUP — 작업을 마칠 때

이 순서 그대로. 하나라도 깨졌으면 넘어가지 말고 보고할 것.
(rogame 의 같은 문서를 이 저장소에 맞게 옮겨 온 것이다.)

## 1. 검증

```bash
tools/verify.sh
```

`전부 통과` 가 나와야 한다. 급할 때는 `tools/verify.sh quick`(족보 전수 검사와
자동 플레이를 줄인다, 약 1분)을 쓰되, **마무리 전에는 반드시 전체를 한 번 돌린다.**

기대값:

| 검사 | 기대 |
|---|---|
| 0. 커맨드라인 | `core/ game/ 어디도 커맨드라인을 읽지 않음` |
| 0-1. 무늬 | `무늬는 전부 도형으로 그린다` (♠♦♣ 를 글자로 쓰면 안 된다 — 아래 참고) |
| 1. 캐릭터 표 | `core/roster.gd 가 tools/roster.json 과 일치` |
| 2. 임포트 | `SCRIPT ERROR` · `Parse Error` 가 하나도 없음 |
| 3. 부팅 | 오류 없이 끝남 |
| 4. 표 검사 | `스크립트 22개 모두 파스됨` · `가장 짧은 사거리 … ≥ 안쪽 한계` · `그림 58장 모두 있음` · `판정: 정상` |
| 5. 족보 판정 | `전수 검사 2598960판` · **족보 열 가지 개수가 전부 이론값과 일치** · `판정: 정상` |
| 6. 화면 한 바퀴 | `판정: 정상` (타이틀 → 카드 → 전투 → 상점을 실제로 눌러서 돈다) |
| 7. 자동 플레이 | `판정: 정상` · `도달 탄: 중간값 35~39` · **1~6탄은 목숨을 잃지 않는다** |
| 8. 폰트 | `화면에 쓰는 모든 문자가 폰트에 있습니다` |
| 9. APK | `ok: APK (약 20~30M)` |

⚠ **멈춤은 조용한 대기가 아니라 실패다.** `verify.sh` 의 모든 Godot 호출에는 `timeout`
이 걸려 있고, 넘기면 출력 파일에 `!! 멈춤` 을 적는다. 실제로 스크립트 하나가 파스가 안 되면
씬이 `quit()` 을 영영 못 불러서 3분을 그냥 기다린 적이 있다.

## 2. 화면을 고쳤으면 사진도 새로

```bash
python3 tools/screenshot.py                  # 기본 아홉 장
python3 tools/screenshot.py reveal:9 battle:14 shop:9
```

`build/shots/` 에 PNG 로 들어간다. **눈으로 한 번 봐라.** 무언가가 가려지거나 화면 밖으로
나가는 문제는 테스트로 안 잡힌다 — 실제로 이 도구가 두 개를 잡았다:

- 로열 연출에서 **빛살이 족보 이름을 덮어** 무슨 족보인지 안 보였다 (`Fx.draw_back` 이 생긴 이유)
- 영웅 설명 두 줄이 **화면 아래로 잘려** 나갔다

찍는 데 시간이 좀 걸린다(소프트웨어 OpenGL 이라 전투 한 장에 1~2분). 여러 장을 한 번에
넘기면 Godot 을 한 번만 띄우므로 훨씬 빠르다.

## 3. 그림을 고쳤으면 다시 굽기

```bash
python3 tools/gen_art.py --list                  # 목록만
python3 tools/gen_art.py                         # 없는 것만 (한 장 65초)
python3 tools/gen_art.py --only 용기사 --force     # 한 놈만 다시
python3 tools/gen_roster.py                      # roster.json 을 고쳤으면 표를 다시 찍는다
~/.local/bin/godot --headless --path . --import  # ★ 새 PNG 는 임포트해야 게임이 본다
```

- 캐릭터를 **더하거나 지우는 것은 `tools/roster.json` 한 곳**만 고치면 된다.
  `core/roster.gd` 는 자동 생성이라 손으로 고치지 마라 (`verify.sh` 1번이 잡는다).
- 58장 전부 다시 만들면 GPU 로 **약 65분**이다. 백그라운드로 돌려라.
- `gen_art.py` 는 흰 배경 오려내기가 실패하면(배경이 안 지워지거나 그림이 통째로
  지워지면) 끝에 `!! 눈으로 봐야 할 것` 으로 알려 준다. **조용히 넘어가지 마라.**

## 4. APK 굽기 (매번)

```bash
mkdir -p build/android && ~/.local/bin/godot --headless --path . \
    --export-debug "Android Test APK" "$PWD/build/android/pokerdefense-test.apk"
cp build/android/pokerdefense-test.apk ~/pokerdefense-test.apk
```

답변 끝에 내려받는 방법까지 적을 것:

```bash
scp dgxmaruta@<호스트>:~/pokerdefense-test.apk .
adb install -r pokerdefense-test.apk
```

- `cannot connect to daemon at tcp:5037` 은 폰이 안 붙어 있어서 나는 것이라 오류가 아니다.
  `[ DONE ] export` 와 `Signed` 가 보이면 성공.
- **APK 가 안 나오면 조용히 넘어가지 말고 왜 실패했는지 말할 것.**
- 이 머신은 aarch64 라 `use_gradle_build=false` 로만 APK 가 나온다. 스토어용 **AAB 는
  이 머신에서 안 된다.** iOS 는 Xcode 프로젝트까지만 나온다(맥이 있어야 IPA 가 된다).

## 5. 커밋

```bash
git add -A && git commit -m "..."
```

⚠ **이 저장소에는 아직 원격이 없다.** rogame 의 `origin`(DevJieung/JingIPA)은 **다른
프로젝트**이고, 거기에 밀면 그 저장소를 덮어쓴다. **절대 그러지 마라.**
GitHub 에 올리려면 사람이 먼저 저장소를 하나 만들고 알려 줘야 한다:

```bash
git remote add origin https://github.com/<사용자>/<새-저장소>.git
git push -u origin main
```

자격증명은 이미 걸려 있다 — `~/.ghtoken`(600) 의 fine-grained 토큰을 전역 git 설정의
`credential.https://github.com.helper` 가 읽어 넘긴다. 새 저장소에도 권한을 줘야 한다
(**Contents RW** 는 필수, Actions 를 쓸 거면 **Workflows RW · Actions RW** 도).

- ⚠ **토큰을 화면에 찍지 마라.** git·curl 출력은 반드시 걸러라:
  `... 2>&1 | sed 's/github_pat_[A-Za-z0-9_]*/<토큰>/g'`
- ⚠ **토큰을 `curl -H "Authorization: Bearer $T"` 로 넘기지 마라.** 프로세스 인자에 올라가
  `ps` · `pgrep -af` 로 이 머신의 누구에게나 보인다. 반드시 stdin(`curl --config -`)으로.
- 이 셸에는 터미널이 없어(`tty` 없음) **대화형 로그인이 원천적으로 불가능**하다.
  파일 기반 헬퍼가 유일한 길이다.

---

## 절대 잊으면 안 되는 것

- **`♠ ♦ ♣` 를 글자로 그리지 마라.** 번들 폰트(DinoKR = Noto Sans CJK KR Bold)에 이 셋이
  **없다**(♥ 만 있다). 글자로 그리면 카드가 통째로 두부(□)가 되고, `.import` 의
  `allow_system_fallback` 때문에 **실기기에서는 OS 폰트가 메워 줘서 눈으로는 절대 안
  잡힌다.** 무늬는 `Look.draw_suit()` 이 도형으로 그린다. `tools/check_font.py` 와
  `verify.sh` 0-1번이 이걸 지킨다.
- **`core/roster.gd` 를 손으로 고치지 마라.** 원본은 `tools/roster.json` 이고
  `tools/gen_roster.py` 가 찍어 낸다. 그림 크기(h)도 `tools/gen_art.py` 의 표에서 나오므로
  그림과 게임이 항상 같은 값을 본다.
- **밸런스 숫자를 감으로 고치지 마라.** `core/balance.gd` 를 건드렸으면
  `tests/balance_check` 를 반드시 돌려라. 몇 개는 손으로 계산할 수 없다:
  - 처음에 `CLOSE_IN_SEC = 26` 이었는데, 그러면 몬스터가 **사거리 안으로 들어오지도 못한 채**
    시간이 끝나서 1탄부터 일곱 마리가 그냥 살아 나갔다.
  - 장판(`aura`)의 피해 배수가 0.55 였을 때, 사거리 안 **모두**를 때리는 탓에 혼자
    50배를 뽑아 40탄이 그냥 깨졌다. 지금은 0.10 이다.
  - 체력 성장 지수 1.28 은 손으로 고른 값이 아니다. 1.255 는 전판 클리어, 1.30 은 전판 실패,
    1.28 이 중간값 38탄 · 12판 중 3판 클리어였다.
- **`build/` 를 저장소에 넣지 마라** (`.gitignore` 에 있다). 촬영본·로그·APK 가 쌓인다.
  반대로 **`art/` 는 넣는다** — GPU 로 다시 만들 수 있지만 한 시간이 걸린다.
- **`tools/gen_art.py` 의 화풍 앵커(`DOT`)를 가볍게 바꾸지 마라.** 후보 셋을 실제로 뽑아
  보고 고른 것이고(`build/styletest/`), 바꾸면 58장을 전부 다시 구워야 한다.
- 헤드리스 stdout 은 **블록 버퍼링**이다. 죽이거나 멈추면 여태 찍은 게 통째로 날아가서
  "실행이 아예 안 된다"로 오해하게 된다. 검사를 돌릴 때는 항상 `stdbuf -oL` 을 붙여라.
- `pkill -f "..."` 로 프로세스를 죽일 때, **그 문자열이 지금 셸의 명령줄에도 들어 있으면
  셸 자신이 죽는다**(실제로 두 번 물렸다). PID 를 먼저 찾아 `kill` 하라.
