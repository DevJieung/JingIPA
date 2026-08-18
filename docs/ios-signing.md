# 아이폰/아이패드에 넣기 — GitHub Actions 로 IPA 만들기

맥이 없어도 됩니다. 이 저장소를 GitHub 에 올리면, GitHub 이 빌려주는 **맥 머신**이
`.github/workflows/ios.yml` 을 따라 IPA 를 만들어 줍니다.

안드로이드와 달리 아이폰은 **애플이 서명한 앱만** 설치됩니다. 그래서 길이 두 갈래입니다.

|                     | ⓐ 무료 (개발자 프로그램 없이)            | ⓑ 유료 (연 $99 개발자 프로그램)          |
| ------------------- | -------------------------------------- | -------------------------------------- |
| GitHub 이 만드는 것 | **서명 없는 IPA**                      | **서명된 IPA** (받아서 바로 설치)      |
| 폰에 넣는 방법      | 윈도우/맥 PC + Sideloadly 또는 AltStore | 링크로 내려받아 설치, 또는 TestFlight  |
| 유효 기간           | **7일**마다 다시 설치 (앱 3개 제한)     | 1년 (프로파일 갱신 전까지)             |
| 기기 등록(UDID)     | 필요 없음                              | 필요 (기기 100대까지)                  |
| 준비물              | 애플 ID(무료), 윈도우/맥 PC 한 대       | 애플 개발자 계정, 인증서, 프로파일     |

> 워크플로는 **하나**입니다. 서명 재료(Secrets)를 안 넣으면 ⓐ, 넣으면 ⓑ 로 자동으로 갑니다.
> ⓐ 로 먼저 굴려서 "빌드가 된다"를 확인하고, 나중에 ⓑ 로 올라가는 걸 권합니다.

---

## 이미 되어 있는 것 (코드 쪽)

- `export_presets.cfg` 에 **iOS 프리셋** 추가 — 가로 화면, iOS 14 이상, 아이폰+아이패드,
  아이콘 16종은 `icon.svg` 에서 자동 생성, 런치 화면 배경색은 게임 배경색과 같은 크림색.
- `.github/workflows/ios.yml` — **두 단계**로 나뉘어 있습니다.

  | 단계 | 어디서 | 하는 일 |
  |---|---|---|
  | `project` | 우분투 | Godot 내려받기 → 애셋 임포트 → **Xcode 프로젝트 생성** → 104MB 꾸러미로 전달 |
  | `ipa` | 맥 | 꾸러미 풀고 **`xcodebuild`** → IPA → 결과물 업로드 (태그면 릴리스까지) |

  서명 Secrets 유무는 `ipa` 단계가 알아서 판단합니다.

**왜 맥에서 Godot 을 안 돌리나** — Godot 4.7 의 iOS 익스포터는 macOS 에서만 도는
"Code-signing dylibs" 블록이 `application/export_project_only` 검사보다 **앞에** 있습니다
(`editor_export_platform_apple_embedded.cpp` 2094~2117줄). 인증서가 없는 CI 맥에서는 여기서
멎습니다. 리눅스에서 나오는 Xcode 프로젝트는 맥에서 나오는 것과 같으므로, 무거운 Godot 은
싼 우분투 러너에 맡기고 맥은 `xcodebuild` 만 시킵니다. 맥 러너는 분당 10배로 깎이니
**요금 면에서도 이쪽이 이득**입니다.

리눅스에서 Xcode 프로젝트가 나오는 것은 이 저장소에서 **확인 완료**입니다
(`godot --headless --path . --export-release "iOS" build/ios/dinofind.ipa`, 종료 코드 0).
`.ipa 는 macOS 에서만 빌드할 수 있습니다` 경고는 정상입니다.

---

## 내가 해야 하는 것

### 1단계. GitHub 에 올리기 (공통)

이 폴더는 아직 git 저장소가 아닙니다. 처음 한 번만:

```bash
cd ~/pjt/dino
git init -b main
git config user.name  "이름"
git config user.email "drpepper1219@gmail.com"
git add .
git commit -m "공룡을 찾아라! + iOS 빌드"
```

그다음 GitHub 에서 빈 저장소를 하나 만들고(README 체크 해제):

```bash
git remote add origin https://github.com/<계정>/dino.git
git push -u origin main
```

- 저장소 크기는 20MB 정도(공룡 그림 100장 포함)라 그냥 올라갑니다. `build/`, `.godot/` 는
  `.gitignore` 로 빠집니다.
- **퍼블릭이면 러너가 무료**입니다. 프라이빗이면 우분투는 1배, 맥은 10배로 깎입니다.
  무거운 Godot 작업은 우분투가 하고 맥은 `xcodebuild` 만 하므로 맥 사용 시간은 5분 안팎입니다.

