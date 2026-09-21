# APK + IPA 자동 빌드

저장소: https://github.com/DevJieung/JingIPA/tree/pokerdefense

이 게임은 `pokerdefense` 브랜치에 둔다. 기존 `main`의 공룡섬과 `ios.yml`은 유지한다.
기본 브랜치에도 `pokerdefense.yml`을 등록해 Actions 화면에서 수동 실행할 수 있다.
수동 실행은 항상 `pokerdefense`의 최신 커밋을 빌드하고, 푸시는 해당 커밋을 빌드한다.

## 매번 빌드하기

변경을 커밋한 뒤 `git push`하면 **올인 디펜스 APK + IPA**가 자동으로 실행된다.
명시적으로 푸시하려면 `git push origin HEAD:pokerdefense`를 사용한다.
워크플로 파일은 `.github/workflows/pokerdefense.yml`이다.
워크플로를 수정하면 수동 실행용 `main`의 동일 파일도 동기화한다.

Actions 실행의 `pokerdefense-apk-ipa` Artifact에 아래 파일이 함께 들어 있다(30일 보관).

- `pokerdefense-test.apk`: Android 테스트용 APK
- `pokerdefense.ipa`: iOS 기기용 Release IPA
- `commit.txt`, `SHA256SUMS.txt`: 두 산출물의 소스 커밋과 체크섬

`pokerdefense-v1.0.0` 형태의 태그를 푸시하면 두 파일을 GitHub Release에도 보관한다.
개별 APK/IPA Artifact도 제공한다. 한 플랫폼이 실패하면 통합 Artifact는 만들지 않는다.

## 빌드 구성

Godot 4.7.1, JDK 17, Android SDK 36을 사용한다. Android 템플릿은 매 빌드에서
공식 Godot 배포본으로 복원한다. 로컬 ARM 전용 Gradle/aapt2 경로는 커밋하지 않는다.
AdMob 5.0.0의 Android ads 플러그인 파일은 저장소에 포함한다.

Linux에서 에셋을 임포트하고 게임 흐름·번역·광고 회귀 검사를 실행한 다음 APK와
Xcode 프로젝트를 내보낸다. macOS에서 그 Xcode 프로젝트를 빌드해 IPA로 묶는다.
IPA에는 같은 커밋의 게임 데이터가 들어간다. Android 서명·광고 플러그인·리소스,
IPA의 실행 파일·번들 ID·게임 데이터도 검사한다.

로컬 APK는 계속 `bash tools/build_apk.sh`로 생성하며, 검증에 성공한 파일만
`/home/dgxmaruta/pokerdefense-test.apk`에 덮어쓴다.
CI의 Android 디버그 키는 Actions 캐시에 보관한다. 로컬 키와는 다르며 캐시를
삭제하면 CI 키가 바뀔 수 있다. 서로 다른 키로 서명한 APK끼리는 덮어 설치할 수 없다.

## IPA 서명

서명 Secrets가 없으면 **서명 없는 IPA**를 만든다. AltStore/Sideloadly에서 본인의
Apple ID로 서명하여 설치한다. 이 파일은 App Store/TestFlight 업로드용이 아니다.

서명 빌드에는 다음 Repository Secrets를 사용한다. `POKERDEFENSE_` 전용 값이
우선이며, 없으면 기존 저장소의 `IOS_*` 값을 사용한다.

| Secret | 내용 |
|---|---|
| `POKERDEFENSE_IOS_TEAM_ID` | Apple 개발자 Team ID |
| `POKERDEFENSE_IOS_P12_BASE64` | 인증서와 개인 키를 포함하는 P12의 base64 |
| `POKERDEFENSE_IOS_P12_PASSWORD` | P12 비밀번호 |
| `POKERDEFENSE_IOS_MOBILEPROVISION_BASE64` | 이 앱용 프로비저닝 프로파일의 base64 |

인증서·프로파일·팀 설정이 일부만 있으면 실패 원인을 표시하고 중단한다.
다른 게임의 프로파일을 잘못 쓰지 않도록 팀·번들 ID·만료일을 확인한다.
기본 번들 ID는 `com.devjieung.pokerdefense`이며 필요하면 Repository Variable
`POKERDEFENSE_IOS_BUNDLE_ID`로 지정한다. 기존 게임의 `IOS_BUNDLE_ID`는 쓰지 않는다.
`POKERDEFENSE_IOS_EXPORT_METHOD` 기본값은 `debugging`이다. 배포 목적에 맞는
프로파일과 `release-testing`/`app-store-connect` 등을 함께 설정해야 한다.
기기 설치 가능 여부는 프로파일의 배포 방식과 등록 기기에 따른다.

## 광고와 비공개 설정

기본 CI APK는 체크인된 Google 테스트 광고 ID를 사용한다. 실제 Android 광고 ID를
적용하려면 `POKERDEFENSE_ADMOB_ENV` Secret에 `tools/admob_config.py`가 읽는
`ADMOB_APP_ID`, `ADMOB_REWARD_CARD_CHANGE_ID`, `ADMOB_REWARD_MERGE_RESTORE_ID`,
`ADMOB_REWARD_REVIVE_ID` 설정만 넣는다. 로컬 `.env` 자체는 업로드하지 않는다.
현재 프로젝트의 iOS AdMob 비활성화 설정은 그대로 유지된다.

생성 도구의 대용량 원본(`art/animation`, `art/concepts`, `art/audio_sources`,
`art/portraits/sources`), 빌드 캐시, SDK, 인증서는 Git에서 제외한다.
실제 게임이 사용하는 스프라이트·배경·UI·음악·폰트는 저장소에 포함한다.
