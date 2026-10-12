# 전투 VFX · 조명 · 캐릭터 재질

2026-10-10, `graphic_design_manager`(VFX·조명·재질 담당)가 모션 개편의 일부로 재제작했다.
대상은 Godot 4.7.1 **GL Compatibility**(Android/iOS)이며, 시뮬레이터(`game/*_sim.gd`)의
값·판정·난수는 읽기만 한다. 아트 방향은 [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md)의
푸른 밤 숲·옅은 안개·따뜻한 등불·입체 캐릭터를 그대로 따른다.

## 파일

| 역할 | 경로 |
| --- | --- |
| 이펙트 런타임 | `game/3d/stellar_vfx.gd` (`StellarWorld`의 자식 `Vfx`) |
| 조명·후처리 | `game/3d/stellar_lighting.gd` |
| 캐릭터·몬스터 재질, 피격 섬광, 디졸브 | `game/3d/stellar_shading.gd` |
| 셰이더 | `art/vfx/vfx_common.gdshaderinc`, `vfx_projectile`, `vfx_muzzle`, `vfx_burst`, `vfx_burst_mix`, `vfx_beam`, `vfx_zone`, `vfx_zone_base`, `vfx_slash`, `vfx_slash_base`, `vfx_dome`, `vfx_status`, `vfx_skill`, `vfx_skill_mix`, `weather.gdshader` |
| 절차 생성 텍스처 | `art/vfx/sprites.png`(4×4 아틀라스), `art/vfx/skill_sprites.png`(기술·보스 등장용 4×4), `art/vfx/noise.png` ← `python3 tools/vfx/gen_vfx_textures.py` |
| 접지 그림자 | `art/models/contact_shadow.gdshader` |
| 검수 하네스 | `tests/3d/vfx_visual_preview.tscn`, `tools/3d/vfx_review.py`; 검 근접·이동 속도는 `tests/3d/melee_visual_preview.tscn`, `tools/3d/melee_review.py` |

아틀라스 칸(256px): 0 글로우, 1 네잎 별, 2 여섯잎 반짝임, 3 링, 4 연기, 5 불꽃, 6 얼음 조각,
7 번개, 8 물방울, 9 화살, 10 예광탄, 11 초승달 베기, 12 룬 원판, 13 육각 격자, 14 불씨, 15 충격 호.
흰색+알파만 담고 색은 셰이더가 입힌다. 칸 번호는 셰이더가 읽으므로 바꾸지 않는다.
기술 아틀라스 `skill_sprites.png`(256px 칸): 0 별 조준 문양, 1 빛기둥, 2 지면 균열, 3 균열 발광(흐림),
4 유성 꼬리, 5 8방 섬광, 6 파편 덩어리, 7 안개 자락, 8 보스 소환진, 9 가시 포털 링, 10 바닥 발광 원판,
11 별 파편 줄기, 12~15 예비(투명). `vfx_skill*`은 전투 아틀라스 칸을 0~15, 기술 칸을 16~31로 읽는다.

## 레이어 구조 (모두 풀링, 생성 후 노드·메쉬·재질 생성 없음)