### 2단계. 굴려 보기 (공통)

GitHub 저장소 → **Actions** 탭 → 왼쪽 **iOS IPA 만들기** → 오른쪽 **Run workflow** →
`release` 그대로 두고 초록 버튼.

끝나면 그 실행 화면 아래 **Artifacts** 에 `dinofind-ipa-1` 이 생깁니다. 내려받아 압축을 풀면
`dinofind-unsigned.ipa` (ⓐ) 또는 `dinofind.ipa` (ⓑ) 가 들어 있습니다.

### 3단계-ⓐ. 서명 없이 폰에 넣기 (무료)

윈도우나 맥 PC 한 대가 필요합니다. **맥 기준 순서**(윈도우도 거의 같습니다):

1. **IPA 받기** — 실행 화면 맨 아래 **Artifacts** → `dinofind-ipa-N` → zip 으로 내려받아 압축 풀기.
2. **Sideloadly 설치** — <https://sideloadly.io> 에서 macOS 판을 받아 `응용 프로그램` 으로 끌어다 놓고,
   처음 열 때만 **오른쪽 클릭 → 열기** (그냥 더블클릭하면 맥이 막습니다).
3. **아이폰을 케이블로 연결** → 폰에 뜨는 **"이 컴퓨터를 신뢰하시겠습니까?" → 신뢰** → 폰 암호.
4. Sideloadly 창 맨 위에서 폰이 잡혔는지 보고, **IPA 파일을 창 안으로 끌어다 놓기**.
5. **Apple ID** 칸에 본인 애플 ID 를 넣고 **Start** → 비밀번호, (2단계 인증이면) 폰에 뜬 **6자리 코드**.
6. 폰 홈 화면에 공룡 아이콘이 생깁니다. 열기 전에 한 번만:
   **설정 → 일반 → VPN 및 기기 관리 → 본인 애플 ID → 신뢰**.

무료 애플 ID 서명은 **7일 뒤 만료**됩니다. 그러면 앱이 안 열리는데, 3~5번을 다시 하면 됩니다
(같은 앱으로 다시 넣는 것이라 **기록은 안 지워집니다**). 무료 계정은 이렇게 넣은 앱을 한 번에
**3개까지** 가질 수 있습니다.

7일마다 케이블 꽂는 게 번거로우면 **AltStore Classic** (<https://altstore.io>) 을 쓰세요.
맥에 AltServer 를 깔고 폰에 AltStore 를 설치해 두면, 폰과 맥이 **같은 와이파이에 있을 때
알아서 갱신**해 줍니다. 대신 처음 설정이 Sideloadly 보다 몇 단계 더 많습니다.

> 리눅스만 있는 경우: 공식 도구가 없습니다. `pymobiledevice3` 로 페어링 파일을 만들어
> **SideStore** 를 쓰는 방법이 있지만 손이 많이 갑니다. 윈도우 PC 가 있으면 그쪽이 훨씬 쉽습니다.

### 3단계-ⓑ. 서명까지 GitHub 에 맡기기 (유료, 연 $99)

**1) 개발자 프로그램 가입** — <https://developer.apple.com/programs/> 에서 결제.
   가입 후 Membership 화면의 **Team ID**(영문+숫자 10자)를 적어 둡니다.

**2) 인증서(.p12) 만들기** — 맥 없이 이 리눅스에서 됩니다.

```bash
cd ~/pjt/dino/build            # 아무 데나 (git 에 안 올라가는 곳)
openssl genrsa -out ios.key 2048
openssl req -new -key ios.key -out ios.csr \
    -subj "/emailAddress=drpepper1219@gmail.com/CN=Dino Find/C=KR"
```

`ios.csr` 를 <https://developer.apple.com/account/resources/certificates/list> 에서
**+ → Apple Development** 로 올리고 `development.cer` 를 내려받습니다. 그다음:

```bash
openssl x509 -inform DER -in development.cer -out development.pem
# 주의: -legacy 가 없으면 맥 키체인이 못 읽습니다 (OpenSSL 3 기본 암호화가 안 맞음)
openssl pkcs12 -export -legacy -inkey ios.key -in development.pem \
    -out ios.p12 -name "Apple Development" -passout pass:원하는비번
base64 -w0 ios.p12 > ios.p12.b64
```

**3) 기기 등록** — 아이폰 UDID 가 필요합니다.
   - 윈도우: Apple Devices(또는 iTunes) 에서 기기 요약 화면의 일련번호를 클릭하면 UDID 가 나옵니다.
   - 리눅스: `sudo apt install libimobiledevice-utils` 후 케이블로 꽂고 `idevice_id -l`.

   <https://developer.apple.com/account/resources/devices/list> 에서 **+** 로 등록.

