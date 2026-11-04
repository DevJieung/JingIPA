# 먹끼리 iOS IPA

GitHub 저장소는 https://github.com/DevJieung/JingIPA 이며, 먹끼리 소스와 빌드는
전용 `meokkiri` 브랜치에서 관리합니다. 다른 앱의 브랜치와 워크플로는 유지합니다.

`meokkiri` 브랜치에 push하면 `.github/workflows/meokkiri-ios.yml`이 `macos-15-intel` 러너에서
Flutter 3.47.8로 iOS 기기용 release AOT 앱을 빌드합니다. 빌드 전에는
`ci/source-manifest.json`으로 현재 웹과 공통인 Dart·자산·의존성 파일의 해시를 검사합니다.
Firebase는 운영 `mkr-web`의 `com.meokkiri.meokkiri` iOS 앱 설정을 사용합니다.
고정된 Dart 의존성의 Firebase·Google 로그인 Swift 패키지 요구 버전이 충돌하므로,
CI에서는 Flutter의 공식 CocoaPods 경로를 사용합니다. FlutterFire 플러그인이 지정한
CocoaPods용 SDK 버전을 그대로 사용하며 웹·Android의 Dart 의존성은 변경하지 않습니다.
`config/firebase.mkr-web.ios.json`과 `GoogleService-Info.plist`는 앱의 공개 SDK 설정이며,
서비스 계정 키·Apple 개인 키·업로드 인증서는 포함하지 않습니다.

결과는 실행 화면의 Artifacts에 `meokkiri-ipa-<버전>-<빌드>-<실행번호>`로 보관합니다.
IPA와 함께 버전·번들 ID·ARM64·AOT·Firebase 앱 ID·공통 소스·정원 자산 검증 결과를 제공합니다.
로컬로 받은 IPA도 `python3 scripts/verify_ios_ipa.py --ipa <경로> --report <JSON경로>`로 검사합니다.

현재 워크플로는 기존 JingIPA의 무료 설치 경로와 같은 **서명 없는 IPA**를 만듭니다.
Sideloadly 또는 AltStore에서 본인의 Apple ID로 서명해 설치해야 합니다.
App Store·TestFlight 배포와 Apple 로그인·Push의 실제 iOS 기기 동작은 별도 검증입니다.

2026-11-04 iPhone에서 Apple 로그인 `AuthorizationError 1000`이 보고됐습니다.
사용자는 유료 개발자 계정의 Team ID가 `V4FGY5SRSX`임을 확인했고,
`identifier.png`에는 AltStore용 `com.meokkiri.meokkiri.V4FGY5SRSX`와
원래 `com.meokkiri.meokkiri`가 각각 등록돼 있습니다.
사용자는 AltStore용 ID를 기존 기본 앱과 그룹화하고 Refresh한 뒤에도 같은 1000을 확인했습니다.
1000은 원인을 특정하는 코드가 아니므로 그룹화만으로 해결됐다고 판단하지 않습니다.
설치본의 실제 서명 entitlement와 프로파일을 확보하지 못해 누락 여부는 미확정입니다.
Apple의 기기 인증 실패와 이후 Firebase 토큰 검증 실패도 구분합니다.

원래 앱 ID를 유지한 개발자 서명을 검증하려면 별도
`.github/workflows/meokkiri-ios-signed.yml`을 사용합니다. 기존 unsigned 워크플로는 유지합니다.
이 경로는 App Store용 export가 아닌 **development/ad hoc 기기 설치용**입니다.
GitHub 저장소 Settings → Secrets and variables → Actions에 다음 repository secrets를 설정합니다.

| Secret | 값 |
| --- | --- |
| `MEOKKIRI_IOS_CERTIFICATE_P12_BASE64` | 개인 키가 포함된 유효한 Apple 서명 인증서 `.p12`의 base64 |
| `MEOKKIRI_IOS_CERTIFICATE_PASSWORD` | 위 `.p12`의 암호. 암호 없는 P12는 빈 값 |
| `MEOKKIRI_IOS_PROFILE_BASE64` | 아래 조건을 충족한 `.mobileprovision`의 base64 |

프로파일은 Team `V4FGY5SRSX`, App ID `com.meokkiri.meokkiri`의 명시적
development 또는 ad hoc 프로파일이어야 합니다. Sign in with Apple을 활성화한 뒤
프로파일을 재생성하고 테스트할 iPhone을 포함해야 합니다. `.p12`의 인증서와 개인 키는
해당 프로파일에 허용된 인증서와 일치해야 합니다.
기존 Sign in with Apple `.p8` 키와 Team ID는 앱 설치용 서명 자격 증명을 대신하지 않습니다.
서명 파일이나 base64·암호를 채팅·소스·공개 artifact에 넣지 않습니다.

