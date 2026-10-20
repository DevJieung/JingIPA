# 몬스터 3D 모션 (대기·보행·회전·피격·사망·등장·수정 포위 공격)

2026-10-10 사용자 요청 "프로덕션 수준의 캐릭터 움직임"에 따라 25종 native 몬스터의 움직임을
재제작한 기준이다. 기하·UV·가중치·뼈 배치는 바꾸지 않았고, 클립 세트와 런타임 어댑터만 새로 만들었다.
2026-10-15 모바일 예산으로 런타임 기하·UV·텍스처는 줄었지만(뼈·클립 바이트는 동일) 이 문서의 모션 기준은 그대로다.
`author_monster_motion.py`는 `game-lod.blend`가 있으면 새 클립을 저폴리 런타임 GLB에 접붙인다
([NATIVE_MONSTER_PRODUCTION.md](NATIVE_MONSTER_PRODUCTION.md) 「2026-10-15 현행 런타임」).
데이터·판정·난수·저장은 건드리지 않는다. 월드 쪽 계약은 `game/3d/stellar_world.gd`(부모 소유)가 정한다.

## 2026-10-18 추가 — 피벗 비트 (캐주얼 3D 개편 WP-D)

사용자 평가 "싼마이 AI 3D" 개편(`build/casual-overhaul/PLAN.md` §3 WP-D)의 몬스터 몫. 모든 레버는 피벗
(`_apply_pivot`)·`face_toward`·`visual_event("spawn")`에 있고 `_compose/_sample/_apply_skeleton`과 C++ 커널은
그대로다(`native_parity_check` 96/0, 재빌드 없음). 체형 배율 `m`(`BEAT_SHAPE`/`BEAT_KIND`): 슬라임·해파리 1.4,
탱크 0.6, 보스 0.7, 우상·트리언트 0.6, 나머지 1.0. 실측은 `build/casual-overhaul/after/wp-d/probe/beats_probe.txt`.

| 레이어 | 구현 | 실측 |
| --- | --- | --- |
| **M1 피격** | 시뮬 `flash`의 순수 함수. 평탄 구간 `a = smoothstep(0.20, 0.50, flash)·min(m·치명타 1.35, 1.5)`: 스케일 `(1+0.22a, 1−0.26a, 1+0.22a)`, 반동 `0.12H·a`(피격 반대쪽), 들썩임 `0.06H·a`; flash<0.20에서 `b = sin(π(0.20−flash)/0.20)·m`로 늘어남 `(1−0.06b, 1+0.08b, 1−0.06b)`. `set_hit_flash(0)`이면 즉시 원위치. 재질 섬광(WP-B `FLASH_ENERGY 2.6·smoothstep(0.80,0.95)`)이 0~1프레임만 희게 덮으므로 눌린 몸이 **색으로** 보인다 | 60Hz: 임프 y 0.742(26%, 6.8px)가 f0~5 유지, f6 0.82, f7 0.92, f9~11 늘어남 1.04~1.08; 치명타 0.651(35%); 슬라임 0.639(36%), 골렘 0.844, 골렘 왕 0.818. 30Hz 피격 띠: 흰 프레임 1 → 색 눌림 3프레임 → 늘어남 |
| **M3 등장** | rise: 0.55까지 ease-out 분출(키 +10%·m 늘림), 0.45~0.75에 0.08H 솟아오름, 0.72~1.0 정착 눌림 (1.18, 0.78, 1.18)·m. drop: 낙하 중 (0.94, 1.10, 0.94)·m 늘림, 0.62 착지 눌림 (1.26, 0.68, 1.26)·m. 둘 다 `SPAWN_SEC` 0.45에 정확히 원위치 | 임프: 땅 위 +0.057u(f16) → y 0.781(f23, 5.7px) → f27 원위치; 슬라임: 낙하 y 1.139 → 착지 0.660(6.5px) |
| **M4 사망** | 0.08~0.20s 팝 ×(1+0.15·m) → 0.20~0.45s 납작 (1+0.25, 1−0.20)·m → 가라앉음(기존 시간). splat은 0.55까지 납작. 쓰러짐(topple/back/side)은 되튐 0.10→0.22rad + 0.08H 튕김. 공중체는 `FALL_SEC` 뒤에 팝. `_death_total` 불변 | 임프 ×1.148(0.13s) → (0.80, 1.25); 골렘 −1.37 → −1.20rad 되튐(0.73s) + 0.09u; 슬라임 ×1.207 → (0.72, 1.35) |
| **M5 출발·정지** | 이동 목표면 `pitch −= 0.12·(1−_w_move)`, 서면 `+= 0.10·_w_move` — FADE 0.18로 사라지는 한 프레임 스냅. 무거운 체형(m<1) 절반, 공중체 0 | 임프 0.12rad ≈ 2.6px |
| **M6 보행 흔들림** | 피벗(발 기준, 수직 바운스 없음) 피치 `−0.07·cos(2π·k·τ − 0.3)`, 롤 `0.045·sin(2πτ)`, `τ = 클립 시계/cycle`, k = 2(두 다리·트롯), 1(갤럽·슬라임·뱀), × `_w_move`·무게 배율 | 임프 1.3px, 거인 2.5px — 보행 무게는 MA1(`--gait v3`)의 몫 |
| **M7 선회 기울임** | `_bank`가 `HeroLocomotion.sod_step`(2.9Hz·ζ 0.5)으로 `yaw_rate·bank`를 따라간다. 루트 요는 그대로(단조) | 한 번 되돌림 ≈1px |
| **S18 군중 변주** | 등장 `sid`의 황금비 해시 h: 보행 위상 `h·cycle`을 **샘플러 시계에 더한다**(`_clip_time = motion_time + phase·_w_move` — 두 샘플러가 같은 수를 보므로 패리티 유지, 서 있는 몸은 맨 시계라 "첫 샘플은 시뮬 시계만의 함수"·`native_monster_check.gd:279-280` 유지), 크기 `1+0.04·sin(2πh)`, 대칭 체형(슬라임·버섯·해파리·우상)은 h>0.5에서 X 미러(롤·요 부호를 미리 뒤집어 기울기 방향 유지). sid 0은 중립 | 슬라임 sid 1~12: 위상 0.04~0.44s, 0.961~1.040, 미러 6/12 |

