# iOS 빌드 · 배포

Godot **4.7.1** 기준. Mac 필수 (Godot이 `xcodebuild` 를 직접 호출합니다).

---

## 두 갈래 길

| | **A. 우리 아이 아이폰에만 넣기** | **B. App Store 출시** |
|---|---|---|
| 비용 | **무료** (무료 Apple ID의 Personal Team) | Apple Developer Program **$99/년** |
| 유효기간 | 프로비저닝 프로파일이 **7일마다 만료** → Xcode에서 다시 Run | 만료 없음 |
| 제한 | 기기 3대, App ID 10개 | 없음 |
| 실제 체감 | 일주일에 한 번 Mac에 폰 연결해서 Run 한 번 | TestFlight/스토어로 자동 설치 |

아이 하나에게 보여줄 목적이면 **A로 충분합니다.**

> ⚠️ A 경로에서도 `application/app_store_team_id` 는 **반드시 채워야 합니다.**
> 비어 있으면 Godot이 `Cannot export project with preset "iOS" due to configuration errors` 로 중단합니다.
> 무료 Personal Team에도 10자리 Team ID가 있습니다:
> Xcode → Settings → Accounts → Apple ID 선택 → "Personal Team" 행에 표시됩니다.

---

## 1. Mac 준비

```bash
sw_vers                 # macOS 26(Tahoe) 이상 권장
xcodebuild -version     # ★ Xcode 26.x 이상이어야 App Store 업로드가 통과합니다
xcode-select -p         # /Applications/Xcode.app/Contents/Developer 여야 함
```

`/Library/Developer/CommandLineTools` 로 나오면 고칩니다:

```bash
sudo xcode-select -s /Applications/Xcode.app
sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch
```

> **2026-04-28부터** App Store Connect는 **Xcode 26 이상 + iOS 26 SDK** 로 빌드한 것만 받습니다.
> Command Line Tools만으로는 안 되고 **전체 Xcode.app** 이 필요합니다.

