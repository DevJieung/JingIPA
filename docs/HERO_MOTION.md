# 영웅 모션 제작 (대기·보행·회전·공격)

2026-10-10. 사용자가 현재 캐릭터 움직임을 "초보 같다"고 평가하고 상용 3D 모바일 게임 수준의
대기·보행·회전·공격 모션을 요청했다. 이 문서는 영웅 49명(native GLB)과 Limne의 모션 2판
설계, 클립 구조, 도구, 검수 자료와 한계를 기록한다. 몬스터 모션과 총구 섬광·탄·피격 VFX,
조명·재질은 별도 담당의 문서를 따른다. 기하·가중치·리그·소켓·재질·초상화는 바꾸지 않았다.

## 설계 요약

- 뼈는 기존 그대로 서로 부모가 없는 절대 컨트롤 9~11개다(`SkinBody`, `SkinArm/Forearm/HandL·R`,
  `SkinLegL·R`, 선택적 `SkinWeaponL·R`). 머리·척추·무릎 뼈는 추가하지 않았다. 60~70px 전투
  화면에서 읽히는 것은 몸의 리듬·반대편 팔 스윙·무기 궤적이므로 이것만으로 목표를 맞췄다.
- 클립은 Blender에서 `tools/3d/author_native_motion.py`가 작성한다. 모션 라이브러리는
  모델 공간 FK/2관절 IK(어깨·팔꿈치·손 피벗은 각 캐릭터 `game.blend`의 실제 뼈 머리), 무기
  끝 방향 제어(검·도구), 측정된 총구 축 정렬(소총), 예비(ease-in) → 해방 스냅(ease-out) →
  반동/오버슈트(back-out, 감쇠 진동) → 정착 곡선을 제공한다. 선형 보간 포즈는 없다.
- 세 클립: `IdleLoop` 6초(호흡·체중 이동·시선 돌림·무기 미세 조정, 발 고정, 경계 무결),
  `WalkLoop` 1주기(왼발 디딤 0%, 오른발 50%, 전속 기준 작성; 다리 교차+반대편 팔 스윙,
  2회/주기 바운스, 골반 롤·몸통 요, 전진 기울기, 무기별 팔 스윙 비율), `Attack` 1.5초
  (0~1.0초 예비·조준, 1.0초 해방 포즈, 1.0~1.5초 해방 동작·반동·정착·복귀).
- 무기 유형별 안무(`attack` 종류): 활=가슴 앞 시위 걸기 → 활팔 밀기+시위 손 당기기(push-pull,
  몸 측면 블레이드) → 유지·떨림 → 손 해방+활 킥 → 복귀. 소총=낮은 준비 → 견착(몸 블레이드,
  측정 총구 축을 정확히 -Z) → 미세 조준 흔들림 → 반동(총 뒤·위 6°, 몸 뒤) → 오버슈트 복귀.
  양손 보조는 총열 중간을 잡고, 쌍권총(Carmen·Conor)은 두 손이 각각 조준·반동(0.05초 엇갈림),
  Kari는 한손 블래스터. 검=가드 → 어깨 뒤 감기(몸통 반대 비틀기) → 3프레임 베기(끝 방향이
  위·뒤 → 정면 → 아래·반대편) → 팔로스루 → 복귀. 캐스터=가슴 앞 모으기(기운 궤도) → 밀어내기+
  몸 기울기 → 반동 → 복귀. 포병(Triton·Frosti)=버티기(웅크림·팔 아래) → 발사 시 몸 반동
  (아래·앞, 감쇠 바운스) → 정착; 등 포는 `SkinBody`를 따르므로 측정 물리 축을 유지한다.
  도구(Pip)=렌치 머리 위 감기 → 내려치기 → 되튐 → 복귀.
- 런타임 `game/3d/native_character_model.gd`는 AnimationPlayer 재생 대신 `Animation` 트랙을
  직접 샘플해 매 프레임 포즈를 새로 합성한다(누적 없음):
  `base = IdleLoop(time) → WalkLoop(거리 위상)로 속도 가중 블렌드`,
  `upper = Attack(q=age/wind 시간 왜곡, 발사 후 실시간 0.5초)`을 base의 몸통 델타 위에 얹고
  (하체=보행, 상체=공격 레이어), 회전·가속 기울기(골반 피벗) → 상태 전환 크로스페이드
  (조준 0.16/0.08초, 발사 0.06초, 취소 0.25초, 복귀 0.22초, smoothstep) → 상체 조준 보정
  (`HeroLocomotion.aim_delta`, ±1.2rad 한도, 즉시) 순서로 적용한다.