검사(2026-10-18): `native_monster_check` 1,239/0(C7 피격 복구·C8 단조 선회·C9 등장 0.8s·C10 사망 1.6s), `native_parity_check`
96/0, `arena_motion_check` 36/0, `arena_air_check` 107/0, `monster_check --assets` 88/0 — 임계값 수정 없음.
M2(뼈 움찔 2배)는 C++ 커널 수정이 필요해 하지 않았다.

### 재저작 `--gait v3` (MA1/MA2, `tools/3d/monster_motion.py`·`author_monster_motion.py`; 사용자 승인 뒤에만)

- `author_monster_motion.py --ids all --gait v3`: `monster_motion.apply_gait(params, shape, "v3")`가 저작 매개변수에만
  덧씌운다 — 두 다리 바운스 ≥0.07H·롤 ≥0.14·머리 ≥0.14·팔 ×1.6(≤0.8)·모든 두 다리 `impact=True`(`footfall` 바운스),
  사족 피치 ≥0.14·신축 ≥0.09; `die_pose`는 0→1 구간 `ease_in(2.0)`(매달렸다 떨어짐)에 앞서 0.06~0.20에 몸통 +7% 늘림.
  `native_monster_specs.json`의 `motion` 블록은 v2 그대로 쓰므로 기본값(`--gait v2`)은 오늘 숫자다.
- 검증(`build/casual-overhaul/after/wp-d/clips/monsters/`, 사본에서만): v2는 HEAD 라이브러리와 **fcurve 240개 전부 동일**;
  ember_imp v3 바운스 0.039→0.070H, 롤 0.099→0.278rad(±0.14), 머리 0.076→0.266rad, 팔 0.35→0.56, EEVEE 시트
  `ember_imp_v3_move_side.jpg`·`ember_imp_v3_die.jpg`. 배치 뒤 `tools/3d/check_native_monster_deformation.py` 필수
  (드래곤 머리 ±0.15 규칙은 v3가 건드리지 않는다 — 드래곤 보행은 `head_bob`을 쓰지 않는다).

## 2026-10-17 추가 — 공중 몬스터(fly): 비행 고도·접지 그림자·낙하

- 계기: 사용자 요청 "날아다니는 로봇이 지금보다도 더 공중에 떠있는 이미지로 수정 (로봇이아니라 몬스터)".
  같은 세션에 총·활 영웅만 공중 몬스터를 맞히고 공중 몬스터는 수호자의 몸에 막히지 않는 규칙이
  들어왔으므로(시뮬, 메인 소유) 로스터의 `fly: true` 세 종(`rapid_ray` ray·`jelly_seer` jelly·
  `runestone_idol` idol)은 실제 카메라 거리(`CAMERA_SIZE` 34, 영웅 1.65u ≈ 48px)에서 한눈에 공중으로
  읽혀야 한다. 기존 클립의 작은 부유(hover 0.12/0.10/0.08H ≈ 0.1u)는 "살짝 들린 것"으로만 읽혔다.
- **어디서**: 클립은 그대로다(GLB 바이트 불변, 재저작 없음). 고도는 어댑터 `native_monster_model.gd`의
  `FLIGHT` 표가 **피벗**에 얹는다 — 루트는 여전히 `world(p, monster_ground)`이고 시뮬 좌표가 유일한
  위치 원천이다. `StellarModels.monster()`가 로스터 `fly`로 메타 `_stellar_fly`를 켜고 접지 그림자
  `StellarContact`(루트 직속, +0.02)를 붙인다. 월드는 등장 이벤트에 `sid`를 실어 준다(봅 위상).

| 체형 | 고도 | 봅 진폭 / 주기 | 선회 기울임 상한 | 그림자(×키) | 화면 간격 1280×800 / 1000×625 |
| --- | --- | --- | --- | --- | --- |
| ray(가오리) | 1.35u | 0.10u / 1.9s | 0.45rad | 1.15×0.85 | 39px / 31px |
| jelly(해파리) | 1.25u | 0.13u / 2.5s | 0.28rad | 0.95×0.80 | 36px / 28px |
| idol(석상) | 0.95u | 0.07u / 2.4s | 0.20rad | 0.72×0.62 | 28px / 22px |

  화면 간격 = 고도 × cos(카메라 앙각 39.3°) × 37.6px/u. 영웅 키 48px의 60~80%라 그림자와 몸 사이가
  비는 것이 확실히 보인다. 다른 체형이 `fly`를 받으면 `FLIGHT_DEFAULT`(1.2u·0.10/2.0s)다.