빌드는 기존 웹과 같은 source manifest를 export한 전용 `meokkiri` checkout에서 실행합니다.
기본 브랜치가 다른 앱의 `main`이므로 새 워크플로를 등록하려고 그 브랜치를 수정하지 않습니다.
서명 secrets를 설정한 후 `ci/device-signing-request.json`에 요청 시각을 기록해
`meokkiri`에 push하면 별도 서명 워크플로가 실행됩니다. GitHub에서 수동 실행이 제공되는
경우에도 반드시 `meokkiri` ref를 지정합니다. 입력이 없으면 즉시 실패하며 unsigned 파일로
대체해 성공 처리하지 않습니다.

`scripts/ios_device_signing.py`는 임시 keychain에 인증서를 가져오고 중첩 framework와 앱을
서명한 뒤, `codesign --verify --deep --strict`와 앱/프로파일/인증서 일치를 확인합니다.
프로파일의 wildcard keychain 권한은 먹끼리의 기본 그룹으로 좁히고, 앱 소스가 요청하지 않은
기능은 추가하지 않습니다. IPA로 패키징한 후에도 다음 명령으로 macOS에서 다시 검사합니다.

```bash
python3 scripts/verify_ios_ipa.py --ipa <경로> --signing device --report <JSON경로>
```

결과는 `meokkiri-signed-ipa-<버전>-<빌드>-<실행번호>` artifact입니다.
등록된 기기에 Apple Configurator/Xcode 등의 서명 보존 설치 경로로 설치해 확인합니다.
AltStore로 다시 서명하면 검증한 앱 ID와 서명이 바뀔 수 있으므로 그 결과를 동일시하지 않습니다.
Windows에서는 Sideloadly의 Advanced Options → Normal Install 모드로 서명된 IPA를 설치합니다.
기본 Apple ID Sideload 모드는 다시 서명하므로 이 전달본의 검증된 서명을 유지하는 모드와 구분합니다.
아래 완료 기록의 빌드/서명 검증과 **실제 iPhone 설치·Apple 로그인 완료**는 별도입니다.

Mac에서 내보낸 P12가 없는 경우를 위해 2026-11-04에 RSA-2048/SHA-256 CSR
`artifacts/meokkiri-ios-distribution-20261104.csr`를 만들고 요청 서명과 공개 키 일치를 확인했습니다.
짝 개인 키는 저장소 밖의 `~/.config/meokkiri/ios-signing/meokkiri-distribution-20261104.key`에
0600 권한으로 보관합니다. 요청 정보는 `artifacts/ios-distribution-csr-20261104.json`에 기록했습니다.
사용자는 Apple Developer Certificates에서 Apple Distribution 인증서를 추가하며 이 CSR을
업로드하고 `.cer`를 받습니다. Profiles에서 원래 Meokkiri ID, 방금 발급한 인증서와 테스트
iPhone을 선택한 Ad Hoc 프로파일도 받습니다. 내려받은 `.cer`의 공개 키가 CSR/개인 키와
일치함을 검사한 뒤 이 작업 환경에서 P12를 만들 수 있습니다. 개인 키를 재생성하거나
다른 CSR로 발급한 인증서를 섞지 않습니다.

사용자가 `distribution.cer`와 `Meokkiri_AdHoc.mobileprovision`을 제공했습니다.
인증서의 공개 키가 위 CSR/개인 키와 일치하며, 프로파일은 원래 앱 ID와 Team ID,
`com.apple.developer.applesignin = [Default]`, 등록 기기 1대를 포함합니다.
프로파일 CMS 서명/Apple 신뢰 체인과 인증서의 Apple 신뢰 체인, 프로파일 내 인증서 일치도
확인했습니다. 프로파일과 인증서는 2027-11-04 13:25:12 UTC까지 유효합니다.
암호화된 P12에는 일치하는 개인 키·인증서와 Apple WWDR G3 중간 인증서를 넣고,
암호로 다시 읽어 공개 키 일치를 확인했습니다. 입력과 암호는 저장소 밖의 같은 보호
디렉터리에만 두며, 값이나 테스트 기기의 UDID를 보고서에 출력하지 않습니다.
검증 기록은 `artifacts/ios-signing-input-validation.json`입니다.

