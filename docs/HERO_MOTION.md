# 영웅 모션 제작 (대기·보행·회전·공격)

2026-10-10. 사용자가 현재 캐릭터 움직임을 "초보 같다"고 평가하고 상용 3D 모바일 게임 수준의
대기·보행·회전·공격 모션을 요청했다. 이 문서는 영웅 49명(native GLB)과 Limne의 모션 2판
설계, 클립 구조, 도구, 검수 자료와 한계를 기록한다. 몬스터 모션과 총구 섬광·탄·피격 VFX,
조명·재질은 별도 담당의 문서를 따른다. 기하·가중치·리그·소켓·재질·초상화는 바꾸지 않았다.

## 2026-10-19 추가 — 팔 비틀림 수정 (B1, motion v4)

사용자 피드백 "칼쓰는 근거리 캐릭터 / 활쏘는 원거리 캐릭터 팔 모션이 어색함 완전 뒤틀려 보임 (ex. 니브 /
글라우코스 / 요쿨 등)". 원인 측정은 `build/feedback-2026-10-19/map/visual-perf.md` B1, 기록·수치·캡처는
`build/feedback-2026-10-19/D5/RECORD.md`. **1단계 = 클립 재저작만**: 기하·UV·가중치·리그·소켓·`height` 바이트 그대로,
`ATTACK_RELEASE` 1.0·`HOLD_START`·wind 왜곡·피해 시점·시뮬 불변. 대상 30명: 활 10(brigid echo eira isa keto niamh
null protea saeta solana)·검 9(caden estoque finn glaukos helga igni jokull nerea phantom)·도구 pip·소총 10(kari
phorkys ceniza brian carmen chispa conor dummy grey marea). 시전형 17·포격 2 는 측정상 깨끗해 v3 클립 그대로다.

### 원인 (v3)

- `Rig.arm_ik`가 위팔과 아래팔을 각자 최소 호로 돌려 아래팔이 위팔에 대해 170~180° 비틀렸고(활 당기는 팔·검 팔·
  pip), 폴이 어깨-목표 축을 지나며 팔꿈치 평면이 뒤집혔다. 검·도구·소총 손은 「절대」 방향이라 손목이 128~180° 꺾였다.
- 활은 손·활이 이동만 해서(upright) 손목이 85~114° 꺾였고, 시위 손 기준점(0.80 h, 몸 중심면)이 큰 머리 **안**이라
  손이 머리 위로 튀어나왔다(닭날개). 걷기 팔꿈치는 모델 X 축으로 굽어 아래팔이 40~46° 비틀렸다.

### 저작 도구 v4 (`tools/3d/author_native_motion.py`)

- **경첩 2본 IK**: 아래팔 = 위팔 ∘ 휴지 경첩 회전 — 아래팔이 제 축으로 돌 수 없다. 경첩은 해부학 축(굽히면 앞으로,
  아래팔에 직교), 휴지에서 20° 넘게 굽은 총 팔(kari L·phorkys R·ceniza R)은 모델링된 평면. 도달 거리 → 경첩각은
  닫힌 해. 위팔은 몸통에 실린 휴지 팔을 비틀림 없이 목표로 스윙한 기준 위에서 폴 방향으로 팔꿈치 평면을 돌리고, 폴이
  도달축에 가까우면 기준으로 페이드한다(평면이 축을 지나며 뒤집히지 않음). 모든 IK 팔은 ±75° 스위블 탐색(폴 선호,
  어깨 굴림 60° 초과 비용, 몸통 관통 방지, 직전 키의 팔꿈치 평면·손 회전·손목 비틀림 기억). 걷기 FK 팔꿈치도 경첩 축.
- **손목 한계**: 모든 손이 아래팔 상대 회전, 연한 한계 비틀림 80°·꺾임 88°(75 %부터 tanh 무릎), 직전 키 기준 언랩.
  조준 손(칼끝·총·활)은 손목 일이 가장 적은 스위블을 고른다 → 칼날·총 방향이 팔꿈치·아래팔에서 먼저 나온다.
- **활이 손을 따름**: `weapon_matrix`가 활도 손에 붙이고, 손목이 활을 세운다(겨눔축 굴림 ±0.3 rad 자유) — 놓을 때
  소켓 정면 0.9997~1.0, +65 ms 0.9965~0.9977. 활팔은 어깨선으로 0.6 rad 바깥, 길이 97 %. 걷기는 활팔 팔꿈치를 덜
  굽히고(0.35 rad) 손목이 활을 세운다(예산 40/45°), 대기 피젯은 손목이 활을 기울인다. upright 모드 제거.
- **당기는 손**: 기준점은 몸통 공간의 뺨 앞(높이 `BOW_ANCHOR_Y` 0.72 h, 앞 `BOW_ANCHOR_FRONT` 0.20 h), 당기는 팔꿈치는
  몸통 공간 폴(뒤·바깥·위). 시위 손은 자기 어깨 도달 안에서 쉬고(낮은 앞) 가슴 앞에서 걸고 뺨으로 당긴다(push-pull).