- **봅 시계**: `_air_t`는 `face_toward` dt(시뮬 dt)로만 늘어 서 있어도(포위·막힘) 계속 떠다니고
  일시정지면 멈춘다. 위상은 등장 이벤트의 `sid` 황금비 해시(난수 없음). 첫 프레임은 시뮬 시계만의
  함수라는 규칙 그대로다.
- **등장**(`descend`): 고도 위 0.5H+0.6u(실측 시작 높이 가오리 2.46·해파리 2.48·석상 2.12u)에서 3제곱 감속으로 내려오며 스케일 인. 그림자는
  몸이 내려올수록 커진다(아래 k 식).
- **포위 타격**: 공격 클립 시간(= (위상−0.3) mod 1) 기준 0.3~0.62 예비에 고도 +10%, 0.62~0.70 타격에
  −22%로 급강하(피해가 드는 위상 감김 순간이 최저점), 0.70~1.0 복귀 상승. 실측(가오리) 1.38 → 0.96u.
- **피격**: 기존 스쿼시·반동에 더해 위로 0.05H×s 들썩임.
- **사망**(`die`): 0.42초 2차 가속 낙하(1.33 → 0.01u, 12프레임) → 고도 6% 튕김(+0.08u) → 기존 가라앉음/
  옆 넘어짐과 디졸브. 총 사망 시간(1.15/1.45s)과 `advance_death` 상한 1.6s는 그대로다. 달아남(scatter)과
  누수(leak)는 고도를 유지한다.
- **접지 그림자**: `contact_shadow.gdshader`에 `soft` 유니폼(0 = 기존 영웅 판, 1 = 공중 몸 — 코어가
  0.30~0.92로 퍼지고 가중치 0.75 → 0.40, 반그림자 0.45 유지; opacity 0.34에서 중심 알파 0.29).
  판 크기 = 표의 그림자 × 몸 키(가오리 0.94×0.70u). 매 프레임 `k = 1 − 0.28·(lift − 고도)/고도`
  (0.5~1.35)로 높이 날수록 작고 떨어질수록 크며, 디졸브와 함께 사라진다.
- **메타 계약**: 어댑터가 매 프레임 `node.set_meta("_stellar_fly_height", lift)` — 피벗이 땅 위로 든
  전체 높이(고도+봅+등장 하강+포위 급강하+피격 들썩임+낙하, 0 이상). 보행 몬스터는
  `StellarModels.monster()`가 0.0으로 둔다(native·원시체 모두). VFX는 `StellarWorld.monster_node(sid)`의
  이 메타로 타격 버스트를 몸에 둔다. 상태 표식(`StellarBurn/Frost/Stun`)도 이 높이에 올린다(월드는
  가시성·스케일·회전만 만진다). `motion_state()["hover"]`는 비행 고도(봅·급강하·낙하 포함, 등장 제외)다.
- **초상화·검수 도구**: `tests/3d/render_portraits.gd`는 `_stellar_grounded` 메타로 고도를 끄고 그림자를
  떼어 초상화 프레이밍을 지킨다. `native_monster_visual_preview.gd`는 카메라 프레이밍에서
  `StellarContact`를 제외한다(몸을 가운데 둔다).
- **검수 하네스**: `tests/3d/flyer_visual_preview.tscn`(실제 투기장: 문 하강 → 같은 차선의 보행 몬스터·
  길가 궁수 옆 보행과 피격 → 제단 앞 내려놓기 → 포위 40틱 → hp 0 사망) +
  `python3 tests/3d/flyer_review.py --out-root build/flyers/after --before build/flyers/before`
  (GPU 디스플레이 :1, 오프스크린 필름 1280×800·1000×625, 프레임 PNG·`<id>.gif`·`<id>_focus.gif/.mp4`
  (몸 추적 2배 크롭)·`<id>_keyframes.jpg`·`<id>_before_after.jpg`·`flyers_sheet.jpg`·`flyers-report.json`
  (프레임별 발·몸 화면 좌표·flash·메타 높이)). 첫 촬영에서 석상 장면의 제단 앞 내려놓기가 나선 차선을
  벗어나 두 몸을 수정 한가운데(거리 0)에 두는 하네스 버그가 있어(그 자리에선 heading이 0이라
  `face_toward`가 dt를 버려 봅도 멈춘다 — 실제 플레이에선 닿지 않는 자리) 차선 길이 기준으로 고쳐 석상만
  전후 재촬영했다.
- 검수 결과·남은 문제는 [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md) 「2026-10-17 공중 몬스터」.

## 2026-10-13 추가 — 흩어짐(scatter): 처치가 아닌 퇴장

- 계기: 한 판이 10탄으로 바뀌면서 탄 보스가 쓰러지면 남은 호위가 `die {scatter: true, gold: 0}`으로 한꺼번에
  전장에서 빠진다(시뮬, 메인 소유). 일반 사망(쓰러짐·가라앉음·디졸브)을 재생하면 「전부 처치했다」로 읽혀서
  세 번째 퇴장 종류를 두었다. 이 경로(`native_monster_model.gd`의 사망 경로)는 2026-10-13부터 VFX 담당 소유다.
  월드(`stellar_world.gd`)는 바꾸지 않았다 — 원래 이벤트 전체를 `visual_event(type, e)`로 넘기고
  `advance_death(dt)`가 끝날 때까지(상한 1.6초) 몸을 붙잡아 둔다.