현재 GitHub 인증으로 `/repos/DevJieung/JingIPA/actions/secrets/public-key`를 조회하면
HTTP 403 `Resource not accessible by personal access token`이 반환되며 필요한 권한은
`secrets=read`입니다. 따라서 연결된 인증으로 Actions Secrets를 설정할 수 없습니다.
사용자가 저장소 Actions Secrets에 위 3개 이름으로 값을 등록했고, CI에서 입력 복호화·인증서
가져오기와 실제 서명을 완료했습니다. 이 연결의 Secrets 관리 권한과 CI의 소비 권한은 구분합니다.

2026-11-04 [서명 실행 41845639448](https://github.com/DevJieung/JingIPA/actions/runs/41845639448)이
성공했습니다. 기존 macOS 기기용 빌드 `41786939801`의 artifact `13303197522`를 재사용했고,
IPA SHA-256 `99dd15f7d0838aa9ef3bbefd3b5ba65d80d0df71ffdeb29c3ab1459927be4b25`와
현재 웹의 공통 소스 manifest 전체가 일치함을 확인했습니다. 재사용 요청은
`ci/device-signing-request.json`의 `reuseUnsignedArtifact`에 원본 run/artifact ID와 IPA SHA-256을
명시합니다. `scripts/restore_unsigned_ios_app.py`는 manifest 또는 파일 해시가 다르면 거부합니다.
이 값이 없는 요청은 기존 전체 Flutter 컴파일 경로를 사용합니다.

서명 과정에서는 임시 keychain을 사용자 검색 목록에 추가한 뒤 기존 목록을 복원합니다.
`codesign`의 선택적 출력 prefix는 `--extract-certificates=<prefix>`처럼 묶고,
ARM64를 명시해 XML entitlement와 leaf 인증서를 확인합니다.
최종 IPA는 [artifact 13332140669](https://github.com/DevJieung/JingIPA/actions/runs/41845639448/artifacts/13332140669)의
`meokkiri-0.20.3-40-ios-ad-hoc.ipa`, 24,686,980바이트이며 SHA-256은
`9665f6744044c38607495c6b5a7405cc51be725f860dc7cdee0bec18048b8476`입니다.
Mac에서 전체 코드 서명·프로파일·인증서 일치를 통과했고, 로컬에서도 artifact/IPA 해시,
주 실행 파일의 CMS 서명과 코드 페이지 380개, Info.plist·리소스·XML/DER entitlement 해시,
Apple 신뢰 프로파일과 권한, 기기용 ARM64 36개 슬라이스를 확인했습니다.
실행 파일의 한 바이트를 바꾼 검증 입력은 코드 해시 검사에서 거부됐습니다.
기록은 `artifacts/ios-signed-0.20.3-40-release.json` 및 같은 prefix의 remote/local validation입니다.
실제 기기 설치와 Apple 계정 로그인 완료는 아직 검증하지 않았습니다.

다음 배포에서는 웹과 같은 버전·소스로 APK·AAB·IPA를 함께 준비합니다.
로컬 먹끼리 작업 공간에서 최신 웹 배포의 소스 manifest를 지정해 전용 checkout으로 복사합니다.

```bash
python3 scripts/export_ipa_source.py \
  --checkout /path/to/JingIPA-meokkiri \
  --source-manifest artifacts/<현재-웹-배포>-source-manifest.json
```

전용 checkout은 처음에 `git init -b meokkiri`로 만들고 원격을
`https://github.com/DevJieung/JingIPA.git`로 설정합니다. 이후에는 원격 `meokkiri` 브랜치를
사용합니다. 복사 내용을 검토하고 커밋한 뒤 `git push origin meokkiri`를 실행합니다.
GitHub 인증은 이 환경에 이미 구성된 Git credential helper를 사용하며 토큰은 출력하지 않습니다.
빌드가 끝나면 IPA를 내려받아 내용을 검증하고 관측한 Actions·artifact 링크를 전달합니다.

2026-11-04에 확인한 `0.20.3+40`의 첫 실행
([41672967295](https://github.com/DevJieung/JingIPA/actions/runs/41672967295))은
macOS ARM64 러너 수용량 부족으로 작업을 배정받지 못해 약 15분 뒤 실패했습니다.
실행 단계와 컴파일 로그가 없었으며, check annotation에
`The job was not acquired by Runner of type hosted even after multiple attempts`가 기록됐습니다.
따라서 `macos-latest` 대신 GitHub가 제공하는 `macos-15-intel`로 빌드 호스트를 고정합니다.
([공식 러너 목록](https://github.com/actions/runner-images))
호스트 아키텍처와 별개로 결과는 기존과 같은 iPhone/iPad 기기용 ARM64 release AOT이며,
워크플로와 로컬 검증에서 IPA의 아키텍처를 확인합니다. 앱 버전과 웹 공통 소스는 변경하지 않습니다.
