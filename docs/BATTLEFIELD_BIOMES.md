# 전장 바이옴 (3D 수호전 맵)

2026-10-13, `graphic_design_manager`(전장 담당)가 제작했다. 사용자 요청은 "맵이 여러 개인데
디자인 차이가 크지 않으니 극적으로, 몬스터 진입 경로도 차이를 두고"이다. 탄 구성·도로
기하·난이도는 메인 소유([STAGE_RUN_2026-10-13.md](STAGE_RUN_2026-10-13.md),
`core/arena_geometry.gd`)이고 이 문서는 **전장의 시각**만 다룬다. 대상은 Godot 4.7.1
GL Compatibility(Android/iOS/Steam)다. 수정 정체성, 등불, HUD 색, 영웅·몬스터·VFX는 바꾸지 않았다.

이전에는 50개 테마가 모두 같은 푸른 밤 전나무 숲이었다(바닥색 5가지, 눈 여부, 작은 랜드마크 하나).
지금은 바이옴 5종 × 험함(rank 1~5) × 테마 고유 장소 50곳이며, 전장은 테마 id와 도로 배치가
바뀔 때 다시 만들어진다.

## 파일

| 역할 | 경로 |
| --- | --- |
| 조립(`build_map`), 날씨, 수정·제단, 조명 수 제한 | `game/3d/arena_world.gd` |
| 바이옴·테마 룩(색·셰이더 값·조명·날씨), 입구, 주변 배치, 랜드마크 50곳, 바닥 명도 표 | `game/3d/arena_biome.gd` |
| 지형 높이 함수, 지형·액체 메시, 도로·연석 메시 | `game/3d/arena_land.gd` |
| 소품 템플릿 39종과 MultiMesh 배치 | `game/3d/arena_scenery.gd` |
| 전장별 하늘·안개·주변광·3점 조명 색 | `game/3d/stellar_lighting.gd` `apply_biome()` |
| 바닥 / 주변 지형 / 물·용암·유빙·구름바다 / 도로·광장 | `art/models/arena_ground.gdshader` · `arena_terrain` · `arena_liquid` · `arena_road` |
| 소품 공용 재질 / 입구 장막·연기·폭포·오로라·안개 | `art/models/arena_scenery.gdshader` · `arena_haze.gdshader` |
| 날씨 입자(셰이더가 이동) | `art/vfx/weather.gdshader` |
| 무늬 텍스처와 생성 도구 | `art/models/terrain_noise.png` ← `tools/3d/gen_terrain_noise.py` |
| 촬영·측정 도구 | `tests/arena_visual_preview.gd` (`--biome-only`), `tests/arena_visual_review.py --only biome` |

`terrain_noise.png`은 512² RGBA 절차 생성물(외부 소재 없음, 시드 20261013, sha256
`1112c6f8…47e2b5`)이다. R 구름 · G 셀 경계까지 거리 · B 셀 고유값 · A 능선. 모든 무늬는 이 한 장을
셰이더가 임계값으로 잘라 만든다. 다시 만들면 `bash tools/godot_import.sh`를 한 번 돌린다.

## 규칙

1. **바닥은 무대다.** 전투 이펙트는 빛을 더하고 영웅·몬스터는 어둡다. 그래서 전장 바닥의
   평균 명도(CIE L\*, 화면 기준)는 장소와 무관하게 **40~66**에 둔다(실측 44.3~65.2, 중앙값 59).
   L 85의 눈밭에서는 별빛 폭발 문양이 사라졌고 L 61에서는 읽혔다. 장소의 밝기(눈, 채석장 벽,
   사막)는 **테두리 밖**에 둔다. 실측값은 `arena_biome.gd` `FLOOR_L` 표에 있고, 촬영 도구가
   창을 벗어나거나 표와 5 이상 어긋나면 실패한다.
2. **도로는 그 바이옴 몬스터의 반대색이다.** 숲(어두운 초록 몬스터) 밝은 회색 돌 · 물(파랑)
   따뜻한 판자길 · 불(노랑~빨강) 불씨 없는 청회색 현무암 · 바위(회색·황갈) 푸른 점판암 ·
   얼음(흰~연파랑) 남색 점판암. 예외: 수도교 폐허(돌 포장), 유빙 바다(판자길), 철광 갱도(궤도).
