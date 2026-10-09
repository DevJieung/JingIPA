# 몬스터 native 3D 제작

2026-10-09 사용자가 기존25몬스터도 실제 native 제작 범위에 포함했다.
영웅의 인간형9bone이나 손/무기 좌표를 비인간형에 복사하지 않는다.
현재25/25 실제 GLB·skin·대기/보행과 같은 모델25초상화를 연결했다.
전체 몬스터 엔진 계약은 `integration/native-all25-monsters-final.log`564건/실패0,
전체25 source-chain 증명도 오류0이다. 개별 실제 검수는 두 해상도 각78PNG/렌더오류0이다.

- 원본은 `tools/3d/monster_sources.json`의 활성 anim.readability.source/source_cells다.
  개별 추출 원본은 `build/monster-native/inputs/<id>.png`이며25종을 직접 읽었다.
- 개별 내장 image_gen 참조는 `monster_reference_sources.json`에 등록한다.
  PNG는 제작용 래스터 참조이며 실제 GLB 렌더와 구분한다.
  연체 DropSlime·사족 BlazeFox·날개 보스 FlameDragon의 실제 게임 검수 뒤 확장했다.
- 실제 TRELLIS+remesh/PBR 원형/workflow/history는 `build/character-3d/monster-raw/<id>/`다.
  `native_monster_specs.json`의 체형·높이·관절을 실제 메시에서 맞추고
  `finish_native_monster.py`가 보존UV/알베도, 경량화, matte 재질과 가변 skin을 작성한다.
  편집 가능한 high/game.blend는 `monster-source/<id>/`에 유지하며 모바일에 넣지 않는다.
- 런타임 GLB/provenance는 `art/models/monsters/<id>/`에 둔다.
  검수 완료 ID만 `art/models/native_monsters.json.ready_ids`에 연결한다.

## 움직임과 엔진 계약

`NativeMonsterModel`은 실제 Skeleton3D/AnimationPlayer의 `IdleLoop`/`MoveLoop`를 읽는다.
glTF에는 루프 속성이 없어 endpoint가 맞는 이 두 이름에 LINEAR 루프를 지정한다.
World는 이미 게임 속도·둔화·마비·일시정지가 반영된 `mo.motion_t+motion_phase`만 전달한다.
모션을 위해 위치/피해/RNG/공격/DB를 변경하거나 둔화를 다시 곱하지 않는다.
native 높이는 모델/spec이 책임지고 기존 generic kind배율·root bob을 중복 적용하지 않는다.
직접 자식 `StellarBurn/Frost/Stun`과 상태 가독성을 유지한다. 매 프레임 리소스를 만들지 않는다.

## 현재 검수와 비용

DropSlime은10,000삼각형/3bone/512텍스처로 두 크기 각78PNG·오류0, 정면/측면/후면/3/4,
24idle/32move·GIF/MP4, 3상태 효과와12고유 영웅+12슬라임 전투를 직접 검수했다.
원본 남청록 teardrop/검은 두 눈/풀린 바닥을 유지한다. 최초 대표 검수1/25였다.
`monster-review/drop_slime/`과 같은 폴더 report/provenance가 현재 GLB hash를 고정한다.

여우/드래곤의14k/28k 초기 collapse LOD는 실제 화면에서 면이 붕괴해 거절했다.
원형 표면은 정상임을 직접 비교했고, UV를 유지한54,979/64,871삼각형 후보로 복구했다.
이는 원시178k급보다 줄었지만 낮은 예산을 달성했다고 주장하지 않는다.
사족7bone·날개9bone의 실물 보행/루프 seam과 엔진 두 크기 검수까지 마쳤다.
잔여 몬스터는 체형별 실제 결과를 보고 LOD를 조절하며 동일예산을 무조건 강제하지 않는다.

최대41몬스터+12영웅의 실제 밀도 장면에서25identity·상태·선택을 확인했다.
촬영만으로 실기기 FPS를 주장하지 않는다. 최종25portrait는 같은 모델을
`render_portraits.py --monster-ids <ids>`로만 촬영해 보호된 영웅/림네 초상화를 보존한다.

