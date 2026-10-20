# 네이티브 커널 (addons/stellar_native)

2026-10-17, 사용자 요청: 「몬스터가 많아서 버벅거리는 부분을 C++ 로 옮겨 달라」.
먼저 어디가 느린지를 쟀고, 몬스터 수에 따라 늘어나는 스크립트 비용 가운데 **순수 계산**인
세 곳을 godot-cpp(GDExtension)로 옮겼다. 게임 규칙·연출·UI 는 그대로 GDScript 다.

## 무엇이 네이티브인가

| C++ 클래스 (`native/src/`) | 대신하는 GDScript | 쓰는 곳 |
|---|---|---|
| `StellarRoads` | `ArenaGeometry.on_road / nearest_road_point / road_direction` 와 구간 표본 판정 | 도로 위 판정 전부 (이동·길찾기·검사기) |
| `StellarArenaNav` | `ArenaSim._road_segment_clear / _segment_clear / _path_from / _join_path / _road_mask` | 몬스터 이동 틱의 기하 질문: 다음 걸음이 길 위이고 수호자에 안 닿는가, 막혔을 때의 새 경로(A* 는 시뮬레이터의 `AStarGrid2D` 그대로), 전장 첫 진입의 도로 마스크 |
| `StellarMonsterPose` | `NativeMonsterModel._compose / _sample / _apply_skeleton` | 몬스터 한 마리의 자세: 클립 네 개를 뼈마다 섞어 스켈레톤에 쓰기 |

규칙은 전부 GDScript 에 남았다. `ArenaSim._move_monsters` 의 화상·저주·포위·사건,
`NativeMonsterModel.animate_visual` 의 블렌드 무게·반응 층(`_apply_pivot`)·등장·사망은
그대로이고, 그 안에서 "이 점이 길 위인가", "이 뼈의 이 시각 자세는 무엇인가"만 C++ 가 답한다.

## 두 길은 같은 답을 낸다

- GDScript 판은 **지우지 않았다.** `ArenaGeometry.on_road_script`, `ArenaSim._path_from_script`
  처럼 `_script` 이름으로 남아 있고, 라이브러리가 없으면(또는 `STELLARDEFENSE_NO_NATIVE=1`)
  그쪽이 돈다. `core/native.gd` 의 `Native.enabled()` 가 갈림길이다.
- `tests/native_parity_check.gd` 가 두 길을 같은 입력으로 돌려 **비트까지 같은지** 본다:
  다섯 배치 x 수천 점의 도로 판정(격자 색인 판·전수 판과 셋 다 일치), 경로·구간·마스크,
  같은 씨앗의 20초 전투(수호자 하나가 원을 돌며 재탐색을 계속 일으킨다 — 몬스터 위치·경로·
  난수 상태까지 일치), 몬스터 25종 x 18 단계의 뼈 자세.
- 그래서 C++ 는 엔진과 **같은 float32 연산 순서**로 적었고, `native/SConstruct` 는
  `-ffp-contract=off` 로 짓는다. 엔진(`platform/linuxbsd/detect.py`)도 그렇게 짓는다 —
  FMA 를 켜면 연석 위의 한 점이 도로 안팎으로 갈려서 `arena_route_check` 가 실제로 실패했다.
- 네이티브 클래스 이름을 GDScript 에 적지 마라(`StellarRoads.new()`). 라이브러리가 없는
  플랫폼에서 그 스크립트가 통째로 컴파일되지 않는다. `Native.make("StellarRoads")` 로 만든다.

## 측정 (2026-10-17, 이 머신의 A725 코어 `taskset -c 0-4,10-14`, 에디터 바이너리, 10탄, 3배속, 수호자 6)

시뮬레이터 한 틱 (`tests/perf/arena_sim_bench.tscn -- --stage 10 --walk`, 몬스터 40~47마리):

| | 틱당 평균 | 최악 틱 | 이동 단계 |
|---|---|---|---|
| GDScript | 0.38 ms | 1.92 ms | 0.24 ms |
| 네이티브 | 0.29 ms | 1.65 ms | 0.15 ms |

실제 전장 한 프레임 (`tools/perf/frame_bench.sh`, GPU 가 붙은 :1 화면, 몬스터 40~47마리):

| | 프레임 | sim (3틱) | 몬스터 자세(`animate_visual`) | 몬스터 루프 나머지 | HUD 전체 |
|---|---|---|---|---|---|
| 적용 전 | 21.4 ms | 1.53 ms | 0.94 ms | 0.75 ms | 8.1 ms |
| 적용 후 | 20.3 ms | 1.26 ms | 0.88 ms | 0.61 ms | 8.0 ms |

(최악 프레임은 30~70 ms 사이에서 실행마다 흔들려 — 모델 첫 생성·GC 로 보인다 — 비교에서 뺐다.
`animate_visual` 0.88 ms 중 C++ 가 답하는 자세 합성은 0.29, 스켈레톤 쓰기 0.08 이고 나머지
0.5 는 GDScript 의 블렌드 무게·`_apply_pivot` 반응 층이다.)