3. **카메라 쪽은 낮다.** 카메라는 남쪽에 있다. 남쪽 지형은 낮추고(`land.south`), 키 큰 소품은
   `tall_room()`으로 줄이고, 입구 상인방은 가늘다. 절벽·폭포·거목은 북쪽과 좌우에 선다.
4. **입구는 어느 각도에서도 같은 문법이다.** 도로 양옆 기둥 한 쌍 + 가는 상인방 + 따뜻한 등불 +
   문턱의 빛나는 띠와 징 6개 + 기둥 사이로 오르는 옅은 장막(랭크가 오를수록 진해짐). 색은
   HUD 입구 표식과 같은 `#ff9a7a`. 테두리 밖 4.6~5.6u의 접근로가 있으며 땅에서는 포장이 낱돌로
   흩어지고, 물·용암·균열 위에서는 부두·석교가 된다. 기둥 재료는 바이옴마다 다르다: 숲 주홍
   도리이와 석등 · 물 계류 말뚝과 밧줄 · 불 현무암 뿔과 화로·사슬 · 바위 쌓은 돌기둥과 깃발 ·
   얼음 얼음 첨탑과 고드름.
5. **랭크는 같은 바이옴 안에서 장소를 바꾼다.** `harsh = (rank-1)/4`가 팔레트, 절벽 높이, 안개,
   날씨 양과 속도, 입구 높이와 장막을 올리고, 그 위에 테마 고유의 지형·랜드마크가 얹힌다.
6. **조명의 방향과 그림자는 고정이다.** 전장마다 하늘·안개·주변광·키/필/림의 색과 세기만 바꾼다.
   캐릭터를 조형하는 빛은 모든 전장에서 같고, 장소의 색만 둘레에서 바뀐다. 밝은 전장은 블룸을
   낮춘다(얼음 0.12).

## 바이옴

| 바이옴 | 바닥 | 도로 | 주변 | 빛·날씨 | rank 1 → 5 |
| --- | --- | --- | --- | --- | --- |
| 물 `aqua` | 모래톱·갯벌·젖은 암반과 물웅덩이 | 판자길, 계류 말뚝 연석 | 사방이 물, 갈대·수련·암초, 부두와 나룻배 | 청록 안개, 따뜻한 림 · 물안개 → 비 | 잔잔한 호수 → 소용돌이 바다·심해 해구 |
| 불 `flame` | 잿빛 흙·현무암 판, 균열 불빛 | 청회색 현무암 | 주상절리, 숯이 된 나무, 화산 능선, 용암 | 차가운 주변광 + 불빛 필 · 불티 → 재눈 | 가마터 → 용암 해자의 분화구 |
| 숲 `wood` | 풀·부엽토, 뿌리 무늬, 꽃 | 밝은 돌 포장, 이끼 가장자리 | 3겹 수림(전나무·활엽수·대나무·고사목·거대 버섯) | 달빛 청록(게임의 기본 분위기) · 반딧불 | 봄 숲 → 세계수 뿌리 |
| 바위 `rock` | 자갈·암반 판 | 푸른 점판암 | 지층이 보이는 계단 절벽, 후두, 마른 덤불 | 낮은 해의 따뜻한 키, 차가운 림 · 모래먼지 | 자갈 언덕 → 구름 위 산정·지진 균열 |
| 얼음 `frost` | 그늘진 푸른 얼음(무대), 가장자리만 눈 | 남색 점판암, 눈 연석 | 눈 덮인 전나무, 얼음 첨탑, 눈더미 | 차가운 확산광, 낮은 블룸 · 눈 → 눈보라·오로라 | 첫눈 언덕 → 극야 빙원 |

## 테마 50곳

배치는 `ArenaGeometry.layout_for_theme()`가 정한다(읽기 전용). 구현은 `_theme_<id>()`(룩)와
`_place_<id>()`(랜드마크)다.

