# 안드로이드 빌드 · 배포

Godot **4.7.1** 기준. 모든 값은 4.7.1 소스(`platform/android/export/export_plugin.cpp`)와
실제 실행으로 확인한 것이며, 공식 문서보다 최신입니다.

> ⚠️ 공식 Godot 문서(4.7/master)는 Build-Tools 35.0.1 / Platform 35 / NDK r28b 로 적혀 있지만,
> 4.7.1 소스의 `platform/android/java/app/config.gradle` 은 **build-tools 36.1.0 / compileSdk 36 / targetSdk 36** 을 요구합니다.
> 문서를 그대로 따르면 빌드가 깨집니다.

---

## 0. 어디서 빌드할 것인가

| 작업 | 이 PC (Ubuntu ARM64) | Mac |
|---|---|---|
| GDScript 작성 · 편집기로 플레이 | ✅ | ✅ |
| 헤드리스 테스트 | ✅ | ✅ |
| **테스트 APK** 만들기 | ✅ (아래 0-1 한 번만) | ✅ |
| 스토어용 **AAB** 만들기 | ❌ | ✅ |
| 만들어진 APK를 폰에 설치 | ✅ (`adb`) | ✅ |

**AAB가 안 되는 이유**: 구글은 Android SDK build-tools, 특히 AGP가 리소스 컴파일마다 호출하는
**`aapt2` 를 x86_64 리눅스 바이너리로만** 배포합니다. aarch64 빌드가 없습니다.
AAB(와 커스텀 gradle 빌드)는 반드시 이 경로를 지나므로 이 PC에서는 막힙니다.

**테스트 APK는 됩니다.** `gradle_build/use_gradle_build=false` 인 "Android Test APK" 프리셋은
Godot이 **미리 구워 둔 `android_debug.apk` 템플릿에 프로젝트를 밀어 넣고** `zipalign` → `apksigner`
만 돌립니다 — `aapt2` 를 한 번도 부르지 않습니다. 그리고 그 세 도구(`zipalign`·`apksigner`·`adb`)는
우분투 저장소에 **arm64 네이티브**로 있습니다.

### 0-1. 이 PC에서 APK를 만들 준비 (한 번만, sudo 불필요)

```bash
python3 tools/setup_android_arm64.py     # 상태 확인은 --check
```

`.deb` 를 내려받아 **설치가 아니라 풀어서** `~/Android/Sdk` 를 Godot이 찾는 모양으로 흉내 냅니다
(그래서 sudo가 필요 없습니다). 디버그 키스토어도 없으면 만들어 줍니다.
스크립트가 마지막에 찍어 주는 값 세 개를 Godot 편집기 설정에 넣으세요
(`~/.config/godot/editor_settings-4.7.tres` 를 직접 고쳐도 됩니다):

```
export/android/android_sdk_path = "/home/<사용자>/Android/Sdk"
export/android/java_sdk_path    = "/usr/lib/jvm/java-8-openjdk-arm64"
export/android/debug_keystore   = "/home/<사용자>/.local/share/godot/keystores/debug.keystore"
export/android/debug_keystore_pass = "android"
```

그다음:

```bash
mkdir -p build/android
~/.local/bin/godot --headless --path . \
    --export-debug "Android Test APK" "$PWD/build/android/frogwarrior-test.apk"
echo "exit=$?"     # 반드시 0
```

**함정**: `java_sdk_path` 가 비어 있으면 `올바른 Java SDK 경로가 필요합니다`,
`platform-tools/adb` 가 없으면 `'platform-tools' 디렉터리가 누락되어 있습니다` 로 막힙니다.
adb는 실제로 쓰지 않아도 **설정 검사를 통과하려면 있어야** 합니다.
익스포트 끝에 나오는 `cannot connect to daemon at tcp:5037` 은 폰이 안 붙어 있어서 나는 것이고 오류가 아닙니다.

우분투 저장소의 `android-sdk-build-tools`(29.0.3)를 gradle 빌드에 쓰면 안 됩니다 — 요구 버전(36.1.0)과 너무 멉니다.
위 방법은 gradle을 아예 지나가지 않으므로 버전이 문제되지 않습니다.

---

## 1. Mac 환경 준비 (한 번만)

```bash
# JDK 17 (Godot 4.7 이 요구하는 버전)
brew install --cask temurin@17
/usr/libexec/java_home -v 17          # 경로 확인 → 나중에 Godot 설정에 넣는다

# Android 커맨드라인 도구
brew install --cask android-commandlinetools
export ANDROID_SDK="$HOME/Library/Android/sdk"
sdkmanager --sdk_root="$ANDROID_SDK" \
  "platform-tools" "build-tools;36.1.0" "platforms;android-36" "cmdline-tools;latest"
sdkmanager --sdk_root="$ANDROID_SDK" --licenses     # 전부 y
```