- **칼 베기**: 손 경로는 어깨 중심 호(`arc`, v3 직선은 어깨 9 cm 옆을 지나 팔꿈치 160° 접힘), 칼끝 키는 slerp.
  키마다 손 자세를 한 번 풀어 몸통 공간에서 slerp하고 칼날만 저작 호로 최소 스윙(`keyed_hand`) — 프레임마다 굴림을
  다시 풀지 않는다. **앞 가드**(기본): 가드 → 들기 → 칼을 어깨 앞 위로 세운 죽은 홀드(손 0.16 h 위·0.15 h 앞) → 해방
  +1키 가슴 높이 중간 키(칼끝 앞) → +3키 대각 베기 → 팔로스루(v3는 첫 키에 75 %를 건너뛰었다), 중간 키도 칼 자세를
  푼다. 칼날이 아래팔과 100° 넘게 꺾인 영웅(phantom)은 머리 위 가드. **옆 가드**(`SWORD_SIDE_KEYS`, FK): 위팔을 옆으로
  들어 칼을 머리 옆에 세우고(칼날 앞으로 기울임 → 손목 비틀림 1/3), 첫 키에 팔꿈치를 옆에서 ~40°만 내린 뒤 낮게 앞으로
  — 키마다 칼날 굴림은 직전 손목 비틀림을 잇는다. 빈손은 폴 없이 비틀림 없는 평면 + 피부 막 비용의 스위블, 낮고 느슨하게.
  pip(렌치)의 중간 키는 가슴 높이.
- **피부 막**(교차 점검 2026-10-19): `Rig.skin_web()`이 몸·위팔·아래팔만 가중치를 가진 어깨/팔꿈치 피부 변을 선형 혼합
  스키닝으로 세워 늘어남을 잰다(원본 메시). jokull 외투는 위팔을 **앞으로** 들면 막이 되고(첫 v4 베기: 놓은 뒤 위팔 85~104°
  앞, 칼 팔 아래 파란 막) 옆으로 들면 깨끗하다. `sword_guard()`가 표본 11자세의 막을 비교해 앞 가드 막이 표본당 120 을 넘고
  옆 가드가 30 % 이상 적을 때만 옆 가드 — 현재 jokull 만(앞 3663·옆 677, 다른 검 86~713). 6프레임 변형 검사는 이 긴 막을
  못 잡으므로 60 fps 사이 프레임까지 본다.
- **소총 쥠**: 놓을 때 총 정렬이 계약이라 영웅마다 한 번 견착 위치를 탐색(설계값 주변 상자, 손목 비용 최소, 양손이면
  보조손 도달), 총열 굴림 ±0.8 rad 자유 → +65 ms 총구 정면 0.987~0.9985(검사 문턱 0.95). 보조손은 총열 축 굴림 자유.
  휴지 총열은 영웅의 조준 회전에서 유도(측정 축이 없는 chispa 의 `weapon_aim_x` 포함). 한손·쌍권총 걷기는 총을 앞-아래
  20°로 든다(손목 예산 45/55°; v3 고정 "앞-위" 손목은 쌍권총에서 93~99° 꺾임).
- **홀드**: `HOLD_START`~해방 키는 첫 홀드 키 복제(죽은 홀드; 기억 항이 홀드 중 흘러가지 않게).
- 기록: provenance `motion.version` 4, `motion.arms`(경첩 축, 손목 피벗↔보이는 손목 거리 = 2단계 진단값, 소켓 정면,
  손목 한계 사용량, 총 견착 오프셋). 조정 도구: `NATIVE_MOTION_DEBUG_SIDE=L|R`(+ `NATIVE_MOTION_DEBUG_T=<초>`)가
  팔꿈치 평면 풀이·스위블 지형을 찍는다.

### 런타임 (`game/3d/native_character_model.gd`)

- `_rechain`: 샘플 뒤 팔 관절을 부모에 다시 앉힌다(위치만, Body→Arm→Forearm→Hand→Weapon). 부모 없는 뼈를 따로
  보간하던 키 사이·idle↔walk 혼합에서 팔꿈치·손목이 벌어지던 것 제거, 키 위에서는 무변화.
- 교차 페이드는 팔 사슬에서 부모 상대 공간(경첩은 경첩으로, 관절 붙은 채).
- 팔 펌프 팔꿈치 굽힘은 몸 X 축 대신 위팔에 실린 경첩 축(도구와 같은 식). H0 굵게(×1.20/×1.12)는 그대로.

### QA 관문 (`tools/3d/audit_native_twist.py`, Godot·Blender 불필요)

```bash
python3 tools/3d/audit_native_twist.py --quiet                       # verify 관문: 49명, 종료 0 = 통과
python3 tools/3d/audit_native_twist.py --scope b1 --baseline ''      # B1 23명 엄격(소총 7명은 --ids 로 추가)
python3 tools/3d/audit_native_twist.py --ids niamh,jokull --glb-dir DIR  # author --candidate DIR 결과
python3 tools/3d/audit_native_twist.py --write-baseline tools/3d/twist_baseline.json   # 승인된 변경 뒤 기준선 갱신
```