- `game/3d/hero_locomotion.gd`(`HeroLocomotion`)가 영웅 공통 상태를 가진다: 보행 위상 =
  이동 거리/보폭(캐릭터별 `stride` 1.30~1.70, 다리 길이에서 유도, 매니페스트 `motion`),
  속도 평활(가속 0.06초, 감속 0.10초 → 멈춤 블렌드 ≈0.2초, 0.5초 안에 대기 복귀),
  부드러운 요 회전(남은 각×18/s, 3.5~26rad/s, 180°를 0.23초에 완료, 첫 호출은 스냅),
  이동 중에는 조준이 ±1.2rad 안이면 뿌리는 진행 방향을 유지하고 상체만 조준(스트레이프),
  그 밖은 뿌리가 돈다. `dt`가 0(일시정지 재그리기)이면 위상·회전·블렌드가 멈춘다.
  `face_toward`가 한 번도 불리지 않은 인스턴스는 `rotation.y`를 건드리지 않는다.
- Limne(`game/3d/limne_model.gd`)는 승인된 조형·GLB를 유지하고 같은 `HeroLocomotion`으로
  보행(다리 컨트롤 회전+들기, 바운스, 반대편 팔 스윙), 회전, 상체 조준 보정을 절차적으로
  수행한다. 공격은 기존처럼 `age/wind`만으로 결정되는 무상태 안무이며 가압 떨림·발사 반동
  (감쇠 진동)·0.22초 복귀를 더했다. 정지 공격 중 다리는 대기와 비트 단위로 같다.
- 해방 코어(`NativeRelease<n>`)는 작은 가산 혼합 구로 축소했다. 실제 총구 섬광·탄·궤적·착탄은
  월드 VFX가 `weapon_transform()`/`fire_strength()`로 그린다.

## 도구와 재현

```bash
# 49명 전체 또는 일부 (Blender를 병렬로 띄운다; 매니페스트는 잠금으로 갱신)
python3 tools/3d/author_native_motion.py --all --jobs 4
python3 tools/3d/author_native_motion.py --ids echo,kari
# 직렬화된 Godot 임포트
bash tools/godot_import.sh
# Blender 측 클립 프레임 시트(제작 확인용)
env -u DISPLAY bl -b --factory-startup --python tools/3d/native_motion_sheet.py -- --id echo
python3 tools/3d/native_motion_sheet.py --compose --id echo
# 실제 Godot GL 촬영(대기·공격·보행·멈춤·곡선 보행·회전·조준 보정·보행 중 공격)
python3 tools/3d/native_character_review.py --ids echo,kari --display-base 120
```

- 편집 원본 `build/character-3d/source/<id>/game.blend`는 액션/NLA만 교체해 다시 저장하며
  첫 실행이 이전 원본을 `game.motion-v1.blend`로 보존한다.
- 런타임 GLB는 검수된 기존 GLB(`build/motion-overhaul/glb-base/<id>.glb`, git HEAD 사본)의
  메시·스킨·재질·텍스처 바이트를 그대로 두고 애니메이션 접근자만 새 export로 교체한다
  (`merge_animations`). 따라서 기하·UV·가중치·법선은 바이트 단위로 동일하다.
- `art/models/<id>/provenance.json`에 `motion`(버전 2, 도구, 클립 길이, stride, grip,
  이전 SHA, 기하 기준 SHA)과 새 `glb_sha256`·`clips`를 기록하고,
  `art/models/native_heroes.json`의 `glb_sha256`와 `motion{stride,grip,clips}`를 갱신한다.
  `ready`·`sockets`·`attack`은 유지한다.
- 무기별 변수는 `tools/3d/native_visual_specs.json`의 영웅별 `motion` 항목으로 덮어쓸 수 있다
  (`grip`: two_hand/one_hand/dual, `stride`, `leg_swing`, `bounce`).

## 검수 자료

- 실제 Godot GL Compatibility 촬영 결과: 49명+Limne 모두 두 해상도 완료(`tools/3d/motion_overhaul_summary.py`
  → `build/motion-overhaul/motion2-review-summary.json`: 50/50 완료, 총 20,900PNG, `render.log` 오류 0,
  매니페스트 SHA 일치 50/50). 대표 7명+Limne은 실제 전투 화면 포함, 나머지 42명은 `--candidate-only`
  (무대 촬영만). 전체 한눈 비교: `build/motion-overhaul/heroes/all50_release_pose.jpg`(해방 포즈),
  `all50_run_pose.jpg`(보행), `all50_walk_attack_pose.jpg`(보행 중 공격).
