# 프로젝트 구조

현재 실행 경로는 `game/boot.tscn` → `Startup` → `game/main.gd` →
타이틀 → `ArenaScreen`의 전장 카드(무작위 전장)·소환·탄 사슬 전투다.

## 책임 분리

| 경로 | 책임 |
|---|---|
| `game/main.gd` | 화면 전환, 단일 활성 화면의 수명, 메뉴와 화면별 음악 연결 |
| `core/arena_run.gd` | 수호전 진행: 100 STAGE 사다리(스테이지마다 새로 시작, 순차 해금)·10웨이브·정비 시간 관문, 보석상자, DLC(리롤 3·부활권 5성·Hellbound 끝없는 웨이브), 영웅 성장/교체, 경험치·레벨·별자리 선택, 저장/복구. 2026-10-19 사다리·웨이브·스킬·부활권·Hellbound 는 [STAGE_LADDER_2026-10-19.md](STAGE_LADDER_2026-10-19.md), 보석상자는 [JEWEL_BOX.md](JEWEL_BOX.md), 2026-10-17 경험치 성장·별자리·공중 몬스터는 [PROGRESSION_2026-10-17.md](PROGRESSION_2026-10-17.md) (옛 10탄 사슬: [STAGE_RUN_2026-10-13.md](STAGE_RUN_2026-10-13.md)) |
| `core/jewel_box.gd` | 보석상자 규칙(상자 등급·카드 5장·보장 카드·다시 뽑기·대공 공정) — 상태 없는 순수 함수 |
| `core/talents.gd` | 별자리(레벨업 노드) 규칙 — 열린 노드, 셋 제시, 효과 합산, 지도용 읽기(clauses · children · graph_depth · state). 표는 `core/balance.gd` 의 `TALENTS` |
| `core/store.gd`, `core/store/` | 영구 해제 상품 하나(DLC 묶음: 리롤 3 · 부활권 · Hellbound, 내부 id `guardian`)의 보유·구매. Google Play · App Store · Steam 백엔드([STORE.md](STORE.md)) |
| `game/store_view.gd` | 구매창(타이틀과 전장 공용, DLC 세 혜택) |
| `game/squad_view.gd` | Hellbound 스쿼드 고르기(도감 영웅 최대 6명) |
| `game/stage_select_view.gd` | 스테이지 선택(챕터마다 10칸, 해금된 곳만) |
| `game/startup.gd`, `startup_splash.gd`, `startup_loading.gd` | 첫 실행: MindMorph 로고 → 키아트 + 실제 로딩 바(타이틀 배경·셰이더 데우기) → 타이틀 |
| `core/arena_geometry.gd` | 원형 전장과 전장별 길 배치(다섯 모양 x 회전 x 반전)의 기하(이동·길찾기·그리기·미니맵이 함께 읽는다). 2026-10-12 나선 도로·배속·기술 횟수·보스 예고는 [ARENA_UPDATE_2026-10-12.md](ARENA_UPDATE_2026-10-12.md) |
| `game/arena_sim.gd` | 웨이브 기계(정비 시간·정예·보스 웨이브·끝없는 모드), 이동/길찾기(공중 몬스터·보스·정예는 수호자를 넘고, 오래 막힌 몸도 통과), 피해, 처치 경험치, 공용 스킬(골드 비용·조준 시전·skill_state), 부활권 |
| `game/arena_screen.gd` | 전투 화면의 상태·입력·시계(팝업 무장·뗄 때 확정, 상자 문, 별빛 폭발 조준, 지도, 절전)와 그리기 순서 지휘 |
| `game/arena_hud.gd`, `arena_cards.gd`, `arena_box_view.gd`, `box_ceremony.gd`, `arena_talent_view.gd`, `arena_help.gd` | 전투 화면 그리기(2026-10-19 분리): 상단·레일·웨이브·배너 / 스테이지·결과 카드 / 보석상자 개봉 의식 / 레벨업 팝업·별자리 지도 / 규칙 페이지. 화면 캔버스에 그리고 존은 화면의 Ui 에 등록 |
| `game/3d/arena_view.gd`, `arena_world.gd`, `arena_frame.gd` | 시뮬레이터 상태를 실제 3D 전장으로 표현, 모델 어댑터에 보행·방향·피격·포위·사망·배치 입력 전달; `arena_frame.gd`는 3D 그림을 LINEAR 자식 노드로 그리는 프레임(비네트·샤픈·디더 `art/models/arena_post.gdshader`, 2026-10-18) |
| `game/3d/arena_biome.gd`, `arena_land.gd`, `arena_scenery.gd` | 전장별 모습: 바이옴·테마 룩과 랜드마크 50곳, 지형·액체·도로 메시, 소품 MultiMesh. 셰이더는 `art/models/arena_*.gdshader`(소품 접지 데칼 `arena_contact_decal.gdshader` 포함), 무늬는 `art/models/terrain_noise.png`([BATTLEFIELD_BIOMES.md](BATTLEFIELD_BIOMES.md)) |
| `game/3d/native_character_model.gd`, `hero_locomotion.gd`, `limne_model.gd` | 영웅 클립 샘플링·보행/공격 레이어·회전·조준 보정 |
| `game/3d/native_monster_model.gd` | 몬스터 클립 샘플링·등장/피격/사망/포위 반응 |
| `game/3d/stellar_vfx.gd`, `stellar_lighting.gd`, `stellar_shading.gd` | 탄·섬광·착탄·광선·장판·기술 이펙트, 조명·후처리(카메라 쪽 키·깊이 안개·룩별 그레이드), 캐릭터 재질(랩 디퓨즈·그늘 틴트)·영웅/보스 역전 헐 외곽선(`art/models/skin_outline.gdshader`)·피격 섬광·디졸브 |
| `core/combat_stats.gd` | 상태를 변경하지 않는 강화·패시브·영웅 능력치·DPS 계산 |
| `native/`, `addons/stellar_native/`, `core/native.gd` | C++ 커널(godot-cpp): 도로 판정·몬스터 길찾기·몬스터 자세 샘플러. GDScript 판이 그대로 남아 라이브러리가 없으면 그쪽이 돈다([PERF_NATIVE.md](PERF_NATIVE.md)) |
| `core/run.gd`, `game/battle_sim.gd` | 두 모드가 공유하는 영웅/경제/전투 규칙과 이전 웨이브 저장 호환 |
| `core/arena_validation.gd`, `run_validation.gd` | 현재 상태를 바꾸기 전 저장 데이터 검증 |
| `core/save.gd` | 설정/진행 기록, 저장 파일과 백업 복구 |
| `core/look.gd`, `ui.gd` | 공통 디자인 토큰, 표면, 타이포, 버튼과 터치 영역 |
| `game/hero_card.gd`, `rite_board.gd`, `constellation.gd` | 영웅 카드, 별맞춤 의식(옛 100탄 모드만), 별자리 인장·지도 그리기 |
| `game/3d/` | 영웅/몬스터 모델, 초상화, 배경, 카메라와 시각 효과 |
| `core/sound.gd`, `i18n.gd` | 앱 생명주기에 맞춘 오디오, 한영 번역 |