| 레이어 | 풀 | 그리는 것 |
| --- | --- | --- |
| 탄 `Bullets` | MultiMesh 120 | 속도 방향으로 정렬한 코어 스프라이트(무기별: 예광탄/화살/포탄/구슬/전기 구; 검은 탄이 없다) + 영웅색 글로우 + 리본 트레일(길이·폭 종류별, 속성별 흔들림) + 속성 입자 4개(불씨 상승·물방울 낙하·얼음 결정·전기 스파크) |
| 총구 `Muzzles` | MultiMesh 24 | 매 프레임 어댑터 `weapon_transform(side)`·`fire_strength()`를 읽는다. 무기별: 소총=별 코어+화염 줄기+스파크, 활=시위 번짐 선, 캐스터=손 밑 룬 원판+상승 반짝임, 포병=압력 원뿔+충격 링, 검=작은 칼날 글린트(코어 0.16·글로우 0.26, 베기 호와 접촉 이펙트 아래에 머문다), 도구=스파크 분사 |
| 버스트 `Bursts` | MultiMesh 64 | 가산 표면: 바닥 충격 링(선두 날카롭고 꼬리 부드러움, 광역은 들어온 방향으로 쏠림)+섬광 빌보드+스파크 8+모트 8+정면 링(사망 후광·방벽 육각·수정 충격; 칼날 접촉 `slash_hit`은 이 자리에 초승달 베인 자국). 혼합 표면: 연기/서리 안개 2+그을음/서리 자국 |
| 광선 `Beams` | MultiMesh 16 | 16분할 스트립. 광선=노이즈 스크롤 샤프트, 연쇄=프레임마다 꺾이는 번개, 도탄=튕긴 자리에서 다음 목표로 달리는 자취 |
| 베기 `Slashes` | MultiMesh 12 | 검 해방마다 하나. `Balance.MELEE_ARC`(110°)+좌우 9° 팔로스루의 부채꼴을 영웅의 **실제 사거리**(`sim.heroes[src].range`/UNIT)로 키우고 `fire.d`를 가운데에 둔다. 두 표면: 혼합 잉크 밑판(`vfx_slash_base`, 밝은 눈·얼음 위 가독성)+가산 칼날 자국(테두리 선·머리). 머리가 0.10초에 호를 가로지르고 쓸고 간 부채꼴 전체가 0.34초에 함께 사라진다. 자세한 규칙은 아래 「검 근접」 |
| 장판 `Zones` | MultiMesh 24+12 | `sim.zones` 룬 원판(착지 전엔 수렴하는 점선 링, 착지 후 회전 룬·틱마다 펄스·속성별 물결/호흡)+상승 모트 8+어두운 바닥판(밝은 눈 위 가독성). 추가 12칸은 캐스터 시전 중 발밑 원 |
| 기술 `Skills` | MultiMesh 6 | 인스턴스 하나가 연출 한 벌을 통째로 재생한다(`vfx_skill` 가산 50쿼드 + `vfx_skill_mix` 혼합 26쿼드, 드로우콜 2). 별빛 폭발(kind 0)·보스 등장 예고(kind 1)·보스 출현(kind 2). 아래 「공용 기술·보스 등장」 |
| 돔 `Dome0/1` | 2 | 수정 방벽 발동·패시브 방벽: 프레넬 반구+육각 격자+상승 스캔 |
| 점광원 `Pulse0..5` | 6 | 발사·광역·사망·수정 피격·기술의 짧은 OmniLight 펄스(그림자 없음, range 2~9). 포락선 `mode`: 0 감쇠(기본), 1 예고(고동치며 끝에서 정점), 2 출현(강한 섬광 뒤 긴 꼬리) |

버스트 종류(셰이더의 kind 코드와 같다): hit, splash, zone_tick, die, leak, block, push, frost,
stun, curse, spawn, wildfire, blast, freeze, ward, muzzle_smoke, ric_spark, beam_cap, bolt_cap,
cast_release, slash_hit(20, 칼날 접촉). 크기는 `r`·`em`·`crit`을 따르며(면역 `em=0`은 그리지 않음,
반감 0.72배, 약점 1.3배, 치명타 1.35배) 색은 이벤트의 `c`(영웅/몬스터 색)와 속성 색(`Balance.ELEM`)을 섞는다.

### 검 근접 (2026-10-11)
- 시뮬 계약: 검 영웅(`Balance.is_melee`)의 `fire`는 `melee=true`이고 **같은 틱에** `hit`(`melee=true`,
  `sid`, `p`=맞은 몬스터 위치)이 관통 수(최대 3)만큼 뒤따른다. `sim.bullets`에 검의 탄은 없다.
  `_flush_fires`가 `fire.melee`(또는 attack `sword`)를 `_melee_release`로 보내고, 그 틱의 melee hit은
  `_pending_hits`에 모았다가 같은 flush에서 `_melee_hit`으로 처리한다.
- **베기 호**(`_slash`): 중심은 시뮬의 영웅 위치(런지로 움직인 모델이 아니라 실제 판정 원점), 높이
  0.88u, 반지름 = 실제 사거리(`WEAPON_RANGE.sword` 60 기준 56~125 logical → 1.1~2.5u; 값이 바뀌면 따라간다).
  **가운데 방향**은 같은 틱의 첫 melee `hit`(겨눈 몬스터) 위치 − 영웅 위치다: `BattleSim._strike`가
  부채꼴을 영웅 위치 기준으로 두는 반면 `fire.d`는 총구점(무기 쪽으로 ~0.7h 떨어진 2D 시절 오프셋)
  기준이라 검 사거리에서는 최대 ~60° 어긋나 호가 맞은 몸들 옆으로 기울었다(`build/melee-speed/geom/`
  오버레이로 확인). hit이 없는 fire(모두 면역 등)만 `fire.d`로 돌아간다.
  메쉬는 단위 반지름·안쪽 0.42의 128° 띠이며 커스텀 y에 「휘두르는 방향 부호 × 띠 비율」을 넣어
  잔광이 반지름의 0.72u만 덮는다(긴 사거리에서 띠가 통째로 두꺼워지지 않게). 방향 부호는 무기 손
  (첫 해방 소켓 L/R): 저작 안무가 무기 손 어깨 뒤에서 반대편으로 베므로 L=왼→오른, R=그 반대.
  롤 ∓0.38rad으로 감아올린 쪽이 높고 팔로스루 쪽이 낮으며 앞 가장자리가 0.22rad 숙여진다.
  핍(도구)은 같은 메쉬를 세워(롤 90°) 위에서 아래로 내려치고 땅 아래는 깊이 검사로 잘린다.