| id | 랭크·배치 | 장소 |
| --- | --- | --- |
| calm_lake | 1 spiral | 모래톱과 얕은 물, 청록 호수, 수련·갈대, 수상 오두막과 나룻배 |
| reed_marsh | 1 pinwheel | 황금 갈대밭과 청록 물길, 고사목, 낮은 안개 |
| aqueduct_ruin | 2 blades | 물이 찬 석판, 돌 포장 도로, 뒤편의 수도교 아치(일부 붕괴) |
| falls_gorge | 2 coil | 젖은 암반, 협곡 벽의 폭포 세 줄기와 물보라 |
| tidal_flats | 3 fork | 잔물결 갯벌과 물웅덩이, 어살 말뚝, 기울어진 배 |
| glacier_lake | 3 spiral | 자갈 바닥과 청록 빙하수, 유빙, 뒤편 빙벽 |
| sunken_fleet | 4 pinwheel | 어두운 물, 난파선 다섯 척, 안개 |
| geyser_mud | 4 blades | 갈라진 진흙과 온천, 간헐천 분구의 증기 기둥 |
| deep_trench | 5 coil | 칠흑 바다 위의 암반, 열수 분출공, 발광 수정, 거대한 늑골 |
| maelstrom_sea | 5 fork | 소용돌이 포말 바다, 암초, 난파선, 비 |
| kiln_yard | 1 pinwheel | 다진 흙마당, 불 지핀 벽돌 가마 여섯, 장작과 옹기 |
| burn_field | 1 blades | 그을린 흙과 황금 그루터기, 타는 불길과 연기 |
| forge_canyon | 2 coil | 협곡 벽의 화덕 다섯, 모루와 담금질 통 |
| burnt_forest | 2 fork | 재 덮인 바닥과 검은 균열, 숯이 된 숲, 연무 |
| sulfur_springs | 3 spiral | 유황 단구와 청록 온천, 증기 |
| ash_city | 3 pinwheel | 재 덮인 포장, 무너진 성벽·아치·기둥 |
| lava_river | 4 blades | 용암 위의 현무암 섬, 주상절리, 석교 |
| obsidian_flats | 4 coil | 보랏빛 흑요석 유리 바닥, 흑요석 파편 |
| volcano_crater | 5 fork | 분화구 벽, 용암 해자, 용암 폭포 |
| ash_blizzard | 5 spiral | 재눈 폭풍, 균열 불빛, 화산 능선 |
| spring_grove | 1 blades | 연초록 풀밭과 꽃, 벚꽃 활엽수, 꽃잎 |
| mushroom_hollow | 1 coil | 어두운 부엽토, 거대 버섯의 고리 |
| bamboo_grove | 2 fork | 대숲, 석등, 정자 |
| vine_ruins | 2 spiral | 이끼 낀 석판, 덩굴 감긴 폐허 |
| misty_cedar | 3 pinwheel | 청록 안개, 줄기가 드러난 키 큰 삼나무 |
| thornbrake | 3 blades | 호박빛 마른 땅, 가시덩굴 아치, 고사목 |
| moss_bog | 4 coil | 이끼 습지와 검은 물, 반딧불 |
| frost_pines | 4 fork | 서리 내린 침엽수림, 눈 |
| rotroot_hollow | 5 spiral | 썩은 뿌리 굴의 입, 뿌리 아치, 발광 버섯 |
| worldtree_roots | 5 pinwheel | 세계수 밑동과 뻗어 나온 뿌리, 발광 수정 |
| gravel_hills | 1 coil | 자갈 언덕, 돌무지, 울타리 |
| stone_terraces | 1 fork | 계단식 밭, 돌담, 건초더미, 헛간 |
| quarry_pit | 2 spiral | 흰 채석장 벽, 석재 더미, 삼각 기중기 |
| red_canyon | 2 pinwheel | 붉은 협곡 벽, 천연 아치, 후두 |
| broken_wall | 3 blades | 풀 난 포장, 무너진 성벽과 망루 둘 |
| crystal_cavern | 3 coil | 보라 동굴, 발광 수정 군락, 석순 |
| desert_mesa | 4 fork | 모래 사막, 메사 기둥, 모래바람 |
| iron_mine | 4 spiral | 궤도가 깔린 도로, 갱도 입구 다섯과 광차 |
| peak_cliffs | 5 pinwheel | 노을 구름바다 위의 산정, 석교, 바위 첨봉 |
| rift_chasm | 5 blades | 깊은 균열에 둘러싸인 암반, 석교, 솟은 판석 |
| first_snow_hills | 1 fork | 마른 풀밭 위의 첫눈, 울타리 |
| frozen_pond | 1 spiral | 얼어붙은 연못, 마른 갈대, 얼음낚시 오두막 |
| snowed_village | 2 pinwheel | 불 켜진 집 여덟 채와 굴뚝 연기, 우물 |
| frost_gorge | 2 blades | 협곡 벽의 얼어붙은 폭포 |
| drift_ice_sea | 3 coil | 유빙 바다, 판자길, 얼어붙은 난파선 |
| icicle_cave | 3 fork | 얼음 동굴의 아치와 고드름, 발광 수정 |
| blizzard_plateau | 4 spiral | 옆으로 긋는 눈보라, 돌무지와 깃대 |
| glacier_crevasse | 4 pinwheel | 푸른 크레바스에 둘러싸인 빙원, 얼음 다리 |
| ice_spire_field | 5 blades | 푸른 시간, 빛나는 거대 얼음 첨탑, 오로라 |
| polar_night | 5 coil | 극야, 오로라 다섯 장, 남보라 빙원 |