GLB 키(1/30 s)에서 양팔마다 팔꿈치 비틀림, 손목 비틀림·꺾임, 키 사이 뒤집힘(관절 비틀림 점프, 또는 같은 키 스윙의
1.5배를 넘는 굴림 — 몸통 기준; 빠른 내려베기에 실린 굴림·해방 스냅은 제외, 원값은 `spin`)을 잰다. 문턱 팔꿈치 ≤30·
손목 비틀림 ≤90·꺾임 ≤100·flip ≤45°/키, JSON + 종료 코드. 기준선 `tools/3d/twist_baseline.json`(추적, `--baseline`
기본값)에서 `fail`인 영웅(시전형·포격 19명)은 5° 까지 나빠지지 않으면 `known`, `pass`인 30명과 기준선에 없는 영웅은
문턱을 지켜야 한다.

결과(전 → 후): 활 팔꿈치 170~179 → 3~8°, 손목 꺾임 85~114 → 57~81; 검 팔꿈치 171~178 → 4, 손목 비틀림 161~179 →
29~80, 꺾임 128~156 → 70~88; pip 178/179/168 → 4/26/88; 소총 10명 팔꿈치 32~166 → 5~21, 꺾임 95~150 → 39~88.
대기(IdleLoop)는 활 10명만 바뀌었고(활이 손을 따름) 나머지는 v3 와 같다. 걷기(WalkLoop)는 30명 모두 재저작이다 —
경첩 팔꿈치로 걷기 아래팔 비틀림 14~48° → 0, 활팔·총 운반 손목도 새로 푼다.
30명 전원 통과, 나머지 19명(시전형·포격) `known`. 어깨 굴림은 15~54 → 29~106°로 늘었다(팔꿈치 비틀림이 위팔로 옮겨
온 것; 팔을 든 자세의 외회전). 검사: native_hero_check 3,791/0(소총 4방향 총구 정렬) · arena_pose_check 350/0 ·
hero_speed_melee_check 171/0 · arena_motion_check 36/0 · arena_idle_facing_check 17/0 · native_parity_check 96/0.
변형(Attack 6프레임, 출시 LOD): 과신장 피크 합 210 → 170(교차 점검 후 검 9명 120 → 108). 검 9명 놓은 뒤 피부 막(LOD,
60 fps 사이 프레임): jokull 306 → 103(v3 119), 나머지도 수정 전 이하. 초상화는 IdleLoop 이 바뀐 활 10명만 재렌더(110장).

### 2단계에 남은 것 (피벗 맞춤·가중치, O7 과 함께)

- 템플릿 피벗(손목 피벗↔보이는 손목 0.17~0.35 m): glaukos, jokull, nerea, helga, finn, pip, niamh, phorkys — 손목
  꺾임(최대 88°)이 소매를 늘인다. 팔꿈치 피벗 오프셋도 같다.
- 가중치: caden·igni 홀드(몸통↔아래팔/칼날 이음, v3 대비 과신장 증가), glaukos 홀드 0.50 m, niamh 활이 팔·몸과 섞임,
  pip 흰 팔 껍질 막, marea(v4 견착에서 55k 원본 과신장 0 → 8). jokull 소매 커프의 무기 가중치·외투 옆판의 아래팔 가중치
  (손 근처 작은 가시, v3 에도 있음), helga·nerea 엉덩이·치마의 손·무기 가중치(클립으로는 v3 수준까지).
- 어깨 굴림 89~106°(팔을 든 홀드·내려치기)는 피벗을 맞추면 줄일 여지. 안드로이드 실기기 미확인.

## 2026-10-18 추가 — 모션 비트 (캐주얼 3D 개편 WP-D)

사용자 평가 "아주 싼마이 AI로 만든 3D게임 느낌"(캐주얼 3D 성공작 분석 요청)에 따른 개편의 모션
패키지. `build/casual-overhaul/PLAN.md` §3 WP-D가 명세이고, `analysis/judge_motion.md`의 픽셀 산수(48px
영웅에서 0.08rad 흔들림은 2px, 오버슈트는 0.3px)를 그대로 받아 **48px에서 보이는 비트만** 남겼다.
원칙: 모든 레버는 샘플러 **위**(어댑터 레이어·스켈레톤 노드)에 있고, 클립(GLB)·해방 시점 1.0s·`wind`·
피해·난수는 그대로다. 예고(anticipation) → 홀드 → 스냅 → 팝 → 정착의 순서로 설계했다.

### 런타임 레이어 (`game/3d/native_character_model.gd`, `game/3d/hero_locomotion.gd`)