- **칼날 접촉**(`Kind.SLASH_HIT`): 원점은 몬스터 몸 중심(키×0.55, 0.3~1.1u), -Z는 그 자리에서의
  칼날 진행 방향(호의 접선 × 부호; 도구는 아래). 초승달(아틀라스 11) 베인 자국이 0.20초 동안
  진행 방향으로 벌어지고, 섬광 0.08초, 진행 방향 쪽 스파크 7, 속성 모트 8. 바닥 링·연기는 없다.
  **시점**: 머리가 호를 ease-out으로 가로지르므로 몬스터 각도 분율 u에 대해 지연
  = 0.10 × (1 − √(1 − u))초를 `_delayed` 큐에 넣고 `update(dt)`에서 꺼낸다 — 관통 3명이 호 순서로
  ≤0.1초 간격을 두고 차례로 맞아 한 덩어리로 뭉개지지 않는다. 피해·숫자·몬스터 피격 스쿼시는
  시뮬 시점 그대로이며(≤0.1초 선행) 큐는 `dt=0`에서 멈춘다. 치명타·약점만 점광원 펄스.
- 예산: 베기 호 life 0.34(우선순위 1, 풀 12), 접촉 0.44(우선순위 0), `hit` 프레임 상한 10에 포함.
  검의 광역(헬가)·연쇄(케이든) 후속은 기존 splash/bolt 이벤트 그대로다. 투사체 셰이더의 초승달
  코어(shape 5)는 제거했고 아틀라스 11칸은 접촉 자국이 쓴다.
- 밝은 얼음 테마에서 가산 잔광만으로는 바닥색에 묻혀 띠가 보이지 않았다(검수에서 확인). 잉크
  밑판은 `elem_tint×0.42 + 영웅색×0.10`(선형)·알파 0.66~0.78로 가산보다 먼저 그려 부채꼴 몸통을
  만들고, 가산 패스는 테두리 선과 머리 위주로 둔다. 어두운 숲에서는 가산이 주가 된다.

### 공용 기술 · 보스 등장 (2026-10-12)
- 사용자 보고: 별빛 폭발이 플레이 중 안 보인다("서리 파동처럼 화려하게"). 캡처로 본 원인
  (`build/blast-vfx/before/`): (1) 바닥 링 2.2u·섬광 0.22초가 전부라 광역 명중(`splash`)과 구분되지
  않았고, (2) 밝은 얼음 바닥에서 가산 금색이 `vfx_wash`까지 받아 거의 흰 얼룩이었으며, (3) 수직
  요소·예고가 없어 화면의 어디서 터졌는지 시선을 끌지 못했고, (4) 몬스터 발밑 원점이라 몸에
  가려졌다. 서리 파동은 지도 전체 링(10.5u, 0.95초)이라 격이 맞지 않았다.
- **별빛 폭발**(`SkillKind.BLAST`, `arena_blast {p, r}`; 시뮬 피해는 시전 즉시, 연출은 아래 시간표):
  | 초 | 층 |
  | --- | --- |
  | 0.00 | 하늘 섬광(원점 +5.2u 위·화면 위쪽·옆 1.4u), 별 조준 문양이 1.35R→R로 수축(실제 피해 반지름 R=110/50=2.2u에 정확히 놓임), 작은 금빛 점광원 |
  | 0.00~0.18 | 유성 낙하(ease-in 제곱, 꼬리 2.2→5.2u, 머리 4잎 별) — `BLAST_FALL` |
  | 0.18 | 착탄: 뜨거운 섬광(0.13초)·8방 섬광 1→5.4u(0.42초)·빛기둥 5u(0.1초 상승, 0.5초 소멸)·조준 문양 백열, 점광원 9.0/범위 3.6R/0.9초(`_delayed` 큐, kind −1 = 펄스만) |
  | 0.18~0.48 | 바닥 충격파 링 0.15→R(ease-out3), 선두 백열·꼬리 금색, 안쪽 채움 0.45→0; **혼합 잉크 밑판**(진한 호박색 0.30/0.13/0.03 선형, 알파 0.62)이 같은 반지름 곡선을 따라 밝은 눈·얼음에서 띠를 만든다 |
  | 0.48~0.98 | 링이 R에 머물며 사라짐 — 플레이어가 맞은 범위를 읽는 구간 |
  | 0.18~1.2 | 별 파편 16(위 5~9.5u/s·바깥 1.6~4.4u/s, 중력 11, 줄기 스프라이트 속도 비례 신장, 흰→진한 금, 반짝임), 어두운 흙덩이 6(혼합층, 땅 아래로 떨어지면 소거) |
  | 0.26~1.7 | 불씨 12 상승, 바닥 잔광 원판 1.1~1.3R(0.65→0), 균열 발광(1.45R, 0.9초), 연기 6(금빛으로 달아오른 0.52/0.27/0.08 → 먼지, 0.5→2.1u) |
  | 0.18~2.1 | 지면 균열(혼합 soot, 1.9초 감쇠) — 슬롯 수명 `BLAST_LIFE` 2.0 |
  색은 `Look.GOLD`(COLOR)에서 셰이더가 `hot`(+흰 0.8)·`deep`(×1/0.62/0.30)을 만든다. 우선순위 4.