★ **몬스터 때문에 늘어나는 스크립트 비용은 애초에 프레임의 작은 몫이었다.** 0마리에서
47마리로 가며 프레임이 13 → 21 ms 로 느는데, 그중 스크립트가 약 4.5 ms, 엔진 렌더
(드로 콜 677 → 979, 스킨 메시 47구)가 약 3.5 ms 다. 반면 **2D HUD(`ArenaScreen._draw`)는
몬스터가 없어도 매 프레임 8 ms** 다 — 명령 레일 `_draw_controls` 4.1, 상단 1.2, 미니맵 1.3,
몬스터 체력 막대 1.0. 이 8 ms 는 C++ 의 일이 아니라 **매 프레임 다시 그리지 않는 구조**
(바뀔 때만 다시 그리는 CanvasItem 분리)의 일이다. 폰에서 60fps 를 지키려면 다음은 그쪽이다.

남은 몬스터 비례 스크립트 비용(47마리): `animate_visual` 의 GDScript 몫(`_apply_pivot` 0.2,
무게·반응 0.3) 약 0.6 ms, 월드 루프 0.3 ms, 체력 막대 1.0 ms, 미니맵 점 0.4 ms. 연출 코드라
옮기지 않았다(연출은 디자인 담당 영역이고, 수치가 작다).

## 빌드와 배포

- 소스 `native/`(`.gdignore` 로 에디터는 보지 않는다), 매니페스트
  `addons/stellar_native/stellar_native.gdextension`, 바이너리 `addons/stellar_native/bin/`
  (Git 제외). godot-cpp 는 `tools/native/build.sh` 가 고정 커밋을 `build/native/godot-cpp`
  에 받는다 (`build_profile.json` 으로 쓰는 클래스만 묶어 1분 안에 짓는다).
- `tools/native/build.sh [linux|android|all]`. `tools/verify.sh` 0-3 단계가 Linux 판을,
  `tools/build_apk.sh` 가 Android 판을 먼저 짓는다. CI(`tools/ci/export.sh`)는 둘 다 짓고
  `native_parity_check` 를 돌린다. `.github/workflows/stellardefense.yml` 이 scons 를 설치하고
  godot-cpp 빌드를 캐시한다.
- 이 머신의 NDK 는 x86_64 판을 qemu-user 로 돌리는 래퍼라 clang 이 제 링커를 못 띄운다.
  `tools/native/android_link.py` 가 드라이버의 링크 명령(`clang++ -###`)을 받아 래퍼로 대신
  링크한다 (aarch64 호스트에서만, `native/SConstruct`).
- **iOS 와 데스크톱(Steam) 판에는 아직 라이브러리가 없다.** 익스포트는 경고 한 줄을 내고
  (오류 아님) 게임은 GDScript 로 돈다. iOS 판을 실으려면 macOS 러너에서
  `scons platform=ios arch=arm64` 로 `.a`/xcframework 를 만들어 Linux 익스포트 전에 받아 와야
  하므로 워크플로에 macOS 잡 하나가 앞에 더 붙는다 — 사용자가 원하면 한다.
- `.gdextension` 은 에디터 스캔(`--import`)이 `.godot/extension_list.cfg` 에 등록한다. 새로
  받은 저장소에서는 라이브러리를 먼저 짓고 임포트를 한 번 돌려야 헤드리스 검사도 네이티브로 돈다.

## 측정 도구

- `tests/perf/arena_sim_bench.tscn -- --stage N --seconds S [--walk]`: 헤드리스. 틱당 비용을
  단계별(길찾기·이동·캐시·사격·탄·장판·수확)로, 몬스터 수 구간마다 표로 찍는다.
- `tools/perf/frame_bench.sh [stage] [frames]`: GPU 화면(:1)에서 실제 `ArenaScreen` 을 띄워
  프레임을 sim · 월드 동기화(영웅·몬스터 자세·상태 표시·VFX) · HUD 부분별로 나눠 찍는다
  (`tests/perf/arena_frame_bench.gd`). 폰 GPU 비용은 여기 안 잡힌다 — 드로 콜 수로 가늠한다.

## 2026-10-19 부활 후보 미리 올림 (D3)
- 「부활 후보 영웅(2026-10-19 LA3): `ArenaWorld._keep_revival`이 스테이지가 바뀌고 부활권이 남았을 때 `Arena.revive_candidate()`의 5성
  리그를 `StellarModels.hero()`로 캐시에 올리고, 그 몸을 땅 밑에 4프레임 그린 뒤 숨긴다(5성 장비 변형 컴파일). 합류하지 않은 앞 후보는
  `StellarModels.forget_hero`로 놓는다. 화면 호출 없음.」