NDK는 **필요 없습니다**. Godot의 gradle 템플릿은 미리 빌드된 `godot-lib.aar` 를 링크할 뿐
C++ 컴파일을 하지 않습니다 (`externalNativeBuild` 블록 자체가 없습니다).

```bash
# Godot 4.7.1 편집기 + 익스포트 템플릿
cd ~/Downloads
curl -LO https://github.com/godotengine/godot-builds/releases/download/4.7.1-stable/Godot_v4.7.1-stable_macos.universal.zip
unzip -q Godot_v4.7.1-stable_macos.universal.zip && mv Godot.app /Applications/
xattr -dr com.apple.quarantine /Applications/Godot.app

curl -LO https://github.com/godotengine/godot-builds/releases/download/4.7.1-stable/Godot_v4.7.1-stable_export_templates.tpz
mkdir -p "$HOME/Library/Application Support/Godot/export_templates"
unzip -q Godot_v4.7.1-stable_export_templates.tpz -d /tmp/gdt
mv /tmp/gdt/templates "$HOME/Library/Application Support/Godot/export_templates/4.7.1.stable"
cat "$HOME/Library/Application Support/Godot/export_templates/4.7.1.stable/version.txt"   # 4.7.1.stable 이어야 함
```

### Godot 편집기 설정 (여기서 자주 막힙니다)

편집기 → **Editor Settings → Export → Android**:

| 키 | 값 |
|---|---|
| `export/android/android_sdk_path` | `~/Library/Android/sdk` |
| `export/android/java_sdk_path` | `/usr/libexec/java_home -v 17` 이 알려준 경로 |

> **함정**: `java_sdk_path` 가 비어 있으면 Godot은 keytool 경로를 상대경로 `bin/keytool` 로 만들고,
> 디버그 키스토어 자동 생성이 **아무 오류 없이 조용히 실패**합니다. 나중에 알 수 없는 서명 실패로 나타납니다.
> 반드시 먼저 채우세요.

---

## 2. 프로젝트에서 바꿔야 하는 값

`export_presets.cfg` 에서 **`com.example.frogwarrior` 두 곳**을 본인 것으로 바꾸세요.
Google Play는 `com.example.*` 패키지를 **거부**합니다.

```
package/unique_name="com.본인도메인역순.frogwarrior"
```

버전을 올릴 때마다 두 프리셋 모두에서:

```
version/code=2          ; 업로드마다 반드시 증가
version/name="0.2.0"
```

---

## 3. 아이 폰에 테스트 APK 넣기 (가장 빠른 길)

AAB도, gradle도, 릴리스 키스토어도 필요 없습니다.
**이 PC(리눅스 ARM64)에서도 됩니다** — 0-1 을 한 번 해 두었다면 `godot` 만 바꿔 쓰세요.

```bash
mkdir -p build/android
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
    --export-debug "Android Test APK" "$PWD/build/android/frogwarrior-test.apk"
echo "exit=$?"     # 반드시 0
```

폰에서 개발자 옵션 켜기(설정 → 휴대전화 정보 → 빌드번호 7번 탭) → USB 디버깅 → 연결 → RSA 허용:

```bash
adb install -r build/android/frogwarrior-test.apk
```

**이 PC(리눅스 ARM64)에서 설치해도 됩니다.** `adb`는 만들어진 APK를 밀어넣기만 하므로 aapt2가 필요 없습니다:

```bash
sudo apt install adb
adb install -r frogwarrior-test.apk
```

더 빠른 반복: Mac의 Godot 편집기에서 폰을 연결한 채 상단 툴바의 **원클릭 배포(휴대폰 아이콘)** 를 누르면
빌드·설치·실행이 한 번에 됩니다.

---

## 4. 스토어용 AAB 만들기

### 4-1. 릴리스 키스토어 (한 번만, 절대 잃어버리면 안 됨)

```bash
keytool -genkeypair -v \
  -keystore ~/keys/frogwarrior-release.keystore \
  -alias frogwarrior -keyalg RSA -keysize 2048 -validity 10000 \
  -storetype PKCS12
```

- **키스토어 비밀번호와 키 비밀번호를 반드시 같게** 하세요. Godot의 서명은 다르면 이상하게 실패합니다.
- 이 파일과 비밀번호를 백업하세요. 잃으면 앱을 업데이트할 수 없습니다
  (Play App Signing 덕에 업로드 키 재발급은 가능하지만 절차가 번거롭습니다).
- `.keystore` 는 **절대 git에 넣지 마세요**.

편집기 → **Project → Export → Android Store AAB → Encryption 아래 Keystore** 항목에
Release 경로 / 사용자(alias) / 비밀번호를 넣습니다.
셋 중 일부만 채우면 하드 에러입니다 — 전부 채우거나 전부 비우거나 둘 중 하나입니다.

> 이 비밀번호들은 `export_presets.cfg` 에 저장되지 **않습니다**. Godot 4.7은 `PROPERTY_USAGE_SECRET`
> 옵션을 `res://.godot/export_credentials.cfg` 로 분리해 저장하고, `.godot/` 는 이미 `.gitignore` 대상입니다.
> 그래서 `export_presets.cfg` 는 안심하고 커밋해도 됩니다.