- **세 가지 퇴장**: `die`(저작 `Die` 클립 + 체형별 쓰러짐/가라앉음 + 디졸브, 1.1~1.5초), `leak`(수정 도달,
  0.4초 축소), `die`+`scatter`(달아남). `motion_state()["death"]`가 `"die"|"leak"|"scatter"`를 돌려준다.
- **달아남의 시간표**(초, 시뮬 dt로만 진행 — 일시정지·배속 그대로):
  | 구간 | 몸 |
  | --- | --- |
  | 0 ~ `wait` | 멈춤: 시뮬이 더는 옮기지 않으므로 보행·포위 가중치가 0.18초에 대기로 풀린다(걷는 자리걸음 없음). 마지막 `FLEE_BRACE` 0.16초에 웅크림(가로 +9%·세로 −14%)과 뒤로 젖힘 0.10rad — 예비 동작. 파동이 곧바로 닿는 몸(`wait`≈0)은 웅크리지 않는다 |
  | `wait` | 승리의 파동 도착 = `StellarVfx.scatter_delay(e.p)`(수정 0 … 테두리 0.6). 같은 프레임에 그 몸의 연무가 태어난다 |
  | `wait` ~ +`FLEE_SEC` 0.50(생성 번호로 ±8%) | 달아남: `FLEE_TURN` 0.14초에 `StellarVfx.scatter_heading(e.p, sid)`(수정 반대쪽 ±0.3rad)로 돌아서고, 웅크림이 튀어 오르며(세로 +11%, 0.22초) `FLEE_DIST` 1.5u(±15%)를 `1−(1−u)^1.8`로 달린다. `MoveLoop`는 달린 거리 ÷ `PATH_SPEED`만큼 진행해 발이 땅을 따라간다. 0.24rad 숙이고 키의 28%(최대 0.34u)까지 뜬다. 디졸브 `q = 0.18 + 0.82·u^1.6` — 재질의 차가운 발광은 출발 순간 켜지고 몸은 달리기 후반에 흩어진다 |
  `Die` 클립은 섞이지 않고(`_w_die` 0) 쓰러짐·가라앉음도 없다. 가장 늦은 몸이 0.6 + 0.54 = 1.14초.
- 방향과 변위는 피벗(`CreatureRig`, 25종 모두 루트 기준 항등 변환임을 탐침으로 확인)에 얹는다: 루트의
  position/rotation은 여전히 월드 것이고, 달아나는 방향은 루트 기준 단위 벡터와 그쪽을 보는 요로 한 번만 구한다.
  난수는 쓰지 않는다(길이·거리·방향의 흩뜨림은 생성 번호의 황금비 해시) — 같은 입력이면 같은 달리기다.
- 일반 사망은 그대로다: 25종 × (처치·피격 중 처치·누수)의 매 프레임 피벗 변환·전 뼈 포즈·디졸브·섬광 값을
  적은 2,331줄 지문이 변경 전후 바이트 단위로 같다. `tests/native_monster_check` 1,239건·
  `tests/arena_motion_check` 30건 실패 0.
- 연무·검수·자료는 [VFX_LIGHTING.md](VFX_LIGHTING.md) 「런 단위 순간」의 「흩어지는 호위」
  (`python3 tests/3d/moments_review.py --moment scatter`, `build/vfx-stage/theme<NN>/<해상도>/scatter_*`).

## 2026-10-12 추가 — 지면 높이와 보스 2배 몸집

- **지면 높이**: 월드가 몬스터 루트를 `world(p, 0.14)`에 두어 투기장 길(윗면 0.029)·흙(0.015) 위에
  0.11~0.125u 떠 있었고 키 라이트 그림자가 발에서 떨어져 보였다(모델의 발바닥은 자기 y=0,
  `finish_native_monster.py`가 최저점을 원점에 둔다). `StellarWorld.MONSTER_GROUND = 0.04`
  (제단 광장 0.046에 서서 수정을 치는 순간 0.006 잠기고 길에서는 0.011 뜬다; 레거시 지도는
  `build_map`이 0.14로 되돌린다). 투기장 시뮬은 `motion_t`를 이동 거리/`PATH_SPEED`로 올리므로
  `MoveLoop`의 발은 원래 미끄러지지 않는다 — 몬스터 쪽 수정은 높이뿐이다.
- **보스 2배**(사용자 지시 "보스 캐릭은 두배 더 키워주고"): `StellarModels.monster()`가 `kind ==
  "boss"`인 native 모델의 루트 `scale`을 `BOSS_SCALE = 2.0`으로 둔다(레거시 원시체 보스는 1.40×2).
  월드는 루트의 position/rotation만 쓰고 scale은 건드리지 않으며, 어댑터의 등장·피격·사망·포위
  오프셋과 상태 표식은 모두 피벗/루트의 자식 로컬 값이라 자동으로 2배를 따른다(`native_monster_
  model.gd` 변경 없음). 검수: `tests/3d/boss_scale_preview.tscn`(실제 투기장에서 보스 5종 등장·
  보행·포위 타격·피격·사망), 자료 `build/walk-grounding/boss/<해상도>/`.