`Run`과 `Arena`는 공통 계산 모듈을 사용한다. 전장 수치와 정보창 수치의 계산식을
각 화면에서 복제하지 않는다. 3D 표현은 전투 판정이나 시간을 변경하지 않는다.
`main._swap()`은 이전 화면을 즉시 트리에서 분리하므로 삭제를 기다리는 화면이
입력이나 시뮬레이션을 계속 처리하지 않는다.

광고 서비스·플러그인·보상 콜백은 없다. 결제는 `Store` 오토로드 하나를 거친다. 이전 저장에 이미 지급된 보상은 보존하며,
사라진 획득 창을 다시 열거나 보상을 중복 지급하지 않는다.

## 데이터와 리소스

| 경로 | 역할 |
|---|---|
| `data/game.db` | 표·수치·문구의 편집 원본, 런타임/모바일 배포에서 제외 |
| `tools/gamedb.py` | 변경 미리보기, 승인 후 적용, 동기화 검사 |
| `tools/roster.json` → `core/roster.gd` | DB에서 내려온 로스터와 생성 코드 |
| `core/locales/`, `balance.gd` | 게임이 실제 읽는 번역과 밸런스 값 |
| `art/models/` | 실제 GLB, 모델 메타데이터, 랭크별 초상화 |
| `art/anim/`, `themes/`, `music/`, `sfx/` | 현재 코드/호환 화면/제작 검사가 참조하는 에셋 |
| `tests/` | 저장·규칙·실제 UI 회귀 검사와 시각 검수 씬. `tests/perf/` 는 틱·프레임 비용 표(판정 없음) |
| `addons/GodotGooglePlayBilling/`, `ios/plugins/ios-in-app-purchase/` | 결제 플러그인(Android · iOS). 게임은 `core/store/` 로만 닿는다 |
| `tools/3d/`, `sprite/`, `audio/`, `vfx/` | 재현 가능한 제작·검수 도구(모션 클립 작성, VFX 텍스처 생성 포함) |
| `tools/3d/audit_native_twist.py` | 영웅 팔 비틀림 관문(GLB 애니메이션을 Godot 없이 읽어 팔꿈치·손목 비틀림과 뒤집힘을 잰다, 2026-10-19) |
| `tools/box/`, `tools/brand/`, `tools/talent_art.py`, `tools/talent_glyphs.py` | 보석상자 그림(Blender 렌더)·브랜드 자산(로고·키아트·아이콘)·별자리 인장·노드 글리프 제작 도구 |
| `art/ui/box/`, `art/ui/talents/`, `art/ui/mindmorph_logo.*`, `art/ui/stellar_keyart.png`, `art/ui/brand_lockup_*.png`, `art/ui/launcher_*` | 상자 다섯 등급, 별자리 인장·노드 글리프, MindMorph 로고, 로딩 키아트, 워드마크 락업, 앱 아이콘(2026-10-19) |
| `art/vfx/` | 전투 이펙트 셰이더와 절차 생성 스프라이트 아틀라스·노이즈 |
| `build/`, `.godot/`, `android/build/` | 생성물과 로컬 캐시, Git 제외 |

DB 승인 절차와 배포 제외 검사는 [GAME_DB.md](GAME_DB.md)를 따른다.
에셋은 정적 경로뿐 아니라 로스터·모델 매니페스트·동적 경로도 확인하고 정리한다.
모델 제작 원본과 진행 중인 사용자 자료를 단순히 런타임 미참조라는 이유로 삭제하지 않는다.

## 빌드

`tools/verify.sh`가 검증을 모으고, `tools/build_apk.sh`가 성공한 APK를 고정 경로로
교체한다. `tools/ci/export.sh`는 APK와 iOS 프로젝트를 함께 내보낸다. 셋 다 먼저
`tools/native/build.sh`로 C++ 커널을 짓는다(바이너리는 Git 에 없다).
`check_no_ads.py`, `check_no_db.py`, `check_stellar_assets.py`가 배포물의 광고 부재,
DB 제외, 실제 3D 리소스 포함을 검사한다. 서명·브랜치·산출물 규칙은
[MOBILE_BUILDS.md](MOBILE_BUILDS.md)에 있다.