테마가 없을 때(타이틀·캠프 배경)는 장소 없는 기본 숲이다.

## 도로와 입구의 구조

- 도로 면은 중심선을 따른 띠다. 팔은 광장으로 들어가는 끝을 **반원으로 닫아** 실제 통행
  영역(`ArenaGeometry.on_road`)과 같은 모양이 된다. 팔끼리는 광장 근처에서 겹치므로 각자
  0.0012씩 다른 높이에 놓고, 보조 도로는 팔보다 낮게(0.0245) 깔아 팔의 포장이 T자 입구를
  끊김 없이 지나간다. 다섯 배치 × 다섯 전장의 광장 25곳과 T자 접합 25곳을 근접 촬영해
  z-파이팅과 연석 접힘이 없음을 확인했다(`after/1280x800/final_plazas.jpg`, `final_joins.jpg`).
- 연석은 띠의 양쪽 가장자리가 아니라 **모든 도로를 합친 실제 외곽선**을 따른다. 가장자리의
  표본마다 7logical 바깥이 도로나 광장이면 연석을 세우지 않는다. 그래서 T자 접합부, blades의
  네 팔이 광장에서 만나는 곳, coil의 겹친 굽이에 연석이 가로지르거나 접히지 않는다.
- 포장 무늬(`arena_road.gdshader`)는 셀 크기·줄 수·어긋남·줄눈으로 돌·판자·현무암·궤도를 만든다.
  가장자리 띠(이끼·서리·모래)는 포석 단위가 아니라 연속 잡음을 따른다.

## 성능

- `build_map`(탄 전환 시 한 번): **16.8~25.6ms**, 중앙값 22.0ms(1280×800, 50개 전장 각 4회 중
  최솟값. 전체 촬영 중 가장 느렸던 단일 표본은 46.7ms). 이전 구현은 같은 방식으로 잰 15개
  전장에서 204~770ms였다. 소품을 수천 개의 고유 삼각형으로 합치지 않고 템플릿 39종의 MultiMesh
  인스턴스(전장당 185~1,181개)로 그리기 때문이다.
- 맵만의 프레임 비용(50개 전장): 삼각형 2.5만~13.3만(대숲이 최대, 이전 46만~103만), 드로콜
  51~75, 이 기기(NVIDIA GB10)에서 GPU 0.9~1.8ms. 참고값이며 실기기 수치가 아니다.
- 점광원은 수정 + 최대 5개(입구 등불 우선). 이전은 수정 + 입구당 하나였다.
- 날씨 입자는 한 번 배치하고 셰이더가 옮긴다. 프레임당 유니폼 하나만 쓴다(이전에는 매 프레임
  56개 변환을 기록). 연기·폭포·오로라·안개는 카메라를 향한 정적 사각형 한 메시다. 풀스크린
  패스와 파티클 시스템은 추가하지 않았다. 물·용암 셰이더는 시작할 때 묻힌 삼각형 하나로 미리
  컴파일해 탄 전환 중 컴파일을 피한다.

## 이펙트 연동

`ArenaWorld.floor_lightness`(실측 L\*)와 `ground_wash`(0~1, L 57부터 오르고 67에서 1)를 낸다.
`StellarVfx._sync_wash`는 아직 **바이옴(물·얼음)으로** 밝은 바닥을 판단한다. 지금은 어두운
물 전장(심해 해구 L 52, 소용돌이 바다 55)이 불필요하게 눌리고, 밝은 다른 전장은 눌리지 않는다.
`ground_wash`가 0.5를 넘는 전장: calm_lake 0.90 · broken_wall, frozen_pond, frost_gorge,
blizzard_plateau, glacier_crevasse 0.78 · tidal_flats, desert_mesa, snowed_village 0.65.
VFX 파일은 전장 담당이 고치지 않았다.

## 검수

```
python3 tests/arena_visual_review.py --only biome --out-root build/biomes/after --before build/biomes/before
python3 tests/arena_visual_review.py --only biome --sets fields --themes all --res 1280x800 --out-root build/biomes/all50
```