- **보스 등장 예고**(`SkillKind.BOSS_WARNING`, `arena_boss_warning {p, sec}`): 인스턴스 하나가 `sec`초
  (기본 4.0, 최소 0.5) 동안 돌고 그 시각에 모든 층이 꺼진다(`live`). 진행도 `prog=age/sec`로 강해진다:
  소환진(8번 칸) 1초에 0.4→1.05R로 자라 느리게 돌다 마지막에 급회전, 0.85초마다 1.9R→0.12R로 수렴하는
  링, 바닥 균열이 0.5→1.5R로 벌어지며 붉은 발광이 고동, 땅안개 8·보라 미스트 6 순환, 나선 상승 불꽃
  16·궤도 불꽃 12, 가늘게 깜빡이는 봉화 기둥(0→6.5u), 마지막 1.3초 번개·0.7초 포털 링 형성.
  점광원 `mode 1`(4.5, 범위 8.3u, sec초). 슬롯 수명 sec+0.2.
- **보스 출현**(`SkillKind.BOSS_BURST`, `arena_boss {p}`): 가시 포털 링이 1.3R 높이에서 0.28초에
  1→4.8u로 열리고 0.6초에 흩어짐, 섬광(1.3u 높이)·8방 섬광 1.5→7.5u·빛기둥 7.5u·바닥 충격파
  0.2→2.8R(0.55초)+먼지 띠(혼합)+소환진 백열 확장, 파편 16·불씨 12·흙덩이 10·먼지 6(0.8→3.4u)·
  안개 자락 8 방출, 0.55초 번개, 균열 2R. 점광원 `mode 2`(8.0, 범위 11u, 1.5초). R=`BOSS_SIZE` 1.5u
  (2.8배 보스 발자국보다 조금 넓게). 슬롯 수명 2.4. 팔레트: COLOR `BOSS_RED #ff3d5c`, 셰이더 내 보라
  (0.58/0.28/1.0)·뜨거운 분홍(1.0/0.80/0.90); 점광원 `BOSS_VIOLET #9a4dff`.
- 두 보스 이벤트는 `arena_world.event()`가 `vfx.arena_event(e)`로 넘긴다(메인 연동). 빛기둥·포털은
  카메라 쪽으로 R만큼 밀어 2.8배 몸체 뒤에 묻히지 않는다. 좌표는 `p`(논리 Vector2)만 읽는다.

### 2배 보스 몸 위의 이펙트 (2026-10-12)
- 보스는 루트 스케일 2(`StellarModels.BOSS_SCALE`)로 선다. 이펙트는 1u 남짓한 몸을 기준으로
  짜여 있어서, 그대로 두면 명중 섬광·스파크·연기(높이 0.3~0.5u, 카메라 쪽 당김 0.12~0.36u)와
  칼날 접촉 자국, 화상·서리 표식(궤도 반지름 0.22~0.30u)이 전부 **보스 몸속**에 묻혔다
  (깊이 검사에 가려 보이지 않음 — `build/blast-vfx/death-fix/boss/`의 before). 높이만 2배로
  올려서는 해결되지 않는다.
- `StellarVfx.fit_body(root)`: 몸이 월드에 들어올 때 한 번(`_on_actor_entered`), 루트 스케일이
  1이 아니면 메쉬 정지 경계의 평균 수평 반치수(월드 단위, 「몸 둘레」)를 재서 메타
  `_stellar_body_radius`에 적고 `_big_bodies`에 등록한다(티탄 블룸 1.46u, 빙하룡 1.84u, 수정 골렘 왕
  1.22u). 스케일 1 몸은 건드리지 않는다(이전과 픽셀 동일).