- 촬영 경로: `build/character-3d/review/<id>/<해상도>/` (1280×800, 1000×625).
  각 영웅·해상도마다 대기 24, 공격 40(20프레임에서 발사), 직진 보행 24, 보행→멈춤 24,
  곡선 보행 24, 90°/180° 회전 16, 조준 보정→발사 12, 보행 중 공격 24프레임과
  `*_contact.jpg`, `motion.gif`(대기·공격), `locomotion.gif`(보행·회전·조준·보행 중 공격),
  `motion.mp4`, 정면/측면/후면/3/4·등급 0/4/9·각성, 대표 7명+Limne은 실제 전투 화면도 포함한다.
  촬영 후 `render.log`에 `ERROR:`가 없어야 도구가 보고서를 쓴다(`review/report.json`).
- 전후 비교: `build/motion-overhaul/heroes/<id>_before_after.jpg`(이전 무대 모션 → 새 공격·보행·
  멈춤·곡선·회전·조준·보행 중 공격 띠), `<id>_before_after.gif`(좌 이전/우 새 motion.gif),
  실제 전투 화면 `arena_en_long_walk_before_after.gif`, `arena_en_echo_attack_before_after.gif`
  (`tests/arena_visual_review.py --only hud --out-root build/motion-overhaul/arena-after` 결과와
  이전 `build/motion-overhaul/before/`의 나란히 비교). 도구: `tools/3d/motion_overhaul_compare.py`.
- Blender 측 클립 프레임 시트(제작 확인): `build/motion-overhaul/blender-sheets/<id>/sheet.jpg`
  (대기 3·보행 8×2시점·공격 10×3시점). 직접 확인: 7명 파일럿의 활 push-pull 당김·소총 견착
  정렬·검 감기/베기 궤적·캐스터 모으기/밀기·포병 반동·렌치 내려치기·쌍권총 조준.
- 변형 검사: `build/character-3d/review/echo/deformation-motion2.json`
  (새 Idle/Attack 11포즈 짧은 edge 폭증 0, 발 이동 0).
- 실제 전투 화면(부모 도구 `tests/arena_visual_review.py --only hud`, 새 모션 적용 후):
  `build/motion-overhaul/arena-after/<해상도>/` 1280×800·1000×625 각각 68PNG·5,074검사·실패 0.
  30초 연속 보행 12프레임(`en_long_walk_*.png`, 추적 카메라 기준 영웅 확대
  `build/motion-overhaul/heroes/arena_long_walk_after_hero_crops.jpg`)과 Echo 공격 6프레임을
  직접 확인했다: 원형 경로를 따라 몸이 진행 방향으로 돌고 다리 교차·반대편 팔 스윙·바운스가
  60~70px에서 읽힌다. 이전 화면과의 나란히 비교는 `arena_long_walk_06_before_after.jpg`,
  `arena_echo_attack_before_after_crops.jpg`, `arena_en_*_before_after.gif`다.
- 직접 확인한 무기 유형별 결과(실제 Godot 1280×800 연속 프레임): Echo·Brigid·Solana·Protea(활)는
  시위 걸기→push-pull 당김→뺨 고정→손 해방이 읽히고 보행 중에는 하체가 계속 달리며 상체만
  옆으로 조준한다. Kari(한손 블래스터)·Chispa·Phorkys(양손 소총)·Carmen(쌍권총)은 견착/양손
  파지/쌍수 조준과 반동, 보행 중 사격이 보인다. Jokull·Igni(검)는 어깨 뒤 감기→몸통 비틀며
  베기→팔로스루가 뚜렷하다. Brasa·Lind·Snorri·Mimic·Rhiannon(캐스터)은 가슴 앞 모으기→밀어내기
  이며 지팡이·닻 같은 translation-only 장비는 손을 따라 이동한다. Triton(포병)은 웅크린 버티기와
  발사 반동 바운스, Pip(도구)은 머리 위 감기→내려치기→되튐이다. Limne는 보행·회전·상체 조준
  보정과 물 분사 반동이 보인다.

## 검사

모두 `STELLARDEFENSE_NO_SAVE=1 godot --headless`이며 로그는 `build/motion-overhaul/logs/full-*.log`다.

