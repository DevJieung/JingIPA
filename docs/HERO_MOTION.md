# 영웅 모션 제작 (대기·보행·회전·공격)

2026-10-10. 사용자가 현재 캐릭터 움직임을 "초보 같다"고 평가하고 상용 3D 모바일 게임 수준의
대기·보행·회전·공격 모션을 요청했다. 이 문서는 영웅 49명(native GLB)과 Limne의 모션 2판
설계, 클립 구조, 도구, 검수 자료와 한계를 기록한다. 몬스터 모션과 총구 섬광·탄·피격 VFX,
조명·재질은 별도 담당의 문서를 따른다. 기하·가중치·리그·소켓·재질·초상화는 바꾸지 않았다.

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