| 레이어 | 구현 | 실측(`build/casual-overhaul/after/wp-d/probe/beats_probe.txt`, 1280×800 기준 37.6px/u 가로·29.3px/u 세로) |
| --- | --- | --- |
| **H1 홀드→스냅** | 조준 진행 `q = age/wind`를 두 구간으로 왜곡: q<0.65는 `hold_t·(q/0.65)^1.8`로 클립의 홀드 자세(`HOLD_T` 활 0.86·검/도구 0.85·캐스터/포병 0.90·소총 0.25)에 이르고, 0.65~1은 홀드→해방 자세를 직선으로. q==1에서 정확히 `ATTACK_RELEASE` | wind 0.5s(60Hz 30프레임)에서 뼈 원점 이동 4mm 미만의 **정지 프레임 10/30**(f21~30), 당김 자체는 f3~9에 몰려 0.12u/프레임 |
| **H2 해방 팝** | 스켈레톤 **노드** 스케일 `(1+a, 1−a, 1+a)`(발 기준, 체적 보존), 매 샘플 기록. `a = 0.10·smoothstep(0,0.012,t)·(1−smoothstep(0.025,0.075,t)) − 0.02·sin²(π·(t−0.075)/0.145)` | 해방 프레임 a=0(소켓·VFX 그대로), f1 0.100(4.8px@48 / 5.5px@55), f2 0.093, f3 0.050, f4 0.007; 되튐 −2%는 1px(읽히지 않음, 솔직히 적음). 소켓 검사가 읽는 65ms에서 1%(기울기 <0.5°) |
| **H3 보행 흔들림** | 골반 기준 상체 피치 `0.14·cos(4πφ+0.3)`(2배 케이던스, 디딤에 앞으로), 롤 `(0.08+0.025·slow)·cos(2π(φ−0.1))` | 머리(골반 위 1.0u 지렛대) 전후 ±5.7px(가로 보행) / ±3.6px(카메라 쪽), 상하 1.9px |
| **H3 출발·정지 기울기** | `HeroLocomotion.sod_step`(반암시적 오일러 2차 역학, dt 안정)으로 속도를 따라가는 스프링(f 3.5Hz·ζ 0.45·r 0)과 실제 속도의 **차이(lag)**를 기울기로: `clamp(0.9·(speed−y)/WALK_FULL_SPEED, −0.20, 0.25)`, τ 0.08 lerp. r>0이면 스프링이 속도보다 앞서 가 가속 중에 뒤로 젖혀지므로 0 | 출발 +0.20rad(0.12s, 머리 +6px) → 0.35s에 정착(한 번 되돌림 −0.05); 정지 −0.175rad(0.15s, 머리 −8.9px 가로/−5.6px 세로) → 0.4s에 2px 미만, 0.55s에 1px 미만 |
| **H3 회전 기울기** | 롤 목표 `clamp(−yaw_rate·0.02, ±0.18)·clamp(speed/0.9, 0.35, 1)`을 같은 스프링(f 3.0·ζ 0.5)으로. 조준 비틀기(`aim_delta`)에는 더하지 않는다(1.3px, `native_hero_check.gd:210`) | 보행 중 90° 회전: 0.18rad = 머리 6.8px 기울기(0.13s), 되돌림 +0.009rad = 0.4px(안 보임 — r<0·미분항도 1px 이하라 넣지 않음) |
| **H4 팔 펌프** | `_pump_arms(pose, φ, min(weight·0.6+run, 1.2))`, `RUN_ARM` 0.55→0.9. 공격 레이어가 상체를 덮으므로 소켓은 그대로 | 걷기 어깨 +0.26rad(≈4px), 달리기 +0.52rad |
| **H5 등장 팝인** | `visual_event({"t":"spawn"})` → `_spawn_clock=_clock`. 0.35s 동안 스켈레톤 노드: 0.6u 낙하(ease-in, u 0.8에 착지) · 크기 0.6→`back_out(u,1.7)`→1(u 0.58에 1.04) · 착지 눌림 (1.12, 0.85, 1.12)·sin². 전투 밖·u≥1이면 항등 | 키 29px→50px→41px→48px, 낙하 17.6px; 0.35s에 정확히 원위치 |
| **H0 두툼한 손·무기** | `SkinHandL/R` ×1.20, `SkinWeapon*` ×1.12, 뼈 원점 기준 균일 스케일(평평한 리그라 전단 없음). 활·검·캐스터·도구만; 소총·포병 제외. 상시 적용 | 소켓 이동 ≤2cm, 방향 불변 |
| **Limne** (`limne_model.gd`) | 같은 곡선을 스켈레톤 노드에(`update_visuals`가 노드의 **기준** 변환으로 뼈 자세를 풀고 비트는 노드에 얹는다 → 뼈 자세·다리 접지 검사 불변), `visual_event("spawn")`, `StellarShading.style()`(create)·`prepare_instance()`(_ready, 패킹 뒤) | 해방 f1 스케일 0.900, 등장 0.6u 낙하; 미리보기 변환 == 기준 |

월드 계약: `spawn`은 첫 `animate_visual`이 시계를 둔 **뒤** 와야 하므로 `stellar_world.gd`가 `_native_pending`
큐로 돌려 보낸다(메인 소유, 2026-10-18 반영). `native_hero_check`는 이 이벤트를 보내지 않는다.
일시정지 재그리기: 스프링은 `step>0`에서만 전진, 팝·등장은 시계의 순수 함수.

검사(2026-10-18, 로그 `build/casual-overhaul/after/wp-d/logs/`): `native_parity_check` 96/0(비트 동일, 재빌드 없음),
`native_hero_check` 3,791/0, `native_monster_check` 1,239/0, `limne_model_check` 182/0, `arena_pose_check` 350/0,
`arena_motion_check` 36/0, `arena_idle_facing_check` 17/0, `hero_speed_melee_check` 171/0, `arena_air_check` 107/0,
`monster_check --assets` 88/0 — 임계값 수정 없음. 캡처는 `build/casual-overhaul/after/wp-d/RECORD.md`.

