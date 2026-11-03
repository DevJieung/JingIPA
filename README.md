# 먹끼리 iOS IPA

GitHub 저장소는 https://github.com/DevJieung/JingIPA 이며, 먹끼리 소스와 빌드는
전용 `meokkiri` 브랜치에서 관리합니다. 다른 앱의 브랜치와 워크플로는 유지합니다.

`meokkiri` 브랜치에 push하면 `.github/workflows/meokkiri-ios.yml`이 macOS 러너에서
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
