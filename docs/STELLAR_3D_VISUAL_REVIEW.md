# 스텔라 디펜스 3D 시각 검수

2026-10-08, `graphic_design_manager`가 실제 Godot 4.7.1 GL Compatibility 렌더로 검수했다.
현재 아트 기준은 [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md), 게임 규칙·모바일 통합은
[STELLAR_3D.md](STELLAR_3D.md)를 따른다.

## 적용 결과

- 전투와 배치는 실제 `Node3D`·`MeshInstance3D`·`Camera3D`·조명·그림자를 사용하는
  `game/3d/stellar_world.gd`다. 기존 두 경로·12발판·생명수정의 논리 좌표를 그대로 투영한다.
- 타이틀·야영지·소환·테마·상점 배경은 같은 3D 월드 경로를 사용한다. 정보와 버튼은
  기존 2D UI를 유지하며 카메라를 회전해도 발판 선택·별·이름·체력이 실제 위치를 따른다.
- 50영웅은 원래 얼굴·의상 설명과 호스, 방열판, 팬, 발전기, 활, 방벽 등의 장비를
  `art/models/manifest.json`에 연결했다. 영웅 한 장의 0~9등급마다 실제 메쉬 장비를 추가한다.
  합성 영웅의 각성 수정 날개·고리와 25몬스터·보스도 같은 방식의 실제 3D 모델이다.
- 도감·상세·소환·편성·전투 피해 목록은 같은 모델에서 촬영한 550초상화를 쓴다.
  전체 메쉬 bounds에 맞춘 구도로 긴 무기·최고 등급 장식까지 화면 안에 들어온다.
- 차가운 이끼 지면, 얇은 이동 안개, 불규칙한 돌·나무, 따뜻한 등불, 테마별 랜드마크를
  사용한다. 실제 게임 경로의 직각과 발판 위치는 기존 게임 규칙에 맞춰 유지한다.
- 앱 아이콘·시작 로고·코인의 스페이드는 생명수정과 별로 교체했다. 3D 에셋의 출처·해시는
  `art/models/generated-assets.json`, 아이콘 기록은 `art/ui/launcher_manifest.json`에 있다.

## 실제 화면 검수

`python3 tools/3d/visual_review.py`를 실행해 1280×800과 1000×625에서 한국어·영어 화면을
각각 촬영했다. 두 실행 모두 통과했고 `render.log`의 스크립트 오류와 종료 리소스 누수는 0건이다.
이 도구의 언어 전환은 실제 `I18n.set_locale()`를 호출한다.

| 검수 상태 | 자료 경로 | 직접 확인한 내용 |
| --- | --- | --- |
| 타이틀 | `build/stellar-3d/<해상도>/ko_title.png`, `en_title.png` | 스텔라 브랜드, 3D 야영지·양쪽 수호자, 의식판과 버튼 가독성 |
| 전장 배치 | `ko_formation.png`, `en_formation.png` | 12발판 이름·등급·NEW, 작은 화면의 전당·출전 버튼 |
| 실제 전투 | `ko_battle.png`, `en_battle.png` | 입체 모델·그림자·생명수정, 몬스터·탄·범위, 같은 3D 피해 목록 초상화 |
| 카메라 회전 | `ko_battle_orbit.png`, `en_battle_orbit.png` | 실제 깊이·장비 방향, 투영된 별·체력·선택 위치 |
| 연속 전투 | `ko_motion_00..11.png`, `en_motion_00..11.png` | 이동·팔 모션·탄·피해 효과·표시가 연속해서 변화하며 모델 크기와 발 위치 유지 |
| 재생·연속 비교 | `ko_battle_motion.gif`, `en_battle_motion.gif`, `*_motion_contact.jpg` | 12프레임의 이동과 공격 비교 |
| 소환 결과 | `ko_summon.png`, `en_summon.png` | 실제 등급의 동일 모델, Grey의 모자·단안경·장비, 긴 영문 소개 |
| 50영웅 갤러리 | `identities_0..4.png` | 5페이지 × 10영웅의 고유 의상·체형·장비 및 전체 초상화 구도 |
| 10등급 갤러리 | `rank_limne.png`, `rank_brasa.png`, `rank_zero.png`, `rank_echo.png` | 반 별부터 5성까지 훈장·갑옷·망토·왕관·보석·날개·광륜·궤도 보석의 실제 변화 |

위 표의 상대 이미지 경로는 모두 `build/stellar-3d/<해상도>/` 안에 있다.
검수 자료는 빌드 폴더에 두며 위 도구로 재현한다. 최종 대표 이미지는
`build/stellar-3d/1280x800/ko_battle.png`와 `rank_limne.png`다.

## 검사 결과와 한계

- `tests/3d/stellar_render_check.tscn`: 모델·등급 변화·각성·몬스터·모바일 캐시 2,628건,
  실패 0건. PackedScene LRU 96개와 초상화 LRU 64장으로 런타임 축적을 제한한다.
- 초상화 550장 모두 알파 임계값 32에서 4px 가장자리 여백을 만족했다. 실패 목록은
  `build/stellar-3d/visual-audit.json`의 빈 `boundary_failures` 배열로 기록했다.
  50명 각각의 인접 등급 PNG도 실제 RGBA 내용이 모두 다르다.
- `python3 tools/check_font.py`: 검사 대상 47파일의 사용 문자가 번들 글꼴에 포함된다.
- 메인 에이전트의 독립 `stellar_gameplay_check` 107건/실패 0건 결과를 공유받았다.
  3시점 발판 선택과 좌표 역투영, 3D 동기화 전후 Run·시뮬레이션·난수 불변을 검증한다.
- APK·iOS 내보내기 및 전체 기능 회귀는 메인 에이전트가 담당한다. Android 실기기에서의
  프레임률, 발열, 장시간 플레이와 육안 검수는 수행하지 않았다.

최종 시각 런타임과 에셋은 모바일 빌드 전에 확정했다. 이후 변경은 촬영 전용 테스트의
언어 캐시 갱신·종료 시 리소스 해제와 이 검수 문서로 한정했다.