### 재저작 도구 v3 (`tools/3d/author_native_motion.py`, HA1/HA2 — 배치는 메인이 WP-A 배포 뒤 실행)

- **HA1 공격**: 예고 키는 `ant = ease_in(·, 2.0)`로 홀드에 **들어가** 멈춘다(홀드 시작 `HOLD_START` 활/검/도구 0.78,
  캐스터/포병 0.80, 소총 0.25). 홀드에서 몸 0.025h 침하(`HOLD_DIP`), 해방 뒤 첫 키는 더 큰 `ease_out`(활 요 1.08,
  소총 총구 0.13, 검 피치 0.16) + 피치 킥, 되돌림 키는 `back_out(·,1.6)`. 손 떨림(0.003h = 0.15px)은 0으로 — 죽은 홀드.
- **HA2 대기**: 호흡 0.006→0.015h(`breathe`: 빠른 들숨·느린 날숨, 주기 경계 0), 흔들림 0.010→0.025h + 체중 이동
  (짐 없는 다리 0.01h 들림, 롤 0.04rad), 3.0~3.6s에 **무기 주도 피젯 1회**(활 기울임 Rx 0.45, 소총 견착, 검 재파지
  Rx 0.5, 지팡이 들기, 렌치 어깨, 포병 버티기). t=0·6s에서 0(루프 이음).
- **검수 모드** `--candidate DIR`: `game.blend` **사본**을 `DIR/<id>/`에 두고 저작·병합 GLB·`candidate.json`만 쓴다
  (원본·`art/models`·매니페스트 불변). 2026-10-18 echo·jokull 후보(`build/casual-overhaul/after/wp-d/clips/`):
  루프 이음 0, 홀드 6프레임(f25~30, 4mm 미만), 침하 0.025h, 해방 킥 0.078/0.132u, 피젯 활끝 0.240u / 검끝 0.266u
  (≥0.2u = 8px), 호흡 0.015h·흔들림 0.027h·다리 0.01h(`<id>/sheet/numbers.json`, EEVEE 시트 `<id>/attack_sheet.jpg`·
  `idle_sheet.jpg`). 런타임 계약(`probe/candidate_probe.gd`: GLTFDocument로 후보를 읽어 어댑터 장착): 조준 무발사·
  해방·복귀·미리보기 정확.
- 실행(메인): `python3 tools/3d/author_native_motion.py --all --jobs 4` → `bash tools/godot_import.sh` → 영웅 검사·
  `tools/3d/check_native_deformation.py`. 배치가 실리면 런타임 `HOLD_T`를 0.78/0.80으로 내려도 된다(선택: 홀드가
  클립 0.78부터라 지금 값도 홀드 안이다).

### 한계

- 되돌림(오버슈트)은 어느 비트에서도 1px 이하다(해방 −2%, 회전 0.4px). 48px에서 읽히는 것은 홀드·스냅·팝·기울기다.
- 보행 흔들림 0.14rad는 카메라 쪽 보행에서 ±3.6px로 줄고, 뼈가 아니라 상체 전체가 끄덕인다(머리 뼈 없음).
- 안드로이드 실기기 검수는 하지 않았다.

## 2026-10-12 추가 — 보행 접지(공중부양 제거)

사용자 피드백 "캐릭터 걷는 모션이 공중부양하는 느낌". 실제 GL 캡처와 스킨 정점 추적
(`tests/3d/grounding_probe.tscn`: 다리 뼈에 지배적으로 가중된 최하단 정점 = 발바닥을 매 프레임
스키닝해 높이·접지점을 잰다)로 특정한 원인은 네 가지였고, 모두 런타임 합성 레이어와 월드 배치
높이에서 고쳤다. 클립(GLB)·기하·소켓·피해 시점·wind 규칙·시뮬 값은 그대로다.

- **원인 1 — 발 미끄러짐(스케이팅)**: 저작 `WalkLoop`의 다리는 정현파 스윙이고 보폭은 기하 보폭의
  1.3배(`5.2·hip·sin A`)라, 디딤 발이 땅에 있는 동안에도 몸 속도의 45~87%로 앞으로 끌려갔다
  (echo 3.4u/s +64%, brasa 2.1u/s +87%, triton 2.0u/s +68%, Limne +65%, pip 5.1u/s +45%).
  다리가 가위질을 해도 발이 땅을 밀지 않으니 미끄러지듯 떠 보였다.
- **원인 2 — 디딤 순간 발이 공중**: 클립의 vault는 기하 낙차의 0.8배이고 2026-10-11 달리기 성형이
  다리를 벌린 순간 몸·다리를 함께 띄웠다(`RUN_FLIGHT`). 그래서 발이 땅에 닿아야 할 디딤 순간에
  앞발이 0.04~0.10u 공중에 있었고, pip 5.1u/s는 한 주기의 35%가 양발 모두 공중이었다.
- **원인 3 — 발바닥 기하**: 이 리그의 발은 고관절 피벗(0.29h) 아래 **뒤꿈치**에 매달린 길이
  0.14~0.26h의 평판이다(피벗 뒤로는 0.04~0.16h). 다리가 뒤로 스윙하면 발끝이 땅을 뚫고(−0.04~
  −0.13u), 앞으로 스윙하면 발끝이 들린다. 점 발 모델로는 심을 수 없다.
