# 자유 배치·3D 렌더 검수

2026-10-08, `graphic_design_manager`가 실제 Godot 4.7.1 GL Compatibility 화면을
1280×800과 1000×625, 한국어와 영어로 촬영해 직접 확인했다.
기준은 [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md)의 최신 자유 배치 항목이다.

## 적용 결과

- 고정 석조 발판과 빈칸 `+`를 제거했다. 실제 좌표와 선택·이름·별·사거리는
  `Run.hero_position`/전투 `pos`를 사용한다. `post`는 최대 12명의 내부 슬롯만 관리한다.
- 영웅 발 아래 얇은 팀 링·부드러운 접지 음영을 적용했다. 선택은 금색 링과 범위,
  후보는 초록 체크 또는 빨강 X다. 수정에 가려지던 금지 표시는 수정 위로 올렸다.
  이 높이 보정은 배치 판정과 전투 좌표를 바꾸지 않는다.
- 외곽 영웅의 이름을 안쪽 여백으로 옮겼다. 중앙은 발 아래에 표시하며 모든 이름은
  지도 상자 내부에 제한한다. 1000 화면의 Rhiannon·Glaukos 등 긴 영문 이름,
  높은 별 장비와 다음 영웅의 별·HUD가 서로 가리지 않는 기본 구도를 확인했다.
- 길을 공유 bevel 석판으로 나누고 지면에 큰 이끼 색 패치와 약한 표면 요철을 적용했다.
  중앙의 큰 지형 장식은 외곽으로 이동하고 숲 테두리·등불의 실루엣을 보강했다.
  차가운 주광·따뜻한 보조광·실제 그림자·약한 glow로 모델의 형태와 수정빛을 분리했다.
- 엔진은 Compatibility, 3D MSAA 2×를 유지한다. FXAA 설정은 실제 미지원 경고를
  확인해 제거했다. SSAO·볼륨 안개·새 고해상도 본체·새 래스터는 도입하지 않았다.

## 최종 검수 자료

재현 명령은 `python3 tools/3d/free_placement_review.py`다.
현재 [촬영 진입점](../tests/3d/free_placement_visual_preview.gd)은 실제 API로 12명을
기존 발판과 다른 유효 지면 좌표에 옮긴 뒤, 각 언어의 관련 상태를 촬영한다.

| 상태 | `build/free-placement-render/<해상도>/` 자료 | 확인 내용 |
| --- | --- | --- |
| 자유 편성 | `ko_formation.png`, `en_formation.png` | 12명 비고정 좌표, 이름·별·전당·출전 버튼·기존 번역 안내 |
| 선택 | `*_selected.png` | 실제 좌표의 금색 링·범위·지도 외곽·선택 꺾쇠 |
| 후보 | `*_valid.png`, `*_invalid.png` | 초록 링·체크, 수정 위의 빨강 링·X |
| 전투 | `*_battle.png`, `*_battle_selected.png` | 실제 모델·도로·그림자·생명수정, 위치에 따른 선택과 전투 안내 |
| 회전·확대 | `*_battle_orbit.png` | 카메라 투영, 장비 깊이, 선택·별·HUD 분리 |
| 움직임 | `*_motion_00..07.png`, `*_battle_motion.gif`, `*_motion_contact.jpg` | 연속 이동·팔·투사체·피해 숫자가 변하며 발과 모델 크기 유지 |
| 전체 비교 | `ko_contact.jpg`, `en_contact.jpg` | 각 언어의 주요 7상태 |
| 타이틀 | `ko_title.png` | 공통 배경 렌더 변경 후 로고·의식판·단추 가독성 |

최종 두 해상도 각각 31장, 합계 62장의 PNG를 촬영했다.
`build/free-placement-render/report.json`에 두 해상도 모두 `render_errors: 0`을 기록했다.
최종 각 `render.log`에 스크립트 오류·종료 리소스 오류는 없으며 정상 종료했다.
남은 경고는 가상 OpenGL의 V-Sync와 기존 2D MSAA 미지원 경고다.

초기 촬영용 테스트의 타입 추론 오류와 일부 재시도의 종료 리소스 오류는 수정/조사했고,
이를 최종 통과 자료로 인용하지 않는다. 1000 화면 종료 실패 로그는
`1000x625/cleanup-retry-error.log`, 오류가 재현되지 않은 상세 실행은
`1000x625/verbose-cleanup.log`에 별도 보존했다. 캐시나 런타임 누수라고 단정하지 않는다.
최종 촬영 도구는 지역 `FormationView`/화면/FileAccess 참조·렌더 캐시를 정리하고,
`async _ready`의 이미지 등 임시 참조가 해제된 뒤 deferred quit로 종료한다.
그 변경 후 최종 두 해상도 통합 실행은 모두 오류 없이 완료됐다.

메인 담당에게 최종 런타임 기준 자유 배치 49건/기존 배치 101건 실패 0과
`tools/verify.sh quick --skip-sprites` 전체 통과 결과를 전달받았다.
APK 재빌드·서명·광고·DB 제외 검사는 메인 담당 범위다.

## 모바일 비용과 다음 제작 단계

정적 석판·지형·나무는 공유 재질로 병합한다. 그림자 조명은 하나이며 등불 네 개와
수정 조명은 그림자를 만들지 않는다. 모델/초상화 캐시와 효과·탄 상한을 유지했다.
검수 전투 말미의 노드 기반 집계는 두 크기에서 같은 결과였다:
가시 상태 MeshInstance3D 567개, 245,296삼각형, 225,224정점.
이 수치는 장면의 활성 메쉬 집계이고 실제 GPU draw call·프레임률 수치가 아니다.
화면 밖 메쉬와 날씨 MultiMesh의 실제 GPU 작업도 이 집계만으로 설명할 수 없다.
Mesa llvmpipe 소프트웨어 렌더에서 확인했으며 Android 실기기 FPS·발열은 측정하지 않았다.
실기기에서 부족하면 먼저 장비/색 재질을 아틀라스로 묶고 캐릭터·몬스터 메쉬를 간소화한다.

현재 구·원뿔·상자 조립 모델을 조명만으로 정교한 게임 모델처럼 만들 수는 없다.
아래는 다음 제작을 위한 제안이며 이번 구현에 포함하지 않았다.

1. **대표 GLB 3명:** Limne의 저수탱크·호스, Brasa의 넓은 꽃잎형 방열 장비,
   Echo의 날씬한 체형·이중 활을 현재 `art/models/manifest.json` 정체성에 맞게 만든다.
2. **작은 화면 우선 검수:** 공통 재질·팔 rig와 0/4/9등급의 실루엣·얼굴·장비 폭을
   실제 1280/1000 화면에서 확인한다. 실제 피해 시점과 공격 모션 계약을 보존한다.
3. **모듈 확장:** 장비를 공유 모듈로 만들어 10등급과 50영웅에 확장하고,
   같은 GLB 모델로 도감/소환/상세 초상화를 다시 촬영한다.
4. **몬스터 순서:** 작은 슬라임→큰 골렘→보스 순서로 형태·재질·움직임을 검수한다.
   representative battle의 모바일 비용을 잰 뒤 나머지를 확장한다.

renderer 전체 전환은 이 모델·재질 개선과 기기 측정 이후에 검토한다.
Compatibility glow의 사용 범위는
[Godot Environment 공식 설명](https://docs.godotengine.org/en/stable/classes/class_environment.html#class-environment-property-glow-enabled)을 확인했다.
