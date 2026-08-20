# 공룡 찾기 — 설계 규칙 (합치기 전의 CLAUDE.md)

> **이 문서는 합치기 전 `dino` 저장소의 CLAUDE.md 다.**
> 게임 안의 규칙(아이용 기본값·가림 정도·공룡 그림·글꼴)은 **여전히 전부 유효하다.**
> 다만 아래는 통합하면서 바뀌었으니, 이 문서를 읽을 때 같이 기억할 것:
>
> | 이 문서에 적힌 것 | 지금은 |
> |---|---|
> | `scripts/`, `assets/dinos/`, `fonts/` | `games/dino/scripts/`, `games/dino/dinos/`, `core/fonts/` |
> | `tools/render_preview.py` 등 | `tools/dino/` 아래로 |
> | `godot --headless -- --dump` | `godot --headless --path . res://tests/dino_dump.tscn -- --dump` |
> | 저장 `user://dino_save.cfg` | `Shell` 이 소유하는 `user://rogame_save.json` 의 프로필별 칸 |
> | 가림 28~74% 고정 | 유효탄에 따라 움직이는 밴드 (`Rooms.band()`), 절대 한계 26~86% |
> | 공룡 수 상한 5 | 프로필별 3~6 (미취학 2~3) |
> | 힌트 12초 고정 | 프로필별 13→8초 / 미취학 8초 고정 |
> | 소리 버튼(놀이 화면) | 없앴다 — 설정은 부모 화면에서만 |
> | "처음으로" 버튼 | "집으로" (허브) |
>
> 전체 설명은 저장소 뿌리의 [`../CLAUDE.md`](../CLAUDE.md) 와
> [`architecture.md`](architecture.md).

---

**공룡을 찾아라!** — 아주 어린 아이(우리 애기)용 공룡 찾기 게임. Godot 4.7.1.
1~6탄은 손으로 꾸민 우리 집, **7탄부터는 방을 자동으로 만들어 내서 끝이 없습니다.**
전체 설명은 [`README.md`](README.md).

## 작업을 마칠 때 (매번, 빠짐없이)

**절차 전체는 [`WRAPUP.md`](WRAPUP.md) 에 있습니다. 그대로 따르세요.**
요약: 미리보기 → `--selftest` → iOS 익스포트 확인 → **APK 굽기** → **커밋 & `git push`**.
`git push` 는 다시 묻지 말고 하세요 — `WRAPUP.md` 가 그 허락입니다.
단, 검증이 하나라도 깨졌으면 push 하지 말고 보고하세요.

**안드로이드 테스트용 APK 를 새로 만들고, 어디에 만들어졌는지 답변에 적어 주세요.**
고친 걸 아이가 바로 폰에서 눌러 볼 수 있어야 합니다.

```bash
mkdir -p build/android && ~/.local/bin/godot --headless --path . \
    --export-debug "Android Test APK" "$PWD/build/android/dinofind-test.apk"
cp build/android/dinofind-test.apk ~/dinofind-test.apk
```

그리고 답변 끝에 내려받는 방법까지 알려주세요:

```bash
scp dgxmaruta@<호스트>:~/dinofind-test.apk .
adb install -r dinofind-test.apk
```

- 화면에 보이는 걸 고쳤으면 APK 를 만들기 전에 **미리보기 그림도 새로 뽑으세요**
  (`godot --headless -- --dump && python3 tools/render_preview.py`).
- **APK 가 안 나오면 조용히 넘어가지 말고 왜 실패했는지 말해 주세요.**
- 익스포트 끝의 `cannot connect to daemon at tcp:5037` 은 폰이 안 붙어 있어서 나는 것이라
  오류가 아닙니다. `[ DONE ] export` 와 `Signed` 가 보이면 성공입니다.

## 자주 쓰는 명령

```bash
~/.local/bin/godot --path .                        # 게임 실행 (이 머신에선 화면이 없어 안 됨)
~/.local/bin/godot -e --path .                     # 편집기
~/.local/bin/godot --headless --import             # 애셋 임포트만

~/.local/bin/godot --headless -- --selftest        # 30탄까지 자동 플레이 (로직 검증, 약 18초)
~/.local/bin/godot --headless -- --dump            # 화면 구성 JSON + 1~6탄 검사 + 7~200탄 검사
python3 tools/render_preview.py                    # 그 JSON 을 PNG 로 (-> preview/, android_icons/)
~/.local/bin/godot --headless -- --dump --boxes    # 클릭 판정 네모까지 그려서 확인

python3 tools/gen_dinos.py --list                  # 공룡 50종 목록
python3 tools/gen_dinos.py                         # 없는 공룡 그림만 생성 (GPU, 종당 약 1분)
python3 tools/gen_dinos.py --only trex --force     # 마음에 안 드는 것만 다시
python3 tools/check_species.py                     # 공룡 목록 두 곳이 어긋나지 않았는지
```

`--selftest` 는 5초 안에 끝납니다 — 자동 테스트일 때만 `_slow = 0.12` 로 연출 길이를 줄입니다
(headless 는 프레임 제한이 없어서, 실제 초 단위 대기가 프레임을 엄청나게 먹습니다).
연출 시간을 새로 넣을 때는 **반드시 `* _slow` 를 곱하세요.**

## 이 머신(aarch64, 화면 없음)에서 알아둘 것