| 검사 | 결과 |
| --- | --- |
| `tests/native_hero_check.tscn` (49명 전체, 보행·회전·조준 보정·보행 중 발사·멈춤 계약 추가) | 3,791건 · 실패 0 |
| `tests/arena_pose_check.tscn` (50명 30초 연속 보행·120회 정지 재그리기·0.5초 복귀) | 300건 · 실패 0 |
| `tests/arena_motion_check.tscn` (월드→모델 연동·실제 6영웅 혼합 전투 90프레임) | 30건 · 실패 0 |
| `tests/limne_model_check.tscn` (방향별 노즐 정렬에 회전 프레임 추가, 보행 계약 추가) | 182건 · 실패 0 |
| `tests/stellar_gameplay_check.tscn` | 107건 · 실패 0 |
| `tests/3d/stellar_render_check.tscn` | 2,628건 · 실패 0 |
| `tests/arena_check.tscn` / `tests/arena_play_check.tscn` | 88건 · 실패 0 / 23건 · 실패 0 |

검사 파일 변경: `tests/native_hero_check.gd`에 `_locomotion_contract`(다리만 보행, 정지 재그리기 동일,
보행 중 조준·발사 시점, 0.5초 복귀, 조준 보정 즉시·0.25초 회전 완료)를 추가했다.
`tests/limne_model_check.gd`는 네 방향 노즐 검사에서 방향마다 16프레임(0.27초)을 진행한 뒤
정렬을 판정하도록 바꿨고(어댑터가 즉시 스냅 대신 0.25초 안에 회전하므로) `_locomotion_contract`를
추가했다. 상태·난수·저장·리소스·인스턴스 독립·발사 전 해방 금지 검사는 그대로다.

## 변경 파일

- 런타임: `game/3d/native_character_model.gd`(클립 직접 샘플·레이어 합성·상태기계·크로스페이드·
  조준 보정), `game/3d/hero_locomotion.gd`(신규, 공통 보행·회전·조준 상태), `game/3d/limne_model.gd`.
- 제작: `tools/3d/author_native_motion.py`(신규, 49명 클립 작성·병합 export·provenance/manifest),
  `tools/3d/glb_animation_merge.py`(신규, 애니메이션만 교체), `tools/3d/style_animate_limne.py`
  (Limne 편집 클립 3종 미러·기하 보존 병합), `tools/3d/native_motion_sheet.py`(신규, Blender 시트).
- 검수: `tests/3d/native_character_visual_preview.gd`(보행·멈춤·곡선·회전·조준·보행 중 공격 촬영,
  Limne 지원), `tools/3d/native_character_review.py`(새 상태 GIF·locomotion.gif),
  `tools/3d/motion_overhaul_compare.py`·`tools/3d/motion_overhaul_summary.py`(신규).
- 검사: `tests/native_hero_check.gd`, `tests/limne_model_check.gd`.
- 데이터: `art/models/<id>/<id>.glb`(49명, 애니메이션 바이트만), `art/models/<id>/provenance.json`,
  `art/models/native_heroes.json`(`glb_sha256`·`motion`), `art/models/limne/limne.glb`·`provenance.json`,
  편집 원본 `build/character-3d/source/<id>/game.blend`(+`game.motion-v1.blend` 보존),
  `build/limne-game-motion/limne_game.blend`.

## 한계

- 머리·무릎·발 뼈가 없어 시선 분리와 무릎 굽힘은 없다. 다리는 고관절 피벗의 강체 스윙이며
  디딤 발은 몸 바운스로 바닥에 맞춘다. 코트·로브 영웅(다리 노출 ≤0.25h)은 다리 진폭을 줄이고
  보폭 1.30으로 걷는다.
- 보행 위상은 이동 거리 기준이지만 전속(3.4단위/s) 주기 0.43초는 치비 비율의 빠른 종종걸음이다.
- 활·지팡이·닻 같은 translation-only 장비(기존 규칙: 손 위치만 따름)는 손목 회전을 받지 않아
  캐스터의 밀어내기에서 지팡이가 수직을 유지한 채 이동한다. 활은 해방 후 짧은 앞 기울기(bow kick)만
  weapon 뼈에 더했다. 장비 회전을 손에 묶는 변경은 소켓 축 계약(소총·포병)과 함께 다뤄야 한다.
- 조준 보정은 뿌리 요와의 차이를 상체 전체(머리 포함)에 즉시 적용한다. 머리 뼈가 없어 시선만
  먼저 돌리는 연출은 없다. 보행 중 조준이 ±1.2rad를 넘으면 뿌리가 돌며 다리는 진행 방향과
  어긋난 채 전진 보행 클립을 재생한다(스트레이프 전용 클립 없음).
- 촬영은 Xvfb 소프트웨어 GL로 1280×800·1000×625 두 창에서만 수행했다. 이 문서의 수치는
  2판 기준이며 Android/iOS 실기기 FPS·육안 검수는 수행하지 않았다.