- 2026-10-12 검수(실제 투기장 GL, `tests/3d/boss_scale_review.py`, 1280×800 5종 + 1000×625 flame_dragon·
  titan_bloom, 렌더 오류 0, 판정 정상): 문 등장(rise/drop) → 차선 보행 → 제단 68 logical에서 포위 예비·
  타격 → 피격(세 사수) → 사망(leviathan·dragon·titan sink 1.17s, golem_king topple 1.47s) 모두 2배
  몸집으로 지면에 붙어 재생된다(`build/walk-grounding/boss/<해상도>/<id>.gif`, `<id>_siege.gif`·
  `<id>_siege_contact.jpg`(제단 2배 확대), `boss_all5_sheet.jpg`). 포위 자세에서 몸이 제단 광장 위에
  서고 수정은 몸 옆에 보이며 타격·넘어짐 순간에만 가려지므로 **포위 시각 오프셋은 넣지 않았다**.
  보스 HP 막대 높이는 UI 담당 몫이다. 하네스는 긴 나선 차선을 24장 촬영 뒤 제단 앞 36 logical로
  옮겨 걷게 하고, 사망 촬영 때 시뮬 항목의 `kind`를 `tank`로 바꿔 승리 화면이 몸을 가리지 않게 한다.
- **사망 자리의 검은 납작 덩어리**(VFX 담당 보고, `build/blast-vfx/final/calm_lake/1000x625/a_skill_
  blast_13~14.png`): 접지 그림자 판(영웅 전용, 몬스터에는 없음)과 지면 높이 변경과는 무관하다.
  어댑터+재질만 있는 무대에서 drop_slime(splat)·ember_imp(sink)를 0.04와 0.14 두 높이로 33ms 연속
  촬영(`tests/3d/grounding_probe.tscn --monster <id> --death`, `build/walk-grounding/death/`)해도 검은
  형체는 한 프레임도 없고, 실제 투기장 보스 사망 5종에서도 없다. 해당 캡처(66ms/프레임)에서는 살아
  있던 몸이 다음 프레임에 **통째로 검게, 납작하게** 바뀌어 2프레임 만에 줄어 사라지므로 사망 1.1~
  1.5초 연출이 아니라 사망 이벤트 위치에 뜨는 `Kind.DIE` 버스트의 혼합 표면(그을음/서리 자국,
  `vfx_burst_mix`)이 첫 프레임에 잘못된 나이/색으로 그려지는 쪽으로 보인다. 빈 땅 프로브에는
  사망이 없어 die 버스트 자체가 생성되지 않으므로 그 프로브로는 배제할 수 없다 — VFX 담당 확인 필요.

## 파일

| 역할 | 경로 |
| --- | --- |
| 체형별 안무 라이브러리(Blender) | `tools/3d/monster_motion.py` |
| 클립 재작성 CLI(편집 원본 `game.blend` → GLB → provenance/manifest/specs) | `tools/3d/author_monster_motion.py` |
| 신규 몬스터 피니셔(같은 라이브러리로 클립 작성) | `tools/3d/finish_native_monster.py` |
| 모션 파라미터(체형 기본값 → 종류 보정 → 몬스터별 `motion` 블록) | `tools/3d/native_monster_specs.json` |
| 런타임 어댑터(샘플링·블렌드·반응 레이어) | `game/3d/native_monster_model.gd` |
| 런타임 파라미터(`motion` 행: cycle/death/spawn/hover/turn_rate/turn_max/bank) | `art/models/native_monsters.json` |
| 공중 몬스터 비행 표(고도·봅·그림자, 2026-10-17) | `game/3d/native_monster_model.gd` `FLIGHT` |
| 변형·루프 이음 검사(4클립) | `tools/3d/check_native_monster_deformation.py` |
| 계약 검사 | `tests/native_monster_check.gd` |
| 연속 프레임 촬영 | `tests/3d/native_monster_visual_preview.gd`, `tools/3d/native_monster_review.py` |
| 공중 몬스터 투기장 촬영(2026-10-17) | `tests/3d/flyer_visual_preview.gd`, `tests/3d/flyer_review.py` |

재현:

```bash
env -u DISPLAY ~/.local/bin/bl -b --factory-startup --python tools/3d/author_monster_motion.py -- --ids all
bash tools/godot_import.sh
STELLARDEFENSE_NO_SAVE=1 ~/.local/bin/godot --headless --path . res://tests/native_monster_check.tscn
python3 tools/3d/native_monster_review.py --ids blaze_fox --display-base 170
```

## 클립 세트(30fps, 모두 GLB 안)

| 클립 | 길이 | 내용 |
| --- | --- | --- |
| `IdleLoop` | 90f(3.0s) | 호흡(2회/루프)·체중 이동·체형별 특징 동작. 1·2·3배 주파수만 써서 루프 이음 0 |
| `MoveLoop` | 체형별 13~48f | 1클립초 = 시뮬 시계 1초 = `PATH_SPEED` 82 logical = 1.64 world units 전진. 보폭을 이 값에 맞춘다 |
| `Attack` | 30f(1.0s) | 0~0.3 유지, 0.3~0.62 예비, 0.62~0.70 타격, 0.70~1.0 복귀. 양 끝 포즈 동일 |
| `Die` | 24f(0.8s) | 체형별 쓰러짐. 이후 런타임 피벗이 넘어뜨리거나 가라앉힌다 |