- **원인 4 — 월드 높이**: 영웅 루트가 `world(p, 0.07)`, 몬스터가 `world(p, 0.14)`인데 투기장 흙
  디스크 윗면은 0.015, 길 0.029, 광장 0.046이다(`arena_world.gd`; 옛 값은 흙 윗면 0.055인 레거시
  지도용). 영웅은 흙 위 0.055u, 몬스터는 길 위 0.11u 떠 있었고 키 라이트 그림자가 발에서 떨어졌다.

### 고친 것 (`hero_locomotion.gd`, `native_character_model.gd`, `limne_model.gd`, `stellar_world.gd`)

- **심는 보행(planted gait)**: 다리와 골반 높이는 더 이상 클립을 샘플하지 않고 `HeroLocomotion`이
  매 샘플 풀어낸다. 발마다 디딤(stance)/스윙 일정을 두고(왼발 디딤 위상 0, 오른발 0.5), 디딤 중에는
  **뒤꿈치 → 발끝으로 구르는 접촉점이 땅에서 움직이지 않도록** 고관절 각을 역산한다(뒤꿈치 구간은
  뒤꿈치를 중심으로 한 호, 발끝 구간은 발끝을 중심으로 한 호; 접촉 이동량 = `leg·sin A_f + heel·
  (1−cos A_f) + leg·sin A_b + toe·(1−cos A_b)`). 골반 높이는 그 순간 땅에 있는 발의 최저점이 땅에
  닿는 값을 따른다(발끝 로커 상승은 70%만 반영, 나머지는 발끝이 살짝 잠겨 몸이 튀지 않게).
  디딤 직후 0.025·leg 가라앉는 체중 정착과 0.03rad 상체 끄덕임, 다음 발이 닿기 전 0.1주기 동안
  미리 내려가는 사전 하강(걷기의 양발 지지)을 넣었다. 스윙 발은 `0.20·leg`(달리기 +60%)만큼
  앞쪽에 치우쳐 들린다(`sin(π·w^0.55)`: 발끝이 땅을 긁지 않게 빨리 뜨고 디딤 전에 내려온다).
- **속도별 일정**: 디딤 비율(duty) = 묵직한 걸음 0.58(양발 지지) → 2.6u/s 0.50 → 5.1u/s 0.32
  (양발 공중의 비행 구간, 비행 길이에 비례한 호 최대 0.10·leg). 한 주기 보폭 = 접촉 이동량 / duty,
  즉 **발이 땅을 미는 만큼만 전진**한다. 앞 스윙은 저작 진폭의 0.72(걷기)~0.92(달리기), 뒤 스윙은
  1.15~1.45(뒤로 뻗는 밀어내기), 묵직한 걸음은 +25%. 짧은 다리 클립(0.40rad)은 최소 0.52rad로
  걷고, 케이던스 상한 2.7주기/s를 넘으면 duty를 0.25까지 내려 미끄러지는 대신 튀어 달린다.
- **발바닥 치수**: `NativeCharacterModel._measure_sole()`이 영웅 id마다 한 번(3~4ms, 정적 캐시)
  다리 뼈에 가중된 최하단 정점의 피벗 기준 앞·뒤 길이를 잰다(echo 발끝 0.168h·뒤꿈치 0.043h,
  pip 0.138h/0.163h, triton 0.264h/0.074h, brasa 0.189h/0.080h, jokull 0.050h/0.250h — 검을 앞으로
  든 영웅은 bbox 중심이 앞으로 가서 발이 피벗 뒤에 있다). 보행 모델에는 발끝 0.10~0.22h, 뒤꿈치
  0~0.12h로 묶어 넣는다(그대로 넣으면 jokull은 디딤마다 0.2u 튄다). `motion.sole {toe, heel}`과
  `motion.leg_swing`을 매니페스트에 적으면 측정값 대신 쓴다. 뼈가 모두 절대 컨트롤이라 다리 원점도
  골반 높이를 함께 탄다(안 그러면 발끝이 몸 상승분만큼 땅에 잠긴다).
- **Limne**: 같은 `HeroLocomotion` 일정을 절차 다리(피벗 0.45, 발끝 0.30, 뒤꿈치 0.05, 진폭 0.6)에
  적용한다.
- **월드 높이**: `StellarWorld.HERO_GROUND 0.03`·`MONSTER_GROUND 0.04`(투기장; 광장에 서는
  몬스터는 0.006 잠기고 길에서는 0.011 뜬다). 레거시 `build_map`은 자기 흙에 맞춰 0.07/0.14로
  되돌린다. 영웅 접지 그림자 판은 루트+0.02(광장 윗면 위).
- 제거: `_shape_gait`, `RUN_FLIGHT`·`RUN_LIFT`·`RUN_LEG_SWING`·`SLOW_STOMP`. 팔 펌프·상체 기울기·
  엉덩이 롤·런지는 그대로다.

### 검수 (`build/walk-grounding/`)