- **버스트**: `_body_scale_at(p)`가 이벤트 위치가 등록된 큰 몸의 둘레 안이면 그 스케일을 돌려주고,
  `_burst(..., body)`가 인스턴스 색의 **알파**에 싣는다(`COLOR.a`, 기본 1). `vfx_burst`·
  `vfx_burst_mix`는 공중 파트(섬광·스파크·모트·정면 링·초승달·연기)의 띄움 높이에 `body`를
  곱하고 `(body − 1) × 1.9u`만큼 카메라 쪽으로 당긴다. 직교 카메라라 당김은 화면 위치를
  바꾸지 않고 깊이만 앞당겨 큰 몸 **앞**에 그려지게 한다. 바닥 링·그을음은 그대로 바닥에 남는다.
  적용: hit·splash·beam/bolt 끝·die·push·frost·stun·curse. 시뮬 이벤트의 `sid`가 아니라 위치로
  찾으므로 `sid`가 없는 splash·beam도 잡힌다.
- **칼날 접촉**: 높이 `clamp(0.55 × 몸 키, 0.3, 1.1 × 스케일)`(3.10u 보스에서 1.10u → 1.71u),
  큰 몸에서는 축에서 칼 든 영웅 쪽으로 「몸 둘레 × 0.5」만큼 옮겨 양옆에서 치는 두 영웅의
  자국이 한 점에 겹치지 않는다. 기절 터짐은 `몸 키 + 0.12 × 스케일`.
- **상태 표식**(`vfx_status.gdshader` `body_scale`·`orbit`): 큰 몸은 그 스케일·둘레용 공유
  재질로 바뀐다(`_status_material(status, height, scale, orbit)`, 몸이 들어올 때 최대 3개 생성).
  크기·높이·궤도가 스케일을 따르고(기절 고리 궤도 1.67u → 3.34u), 불꽃·얼음 조각 궤도는
  `max(기본 × 스케일, 몸 둘레 × 0.75)`, 카메라 쪽 당김에 `(스케일 − 1) × 1.9u`를 더한다.
- 검사: `vfx_visual_preview --boss-melee`가 접촉 높이(몸 키의 40% 이상), 모든 명중 버스트의
  `body` 값, 표식 재질의 스케일, 큰 몸 탐색을 수치로 확인한다.

### 시계와 예산
- 모든 애니메이션은 셰이더가 `vfx_time`을 읽는다. 이 값은 `update(dt)`에서만 늘어나므로
  `dt=0`인 일시정지 재그리기에서는 탄·섬광·장판까지 전부 멈춘다.
- Compatibility의 MultiMesh 색·커스텀 데이터는 **16비트 부동소수**로 저장된다(실측: 2.2 →
  2.1992). 그래서 탄생 시각은 8초 단위 epoch(`vfx_epoch` 유니폼)에 상대적으로 기록하고,
  epoch가 넘어갈 때 살아 있는 인스턴스의 값을 다시 쓴다. 절대 시각을 넣으면 1분만 지나도
  나이가 어긋나 짧은 섬광이 사라진다.
- 일회성 효과(버스트·광선·베기)는 `StellarWorld.effects`(상한 72)를 예산으로 쓰고, 풀마다
  빈 슬롯 목록으로 슬롯을 준다. 예산이나 풀이 가득 차면 우선순위(기술 4 > 수정 피격 3 >
  사망·등장·방벽 2 > 광역·상태·광선 1 > 명중·틱·연기 0)가 같거나 낮은 것 중 가장 오래된
  효과를 내보낸다. 프레임당 상한: 명중 10, 광역 6, 서리 4, 마비 5, 밀침 6, 사망 8, 장판 틱 8.
  분열 탄두의 `split` 광역은 0.09초 간격으로만 그린다.
- 밝은 눈·얼음 테마(`main_body` aqua/frost)에서는 가산 레이어가 흰색으로 날아가므로
  `vfx_wash=1` 유니폼으로 알파를 0.66배, 색을 제곱 쪽으로 당겨 채도를 지킨다. 테마는
  `world.theme_id`로 판단한다.
- 혼합(blend_mix) 연기·안개·자국의 색은 **선형 값**이다. ACES 톤맵과 sRGB 출력이 중간톤을
  끌어올리므로 화면에서 중간 회색으로 보이려면 0.15~0.3 선형을 써야 한다(밝은 눈 위에서
  하얀 덩어리로 번지던 원인).
- 탄 풀 120·장판 24·총구 24는 시뮬 목록 크기만큼 `visible_instance_count`로 그린다.
- 드로우콜: 레이어마다 표면 1~2개(탄 1, 총구 1, 버스트 2, 광선 1, 베기 1, 장판 2) + 돔 2.
  CPU 작업은 탄·총구·장판의 인스턴스 변환 갱신뿐이다. 헤드리스 측정(이 작업용 데스크톱,
  GDScript): 탄 120·장판 24·영웅 12·프레임당 이벤트 40(예산 포화) 조건에서 2.4ms/프레임,
  이벤트 없이 탄·장판 동기화만 0.54ms/프레임.

