# Stellar Defense 3D 전환

2026-10-08. 기존 별맞춤 의식·전투·편성·합성·보상 규칙을 유지하고 표현을 실제 3D로 전환한다.
참고 영상: https://www.youtube.com/watch?v=7gyIit5TtsI (00:55, 04:09–05:05, 06:17 전투 화면).

## 이름과 산출물

- 한국어 앱 이름: **스텔라 디펜스**, 영어: **Stellar Defense**.
- Android 패키지 / iOS 기본 번들 ID: `com.devjieung.stellardefense`.
- 사용자 저장 폴더: `stellardefense`. 데스크톱에서는 접근 가능한 이전 저장을 읽으며,
  이후 변경을 새 경로에 저장한다. 이전 원본은 덮어쓰지 않는다. 새 저장과 그 백업이 우선이다.
- 모바일은 기존 패키지와 별도로 설치된다. 다른 앱의 저장 샌드박스는 자동 이전하지 않는다.
- APK는 지정된 `/home/dgxmaruta/stellardefense-test.apk`에 성공한 새 빌드로만 교체한다.
- GitHub 브랜치·워크플로·APK/IPA Artifact는 모두 `stellardefense` 이름을 사용한다.
  새 Secret도 `STELLARDEFENSE_`를 사용하며 이전 설정은 읽기 호환 별칭으로만 남긴다.
  Xcode 프로젝트·앱은 `StellarDefense`이며 iOS 번들 ID 변수는 `STELLARDEFENSE_IOS_BUNDLE_ID`다.

## 실제 3D 렌더링

`game/3d/stellar_models.gd`는 공유 Mesh·재질과 움직이는 팔·몸 리그를 생성한다.
`art/models/manifest.json`은 각 영웅의 머리·피부·체형·의복·고유 장비를 지정하는 시각 메타데이터다.
50명 모두 기존 id와 무기를 유지하고, 합성 수호자는 `base_id`에 각성 장식을 더한다.

`stellar_world.gd`는 입체 지형·도로·발판·수정·영웅·몬스터·투사체·효과·조명·안개를 관리한다.
`stellar_view.gd`는 독립된 `SubViewport`의 실제 3D 렌더를 기존 읽기 쉬운 UI 아래에 합성한다.
`stellar_backdrop.gd`는 같은 3D 전장을 타이틀·소환·상점·테마 화면의 배경으로 사용한다.

전투 규칙은 `BattleSim`이 계속 관리한다. 논리 좌표를 XZ 평면으로 변환하며 시각 코드는
진행 상태·피해·능력치·난수를 바꾸지 않는다. 발판 선택은 현재 카메라 투영과 역투영을 사용한다.
게임 데이터 원본은 계속 `data/game.db`다. 승인된 명칭 문구 2건과 타이틀 에셋 경로 1건을
내렸으며, 밸런스 값은 변경하지 않았다.

## 랭크별 외형

현재 반 별 단위의 10등급을 그대로 사용한다. 각 단계에서 장비·갑옷·투구·망토·발광 장식 등이
발전하며, 3D 전투 모델과 소환·도감·편성·상세창·합성 결과의 랭크가 일치한다.
`art/models/portraits/`의 550개 PNG는 실제 같은 리그에서 렌더링한 초상화다
(영웅 50명 × 10등급 500개 + 합성 수호자 5명 × 10등급 50개).

초상화 재현은 `tests/3d/render_portraits.tscn`을 실제 그래픽 드라이버/Xvfb에서 실행한다.
헤드리스는 화면을 그리지 않으므로 초상화 생성이나 시각 검수에 사용하지 않는다.
초상화 텍스처 캐시는 64장, 리그 캐시는 96개로 제한한다. 정적 지형 메쉬와 재질은 공유한다.

## 카메라

전장 안의 휠로 확대·축소, 오른쪽 드래그로 회전, 가운데 버튼 또는 Shift 드래그로 이동한다.
모바일에서는 두 손가락 확대·축소·이동을 사용하며 화면의 카메라 버튼으로
회전·확대·축소·기본 시점을 선택한다.
기존 왼쪽 클릭/터치 선택과 드래그 재배치, 배속과 중간 지원 동작을 유지한다.

## 검증과 모바일 패키징

- `tests/stellar_identity_check.tscn`: 이름·저장 이전·기존 원본 보존·새 저장/백업 우선.
- `tests/stellar_gameplay_check.tscn`: 3D 연동·카메라별 발판 판정·시뮬 좌표/타이머/난수 불변.
- `tests/3d/stellar_render_check.tscn`: 전체 3D 모델·랭크·렌더링 계약.
- `bash tools/verify.sh quick --skip-sprites`: 현재 3D 및 기존 게임 규칙·광고·저장·흐름 검사.
- `tools/ci/check_stellar_assets.py`: APK의 50개 모델 프로필과 3D 런타임 모듈 확인.
- `tools/ci/check_stellar_pack.gd`: 실제 iOS PCK를 열어 3D 메타데이터·스크립트·이름 확인.

Android/iOS 모두 `art/models/*.json`을 포함한다. 생성용 대용량 원본은 `art/models/sources/`에
두고 Git·모바일 배포에서 제외한다. 기존 `data/.gdignore`·DB 제외 필터·`check_no_db.py`
검사를 유지한다. 검증 로그와 실제 시각 검수 자료는 `build/stellar-integration/`와 디자인
담당이 기록한 `docs/DESIGN_SYSTEM.md`의 최신 3D 전환 항목을 참고한다.

2026-10-08 검증: 전체 quick 회귀 검사 통과, 명칭·저장 이전 13건, 3D 게임성 보존 107건,
모델·랭크 계약 2,628건 통과. 초상화 550장 모두 4px 안전 여백 검사를 통과했다.
Android APK는 서명·광고·음원·550개 실제 변환 텍스처·DB 제외 검사를 통과한 파일로
고정 경로에 교체했다. iOS는 Xcode 프로젝트 내보내기와 실제 PCK 검사를 로컬에서 수행한다.
IPA 컴파일은 GitHub의 macOS 작업에서 진행한다. 실제 모바일 기기 설치·프레임률은 측정하지 않았다.