`MoveLoop` 길이(= 보행 주기)와 1주기 전진 거리:

| 체형(종류) | 프레임 | 주기 | 전진/주기 | 보행 |
| --- | --- | --- | --- | --- |
| blob 슬라임 | 14 | 0.47s | 0.77u | 웅크림→도약(늘어남)→체공→착지 눌림, 왕관부 지연 |
| quadruped 쾌속(여우·늑대·스라소니·도마뱀) | 15 | 0.50s | 0.82u | 횡단 갤럽(뒤왼0/뒤오른0.14/앞왼0.5/앞오른0.64), 지면 35%, 몸통 피치·신축, 머리 지연, 꼬리 추종 |
| quadruped 육중(마그마 브루트) | 26 | 0.87s | 1.42u | 대각 트롯(앞왼+뒤오른), 발 디딤 충격 하강, 머리 묵직한 끄덕임 |
| biped 떼거리(임프4) | 13 | 0.43s | 0.71u | 잰걸음, 다리 교차·팔 반대 스윙·몸통 바운스·요 비틀림 |
| biped 육중(거인3) / 보스(골렘 왕) | 30 / 36 | 1.0 / 1.2s | 1.64 / 1.97u | 느린 보폭, 발 디딤 충격 하강, 큰 롤, 팔 적게 |
| biped 주술(화염 사제·서리 마녀) | 23 | 0.77s | 1.26u | 로브 걸음, 지팡이 팔은 몸통 추종, 자유 팔만 스윙 |
| dragon(2) | 30 | 1.0s | 1.64u | 두 다리 보행 + 날갯짓(하강 빠름), 몸통 부유 바운스, 꼬리 파동 |
| ray | 21 | 0.70s | 1.15u | 양 지느러미 날갯짓+비틀림 지연, 상하 부유(hover 0.12H), 꼬리 채찍 |
| jelly | 36 | 1.2s | 1.97u | 갓 수축(빠름)→이완(느림) 펄스, 몸통 추진 지연, 촉수 끌림 |
| idol | 48 | 1.6s | 2.62u | 부유 바운스·진자 기울임·요 흔들림, 수정 1회전/주기 |
| serpent | 33 | 1.1s | 1.80u | S자 슬리더(몸통→목→머리 위상 지연, 꼬리 반대 위상), 지느러미 2배속 |
| tree | 33 | 1.1s | 1.80u | 뿌리 끌기(지면 60%), 큰 좌우 롤, 가지·수관 지연 흔들림 |
| mushroom | 17 | 0.57s | 0.93u | 뒤뚱 보행, 갓이 반대로 지연 흔들림 |
| plant(타이탄 블룸) | 36 | 1.2s | 1.97u | 뿌리 교대 끌기, 몸통 융기·휘청, 덩굴 뒤틀림, 꽃입 흔들림·맥동 |

좌표: Blender +Y 앞, +Z 위, +X 오른쪽. 뼈는 전부 독립 절대 제어라 `Pose` DSL이
`T·R(피벗)·S(피벗)`을 뼈마다 합성하고, 머리·꼬리·팔·날개·촉수·덩굴은 몸통 뼈를 **강체 추종**(`follow`)한다.
추종 체인에는 몸통의 비균일 스케일을 넣지 않아 glTF TRS 분해에서 전단이 생기지 않는다.

### 가중치 하드 시임과 진폭 한계

피니셔 가중치에는 매끈한 띠 외에 몇 군데 하드 경계가 있다: 드래곤·가오리 머리(`|x|<0.26H` 게이트),
타이탄 꽃입(`|x|<0.34H`), 젤리 촉수 좌/우(x=0 분할), 임프 가랑이 x띠(0.045~0.09H).
`tools/3d/check_native_monster_deformation.py`(짧은 모서리 8배 과신장)와 프레임별 감사로 확인한 규칙:

- 추종 뼈(머리·날개·덩굴 등)는 **피벗 회전만**, 몸통 대비 평행이동은 0.04H 이하.
- 드래곤 머리 회전 ±0.15, 타이탄 꽃입 ±0.16 이내. 돌진감은 몸통(`Body`) 피치·이동으로 만든다.
- 젤리 촉수 좌우는 같은 값으로 움직인다.
- 돌진·웅크림은 `Pose.shift`(추종하지 않는 모든 뼈 동시 이동)로 **몸 전체**를 옮긴다. 다리만 두고 몸통만
  0.2H 이상 옮기면 엉덩이 띠가 찢어진다. 사망의 몸통 하강은 0.20H 이내, 다리도 0.08~0.12H 같이 내린다.
- 25종 모두 4클립 과신장 0, `IdleLoop/MoveLoop/Attack` 끝점 이음 오차 0이어야 한다.

## 수정 포위 공격(Attack) 위상 매핑

아레나는 제단 반경 안에 들어온 몬스터의 `siege_t`를 1초마다 감고, 감기는 순간 수정에 피해를 준다.
월드가 `set_siege(phase)`에 [0,1) 위상을 주면 어댑터는 `clip_t = (phase - 0.3) mod 1`로 샘플한다.

