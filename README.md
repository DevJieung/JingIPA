# 스텔라 디펜스 (Stellar Defense)

Godot 4.7.1 기반의 가로 화면 3D 수호전 게임. 별맞춤 의식으로 영웅을 소환하고,
무작위로 열리는 열 탄의 전장에서 생명 수정을 지키며 최종 보스까지 버틴다.
Android와 iOS를 함께 빌드하고, Steam용 데스크톱 프리셋이 있다.

## 현재 게임

- 한 판은 열 탄이다. 탄마다 전장이 무작위로 열리고(다섯 지형, 전장마다 다른 길과 입구),
  보스를 잡으면 다음 탄으로 넘어간다. 탄을 거듭할수록 몬스터가 강해진다([탄 사슬](docs/STAGE_RUN_2026-10-13.md)).
- 첫 의식은 무료이고 이후에는 전투 골드로 추가 소환한다.
- 최대 6명이 출전한다. 선택한 영웅을 조이스틱으로 움직이고, 영웅들은 사거리 안의 적을 자동 공격한다.
- 같은 영웅을 다시 소환하면 강화 포인트가 누적된다. 대기 영웅과 출전 영웅을 교체할 수 있다.
- 별빛 폭발·서리 파동·수정 방벽을 전투 중 사용한다. 소환·상점·교체 창과 메뉴를 열면 전투가 멈춘다.
- 영웅·몬스터는 실제 3D 모델이다. 타이틀·전장·의식·정보창은 공통 표면·색상·버튼 상태를 사용한다.
- 한글/영문, 자동 저장/이어하기, 음악/효과음 설정을 지원한다.
- 광고 SDK, 광고 시청 버튼, 광고 보상은 없다.
- 파는 것은 영구 해제 상품 하나다: 수호자의 가호(판마다 수정이 세 번까지 되살아나고 그때마다 골드를
  받는다). 1~3배속은 무료다. Google Play · App Store · Steam 을 한 코드로 지원한다([상점](docs/STORE.md)).

이전 웨이브 모드의 저장을 불러오는 데 필요한 화면과 규칙은 호환 경로로 유지한다.
이전 저장의 광고 관련 필드는 새 보상을 지급하지 않고 정리한다.

## 실행과 검증

```bash
godot --path . --editor
godot --path .
tools/verify.sh quick
tools/verify.sh
python3 tests/arena_visual_review.py --out-root build/design-overhaul
```

`tools/verify.sh`는 데이터 동기화, 실제 화면 입력, 저장, 전투/소환 규칙,
3D 모델, 번역/폰트, 오디오와 APK를 검증한다. 테스트는 실제 플레이 저장을 덮어쓰지 않는다.
시각 검수는 1280×800과 1000×625에서 실제 Godot 렌더링으로 진행한다.

## 모바일 빌드

```bash
bash tools/build_apk.sh
```

검증에 성공한 APK만 **`/home/dgxmaruta/sd-tst.apk`**에 덮어쓴다.
`DevJieung/JingIPA`의 `stellardefense` 브랜치에 푸시하면
`.github/workflows/stellardefense.yml`에서 APK와 IPA를 함께 생성한다.
다운로드·서명·수동 실행은 [모바일 빌드 안내](docs/MOBILE_BUILDS.md)를 따른다.

## 개발 문서

- [코드와 데이터 구조](docs/PROJECT_STRUCTURE.md)
- [DB 수정과 승인 절차](docs/GAME_DB.md)
- [디자인 기준과 시각 검수](docs/DESIGN_SYSTEM.md)
- [별맞춤 의식](docs/STAR_RITE.md), [탄 사슬과 전장별 길](docs/STAGE_RUN_2026-10-13.md)
- [상점과 플랫폼 결제](docs/STORE.md)
- [3D 영웅 제작](docs/NATIVE_HERO_PRODUCTION.md), [3D 몬스터 제작](docs/NATIVE_MONSTER_PRODUCTION.md)
- [한영 표시](docs/LOCALIZATION.md), [작업 완료 검사](WRAPUP.md)

게임 데이터 원본은 `data/game.db`다. 승인된 값을 기존 JSON과 게임 코드로 내리며,
게임은 DB를 직접 읽지 않고 APK/IPA에도 DB를 포함하지 않는다. `.env`, SDK, 인증서,
생성용 원본과 빌드 캐시는 Git에 넣지 않는다. 상세 작업 규칙은 [AGENTS.md](AGENTS.md)에 있다.