## 조명 (`stellar_lighting.gd`)
- 키: 달빛 `#c4dbf5` 1.12, 오른쪽 뒤 위에서(`(-0.42,-0.74,0.52)`) 비춰 그림자가 카메라 쪽으로
  떨어지고 어깨·머리에 빛이 걸린다. 직교 그림자, `shadow_blur 1.6`, bias 0.028/normal 1.1,
  opacity 0.86. 아레나는 1.08·`(-0.40,-0.80,0.45)`·거리 66.
- 필: 등불 `#ffcf9a` 0.34, 카메라 왼쪽 앞(그림자 없음) — 얼굴·정면 가독성.
- 림: `#7fb0ff` 0.42, 정후방. 캐릭터 재질의 rim 항과 함께 실루엣 가장자리를 긋는다.
- 환경: 앰비언트 `#8fb2d4` 0.27(아레나 `#8db4da` 0.29), ACES 톤맵·노출 1.04·white 4,
  깊이 안개 `#1a3449` 0.0042(아레나 `#143148` 0.0070), 글로우 가산 0.42(아레나 0.48),
  임계 0.84 — LDR 버퍼라 임계는 밝기 컷이다. 섬광·수정·등불·탄 코어만 번진다.
- 지형 점광원(등불·수정)은 `arena_world.gd`/`stellar_world.gd`의 기존 값을 유지했다.
  날씨 입자는 발광 구체 대신 `weather.gdshader` 빌보드 모트(눈·불씨·꽃가루)로 바꿨다.

## 캐릭터·몬스터 재질 (`stellar_shading.gd`)
- `style(root, metal)`: 공유 GLB 재질을 roughness 0.70·specular 0.33·authored metallic·
  `rim 0.34 / rim_tint 0.55`로 맞춘다(이전 0.84/0.16 평탄 플라스틱 대체).
- 인스턴스별 상태는 Compatibility에 instance uniform이 없으므로 **표면별 override
  StandardMaterial3D**를 쓴다. `prepare_instance(root)`가 live 인스턴스마다 한 번 만든다
  (emission 켜고 에너지 0, 거리 페이드 **픽셀 디더**를 「온전」 값으로 켬, 투명도는 끔·알파 1
  고정 — 이후 값만 바꾸므로 셰이더 재컴파일이 없다). 호출 시점은 `StellarVfx`가 `world.actors.child_entered_tree`로
  잡는다(첫 프레임 전). 월드 밖에서 만든 카드는 첫 0이 아닌 섬광/디졸브에서 지연 생성된다.
  패킹 전에 override를 만들지 않는 이유: 헤드리스(dummy) 렌더러가 패킹된
  local-to-scene override 재질을 열거하지 못해 `ERROR`를 낸다.
- 발광은 `EMISSION_OP_MULTIPLY`에 **피부 텍스처를 emission 텍스처로** 넣어 몸의 무늬를
  따라 밝아진다(흰 실루엣이 되지 않는다 — 몬스터 담당 검수 반영).
  `set_hit_flash(root, 0..1)`: 따뜻한 `#ffebc7` 최대 1.5.
  `set_dissolve(root, q)`: q 0.30까지는 온전한 몸(사망 동작이 보이는 구간), 0.30→0.92에
  픽셀 디더로 빠르게 흩어진다(남는 비율 = 1 − smoothstep(0.30, 0.92, q)). 차가운 `#8ce6ff`
  발광(최대 1.9)이 흩어지기 직전에 올라 중간에 정점이라 성긴 구간이 평평한 회색 컷아웃으로
  보이지 않는다. 불투명 패스라 깊이·그림자·정렬이 유지되고 그림자도 같이 성겨진다.