- **화면이 없습니다.** `DISPLAY` 가 비어 있고 Xvfb 도 없어서 게임 창을 띄우거나
  스크린샷을 찍을 수 없습니다. `--headless` 는 더미 렌더러라 `RenderingServer.frame_post_draw`
  가 오지 않아 그대로 멈춥니다.
- **대신 `--dump` + `tools/render_preview.py` 로 화면을 봅니다.** 그리기 명령을 JSON 으로
  기록해서 Pillow 로 다시 그리는 방식입니다. 그래서 그리기 코드는 `_draw()` 안에 두지 말고
  `_paint(ci)` 로 빼서, 실제 CanvasItem 대신 `tools/recorder.gd` 에도 그릴 수 있게 유지하세요.
- **APK 는 `use_gradle_build=false` 라서 만들어집니다.** 미리 구운 템플릿에 프로젝트만 밀어
  넣고 `zipalign`/`apksigner` 만 쓰므로 x86_64 전용인 `aapt2` 를 안 탑니다.
  (`~/Android/Sdk/build-tools/35.0.0/zipalign` 은 우분투 arm64 바이너리를 부르는 스크립트입니다.)
  스토어용 **AAB 는 이 머신에서 안 됩니다.**
- **iOS 는 여기서 Xcode 프로젝트까지만 나옵니다.** `--export-release "iOS" .../dinofind.ipa`
  를 돌리면 `build/ios/dinofind.xcodeproj` 가 생기고 `.ipa 는 macOS 에서만` 경고가 뜹니다
  (정상, 종료 코드 0). IPA 로 굽는 일은 GitHub Actions 가 합니다 —
  `.github/workflows/ios.yml` 은 **우분투에서 Xcode 프로젝트를 만들어 맥으로 넘겨
  `xcodebuild` 만 시킵니다.** 맥에서 Godot 익스포트를 그냥 돌리면 인증서 없는 CI 에서
  실패합니다(4.7 의 dylib 코드사이닝이 `export_project_only` 검사보다 앞에 있음).
  사람이 할 일은 [`ios-signing.md`](ios-signing.md).
- **`project.godot` 의 `textures/vram_compression/import_etc2_astc=true` 를 지우지 마세요.**
  이게 없으면 Godot 이 CPU 종류로 대신 판단해서, 이 arm 머신에선 폰용 익스포트가 되지만
  x86_64 (GitHub Actions 우분투 러너)에선 **오류 메시지도 없이** 거부합니다.
  익스포트 옵션을 고쳤으면 위 명령으로 **Xcode 프로젝트가 나오는지까지는 꼭 확인**하세요.

## 게임을 고칠 때 지켜야 할 것

- **아이용 기본값을 깨지 마세요**: 한국어 UI, 탭 하나로 되는 조작, 실패·점수·시간제한 없음,
  틀려도 벌 대신 귀여운 반응, 큰 글씨/큰 버튼. 어른용(소리 끄기·처음으로·F11)은 구석에 작게.
- **숨는 자리를 옮겼으면 `--dump` 의 가림 % 를 확인하세요.** 28% 미만이면 너무 잘 보이고,
  74% 초과면 아이가 못 찾습니다. 벗어나면 `!!` 가 찍힙니다.
- **`--dump` 는 자동 생성 방 7~200탄을 각 3회씩(582개) 만들어 검사합니다.** `room_gen.gd` 의
  가구 목록·크기·테마를 건드렸으면 반드시 이 줄이 "자리부족 0건, 가림이상 0건" 인지 보세요.
  숨을 자리가 모자란 방이 나오면 그 탄에서 공룡 수가 줄어들 뿐 게임이 멈추지는 않습니다.
- **공룡끼리 겹치지 않게** — `game.gd` 의 `_pick_spots()` 가 175px 이상 떨어진 자리만 고릅니다.
- 기록은 `user://dino_save.cfg` 에 저장됩니다(최고 탄, 여태 찾은 공룡 수).
- **방·가구·효과음은 코드로 만듭니다**(`room_bg.gd`, `prop.gd`, `sfx.gd`). 손으로 그린
  그림 파일을 새로 넣지 마세요 — 미리보기 렌더러로 검증할 수 없게 됩니다.
- **공룡 그림은 "실제 공룡의 피규어" 화풍입니다**(`assets/dinos/*.png`, Krea 2 생성, 높이 420px).
  만화체로 바꾸지 마세요 — 종끼리 구분이 안 돼서 일부러 바꾼 것입니다. 예전 만화체 그림은
  `.art_cartoon/` 에 남겨 뒀습니다(점으로 시작해서 Godot 이 무시합니다).
  종을 늘리거나 바꿀 때는 `tools/gen_dinos.py` 의 `DINOS` 와 `scripts/dino_species.gd` 의
  `LIST` 를 **둘 다 같은 순서로** 고치고 **`python3 tools/check_species.py` 로 확인**하세요.
  그림이 없으면 `dino_art.gd` 손그림으로 자동 대체되므로 게임은 그래도 돌아갑니다.
- **이름이 길어지면 카드 밖으로 나갑니다.** 9자(파키케팔로사우루스)까지는 들어갑니다.
  더 긴 이름을 넣었다면 `--dump` 의 "카드 이름 최대폭" 줄을 확인하세요.
- 한글 글꼴은 `fonts/DinoKR.ttf` (Noto Sans CJK KR Bold 서브셋). 한글 음절 전체가 들어 있어
  새 문구를 넣어도 글자가 깨지지 않습니다.