| 위상 | 클립 시간 | 동작 |
| --- | --- | --- |
| 0.3~0.6 | 0~0.3 | 유지(미세 호흡) |
| 0.6~0.92 | 0.3~0.62 | 예비: 몸 전체 뒤·아래로 웅크림(`shift`), 머리/팔/날개 들기 |
| 0.92~1.0 | 0.62~0.70 | 타격: 몸 전체 앞으로 돌진, 프레임 21(=위상 감김 순간)에 타격 포즈 |
| 0.0~0.3 | 0.70~1.0 | 복귀(약간 지나쳐 되돌아옴) |

체형별 타격: 임프·거인·골렘 내려찍기, 지팡이 주술사 지팡이 찌르기(지팡이는 든 팔 추종), 사족 덮치기/들이받기,
슬라임 몸통 박치기(눌림→늘어나며 돌진), 드래곤 물기(날개 내려침), 가오리 급강하, 젤리·우상 마법 분출,
리바이어던 머리 내리치기, 트리언트 가지 내려치기, 포자 갓 내려찍기, 타이탄 꽃입 물기(덩굴 휘두름).
막힘(`blocked`)·마비는 위상 -1이라 대기 포즈다.

## 런타임 어댑터 상태기계

`animate_visual(motion_time, moving)`은 `IdleLoop`/`MoveLoop`/`Attack`/`Die` 트랙을 직접 샘플링해
가중 블렌드(위치 lerp·회전 slerp·스케일 lerp)한 뒤 뼈 포즈를 쓴다. 매 호출 입력에서 전부 재계산한다.

- 가중치 목표: `moving` → move, 서 있고 `siege≥0` → attack, 그 외 → idle. 크로스페이드 0.18s.
- 전진 시계 `step = max(face_toward가 준 dt, |Δmotion_time|)`. 첫 호출은 목표로 즉시 스냅하고
  dt를 버린다(같은 시계 = 같은 포즈). dt 0·같은 시계면 포즈가 변하지 않는다(일시정지 안정).
- 서 있는 몸의 `IdleLoop`는 `motion_time + stand_t`로 샘플하고 `stand_t`는 `face_toward` dt로만 는다.
  막혀 서 있어도 호흡하고, 아레나처럼 시뮬 시계가 멈춘 동안에도 월드 dt가 0이면 그대로 멈춘다.
- 마비: 월드가 켜는 `StellarStun` 가시성을 읽어 0.25s에 걸쳐 피벗 비틀거림(롤 0.07·피치 0.05)을 올린다.
- 피격: `set_hit_flash(f)`(시뮬 flash, 초당 5 감쇠) → `s=f^1.5`(치명타 ×1.35). 피벗 스쿼시
  (1+0.10s, 1−0.12s, 1+0.10s), `visual_event("hit")`의 `p` 반대 방향으로 0.05H·s 반동,
  머리 +0.22s·몸통 +0.06s rad 움찔. `StellarShading.set_hit_flash`로 재질 섬광은 VFX 담당에 넘긴다.
- `push` → 0.4s 비틀거림(피치 뒤로), `stun` 이벤트 → 비틀거림 선행.
- 회전 `face_toward(d, dt)`: 목표 `atan2(-d.x,-d.y)`. 첫 호출 스냅, dt 0이면 정지, 이후
  `1−exp(−turn_rate·dt)` 지수 접근을 `turn_max·dt`로 제한. 요 각속도×`bank`를 피벗 롤(±0.28)로
  올려 빠른 종은 몸을 기울이고 무거운 종은 느리게 돈다(종류별 `turn_rate` 4~12, `turn_max` 2.5~10).
- 등장 `visual_event("spawn")` 0.45s: `rise`(땅에서 솟음, 착지 눌림), `drop`(슬라임·드래곤·포자:
  위에서 떨어져 눌림 반동), `descend`(가오리·젤리·우상: 내려오며 스케일 인). 뼈 포즈는 건드리지 않는다.
- 사망 `visual_event("die")` 뒤 `advance_death(dt)`: `Die` 클립 0.08s 페이드 인, 이후 피벗이
  `sink`(0.45s부터 1.1H 가라앉음, 총 1.15s) / `splat`(슬라임, 1.1s) / `topple`(거인·골렘: 발을 축으로
  앞으로 1.4rad, 1.45s) / `topple_back`(트리언트, 1.5s) / `topple_side`(우상, 1.45s).
  디졸브 진행은 `StellarShading.set_dissolve`로 넘긴다. `leak`은 0.4s 축소·침강.
  `die`에 `scatter`가 실려 오면 죽지 않고 달아난다(맨 위 「2026-10-13 추가」).
  사망 중 상태 고리 3종은 숨기고 `animate_visual`은 무시한다. 모두 월드 상한 1.6s 안에 끝난다.
- 리소스: 생성 뒤 노드·메시·재질을 만들지 않는다. 피벗은 GLB의 `CreatureRig` 노드다
  (루트 position/rotation.z는 월드가 쓴다).