Godot 편집기와 익스포트 템플릿 설치는 [`build-android.md` 1절](build-android.md#1-mac-환경-준비-한-번만)과 동일합니다.
(템플릿 경로만 `~/Library/Application Support/Godot/export_templates/4.7.1.stable`)

---

## 2. 프로젝트에서 바꿔야 하는 값

`export_presets.cfg` 의 `[preset.2.options]`:

```
application/app_store_team_id="ABCDE12345"        ← 본인 10자리 Team ID
application/bundle_identifier="com.본인도메인역순.frogwarrior"
```

> **번들 ID 문자 제약이 안드로이드보다 엄격합니다.** `A-Z a-z 0-9 - .` 만 됩니다.
> **밑줄(`_`)이 들어가면 익스포트가 중단됩니다.** 안드로이드 패키지명을 그대로 복사할 때 주의하세요.

이미 올바르게 설정되어 있는 것들 (건드리지 마세요):

- `application/targeted_device_family=2` — **아이폰 + 아이패드.**

  > ⚠️ **여기를 `0`(아이폰 전용)으로 되돌리지 마세요.** 그러면 아이패드가 앱을
  > **아이폰 호환 모드**로 띄웁니다 — 폰 크기 창 하나가 화면 가운데에 뜨고 나머지는
  > 통째로 검은 여백이 됩니다. 실제로 그렇게 나왔습니다.
  > 이 게임의 기준 해상도가 **가로 태블릿 1280×800** 인데 정작 태블릿에서 그러면 안 됩니다.
  >
  > 확인하는 법: 익스포트한 뒤 `TARGETED_DEVICE_FAMILY` 가 `"1,2"` 여야 합니다.
  > ```bash
  > grep -a TARGETED_DEVICE_FAMILY build/ios/frogwarrior.xcodeproj/project.pbxproj | sort -u
  > ```
  >
  > 대신 **App Store 에 낼 때만** 13인치 아이패드 스크린샷 한 세트가 더 필요합니다
  > (2064 × 2752). 사이드로딩(경로 A)에는 아무 영향이 없습니다.

  배치 자체는 손댈 것이 없습니다. `stretch/aspect="expand"` + `Layout.is_wide()` 라
  11인치(1194×834)든 4:3(1024×768)이든 전부 가로 배치로 꽉 찹니다.
  화면으로 확인하려면:
  ```bash
  python3 tools/screenshot.py --res 1194x834 battle:2
  ```
- `capabilities/performance_a12=false` + `rendering_method.mobile="gl_compatibility"`
  → **iPhone 8 / X 같은 구형 기기도 설치 가능**합니다.
  ⚠️ 렌더러를 `mobile` 이나 `forward_plus` 로 바꾸면 Godot이 `iphone-ipad-minimum-performance-a12` 를
  **강제로** Info.plist에 넣어 A12 미만 기기(2018년 이전)가 전부 잘려 나갑니다.
- `shader_baker/enabled=false` — Compatibility 렌더러와 호환되지 않습니다.
- `privacy/*` — Godot이 `PrivacyInfo.xcprivacy` 를 자동 생성합니다. 손으로 쓸 필요 없습니다.
  현재 값은 "추적 없음 / 수집 데이터 없음 / 엔진이 쓰는 필수 사유 3종"으로 정확히 설정되어 있습니다.
- `icons/icon_1024x1024` 와 `storyboard/custom_image@2x/@3x`
  → **이걸 비워두면 앱 아이콘에 알파 채널이 생겨 업로드가 거부되고, 런치 화면에 Godot 로고가 뜹니다.**
  `python3 tools/gen_icons.py` 로 만들어지는 PNG를 가리키고 있으니 그대로 두세요.

---

## 3. 내보내기

```bash
mkdir -p build/ios          # ★ Godot은 출력 폴더를 만들어 주지 않습니다
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
    --export-debug "iOS" "$PWD/build/ios/frogwarrior.ipa"
echo "exit=$?"
```

파일 이름은 **공백 없는 ASCII** 로 쓰세요 — 이게 `PRODUCT_NAME` 과 Xcode 스킴 이름이 됩니다.

`application/export_project_only=false` 라서 macOS에서는 Godot이 `xcodebuild` 까지 직접 돌려
**`.ipa` 를 바로** 만들어 줍니다. Xcode 프로젝트도 `build/ios/frogwarrior.xcodeproj` 에 함께 남습니다.

---

## 4. 아이 아이폰에 설치 (경로 A)

```bash
open build/ios/frogwarrior.xcodeproj
```

1. 좌측에서 타겟 선택 → **Signing & Capabilities**
2. **Automatically manage signing** 체크
3. **Team** 에서 `본인이름 (Personal Team)` 선택
4. 아이폰을 USB로 연결하고 잠금 해제 → "이 컴퓨터를 신뢰" 탭
5. 상단 기기 목록에서 아이폰 선택 → **⌘R**

첫 실행 시 폰에서 "신뢰할 수 없는 개발자" 가 뜹니다:
**설정 → 일반 → VPN 및 기기 관리 → 본인 Apple ID → 신뢰**.

무료 Personal Team은 7일 뒤 앱이 안 열립니다. Mac에 다시 연결해 ⌘R 하면 갱신됩니다.

> Xcode 26이 "Update to recommended settings" 를 권합니다. 눌러도 빌드는 되지만,
> 다음 익스포트에서 `.xcodeproj` 가 통째로 새로 생성되므로 수동 변경은 매번 사라집니다.
> 지속적인 변경이 필요하면 `application/additional_plist_content` 를 쓰세요.

---

## 5. App Store 출시 (경로 B)

```bash
# 릴리스로 다시 내보내기 (export_method_release=0 = app-store)
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
    --export-release "iOS" "$PWD/build/ios/frogwarrior.ipa"
```

Xcode에서 아카이브하려면: 대상 기기를 **Any iOS Device (arm64)** 로 두고 **Product → Archive**,
그다음 **Window → Organizer → Distribute App → App Store Connect → Upload**.

CLI로 하려면:

```bash
xcodebuild -project build/ios/frogwarrior.xcodeproj -scheme frogwarrior \
  -sdk iphoneos -configuration Release archive \
  -archivePath build/ios/frogwarrior.xcarchive -allowProvisioningUpdates

xcodebuild -exportArchive -archivePath build/ios/frogwarrior.xcarchive \
  -exportOptionsPlist build/ios/frogwarrior/export_options.plist \
  -allowProvisioningUpdates -exportPath build/ios
```

`export_options.plist` 는 Godot이 이미 `method=app-store` 로 써 둡니다.

### App Store Connect 체크리스트 (2026)

- [ ] **개인정보처리방침 URL** — 가이드라인 5.1.1(i). 데이터를 하나도 안 모아도 **필수**입니다.
      템플릿: [`privacy-policy.md`](privacy-policy.md)
- [ ] **App Privacy** 항목: **"Data Not Collected"** 선택.
- [ ] **연령 등급 설문** (2025년 7월 개편, 등급대: 4+ / 9+ / 13+ / 16+ / 18+) → **4+**.
- [ ] **스크린샷**: 아이폰 + 아이패드라 **두 세트**입니다
      (`targeted_device_family=2` — 위 2절 참고).
      - 아이폰 6.9인치 **1320 × 2868** 세로 (1290 × 2796, 1260 × 2736 도 허용)
      - 아이패드 13인치 **2064 × 2752** 세로 (2048 × 2732 도 허용)

      **알파 채널이 있으면 거부됩니다.** 이 게임은 가로 고정이므로 세로 규격 안에
      가로 화면을 넣어 만들면 됩니다.
- [ ] **한국어** 를 기본 언어로 등록하고 한국어 이름/설명/키워드/스크린샷 제공.
- [ ] **Kids Category** 에 넣을지 결정:
      - 넣으면 → 외부 링크·구매·제3자 분석/광고가 **전부 금지**되고, 외부로 나가는 것은 모두
        **부모 관문(parental gate)** 뒤에 있어야 합니다 (가이드라인 1.3, 5.1.4).
        이 게임은 광고·결제·네트워크·분석이 전부 없어서 그대로 통과합니다.
        (게임 안의 부모 메뉴에는 이미 두 자리 곱셈 관문이 들어 있습니다.)
      - 안 넣으면 → 앱 이름·부제·아이콘·스크린샷·설명에 "For Kids / 어린이용" 같은
        **아동 대상임을 암시하는 표현을 쓰면 안 됩니다** (가이드라인 2.3.8).

---

## 6. 함정 모음

| 증상 | 원인 / 해결 |
|---|---|
| 아이콘에 알파 채널이 있다며 업로드 거부 | `icons/icon_1024x1024` 를 비워 두면 `icon.svg` 에서 RGBA로 생성됩니다. `tools/gen_icons.py` 가 만든 **RGB(알파 없음)** PNG를 쓰세요 |
| 실행 시 Godot 로고가 뜸 | `storyboard/custom_image@2x` **와** `@3x` **둘 다** 채워야 합니다. 하나라도 비면 내장 Godot 로고로 대체됩니다 |
| `Cannot export project ... configuration errors` | `app_store_team_id` 가 비어 있음 |
| 번들 ID 거부 | 밑줄(`_`) 사용 |
| `Target folder does not exist` | `mkdir -p build/ios` 를 안 함 |
| 구형 아이폰에 설치가 안 됨 | 렌더러를 `mobile` 로 바꿔 A12 요구가 주입됨 |
| 프로비저닝 UUID를 넣었더니 서명이 꼬임 | UUID를 넣는 순간 `CODE_SIGN_STYLE` 이 Manual로 바뀝니다. 자동 서명을 쓰려면 비워 두세요 |
| 비트코드 설정을 찾는데 없음 | 이미 없어졌습니다. Godot이 `ENABLE_BITCODE = NO` 로 생성합니다. 3.x 시절 문서 무시 |
