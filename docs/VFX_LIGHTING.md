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
| 셰이더 | `art/vfx/vfx_common.gdshaderinc`, `vfx_projectile`, `vfx_muzzle`, `vfx_burst`, `vfx_burst_mix`, `vfx_beam`, `vfx_zone`, `vfx_zone_base`, `vfx_slash`, `vfx_dome`, `vfx_status`, `weather.gdshader` |
| 절차 생성 텍스처 | `art/vfx/sprites.png`(4×4 아틀라스), `art/vfx/noise.png` ← `python3 tools/vfx/gen_vfx_textures.py` |
| 접지 그림자 | `art/models/contact_shadow.gdshader` |
| 검수 하네스 | `tests/3d/vfx_visual_preview.tscn`, `tools/3d/vfx_review.py` |

아틀라스 칸(256px): 0 글로우, 1 네잎 별, 2 여섯잎 반짝임, 3 링, 4 연기, 5 불꽃, 6 얼음 조각,
7 번개, 8 물방울, 9 화살, 10 예광탄, 11 초승달 베기, 12 룬 원판, 13 육각 격자, 14 불씨, 15 충격 호.
흰색+알파만 담고 색은 셰이더가 입힌다. 칸 번호는 셰이더가 읽으므로 바꾸지 않는다.

## 레이어 구조 (모두 풀링, 생성 후 노드·메쉬·재질 생성 없음)

| 레이어 | 풀 | 그리는 것 |
| --- | --- | --- |
| 탄 `Bullets` | MultiMesh 120 | 속도 방향으로 정렬한 코어 스프라이트(무기별: 예광탄/화살/포탄/구슬/전기 구/베기 초승달) + 영웅색 글로우 + 리본 트레일(길이·폭 종류별, 속성별 흔들림) + 속성 입자 4개(불씨 상승·물방울 낙하·얼음 결정·전기 스파크) |
| 총구 `Muzzles` | MultiMesh 24 | 매 프레임 어댑터 `weapon_transform(side)`·`fire_strength()`를 읽는다. 무기별: 소총=별 코어+화염 줄기+스파크, 활=시위 번짐 선, 캐스터=손 밑 룬 원판+상승 반짝임, 포병=압력 원뿔+충격 링, 검=섬광(베기 호는 `Slashes`), 도구=스파크 분사 |
| 버스트 `Bursts` | MultiMesh 64 | 가산 표면: 바닥 충격 링(선두 날카롭고 꼬리 부드러움, 광역은 들어온 방향으로 쏠림)+섬광 빌보드+스파크 8+모트 8+정면 링(사망 후광·방벽 육각·수정 충격). 혼합 표면: 연기/서리 안개 2+그을음/서리 자국 |
| 광선 `Beams` | MultiMesh 16 | 16분할 스트립. 광선=노이즈 스크롤 샤프트, 연쇄=프레임마다 꺾이는 번개, 도탄=튕긴 자리에서 다음 목표로 달리는 자취 |
| 베기 `Slashes` | MultiMesh 12 | 영웅 정면 150° 호를 0.22초에 쓸고 지나가는 밝은 머리+잔광. 발사마다 좌우 교대 |
| 장판 `Zones` | MultiMesh 24+12 | `sim.zones` 룬 원판(착지 전엔 수렴하는 점선 링, 착지 후 회전 룬·틱마다 펄스·속성별 물결/호흡)+상승 모트 8+어두운 바닥판(밝은 눈 위 가독성). 추가 12칸은 캐스터 시전 중 발밑 원 |
| 돔 `Dome0/1` | 2 | 수정 방벽 발동·패시브 방벽: 프레넬 반구+육각 격자+상승 스캔 |
| 점광원 `Pulse0..5` | 6 | 발사·광역·사망·수정 피격·기술의 짧은 OmniLight 펄스(그림자 없음, range 2~8) |