- 여우/드래곤 최종 두 해상도 각78PNG/오류0의 다각도·연속MoveLoop·Burn/Frost/Stun·12영웅 혼합 전투를 직접 검수했다. `monster-review/report.json`에 실제 GLB SHA를 고정해 게시했다. 첫3대표가 통과해 나머지22종의 개별 참조→raw 생성으로 확대했다. 초상화는 `--monster-ids`로 현재 모델3개만 갱신하며 영웅/Limne를 건드리지 않는다. DropSlime 초상화 알파 여백38px/edge0; 여우·드래곤2PNG도 같은 최종 모델로 촬영했다.

## 최신 진행과 보수 범위

첫 확대 DropSlime/BlazeFox/FlameDragon/RapidRay/JellySeer/WaveGiant/EmberImp 7종을
두 크기 각각78PNG·오류0, 실제 다각도/연속보행·상태/12영웅 전투에서 직접 검수해 연결했다.
이후 Magma/Bramble/Vine/Spore/Stone/Idol과 Pyre/Elder/Pebble/Blizzard/Skink/Frost도
같은 직접 검수를 마쳤고 GlacierTitan/RimeWitch/AbyssLeviathan도 같은 검수로
이어 CrystalGolemKing/GlacierDragon도 게시해 당시24/25 모델을 연결했다.
같은 모델 초상화24장은 알파 잘림0이며
King/Dragon 두 PNG도 `final-two-boss-portrait-audit.json`에 현재 frozen 모델 hash와 함께 확인했다.
각6종 기술계약138/0이다. 마지막 TitanBloom은 아래 연속 표면 보수 후25번째로 검수를 마쳤다.
Ray/Jelly/Wave 기술계약75/0, Ember33/0이다.

Pyre의 실제 긴 shaft/brazier/flame은 실측 Staff 관절 하나로 유지하고 holding arm은
body와 같은 움직임으로 맞춘다. 인간형 좌표를 비인간형이나 다른 caster에 복사하지 않는다.
Elder의 첫 raw는 큰 몸통 구멍과 사라진 ivory face가 있어 거절했다. 원본 SHA와 실패 원형을
보존한 `elder_closed_trunk_reference_sources.json`의 단일 closed-trunk 재구성은
`monster-raw-elder-closed-v2`에 저장했고 실제 얼굴·닫힌 몸통·olive canopy 회복을 확인했다.
Pebble/Blizzard의 UV collapse가 실제 표면을 손상하면 coherent high 원형을 보존한다.
이는 조형 품질을 위한 개별 예외이며 모바일 LOD 최적화·실기기 FPS 통과를 뜻하지 않는다.
41몬스터+12영웅의 최종 밀도 실제 검수는 개별 모델 검수와 구분한다.
Glacier/Rime/Leviathan 실제 검수는 `monster-review/<id>/` 두 크기 각78PNG/오류0과
`last-first3-portrait-audit.json`의 같은 모델3PNG 여백 실패0에 고정했다.

## 실제 표면 보존 예외

Pebble 174,565tri/BlizzardWolf174,588tri는 collapse 후 생긴 표면 파편 때문에
같은 원시 UV geometry를 보존하고512atlas를 사용한다. GlacierTitan177,353tri와
RimeWitch175,972tri도 고해상도 표면을 보존해 실제 얼음판/robe 붕괴를 해소하고 두 화면 크기까지 검수한 모델이다.
이 수치는 캐릭터마다 실제 비교로 선택한 비용이며 모바일 FPS·최적화 완료 판정이 아니다.
모바일 실기기에서 최악 밀도 프로파일과 더 보수적인 retopology/LOD가 필요하다.
Elder는 closed-trunk별도 raw-v2를 사용하며 기존 실패 원형은 보존했다.
Rime의 Staff7은 해당 원형의 높이0.005H까지 내려가는 실제 shaft/고리/gem을 실측했고,
Pyre의 Staff 좌표를 복사하지 않았다.

전체25종의 high/game50파일은 `integration/all25-monster-editable-texture-audit.json`에서
읽기 전용으로 packed 텍스처·실제 픽셀을 확인했다. 문제0·현재 편집 원본 SHA 변경0이다.

