# 프로젝트 구조

현재 실행 경로는 `game/boot.tscn` → `Startup` → `game/main.gd` →
타이틀 → `ArenaScreen`의 테마 선택·소환·연속 전투다.

## 책임 분리

| 경로 | 책임 |
|---|---|
| `game/main.gd` | 화면 전환, 단일 활성 화면의 수명, 메뉴와 화면별 음악 연결 |
| `core/arena_run.gd` | 연속 수호전 진행, 영웅 성장/교체, 상점, 저장/복구 |
| `game/arena_sim.gd` | 전투 시간, 이동/길찾기, 피해, 보스, 공용 스킬 |
| `game/arena_screen.gd` | 사용자 입력과 전투/모달 표시 |
| `game/3d/arena_view.gd`, `arena_world.gd` | 시뮬레이터 상태를 실제 3D 전장으로 표현, 모델 어댑터에 보행·방향·피격·포위·사망 입력 전달 |
| `game/3d/native_character_model.gd`, `hero_locomotion.gd`, `limne_model.gd` | 영웅 클립 샘플링·보행/공격 레이어·회전·조준 보정 |
| `game/3d/native_monster_model.gd` | 몬스터 클립 샘플링·등장/피격/사망/포위 반응 |
| `game/3d/stellar_vfx.gd`, `stellar_lighting.gd`, `stellar_shading.gd` | 탄·섬광·착탄·광선·장판·기술 이펙트, 조명·후처리, 캐릭터 재질·피격 섬광·디졸브 |
| `core/combat_stats.gd` | 상태를 변경하지 않는 강화·패시브·영웅 능력치·DPS 계산 |
| `core/run.gd`, `game/battle_sim.gd` | 두 모드가 공유하는 영웅/경제/전투 규칙과 이전 웨이브 저장 호환 |
| `core/arena_validation.gd`, `run_validation.gd` | 현재 상태를 바꾸기 전 저장 데이터 검증 |
| `core/save.gd` | 설정/진행 기록, 저장 파일과 백업 복구 |
| `core/look.gd`, `ui.gd` | 공통 디자인 토큰, 표면, 타이포, 버튼과 터치 영역 |
| `game/hero_card.gd`, `rite_board.gd` | 영웅 카드와 별맞춤 의식의 공통 표현 |
| `game/3d/` | 영웅/몬스터 모델, 초상화, 배경, 카메라와 시각 효과 |
| `core/sound.gd`, `i18n.gd` | 앱 생명주기에 맞춘 오디오, 한영 번역 |

`Run`과 `Arena`는 공통 계산 모듈을 사용한다. 전장 수치와 정보창 수치의 계산식을
각 화면에서 복제하지 않는다. 3D 표현은 전투 판정이나 시간을 변경하지 않는다.
`main._swap()`은 이전 화면을 즉시 트리에서 분리하므로 삭제를 기다리는 화면이
입력이나 시뮬레이션을 계속 처리하지 않는다.

광고 서비스·플러그인·보상 콜백은 없다. 이전 저장에 이미 지급된 보상은 보존하며,
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
| `tests/` | 저장·규칙·실제 UI 회귀 검사와 시각 검수 씬 |
| `tools/3d/`, `sprite/`, `audio/`, `vfx/` | 재현 가능한 제작·검수 도구(모션 클립 작성, VFX 텍스처 생성 포함) |
| `art/vfx/` | 전투 이펙트 셰이더와 절차 생성 스프라이트 아틀라스·노이즈 |
| `build/`, `.godot/`, `android/build/` | 생성물과 로컬 캐시, Git 제외 |

DB 승인 절차와 배포 제외 검사는 [GAME_DB.md](GAME_DB.md)를 따른다.
에셋은 정적 경로뿐 아니라 로스터·모델 매니페스트·동적 경로도 확인하고 정리한다.
모델 제작 원본과 진행 중인 사용자 자료를 단순히 런타임 미참조라는 이유로 삭제하지 않는다.

## 빌드

`tools/verify.sh`가 검증을 모으고, `tools/build_apk.sh`가 성공한 APK를 고정 경로로
교체한다. `tools/ci/export.sh`는 APK와 iOS 프로젝트를 함께 내보낸다.
`check_no_ads.py`, `check_no_db.py`, `check_stellar_assets.py`가 배포물의 광고 부재,
DB 제외, 실제 3D 리소스 포함을 검사한다. 서명·브랜치·산출물 규칙은
[MOBILE_BUILDS.md](MOBILE_BUILDS.md)에 있다.