실제 GL(Xvfb, llvmpipe) 촬영. 무대 프로브 `tests/3d/grounding_probe.tscn`(투기장 조명·흙 높이·0.5u
눈금 지면, 모델이 실제로 이동하고 두 카메라가 따라감: 옆면 210px/u·게임 각도 49px/u=1280 기준)와
실제 투기장 `tools/3d/melee_review.py --only gait`(1280×800·1000×625, 조이스틱 주행 핍 spd 1.50·브라사
0.62). 전은 커밋 `6b5f581`의 코드(worktree; 투기장도 그 시점의 반지름 500 지형), 후는 이 작업(메인이 작업 중인 반지름 600·나선 도로 위) — 지형·배율 차이는 비교 대상이 아니다. 재현: `python3 tests/3d/grounding_review.py
--state after`(전 상태는 `--state before --root-y hero=0.07,monster=0.14`), 표는 `summary.md`.

| 대상 | 디딤 순간 발 높이(u) 전→후 | 평균 최저 발(u) | 디딤 중 접지점 이동(몸 속도 대비, 진행 방향) | 양발 공중 | 케이던스(주기/s) |
| --- | --- | --- | --- | --- | --- |
| echo 3.4u/s | +0.099 → +0.004 | −0.033 → −0.010 | +71% → +1% | 0% → 0% | 1.91 → 2.16 |
| jokull 3.4u/s | −0.129 → 0.000 | −0.088 → +0.024 | +77% → (디딤 판정 3프레임, 발이 0.02~0.05 떠서 비교 불가) | 0% → 48% | 2.18 → 2.70 |
| brasa 2.1u/s | −0.012 → −0.001 | −0.048 → −0.031 | +71% → +5% | 0% → 0% | 1.62 → 1.91 |
| triton 2.0u/s | +0.023 → +0.019 | −0.084 → −0.064 | +53% → +2% | 0% → 0% | 1.50 → 1.64 |
| pip 5.1u/s | +0.041 → +0.003 | +0.007 → +0.003 | +29% → +4% | 38% → 30% | 2.45 → 2.70 |
| Limne 3.4u/s | +0.088 → +0.026 | −0.040 → −0.015 | +69% → +19% | 0% → 0% | 2.05 → 2.54 |
| ember_imp / blaze_fox / stone_golem | (클립 그대로) | 흙 위 간격 +0.114/+0.084/+0.095 → +0.014/−0.016/−0.005 | 변화 없음 | | |

- 직접 확인(`build/walk-grounding/*_game.gif`·`*_side.gif`, 컨택트 `*_contact.jpg`, 발 확대
  `*_feet_*.jpg`·`*_final_game.jpg`, 투기장 `arena_gait_before_after_{1280x800,1000x625}.jpg`,
  `after/arena/<해상도>/gait_*.gif`): 전에는 여섯 영웅 모두 부츠가 팀 링 위에 떠 있고 다리만
  가위질했으며, 후에는 부츠가 링·지면에 닿은 채 뒤꿈치→발끝으로 구르고 디딤 발이 눈금 위에서
  멈춘다. 몬스터는 키 라이트 그림자가 발에서 떨어져 있던 것이 붙는다. 수직 진폭은 0.03→0.05~0.08u
  (디딤에서 가장 낮고 밀어내기에서 조금 오르는 다운-업).
- 남은 것: 발이 피벗 뒤에 있는 리그(jokull·phorkys·candela 등)는 앞 스윙이 0.08~0.12rad로 줄어
  뒷다리 위주로 달리고 디딤 발이 늦은 디딤에서 0.02~0.05u 뜬다(5.4걸음/s). 긴 발끝(triton 지느러미
  0.26h, 로브 자락 0.3~0.4h)은 밀어내기에서 발끝이 0.06~0.1u 땅에 잠긴다(이전에도 잠겼음, 발목이
  없어 남김). 짧은 다리 영웅은 2.7주기/s 상한에서 25% duty로 튀어 달린다. Android/iOS 실기기 검수는
  하지 않았다.
- 회귀 검사(`STELLARDEFENSE_NO_SAVE=1 godot --headless`, 로그 `build/walk-grounding/logs/`):
  `arena_motion_check` 30/0, `arena_idle_facing_check` 17/0, `hero_speed_melee_check` 171/0.
  `arena_pose_check` 300건 중 39건·`native_hero_check` 3,779건 중 54건·`limne_model_check` 182건 중
  1건은 모두 「다리 뼈 원점이 rest에서 0.10 안」이라는 옛 가정(레거시 누적 버그 방지용)에 걸린다 —
  심는 보행은 다리 원점이 골반 높이+들기(≤0.13u, 30초 뒤에도 0.11~0.13으로 누적 없음)를 타므로
  임계를 0.25로 올려야 한다(`tests/arena_pose_check.gd:25`, `tests/native_hero_check.gd`
  `walking keeps the leg pivot grounded`, `tests/limne_model_check.gd:143`). `native_monster_check`
  1,239건 중 1건은 `world(at, 0.14)`를 고정한 옛 가정(`tests/native_monster_check.gd:265`,
  `StellarWorld.MONSTER_GROUND`로 바꿔야 함). 검사 파일은 이 작업 범위 밖이라 고치지 않았다.