- **디졸브는 알파를 쓰지 않는다 (2026-10-12 수정).** 이전 구현은 `TRANSPARENCY_ALPHA_HASH`에
  `albedo.a = 1 − fade`였다. GL Compatibility의 씬 셰이더에는 알파 해시 경로가 없어서(해시
  함수는 Forward+/Mobile에만 있다) 몸이 불투명 패스에서 **온전히 그려진 채** 재질 알파만
  프레임 버퍼의 알파 채널로 나간다. 투기장은 3D 뷰포트 텍스처를 2D 캔버스에 알파 혼합으로
  그리므로(`arena_view.gd` `draw_texture_rect`), 재질 알파가 1/6 밑으로 내려가는 순간
  (실측: 0.17까지 뷰포트 알파 1, 0.16부터 0; q≈0.76 이후, 몸이 사라질 때까지 0.18~0.26초)
  몸의 실루엣 전체가 화면 밑바탕색 `Look.BG_DEEP #080f19`(8,15,25)로 뚫렸다 — 사용자가 본
  「검은 덩어리」다. 3D 환경 배경색이나 깊이 프리패스 구멍이 아니다: 환경 배경을 자홍으로
  바꿔도 구멍 색은 그대로 (8,15,25)였고, 그 픽셀의 뷰포트 색 버퍼에는 몸 색이 그대로 있으며
  알파만 0이었다. 스킨 없는 `BoxMesh`도 같은 재질이면 똑같이 뚫린다. 2026-10-10부터 있던
  문제이며 어두운 숲 테마에서도 돌길(밝은 회색) 위에서는 똑같이 보인다. 영웅은 디졸브하지
  않아 알파가 늘 1이었으므로 증상이 없었다(같은 재질 경로를 쓰므로 함께 디더로 바뀌었다).
  지금은 `BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER`(인터리브드 그라디언트 노이즈 + `discard`)를
  쓴다: 폭 8000u 창을 밀어 `smoothstep(min, max, 카메라 거리)`를 몸 전체에서 사실상 상수로
  만들고(시야 깊이 80u 전체에서 편차 약 1%), 유니폼 두 개(`distance_fade_min/max_distance`)로
  남는 비율을 정한다. 온전(1)과 소멸(0)은 창 밖에 두어 정확하고, 모든 값은 mediump 보장
  범위(±16384) 안이다. 깊이 프리패스·색·그림자 패스가 같은 `discard`를 타고 프레임 버퍼
  알파는 1로 남으므로 구멍으로 **바닥**이 보인다. 재질·셰이더는 여전히 인스턴스 준비 때 한 번만
  만들어진다. 근거: `build/blast-vfx/death-fix/`(아래 「검수」).
- 어댑터가 이미 override한 표면(예: `NativeReactorAmber`)과 authored 발광 표면은 건드리지 않는다.
- 몬스터 상태 그룹(`StellarBurn/Frost/Stun`) 교체안: `StellarVfx.status_group("Burn"|"Frost"|"Stun",
  height)`가 공유 메쉬·재질의 루프 마커(불꽃 상승·얼음 조각 부유·머리 위 반짝임 궤도)를 돌려준다.
  어댑터 파일은 몬스터 담당 소유이므로 교체는 그쪽에서 결정한다.

## 검수
```
python3 tools/3d/vfx_review.py                       # 1280x800 + 1000x625, 두 분대
python3 tools/3d/vfx_review.py --res 1280x800 --squad a --quick
python3 tools/3d/vfx_review.py --skills-only --theme 0 --out-root build/blast-vfx/final/calm_lake   # 기술·보스 등장만
python3 tools/3d/vfx_review.py --skills-only --gate-only --probe --theme 20 --out-root DIR          # 보스 문 + 빈 땅 폭발
python3 tools/3d/vfx_review.py --death-only --dissolve-probe --theme 0 --out-root DIR                # 사망 디졸브(매 틱) + 재질 탐침
python3 tools/3d/vfx_review.py --boss-melee --theme 20 --out-root DIR [--no-body-fit]                # 2배 보스 위 명중·접촉·상태 표식
python3 tools/3d/melee_review.py                     # 검 근접·이동 속도·영웅 정보 팝업 (build/melee-speed/)
python3 tools/3d/melee_review.py --res 1280x800 --only strike --current-range
```
`--death-only`는 빈 전장에 여섯 몸(젤리·슬라임·거인·임프·트렌트·우상: sink/splat/topple 세 방향)을
시뮬 `_hurt`로 죽이는 `*_kill`과, 네 몸을 실제 `cast_skill("blast")`로 죽이는 `*_blast`를 매 틱
54장씩 찍는다. 테마 색 그대로인 `plain_*`와 환경 배경을 자홍으로 바꾼 `marker_*` 두 번이며,
모든 프레임에서 (1) 3D 뷰포트 텍스처의 알파가 1인지(몸 자리와 전체), (2) 자홍이 몸 자리에
비치지 않는지를 검사한다 — 알파가 1 밑이면 화면 밑바탕이 비치는 구멍이고, 자홍이 비치면 깊이만
쓴 실루엣이다. `--dissolve-probe`는 한 몸과 대조용 상자를 세워 두고 재질 상태(알파 해시 알파
1.0→0, 디더 0.75→0, 실제 `set_dissolve` 곡선)를 바꿔 가며 화면 픽셀·뷰포트 원본 픽셀·알파를
표로 남긴다(`probe_states.png`, `render.log`의 `probe` 줄). `--boss-melee`는 그 테마의 보스를 검
영웅 둘(요쿨·핀) 사이에 세우고 소총·활·포병·광선을 둘러 세워 게임 카메라(`boss_melee_*`)와
검수용 확대(`boss_zoom_*`)로 찍는다. `--no-body-fit`은 같은 장면을 맞춤 이전 동작으로 보여 준다.
자료(2026-10-12): `build/blast-vfx/death-fix/`의 `before|after/<calm_lake|first_snow_hills|
spring_grove>/<해상도>/`(`*_bodies.png`·몸별 GIF), `compare_blast_kill_all_themes.png`,
`compare_kill_<테마>_<해상도>.png`, `probe/1000x625/`, `boss/before|after/<보스>/<해상도>/`,
`boss/titan_bloom_*`·`dragon_golem_after.png`. 수치: 밑바탕색 (8,15,25) 픽셀이 수정 전 최악
708(처치)·1,267(별빛 폭발) px/프레임(1280×800, 프레임 26~31·38~39) → 수정 후 세 테마·두 창
크기 모든 프레임 0.