- 로드(2026-10-15): `NativeMonsterModel`이 종류별 PackedScene을 붙잡아 둔다. 전에는 한 종류의
  마지막 몸이 사라지면 장면이 메모리에서 내려갔고, 다음 등장 때 저장소에서 다시 읽었다(폰급 코어에서
  임프 30ms대, 보스 73ms 프레임). `StellarShading.style()`(공유 재질 조정, 정점 배열을 읽어 온다)은
  로드당 한 번만 돈다. 아레나는 전장 카드가 열릴 때 `ArenaScreen._load_stage_monsters()`가 그 탄의 두
  습격 몬스터와 보스로 `keep_only()`를 불러 미리 읽고 지난 탄 종류를 놓는다. 같은 측정에서 가장 무거운
  등장 프레임은 13.9ms(평소 11~14ms)다.

## 검수

- `tests/native_monster_check.gd`: 기존 계약(루프·인스턴스 독립·정지 재그리기·저장·RNG)에 더해
  회전 스냅/정지/수렴, 피격 스쿼시와 정확한 복구, 등장이 뼈 포즈를 바꾸지 않음, 포위 예비/타격/감김
  연속성, 사망 완료 시간·디졸브·정지 프레임, 반응 중 리소스 불변, 로스터 보존을 검사한다.
- 촬영: `native_monster_review.py`가 종마다 다각도·idle 24·move 32·상태 3·turn 16·blocked 12·
  siege 30·hit 8·spawn 14·die ≤48 프레임과 전투/밀도 장면을 찍고 `reactions.gif`·`reactions_contact.jpg`를
  만든다. 전후 비교는 `build/motion-overhaul/monsters/<id>/before/<해상도>/`(이전 GIF)와
  `build/character-3d/monster-review/<id>/<해상도>/`(현재)다.
- 결과 수치와 남은 문제는 아래 기록을 따른다.

## 기록 (2026-10-10)

- 25종 전체를 `author_monster_motion.py --ids all`로 재작성했다. TitanBloom은 수작업 보수 `game.blend`에
  클립만 다시 썼고 `provenance.topology_repair`를 유지했다. 기하 지문(정점·가중치·뼈) 25종 변경 0.
- 프레임별 찢김 감사(`build/motion-overhaul/tear-audit.json`): 4클립 전 프레임 과신장 모서리 0/25,
  `IdleLoop/MoveLoop/Attack` 끝점 이음 오차 ≤2e-18. 첫 통과 때 드래곤 머리·캐스터 지팡이·임프 가랑이에서
  찢김이 나와 위 진폭 규칙(추종 뼈 회전만, 몸 전체 `shift`, 지팡이 팔 0.2배)으로 고친 뒤 0이 됐다.
- `tests/native_monster_check.tscn` 전체 1,240건·실패 0. `--bench`: 41 몬스터 × 300프레임, 프레임당
  0.27ms(몸당 6.7µs, 헤드리스 GDScript·스켈레톤 비용만, 부하 평균 60 이상인 호스트).
- 통합: `arena_motion_check` 30/0, `monster_check --assets` 88/0, `arena_check` 88/0,
  `stellar_gameplay_check` 107/0, `stellar_render_check` 2,628/0. 로그는 `build/motion-overhaul/logs/`.
- 촬영: 25종 × 1280×800/1000×625, 종당 191~203PNG(사망 길이에 따라 다름), 렌더 오류 0.
  `build/character-3d/monster-review/<id>/<해상도>/`의 `reactions.gif`, `reactions_contact.jpg`,
  `move.gif`, `turnaround.jpg`. 전후 비교 `build/motion-overhaul/monsters/<id>/before_after.jpg`
  (이전 보행 → 새 보행 → 등장/회전/피격/막힘 → 포위 타격 → 사망), 로스터 시트
  `all25_walk_frame.jpg`·`all25_anticipation_pose.jpg`·`all25_strike_pose.jpg`·`all25_death_frame12.jpg`.
  직접 확인: 사족 갤럽/트롯/스프롤, 슬라임 도약, 드래곤 날갯짓, 가오리·젤리·우상 부유, 리바이어던 슬리더,
  트리언트·포자 걸음, 타이탄 융기; 25종 포위 예비(웅크림·팔/날개 들기)와 돌진 타격; 거인·골렘 왕 앞으로 넘어짐,
  트리언트 뒤로, 우상 옆으로, 슬라임 퍼짐, 그 외 주저앉음; 작은 화면에서도 실루엣과 반응이 읽힌다.
- 밀도 장면(`tools/3d/native_density_review.py`): 41몬스터(25종 전부)+12영웅, 1280×800/1000×625 각 15PNG,
  렌더 오류 0, 12연속 모션 프레임에서 종마다 다른 보행 위상이 보인다(`build/character-3d/density-review/`).
- 피격 프레임의 완전 흰색 2~3프레임은 VFX 담당의 재질 섬광(`StellarShading`, emission 2.4)이며
  이 문서의 몸 스쿼시·반동과 별개다. 디졸브도 같은 재질 구현을 쓴다.
- 한계: 뼈 추가(무릎·목)는 하지 않았다. 가중치 하드 시임 때문에 드래곤·타이탄의 머리/꽃입 자체 회전은 작고,
  돌진감은 몸통이 만든다. 지팡이 캐스터의 타격은 몸 전체 돌진과 자유 팔 위주다.
  실기기 FPS·GPU 스키닝 비용은 측정하지 않았다(기하·재질 수 불변).