## 2026-10-11 추가 — 캐릭터별 이동 속도 보행과 검 근접 런지

사용자 요청으로 캐릭터마다 이동 속도 배수(`spd`, `Balance.hero_speed` = 170 logical/s × spd,
표는 0.60~1.50 → 2.0~5.1 world units/s; 이 세션 중 메인이 적용)가 생기고, 검 영웅 10명은 투사체 없이
해방 순간 칼이 직접 벤다(`BattleSim._strike`). 모션 쪽 대응은 두 가지이며 클립(GLB)·기하·
소켓·피해 시점·wind 시간 왜곡 규칙은 바꾸지 않았다. 모두 런타임 합성 레이어다.

- **속도별 보행 성형**(`HeroLocomotion` + `native_character_model.gd` `_shape_gait`/`_pump_arms`,
  `limne_model.gd`). 저작된 `WalkLoop`은 빠른 한 주기라 5.1u/s에서는 발이 3.9주기/s로 돌아
  잔떨림이 됐다. `run_factor()` = smoothstep(2.6, 5.1, 속도), `slow_factor()` = 2.0u/s에서 1 →
  2.6u/s에서 0. 보행 위상은 `stride × stride_scale()`(달리기에서 ×1.6, 5.1u/s 보폭 1.36 기준
  2.3주기/s; 핍 1.30은 2.45주기/s)로 나눈 이동 거리로 전진하므로 발 미끄러짐 원칙은 그대로다.
  달리기(run)는 다리 스윙 ×(1+0.35r)·무릎 들기 ×(1+0.7r), 보행의 「받침 다리 위에서 몸이
  내려앉는 vault」를 **비행 호**(다리가 벌어질 때 몸·다리가 함께 0.11u(키 비율) 올라가 두 발이
  땅에서 뜨고, 다리가 모일 때 내려앉음)로 바꾸며, 상체 기울기 +0.10rad, 팔 스윙 +55%·팔꿈치
  +0.32rad(저작 보행의 팔 배율을 그대로 따라 양손 소총 파지는 0, 활·검 주무기 팔은 0.45/0.7).
  묵직한 걸음(slow)은 vault를 1.35배 깊게, 상체를 0.05rad 세우고 엉덩이 롤 +0.045rad.
  Limne는 같은 인수를 절차 보행에 곱한다. 수치 확인: `tests/3d/gait_numeric_preview.tscn --id pip
  --speed 5.1`(위상 0.082/프레임=2.45주기/s, 다리 ±30.7°, 몸 높이 0.007~0.114u 비행 호, 양팔
  교대 10~50°).
- **검 런지**(`NativeCharacterModel._apply_lunge`, `Balance.is_melee(unit)`인 영웅만). 적이 1.1~2.5u
  앞에 있으므로 해방(fire) 순간부터 0.09초 동안 진행·조준 방향으로 0.17u(키 비율) 전진하며
  0.045u 뜀, 0.20초까지 유지, 0.46초에 제자리(0.5초 회복 안). 시뮬 위치는 변하지 않는다 —
  월드가 매 프레임 쓰는 `position` 위에 오프셋을 더하고, 월드가 되돌리지 않은 호출(이벤트
  재생의 두 번째 `animate_visual`)에서는 먼저 빼므로 누적되지 않는다. 서 있을 때는 무기 손 쪽
  다리를 0.42rad 앞으로, 반대 다리를 0.22rad 뒤로 디뎌(보행 중에는 생략) 발 미끄러짐 없이
  한 걸음 들어가 베는 것으로 읽힌다. 접지 그림자·팀 링은 루트의 자식이라 함께 움직인다.
- 베기 호·칼날 접촉 이펙트는 [VFX_LIGHTING.md](VFX_LIGHTING.md)의 「검 근접」 절, 검수 자료는
  `build/melee-speed/`(두 해상도, 전투 화면 `strike_*`, 보행 `gait_*`, 무대 `stage/`)이다.
  검수 하네스: `tests/3d/melee_visual_preview.tscn`(`--gait-only`, `--probe`),
  `tests/3d/native_character_visual_preview.tscn --gait-only --speed N`, `tools/3d/melee_review.py`.
- 한계: 비행 구간이 저작 클립이 아니라 수직 오프셋이므로 발목·무릎 굽힘은 없고, 팔 펌프는
  저작 스윙 공식의 근사(어깨·팔꿈치 피벗 회전)다. 양손 소총 파지는 팔을 흔들지 않는다.
  런지는 월드가 `position`을 매 프레임 다시 쓰는 계약에 기대므로 다른 어댑터가 루트를
  직접 옮기면 함께 옮겨진다(현재 월드만 쓴다).

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
  2026-10-15 모바일 예산 이후 이 기준 GLB는 저폴리 런타임 GLB(6,000삼각형·512² 아틀라스)이고 고폴리 원본은
  `build/character-3d/highpoly-2026-10-15/glb-base/`에 있다. 클립은 이전과 같이 접붙고 저폴리 기하가 유지된다
  ([NATIVE_HERO_PRODUCTION.md](NATIVE_HERO_PRODUCTION.md) 「2026-10-15 현행 런타임」).
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