`tests/3d/melee_visual_preview.tscn`은 실제 `ArenaScreen`에 요쿨(얼음 관통 3)·핍(도구)·헬가(얼음
광역)·케이든(전기 연쇄)·이그니(불 관통)·에코를 세우고 각 검 앞 0.5~0.9 사거리에 몬스터를 틱마다
고정해(사거리 밖 1·부채꼴 밖 1 포함) 연속 프레임을 찍는다. `--planned-range`(기본)는 승인 대기 중인
검 사거리(기본 60)를 시뮬 영웅의 `range`에만 덮어써 승인 뒤의 모습을 미리 본다; `--current-range`는
파일 값 그대로다. `--gait-only`는 핍(spd 1.50)과 브라사(spd 0.62) 사본을 같은 레인에서 조이스틱으로
달리게 하고, `--probe`는 호만 손으로 띄워 셰이더를 본다. 결과는 `build/melee-speed/<해상도>/`의
`strike_*`(전체·영웅별 2배 GIF·컨택트), `gait_*`(레인 GIF·나란히 비교), `hero_info_*_{ko,en}.png`,
`stage/`(무대 보행 GIF)와 `melee-report.json`·`render.log`다.
`tests/3d/vfx_visual_preview.tscn`은 실제 `ArenaScreen`에서 분대 a(echo 활·kari 소총 얼음
광역·brasa 캐스터 불 장판·jokull 검 얼음 관통·triton 포병·limne 물 장판)와 분대 b(rhiannon
연쇄·brian 광선·protea 도탄·conor 전기 소총·pip 도구·finn 전기 검)를 세우고, 연속 프레임
(33ms), 전투(100ms), 세 기술, 수정 피격·방벽·등장을 촬영한다. 시뮬 틱마다 정확히 한 번
그려(실제 플레이처럼 이벤트가 매 프레임 비워지고 이펙트 시계가 dt만큼 간다) 촬영은
`dt=0` 재그리기로 한다. `--skills-only`는 기술·수정 피격·등장만 찍는다: `<분대>_skill_<blast|freeze|ward>` 22장(2틱/장, 1.5초),
`<분대>_blast_slow` 18장(1틱/장: 낙하·착탄·링), `<분대>_gate_warn` 20장(6틱/장, 4초 예고),
`<분대>_gate_burst` 24장(1틱/장), `--probe`면 빈 땅 폭발 `<분대>_blast_probe` 22장. 보스 문은
프레임 안에 가장 깊이 들어오는 입구(`_visible_gate`)를 골라 `vfx.arena_event`에 직접 넣는다. 결과는
`build/motion-overhaul/vfx/<해상도>/`의 PNG·GIF(`*_zoom.gif`는 전장 중앙 2배)·컨택트 시트·
MP4·`render.log`·`vfx-report.json`이다. 2026-10-10 최종 자료: 두 해상도 각 202장
(`a_battle/a_fight/a_skill_*/a_events`, `b_*`), 전후 비교
`build/motion-overhaul/vfx/compare_battle_before_after.jpg`(이전 `build/motion-overhaul/before/
en_echo_attack.gif` 대비), 어두운 숲 테마 확인 `build/motion-overhaul/vfx/theme-wood/1280x800/`,
몬스터 재질 확인 `build/motion-overhaul/vfx/shading-check/blaze_fox/`. 하네스는 풀 노드·재질 수 불변, 72 예산, 탄
인스턴스 수와 시뮬 목록 일치, `dt=0` 정지, 기술 시전 성공을 함께 검사한다.