CI에서는 파일 대신 환경변수를 쓸 수 있습니다:
`GODOT_ANDROID_KEYSTORE_RELEASE_PATH` / `_USER` / `_PASSWORD`
(디버그용은 `GODOT_ANDROID_KEYSTORE_DEBUG_*`).

### 4-2. Android 빌드 템플릿 설치 (AAB에 필수)

편집기 → **Project → Install Android Build Template**
또는 CLI:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --install-android-build-template
```

`res://android/` 폴더가 생깁니다. 이 폴더는 `.gitignore` 에 들어 있습니다(재생성 가능).

### 4-3. 내보내기

```bash
mkdir -p build/android
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
    --export-release "Android Store AAB" "$PWD/build/android/frogwarrior.aab"
echo "exit=$?"
```

**확인할 것**: 종료 코드가 0이고, 출력에 `ERROR:` 가 없고, `.aab` 파일이 실제로 생겼는지.
(과거 Godot 버전은 실패해도 0을 반환한 적이 있습니다. 4.7.1은 설정 오류 시 1을 반환하는 걸 확인했지만,
CI에서는 세 가지를 모두 검사하세요.)

**자주 나는 오류**
- `"Export AAB" is only valid when "Use Gradle Build" is enabled` → 4-2를 안 했습니다.
- `Invalid filename! Android App Bundle requires the *.aab extension` → 출력 경로 확장자.
- `프로젝트에 Android 빌드 템플릿을 설치하지 않았습니다` → 4-2를 안 했습니다.

---

## 5. Google Play 등록 (2026년 기준)

체크리스트:

- [ ] **등록비 US$25** (1회) + 개인 계정 본인 확인.
- [ ] **targetSdk 36 (Android 16)** — 2026-08-31부터 모든 신규 앱/업데이트에 필수.
      Godot 4.7.1은 이미 36이 기본이라 그대로 두면 됩니다.
- [ ] **AAB 필수** (신규 앱). APK는 사이드로드/테스트용으로만.
- [ ] **64비트(arm64-v8a) 필수.** 프리셋이 이미 arm64-v8a + x86_64 로 되어 있습니다.
- [ ] **16 KB 페이지 정렬** — 2025-11-01부터 시행(2026-05-31로 유예 후 현재 완전 적용).
      Godot 4.7.1의 gradle 경로는 NDK 29 기반이라 준수합니다.
- [ ] **Play App Signing** — 업로드 키로 서명한 AAB를 올리면 구글이 다시 서명합니다.
- [ ] ★ **비공개 테스트 12명 / 14일** — 2023-11-13 이후 만든 **개인(비법인) 계정**은
      프로덕션 승인 전에 테스터 12명이 14일 연속 참여한 비공개 테스트를 마쳐야 합니다.
      **미리 계획하세요.** 가족·친척 계정을 모으면 됩니다.
- [ ] **Target Audience and Content** 에서 대상 연령대를 "만 5~8세"로 신고.
      아동 대상 앱은 **개인정보처리방침 URL이 필수**입니다 → `docs/privacy-policy.md` 참고.
- [ ] **Data Safety** 양식: 이 게임은 수집하는 데이터가 0이므로 전부 "수집 안 함".
      (권한 0개, 네트워크 0개, 분석 도구 0개, 광고 0개 — 프리셋이 이미 그렇게 되어 있습니다.)
- [ ] 한국 출시 시 IARC 설문이 **GRAC(게임물관리위원회)** 로 연결됩니다.
      단순 산수 퀴즈는 문제없이 **전체이용가**로 나옵니다.

**강력 권장**: 광고·분석·네트워크 권한을 앞으로도 넣지 마세요. 아동 대상 앱에 그것들이 들어가는 순간
Families 정책 심사, COPPA/개인정보 신고, 데이터 안전성 양식이 전부 복잡해집니다.

---

## 6. 자주 겪는 함정 모음

| 증상 | 원인 |
|---|---|
| 디버그 키스토어가 조용히 안 만들어짐 | `export/android/java_sdk_path` 가 비어 있음 |
| 서명 실패 | 키스토어 비밀번호 ≠ 키 비밀번호 |
| gradle 빌드가 aapt2에서 죽음 (리눅스 ARM64) | 구조적으로 불가능. Mac/x86_64에서 빌드 |
| `.godot/` 를 커밋함 | `export_credentials.cfg`(비밀번호)가 그 안에 있습니다. 즉시 되돌리세요 |
| `*.uid` 를 gitignore 함 | ❌ 하지 마세요. Godot 4.4+ 가 리소스 참조에 씁니다 |
| 익스포트가 편집기 바이너리가 아닌 템플릿으로 안 됨 | `--export-*` 는 편집기 전용 플래그입니다 |
