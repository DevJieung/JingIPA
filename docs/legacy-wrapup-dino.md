# 갈무리 지침 — 게임 고치는 일이 끝날 때마다

작업이 끝나면 **Claude 가 여기 적힌 절차를 그대로** 밟습니다.
형은 맨 아래 [5. 여기서부터는 형 몫](#5-여기서부터는-형-몫) 부터 이어받으면 됩니다.

| 누가 | 무엇을 |
| --- | --- |
| **Claude** | 검증 → 미리보기 → **APK 굽기** → 커밋 → **`git push` 까지** |
| **형** | Actions 에서 **Run workflow** → IPA 내려받기 → AltStore/Sideloadly 로 폰에 설치 |

> **push 는 다시 묻지 말고 하세요.** 이 문서가 그 허락입니다.
> 단 아래 (1)~(4) 가 전부 통과한 뒤에만입니다. 하나라도 깨졌으면 **push 하지 말고 보고**하세요.

---

## 1. 복붙 한 덩어리

```bash

# (1) 화면에 보이는 것이 바뀌었으면 미리보기부터
~/.local/bin/godot --headless -- --dump && python3 tools/render_preview.py

# (2) 로직 확인 — 30탄까지 자동 플레이 (약 18초)
~/.local/bin/godot --headless -- --selftest

# (3) 아이폰 쪽이 안 깨졌는지 — Xcode 프로젝트까지 나오면 통과
rm -rf build/ios && mkdir -p build/ios
~/.local/bin/godot --headless --path . --export-release "iOS" "$PWD/build/ios/dinofind.ipa"
test -d build/ios/dinofind.xcodeproj || echo "!! iOS 익스포트 깨짐 — push 금지"

# (4) 안드로이드 테스트 APK
mkdir -p build/android
~/.local/bin/godot --headless --path . --export-debug "Android Test APK" \
    "$PWD/build/android/dinofind-test.apk"
cp build/android/dinofind-test.apk ~/dinofind-test.apk

# (5) 푸시
git add -A
git commit -m "무엇을 왜 고쳤는지 한 줄"
git push
```

그리고 **답변 끝에 반드시** 적을 것:

- APK 가 어디에 생겼는지 (`~/~~.apk`, 크기)
- 내려받는 방법
  ```bash
  scp dgxmaruta@100.106.187.127:~/~~.apk .
  adb install -r ~~.apk
  ```
- 푸시했으니 **Actions → iOS IPA 만들기 → Run workflow** 를 누르면 된다는 안내

---

## 2. 단계마다 지켜볼 것

| 단계 | 통과 기준 | 어긋나면 |
| --- | --- | --- |
| (1) `--dump` | 가림 **28~74%**, 자동 생성 방 "자리부족 0건, 가림이상 0건" | `!!` 가 찍힌 자리를 고치기 전엔 커밋 금지 |
| (2) `--selftest` | `자동 테스트: 30탄까지 진행 …` 이 나오고 `ERROR` 없음 | 오류 그대로 보고 |
| (3) iOS | **종료 코드 0** + `build/ios/dinofind.xcodeproj` 생성 | 아래 3번 지뢰 점검 |
| (4) APK | `Signed` 와 `[ DONE ] export` | **조용히 넘어가지 말고 왜 실패했는지 말할 것** |

- iOS 익스포트 끝의 `.ipa 는 macOS 에서만 빌드할 수 있습니다` 경고는 **정상**입니다.
  이 머신은 Xcode 프로젝트까지만 만들고, IPA 는 GitHub 의 맥이 굽습니다.
- APK 익스포트 끝의 `cannot connect to daemon at tcp:5037` 은 **폰이 안 꽂혀 있어서** 나는 것이라
  오류가 아닙니다.
- 화면에 보이는 것을 안 건드렸으면 (1) 은 건너뛰어도 되지만, **(2)(3)(4) 는 매번** 합니다.
  프로젝트 파일을 하나도 안 고친 턴이라면 APK 를 다시 굽지 말고 "지난번 것이 그대로 최신"
  이라고만 적으세요.

---

## 3. 푸시 전 지뢰 점검

이 값들이 사라지면 **CI 가 오류 문구도 없이** 죽습니다. 한 줄로 확인하세요.

```bash
grep -E 'import_etc2_astc|config/name\.ios' project.godot
grep -E 'export_project_only|app_store_team_id|bundle_identifier' export_presets.cfg
```

| 있어야 하는 값 | 없으면 벌어지는 일 |
| --- | --- |
| `project.godot` : `textures/vram_compression/import_etc2_astc=true` | Godot 이 CPU 로 대신 판단 → **x86_64 러너에서 빈 메시지로 거부** (이 머신은 arm 이라 여기선 잘 됨) |
| `project.godot` : `config/name.ios="DinoFind"` | 앱 표시 이름이 한글 그대로 → 무료 서명 시 **AltStore/Sideloadly 가 App ID 를 못 만듦** |
| `export_presets.cfg` : `application/export_project_only=true` | 맥 러너에서 Godot 이 `xcodebuild` 를 직접 돌리려다 실패 |
| `export_presets.cfg` : `application/app_store_team_id="0000000000"` | 비면 `App Store Team ID not specified` 로 익스포트 거부 (자리표시자라도 필요) |
| `export_presets.cfg` : `application/bundle_identifier="com.example.dinofind"` | 저장소 Variables 의 `IOS_BUNDLE_ID` 가 덮어씁니다. 비워 두지 말 것 |

`.github/workflows/ios.yml` 의 **두 단계 구조(우분투에서 Xcode 프로젝트 → 맥에서 `xcodebuild`)**
도 그대로 두세요. 맥에서 Godot 익스포트를 직접 돌리면 맥에만 있는 dylib 코드사이닝 구간을
지나야 하고(인증서 없는 CI 에선 위험), 무엇보다 맥 러너는 **분당 10배**로 과금됩니다.

---

## 4. 커밋과 푸시

```bash
git config user.name  "DevJieung"
git config user.email "drpepper1219@gmail.com"
git remote -v          # https://github.com/DevJieung/JingIPA.git 이어야 한다
```

리모트가 다르면:

```bash
git remote set-url origin https://github.com/DevJieung/JingIPA.git
```

- 커밋 메시지는 **한국어 한 줄**로, "무엇을 왜" 가 보이게. (예: `아이폰에서는 영문 이름 사용 (무료 서명이 한글 앱 이름을 못 받음)`)
- `build/`, `.godot/` 은 `.gitignore` 로 빠지니 `git add -A` 해도 안전합니다.
- HTTPS 푸시라 처음 한 번은 GitHub 토큰(PAT)을 물어봅니다. 그건 형이 넣어야 합니다.
- **브랜치는 `main` 하나**만 씁니다.

---

## 5. 여기서부터는 형 몫

1. 저장소 → **Actions** 탭 → 왼쪽 **iOS IPA 만들기** → 오른쪽 **Run workflow** (Branch: `main`)
   - ⚠️ **"Re-run jobs" 는 누르지 마세요.** 그건 **옛날 커밋**을 그대로 다시 돌립니다.
     새 코드로 굽고 싶으면 반드시 **Run workflow**.
2. 10분쯤 뒤 실행 화면 **맨 아래 Artifacts** → `dinofind-ipa-N` → zip 내려받아 압축 풀기
3. 맥에서 **Sideloadly** 또는 **AltStore** 로 서명해서 설치
   ([`IOS.md`](IOS.md) 3단계-ⓐ 에 순서가 있습니다)
4. 폰에서 **설정 → 일반 → VPN 및 기기 관리 → 애플 ID → 신뢰**
5. 무료 서명은 **7일**마다 다시 넣어야 합니다. 기록은 안 지워집니다.

---

## 6. CI 가 실패하면 (Claude 용 진단 순서)

로그 본문은 저장소 admin 권한이 있어야 API 로 받을 수 있습니다(익명 403).
그래서 순서가 정해져 있습니다.

1. 형에게 **실행 URL** 을 받는다.
2. 어느 단계에서 죽었는지는 익명으로도 보인다:
   ```bash
   curl -s "https://api.github.com/repos/DevJieung/JingIPA/actions/runs/<런ID>/jobs" | python3 -c "
   import json,sys
   for j in json.load(sys.stdin)['jobs']:
       print(j['name'], j['conclusion'])
       for s in j['steps']: print(' ', s['number'], s['conclusion'], s['name'])"
   ```
3. `xcodebuild` 단계라면 워크플로가 **실행 화면 Summary 에 `error:` 줄과 마지막 60줄**을
   찍어 둡니다. Summary 는 퍼블릭 저장소면 익명으로도 읽힙니다.
4. 그래도 모자라면 그 단계 로그를 붙여 달라고 한다.
5. 어떤 커밋으로 돌았는지 꼭 확인한다 (`head_sha`). 옛 커밋 재시도인 경우가 잦습니다.
   ```bash
   curl -s "https://api.github.com/repos/DevJieung/JingIPA/actions/runs?per_page=5" | python3 -c "
   import json,sys
   for r in json.load(sys.stdin)['workflow_runs']:
       print('#%s attempt=%s %s %s' % (r['run_number'], r['run_attempt'], r['conclusion'], r['head_sha'][:8]))"
   ```
6. Godot 쪽이 의심되면 **소스를 직접 확인**한다. 추측보다 빠릅니다.
   ```
   https://raw.githubusercontent.com/godotengine/godot/4.7.1-stable/editor/export/editor_export_platform_apple_embedded.cpp
   ```

---

## 7. 이미 밟은 지뢰 (같은 데 두 번 빠지지 말 것)

| 증상 | 진짜 원인 | 해결 |
| --- | --- | --- |
| `configuration errors:` 뒤가 **비어 있음** | `should_import_etc2_astc()` 가 프로젝트 설정이 없으면 **호스트 CPU** 로 판단. arm=통과, x86_64 러너=거부. 그런데 실패 메시지를 안 붙임 | `project.godot` 에 `textures/vram_compression/import_etc2_astc=true` |
| 맥 러너에서도 같은 빈 오류 | `OS_MacOS::get_preferred_texture_format()` 는 애플 실리콘에서도 **S3TC** 를 답함 | 위와 같음 |
| AltStore 가 앱 이름에서 오류 | 애플은 App ID 이름에 **영문·숫자만** 허용. "공룡을 찾아라!" 는 한글+띄어쓰기+`!` | `project.godot` 에 `config/name.ios="DinoFind"` (안드로이드·PC 는 한글 그대로) |
| 고쳤는데 CI 결과가 그대로 | **Re-run jobs** 는 옛 커밋을 다시 돌림 | 반드시 **Run workflow** |
| `App Store Team ID not specified` | 팀 ID 가 비면 익스포트 자체를 거부 | 자리표시자 `"0000000000"` 유지, 실제 값은 CI 가 Secrets 로 덮어씀 |
| `.ipa 는 macOS 에서만` 경고 | 리눅스에선 원래 Xcode 프로젝트까지만 만듦 | **정상.** 종료 코드 0 이면 성공 |
| `cannot connect to daemon at tcp:5037` | 폰이 안 꽂혀 있음 | **정상.** 오류 아님 |
| 익스포트 로그가 안 보임 | Actions 로그 API 는 admin 권한 필요 | Summary 를 읽거나 형에게 붙여 달라고 함 |