버스트 종류(셰이더의 kind 코드와 같다): hit, splash, zone_tick, die, leak, block, push, frost,
stun, curse, spawn, wildfire, blast, freeze, ward, muzzle_smoke, ric_spark, beam_cap, bolt_cap,
cast_release. 크기는 `r`·`em`·`crit`을 따르며(면역 `em=0`은 그리지 않음, 반감 0.72배, 약점 1.3배,
치명타 1.35배) 색은 이벤트의 `c`(영웅/몬스터 색)와 속성 색(`Balance.ELEM`)을 섞는다.

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
  (emission 켜고 에너지 0, `TRANSPARENCY_ALPHA_HASH` 켜고 알파 1 — 이후 값만 바꾸므로
  셰이더 재컴파일이 없다). 호출 시점은 `StellarVfx`가 `world.actors.child_entered_tree`로
  잡는다(첫 프레임 전). 월드 밖에서 만든 카드는 첫 0이 아닌 섬광/디졸브에서 지연 생성된다.
  패킹 전에 override를 만들지 않는 이유: 헤드리스(dummy) 렌더러가 패킹된
  local-to-scene override 재질을 열거하지 못해 `ERROR`를 낸다.
- 발광은 `EMISSION_OP_MULTIPLY`에 **피부 텍스처를 emission 텍스처로** 넣어 몸의 무늬를
  따라 밝아진다(흰 실루엣이 되지 않는다 — 몬스터 담당 검수 반영).
  `set_hit_flash(root, 0..1)`: 따뜻한 `#ffebc7` 최대 1.5.
  `set_dissolve(root, q)`: q 0.30까지는 온전한 몸(사망 동작이 보이는 구간), 0.30→0.92에
  해시 투명으로 빠르게 흩어진다. 차가운 `#8ce6ff` 발광(최대 1.9)이 흩어지기 직전에 올라
  중간에 정점이라 반투명 구간이 평평한 회색 컷아웃으로 보이지 않는다. 불투명 패스라
  깊이·그림자·정렬이 유지된다. 검수 자료: `build/motion-overhaul/vfx/shading-check/blaze_fox/`
  (`hit_00..03`, `die_08..31`).
- 어댑터가 이미 override한 표면(예: `NativeReactorAmber`)과 authored 발광 표면은 건드리지 않는다.
- 몬스터 상태 그룹(`StellarBurn/Frost/Stun`) 교체안: `StellarVfx.status_group("Burn"|"Frost"|"Stun",
  height)`가 공유 메쉬·재질의 루프 마커(불꽃 상승·얼음 조각 부유·머리 위 반짝임 궤도)를 돌려준다.
  어댑터 파일은 몬스터 담당 소유이므로 교체는 그쪽에서 결정한다.

## 검수
```
python3 tools/3d/vfx_review.py                       # 1280x800 + 1000x625, 두 분대
python3 tools/3d/vfx_review.py --res 1280x800 --squad a --quick
```
`tests/3d/vfx_visual_preview.tscn`은 실제 `ArenaScreen`에서 분대 a(echo 활·kari 소총 얼음
광역·brasa 캐스터 불 장판·jokull 검 얼음 관통·triton 포병·limne 물 장판)와 분대 b(rhiannon
연쇄·brian 광선·protea 도탄·conor 전기 소총·pip 도구·finn 전기 검)를 세우고, 연속 프레임
(33ms), 전투(100ms), 세 기술, 수정 피격·방벽·등장을 촬영한다. 시뮬 틱마다 정확히 한 번
그려(실제 플레이처럼 이벤트가 매 프레임 비워지고 이펙트 시계가 dt만큼 간다) 촬영은
`dt=0` 재그리기로 한다. `--skills-only`는 기술·수정 피격·등장만 짧게 찍는다. 결과는
`build/motion-overhaul/vfx/<해상도>/`의 PNG·GIF(`*_zoom.gif`는 전장 중앙 2배)·컨택트 시트·
MP4·`render.log`·`vfx-report.json`이다. 2026-10-10 최종 자료: 두 해상도 각 202장
(`a_battle/a_fight/a_skill_*/a_events`, `b_*`), 전후 비교
`build/motion-overhaul/vfx/compare_battle_before_after.jpg`(이전 `build/motion-overhaul/before/
en_echo_attack.gif` 대비), 어두운 숲 테마 확인 `build/motion-overhaul/vfx/theme-wood/1280x800/`,
몬스터 재질 확인 `build/motion-overhaul/vfx/shading-check/blaze_fox/`. 하네스는 풀 노드·재질 수 불변, 72 예산, 탄
인스턴스 수와 시뮬 목록 일치, `dt=0` 정지, 기술 시전 성공을 함께 검사한다.