**4) 프로비저닝 프로파일 만들기**
   - Identifiers → **+** → App IDs → App → Bundle ID 를 직접 입력
     (예: `com.내이름.dinofind` — 아래 `IOS_BUNDLE_ID` 와 **똑같아야** 합니다).
   - Profiles → **+** → **iOS App Development** → 방금 App ID → 인증서 선택 → 기기 선택 →
     이름 짓고 → `.mobileprovision` 내려받기.

```bash
base64 -w0 dinofind.mobileprovision > profile.b64
```

**5) GitHub 에 넣기** — 저장소 → Settings → Secrets and variables → Actions

  **Secrets** (New repository secret)

  | 이름                          | 값                                   |
  | ----------------------------- | ------------------------------------ |
  | `IOS_TEAM_ID`                 | Team ID 10자                         |
  | `IOS_P12_BASE64`              | `ios.p12.b64` 내용 전부              |
  | `IOS_P12_PASSWORD`            | 위에서 정한 비번                     |
  | `IOS_MOBILEPROVISION_BASE64`  | `profile.b64` 내용 전부              |

  **Variables** (Variables 탭 → New repository variable)

  | 이름                | 값                          | 설명                                     |
  | ------------------- | --------------------------- | ---------------------------------------- |
  | `IOS_BUNDLE_ID`     | `com.내이름.dinofind`       | App ID 와 같은 값 (안 넣으면 예제값 사용) |
  | `IOS_EXPORT_METHOD` | `development`               | 내 기기용. 여러 대 배포는 `ad-hoc`        |
  | `MACOS_RUNNER`      | (보통 비워 둠)              | 맥 이미지 고정하고 싶을 때 `macos-15` 등  |

넣고 다시 **Run workflow** 하면 이번엔 서명된 `dinofind.ipa` 가 나옵니다.
등록한 기기에서 링크로 받아 바로 설치할 수 있고, 1년 갑니다.

---

## 버전 태그로 릴리스 만들기

```bash
git tag v1.0.0 && git push origin v1.0.0
```

태그를 올리면 워크플로가 자동으로 돌고, **Releases** 에 IPA 가 붙습니다.
폰 사파리에서 그 주소로 바로 받을 수 있어 편합니다(서명된 IPA 일 때).

## 잘 안 될 때

| 증상                                              | 볼 곳                                                                 |
| ------------------------------------------------- | --------------------------------------------------------------------- |
| `configuration errors:` 뒤가 **비어 있음**        | `project.godot` 의 `textures/vram_compression/import_etc2_astc=true` 가 지워진 것입니다. 없으면 x86_64 러너에서 메시지 없이 거부됩니다. |
| `App Store Team ID not specified`                 | `export_presets.cfg` 의 `app_store_team_id` 가 빈 값. 자리표시자라도 필요합니다. |
| `No signing certificate "iOS Development" found`  | `.p12` 를 `-legacy` 없이 만든 경우가 대부분입니다. 다시 만드세요.        |
| `Provisioning profile ... doesn't include device` | 폰 UDID 를 등록한 뒤 프로파일을 **다시 내려받아** Secret 을 갱신해야 합니다. |
| Godot 다운로드 실패                                | Godot 버전이 바뀌었을 수 있습니다. `ios.yml` 의 `GODOT_VERSION` 확인.    |
| `xcodebuild` 실패                                 | 실행 화면 맨 위 **Summary** 에 `error:` 줄과 마지막 60줄을 찍어 둡니다.   |
| Xcode 버전이 안 맞는다는 오류                      | Variables 에 `MACOS_RUNNER` 를 `macos-15` / `macos-latest` 로 바꿔 보세요. |
| 설치했는데 "신뢰할 수 없는 개발자"                 | 폰 → 설정 → 일반 → VPN 및 기기 관리 → 신뢰                              |
| AltStore/Sideloadly 가 **앱 이름**에서 오류        | 애플은 App ID 이름에 영문·숫자만 받습니다. `project.godot` 의 `config/name.ios="DinoFind"` 를 지우지 마세요(한글 이름이 그대로 넘어가면 막힙니다). |

## 알아 둘 것

- 아이패드/아이폰 **iOS 14 이상**이면 됩니다.
- 게임 저장 파일은 앱 안에 있어서, 7일마다 재설치해도(같은 서명이면) 기록은 남습니다.
  다른 서명으로 다시 깔면 새로 시작합니다.
- 앱스토어에 올리려면 별도 작업(스크린샷, 심사, App Store Connect 업로드)이 더 필요합니다.
  지금 워크플로는 **내 아이 폰에 넣는 것**까지가 목표입니다.