GPU가 붙은 로그인 X 세션(:1)이 있으면 그 GL 컨텍스트를 빌려 화면 밖 뷰포트를 찍고, 없으면 Xvfb로
내려간다(`REVIEW_DISPLAY=xvfb`). `--sets`는 `fields`(전장별 빈 맵·전투·HUD 없는 전투),
`shapes`(도로 배치 5종), `detail`(광장·모든 입구·모든 T자 접합 근접), `switch`(실제 탄 전환 연속
프레임), `timing`, `vfx`(공용 기술 세 가지를 바닥 위에서)다. 산출물은 해상도별 폴더의
`sheet_fields_320.jpg`(썸네일 판별), `compare_fields.jpg`(전후), `sheet_shapes_*`,
`sheet_detail_*`, `switch.gif`·`switch_strip.jpg`, `sheet_vfx_*`, `contrast.json`,
`biome-report.json`이다.

최종 촬영(2026-10-13): `build/biomes/after/{1280x800,1000x625}/` 각 330PNG · 검사 12,962건 실패 0,
`build/biomes/all50/1280x800/` 150PNG(50개 전장, `final_<바이옴>.jpg`), 개편 전
`build/biomes/before/`.

측정(50개 전장, 1280×800): 바닥 L\* 44.3~65.2. 캐릭터 몸과 발밑 바닥의 색차(CIE76, 전장별
중앙값)는 영웅 24.8~56.4, 몬스터 24.0~65.2다. 개편 전 15개 전장은 영웅 19.4~52.5, 몬스터
20.2~53.5였고 같은 15곳이 지금은 32.1~55.2, 30.0~61.9다.

## 남은 문제

- **얼음 전장의 몬스터 대비가 가장 낮다.** frozen_pond 24.0, icicle_cave 27.9, blizzard_plateau
  28.0, snowed_village·ice_spire_field 28.7(다른 바이옴은 34 이상). 눈으로는 남색 도로 위의 밝은
  몸으로 읽히지만 여유가 적다. blizzard_plateau는 영웅도 24.8이다(눈발이 몸 위를 지난다).
- **얼음 1~2랭크 세 곳(frozen_pond, snowed_village, frost_gorge)은 바닥이 서로 비슷하다.**
  주변과 배치로만 구별된다. 다음 단계는 바닥 자체의 구분(마을의 밟힌 눈과 수레 자국, 협곡의
  암반과 얼음판, 연못의 맑고 어두운 얼음)이다.
- **frost_pines(숲 4랭크)의 바닥이 썸네일에서 얼음으로 읽힌다.** 도리이와 전나무 숲은 숲
  문법이지만 바닥은 더 어두운 낙엽·솔잎 색에 서리 선만 얹어야 한다.
- **deep_trench의 바닥이 창백한 푸른 원반으로 보인다.** 무대 규칙의 하한 안에서 더 어둡고
  청록 쪽으로 내릴 여지가 있다. burnt_forest의 검은 균열 무늬는 다소 어지럽다.
  frozen_pond는 평균은 창 안이지만 테두리 안쪽 눈 띠가 L 86까지 올라간다.
- 소품과 랜드마크는 기본 도형과 저폴리 템플릿의 조합이다. 게임 카메라 거리에 맞춘 것이며
  근접 촬영(트레일러)용 품질이 아니다.
- 팔 도로의 가장자리 띠(이끼·서리)가 보조 도로 입구를 옅은 선으로 가로지른다(연석은 아님).
- 4입구 전장에서 장소 조명이 있으면 점광원이 이전보다 하나 많다(6개).
- Android/iOS 실기기의 FPS·발열, ETC2/ASTC 기기에서의 무늬 텍스처(무손실 512² RGBA) 표시는
  확인하지 못했다.

## 테마를 고치거나 더할 때

`_theme_<id>()`에서 바이옴 룩 위에 덮어쓸 값만 돌려주고, `_place_<id>()`에서 `spot()`·`frame()`·
`put()`과 공용 소품 함수로 랜드마크를 세운다. 그 뒤 위의 50개 전장 촬영을 돌려 바닥 명도가 창
안인지 보고 `floor_l_table.txt`의 값을 `FLOOR_L`에 옮긴다. `Scenery.MAP_MOTIFS`와 테마 표의
값은 게임 데이터이므로 건드리지 않는다.