TitanBloom 최초452,863tri raw는 actual rawGLB/high.blend에서 동일하게 심한
표면 찢김이 확인돼 거절했다. 실패 raw/reference와 high/game/GLB를 보존하고
`titan_closed_volume_reference_sources.json`의 thick-leaf closed-volume 단일 참조를
별도 `monster-raw-titan-closed-v2`에서 재구성했다. 래스터 참조는 actual GLB와 구분한다.
closed-v2 실제 원형은178,603tri이며 collapse뿐 아니라 일부 원래 표면의 중첩·뒤틀림도
직접 확인했다. 단순 rest smoothing/색 정리는 거절했으며 그 실패 자료도 보존한다.
추가 추론 없이 원래 체적을 따르는6.2mm voxel 연속 표면을 만들고, 새 geometry를
UV 전송 전에 정리했다. 실제 source triangle UV·skin과 기존 IdleLoop/MoveLoop를
옮겨 최종139,999tri/6bone/1024 실제 atlas로 보수했다. 도구는
`repair_titan_bloom.py`와 `titan_surface_voxel.py`다. Blender4.0.2가 OpenVDB 없이 빌드되어
기존 TRELLIS 환경의 CPU scipy/trimesh/skimage를 사용했다. 별도 primitive 캐릭터로 교체하지 않았다.
기존 high와 거절된 polish를 보존하고, 편집용 `game.blend`/`repaired-high.blend`에
실제 UV·skin·2clip을 유지했다. 원본 분홍 꽃입·송곳니·3붉은 봉오리·덩굴과 뿌리를
정면/후면/측면/3/4와 연속 보행, 두 크기 각78PNG/오류0의 상태·전투·회전에서 직접 확인했다.
source painting의 거친 부분은 남아 있으며 래스터 참조와 같은 조형 완성을 주장하지 않는다.
일반 batch finisher는 `topology_repair`가 기록된 수작업 모델을 기본으로 덮어쓰지 않는다.
거절된 색정리 도구도 명시적인 `--rejected-polish` 없이는 실행되지 않는다.
최종 SHA는 `ceef7b53ef047ba03a1679de9aa62d8392d584f88adf34c879f400eef6d14fb3`다.

전체25초상화는 `monster-review/all25-portrait-audit.json`의 현재 GLB SHA와 맞고
알파 잘림/4px 여백 실패0이다. 영웅550초상화와 보호Limne를 건드리지 않았다.
전체 실제 모델 모음은 `review/native-overview-75.png/.json`이며 새 래스터 참조를 섞지 않았다.

## 최종 최대 밀도 검수

`density-review/report.json`은 전체75 GLB SHA와 실제 factory가 만든12native 영웅·
41native 몬스터·25unique identity를 고정한다. 1280×800/1000×625 각각15PNG/렌더오류0이며
기본·선택·회전/확대·12연속 모션 프레임을 직접 확인했다. 작은 화면에서도 고유 실루엣·
무기·상태를 읽을 수 있고 새 표면 파편/잘림을 보지 못했다.
이는 위치를 고정한 격리 밀도 fixture에서 `motion_t`로 보행 pose를 비교하는 실제 엔진 검수다.
전체 게임 진행·공격 판정은 별도 기능 회귀 결과와 구분한다.
같은 프레임의 `density-motion.gif`와 `motion.mp4`를 두 해상도 폴더에 보존했다.
1000×625 MP4만 H264 호환을 위해 하단1px을 더한1000×626이며 실제 캡처 크기는 그대로다.
초기 홀수높이 인코딩 실패는 `density-review-initial-video.log`에 보존했다.
두 실제 Godot `render.log`에는 오류가 없고 최종 인코딩은 완료됐다.
별도 모바일 기기 FPS는 측정하지 않았으며 일부 고해상도 표면 보존 예외는 남아 있다.
최종 필수 기능 회귀 `tools/verify.sh quick --skip-sprites`도 부모가 전부 통과 확인했다.

## 적용 산출물

영웅50/몬스터25와575초상화는 새 서명 APK `/home/dgxmaruta/sd-tst.apk`에 반영됐다.
601,494,701bytes, SHA256 `c6fb02cc218b25da56f7aca7ad8c50bd20631c22c48b39d3b8dda2d08a8dfd8a`.
부모의 서명·광고·오디오·DB 제외·전체 native rig/texture/clip/portrait 포함 검사를 통과했다.
iOS는 Linux에서 생성한 Xcode 프로젝트/PCK와 실제 packed 모델 payload 검사 결과이며
서명 IPA를 생성했다고 표시하지 않는다. 기기에서의 시각/FPS 검수는 수행하지 않았다.
현재 요청 범위의 남은 시각 제작은 없으며 고해상도 보존 비용과 Titan의 거친 source painting은
앞서 기록한 실제 한계다.
