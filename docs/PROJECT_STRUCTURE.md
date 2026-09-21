# 프로젝트 구조 안내 — 올인 디펜스

> 2026-09-15 기준. 폴더·파일이 무슨 역할을 하는지 한 곳에 적은 지도다.
> 게임 규칙은 [README.md](../README.md), 마무리 절차는 [WRAPUP.md](../WRAPUP.md) 를 본다.

**한 줄 요약**: 트럼프 다섯 장으로 영웅을 뽑아 크리스탈을 지키는 디펜스. Godot 4.7.1 · 안드로이드 가로 화면 · 전부 2D 픽셀아트.
화면은 `.tscn` 없이 GDScript `_draw()` 로 그리고, 그림·소리·애니메이션은 이 PC 의 로컬 모델(Krea 2 · Wan 2.2 · MiniMax H3 · ElevenLabs)로 만든다.

---

## 0. 한눈에 보기

```
pocker/
├── project.godot          Godot 프로젝트 설정 (오토로드 5개 · 메인 씬)
├── export_presets.cfg     안드로이드 APK · iOS 익스포트 프리셋
├── README.md              게임 규칙 전체 · 돌려 보기 · 그림 만드는 법
├── WRAPUP.md              마무리 절차 (검증 → 사진 → 굽기 → APK → 커밋)
├── AGENTS.md              에이전트 작업 규칙 (APK 고정 경로 · 디자인 서브에이전트)
├── pokerdefense_world_characters_v2.md   세계관 · 50캐릭터 설정서
├── core/      게임 규칙 · 데이터 · 오토로드 (화면을 모르는 순수 로직)
├── game/      화면 하나 = 파일 하나 · 전투 시뮬레이터 · 이펙트
├── tests/     헤드리스 검사기 · 촬영 진입점 (Godot 씬)
├── tools/     생성 · 검증 · 빌드 도구 (Python · Bash)
│   ├── sprite/     스프라이트 파이프라인 (원화 → 클립 → 시트 → 반입)
│   ├── anim/       리그 기반 구(舊) 애니메이션 파이프라인
│   ├── audio/      ElevenLabs 음원 생성 · 검사
│   └── blender3d/  3D → 도트 시험용 길 (공식 아님)
├── art/       그림 · 소리 · 애니메이션 에셋 (저장소에 넣는다)
├── docs/      설계 · 변경 기록 · 제출용 웹 페이지 소스
├── addons/admob/   AdMob 플러그인 (외부, Poing Studios)
├── android/        Godot 안드로이드 gradle 빌드 템플릿
├── .codex/         Codex 서브에이전트 정의
├── .godot/         에디터 캐시 (git 제외)
└── build/          생성물 — 사진 · 로그 · 시트 중간물 · APK (git 제외)
```

**데이터가 흐르는 길 셋**

| 흐름 | 원본 | 도구 | 결과 |
|---|---|---|---|
| 캐릭터·몬스터·테마 표 | `tools/roster.json` | `tools/gen_roster.py` | `core/roster.gd` (손으로 고치지 않는다) |
| 정지 그림 | `tools/roster.json` 의 prompt | `tools/gen_art.py` (Krea 2) | `art/units/` · `art/monsters/` · `art/ui/` · `art/themes/` |
| 애니메이션 | 원화 한 장 | `tools/sprite/*` (Wan 2.2 / H3) | `art/anim/<id>/` (`core/anim.gd` 가 읽는다) |

---

## 1. 루트 파일

| 파일 | 역할 |
|---|---|
| `project.godot` | Godot 설정. 앱 이름 「올인 디펜스」, 메인 씬 `game/boot.tscn`, 오토로드 **Save · I18n · Run · Sfx · Ads**, 뷰포트 1280x800 가로, GL Compatibility 렌더러, 기본 폰트 `core/fonts/RefugeSans-Bold.otf`, AdMob 플러그인 활성, 아이콘 `art/ui/crystal.png` |
| `export_presets.cfg` | 프리셋 둘 — **Android Test APK** (`../../pokerdefense-test.apk` 로 굽는다, 패키지 `com.devjieung.pokerdefense`) · **iOS**. `include_filter` 에 `art/anim/*/anim.json` 과 `core/locales/*.json` 을 넣고, `exclude_filter` 로 `tools/ build/ docs/ tests/ art/sprite/ art/concepts/ art/animation/ art/audio_sources/` 등을 뺀다. 머리말에 그 까닭이 적혀 있다 |
| `README.md` | 게임이 무엇인지 전부 — 카드 뽑기 → 영웅 → 전장 12자리 → 크리스탈 → 상점 → 100탄, 돌려 보는 법, 그림 만드는 법, 만듦새 |
| `WRAPUP.md` | 작업을 마칠 때의 순서 — `tools/verify.sh` 검증, 스크린샷, 그림·스프라이트 다시 굽기, APK, 커밋. 끝에 「절대 잊으면 안 되는 것」 |
| `AGENTS.md` | 에이전트 작업 규칙. APK 는 항상 `~/pokerdefense-test.apk` 에 덮어쓴다. 디자인 작업은 `graphic_design_manager` 서브에이전트에 위임한다 |
| `pokerdefense_world_characters_v2.md` | 세계관 「마지막 불빛의 카지노」 와 50캐릭터(속성 5 x 등급 10) 설정서. 이름·외형·기믹·프롬프트의 근거 문서 |
| `.gitignore` | `.godot/` · `build/*` · `__pycache__` · `.env` 제외. **`art/` 는 일부러 넣는다** (다시 만드는 데 GPU 로 한 시간) |
| `.env` | `ELEVENLABS_API_KEY`. git 제외 |
| `CLAUDE.md` | 저장소 HEAD 에는 있으나 **작업 트리에서 지워진 상태**다. 코드 주석과 문서 곳곳이 `CLAUDE.md 4-3`, `CLAUDE.md 19` 처럼 절 번호로 참조한다 |
| `icon.svg` | 마찬가지로 HEAD 에만 있고 작업 트리에는 없다. 실제 아이콘은 `art/ui/crystal.png` |

---

## 2. `core/` — 게임 규칙 · 데이터 · 오토로드

화면을 모르는 순수 로직과, 화면 셋이 함께 쓰는 공용 그리기가 있다. 모든 `.gd` 옆의 `.uid` 는 Godot 4.4+ 가 붙이는 리소스 ID 사이드카다.

### 오토로드 (project.godot 에 등록, 이름으로 어디서나 부른다)

| 파일 | 이름 | 역할 |
|---|---|---|
| `run.gd` | `Run` | **한 판(런)의 상태 전부** — 단계(phase), 탄, 크리스탈(목숨), 골드, 영웅 편성, 카드 다섯 장과 칸별 카드 더미, 리롤 횟수, 패시브. 되돌릴 수 없는 순간(리롤·확정·구매)의 자동 저장도 여기서 건다 |
| `save.gd` | `Save` | 저장 파일 하나 `user://save.cfg`. `run`(평생 기록) · `cur`(하던 판 통째로 = 자동 저장) · `opt`(설정·언어). `POCKER_NO_SAVE=1` 이면 읽기만 한다 |
| `i18n.gd` | `I18n` | Kor / Eng 번역. `core/locales/*.json` 카탈로그를 읽고 `language_changed` 시그널을 낸다. 게임 ID·저장·전투 값은 언어와 무관하게 둔다 |
| `sound.gd` | `Sfx` | 효과음·장면별 BGM 재생. 소리마다 최소 간격을 두어 겹침을 버린다. 파일이 없어도 조용히 넘어간다 |
| `ads.gd` | `Ads` | 보상형 광고(AdMob) 래퍼. `completed(kind, rewarded)` 시그널. 테스트 유닛 ID 사용 |

### 순수 로직 (`RefCounted` · `class_name`)

| 파일 | class | 역할 |
|---|---|---|
| `poker.gd` | `Poker` | 트럼프 카드와 **족보 판정**. `Hand` enum 값이 곧 캐릭터 등급 인덱스. `tests/poker_check.gd` 가 전수 검사한다 |
| `balance.gd` | `Balance` | **게임의 숫자 전부** — 투기장 좌표와 길(`path_at`), 체력 곡선, 상성 배수, 골드, 상점 가격, 공격 방식별 계산. 순수 함수만 |
| `roster.gd` | `Roster` | **자동 생성 파일** (`tools/gen_roster.py` ← `tools/roster.json`). 캐릭터 50 · 몬스터 25 · 테마 50 표와 등급 이름, 그림 높이, 총구 좌표(`muz`), 팔 뻗는 시간(`wind`) |
| `run_validation.gd` | `RunValidation` | 저장 파일에서 온 값을 형 변환 전에 검사. 복구 실패 시 현재 판을 바꾸지 않는다 |
| `dbg.gd` | `Dbg` | 디버그 오버레이 상태(정적 변수). 꺼져 있으면 아무 일도 안 한다 |

### 공용 그리기 · 리소스

| 파일 | class | 역할 |
|---|---|---|
| `look.gd` | `Look` | **색 · 글꼴 · 카드 그리기 한 곳.** 밤의 도박장 팔레트, 등급 색(`TIER_COLOR`), 카드 무늬는 글자가 아니라 도형으로(`draw_suit`) |
| `ui.gd` | `Ui` | `_draw()` 화면용 버튼 도우미 — 그리면서 동시에 눌리는 자리를 등록한다 |
| `art.gd` | `Art` | 텍스처 캐시. 그림이 없으면 `null` 을 주고 화면이 도형으로 대신 그린다 |
| `anim.gd` | `Anim` | 영웅 Idle · Attack · Shot, 몬스터 Move 클립 로더. `art/anim/<id>/` 의 스트립 PNG + `anim.json`. 없으면 빈 딕셔너리 → 정지 그림으로 돈다 |
| `scenery.gd` | `Scenery` | 테마 배경을 **코드로** 그린다(하늘·능선·땅·날씨). `art/themes/` 그림이 있으면 그림이 먼저고 날씨만 얹는다 |

### 하위 폴더

| 경로 | 역할 |
|---|---|
| `fonts/RefugeSans-Bold.otf` | 본문·버튼 기본 폰트. Noto Sans CJK KR Bold 의 한글·라틴·UI 기호 서브셋(MSDF) |
| `fonts/NeoDunggeunmoPro.ttf` | 한국어 픽셀 폰트(큰 제목용). `OFL.txt` 라이선스 |
| `fonts/DinoKR.ttf` | 이전 번들 폰트(Noto Sans CJK KR Bold). ♠♦♣ 글리프가 없어 무늬를 도형으로 그리게 된 계기 |
| `locales/ui.json` | UI 문자열 ko / en 카탈로그 |
| `locales/heroes.json` | 영웅 50명 소개문 ko / en |

---

## 3. `game/` — 화면과 전투

씬 파일은 `boot.tscn` 하나뿐이다. 화면 하나가 `.gd` 파일 하나이고 코드로 세운다(헤드리스 검사기가 씬 없이 화면을 세울 수 있게).

### 진행

| 파일 | class | 역할 |
|---|---|---|
| `boot.tscn` | — | 메인 씬. `main.gd` 가 붙은 `Node2D` 하나 |
| `main.gd` | — | **화면을 갈아 끼우는 곳.** 타이틀 → [테마 판] → (카드 뽑기 → 전투 → 상점) 반복 → 끝. 단계가 바뀔 때 자동 저장 |
| `title_screen.gd` | `TitleScreen` | 타이틀. Kor / Eng 선택, 새로 시작 · 이어하기, 평생 기록 한 줄 |
| `theme_screen.gd` | `ThemeScreen` | 테마가 바뀔 때 등장 몬스터 · 속성 · 비율을 보여 주는 판 |
| `draw_screen.gd` | `DrawScreen` | 카드 다섯 장 받기 · 리롤 · 족보 확정 (PICK → REVEAL → SWAP) |
| `summon_art.gd` | `SummonArt` | 뽑기 화면의 마녀 딜러 그림(`art/ui/dealer/witch.png`) 과 소환 연출 |
| `shop_screen.gd` | `ShopScreen` | 탄 사이 상점 — 능력치 · 패시브(셋만) · 크리스탈 되사기 탭 |
| `over_screen.gd` | `OverScreen` | 판 끝 화면. 이겼든 졌든 같은 화면, 문구와 색만 다르다 |
| `menu_overlay.gd` | `MenuOverlay` | 모든 화면 공용 일시정지 메뉴. 화면의 처리와 입력을 함께 멈춘다 |

### 편성

| 파일 | class | 역할 |
|---|---|---|
| `hero_view.gd` | `HeroView` | **영웅 편성 판** — 성역 자리와 영웅 전당(대기)을 한 판에. 설명 팝업, 옮기기, 전당 스크롤 |
| `formation_view.gd` | `FormationView` | 편성 판의 속성 필터 · 페이지 · 선택 상태. 필터해도 실제 카드 인덱스를 보존한다 |
| `fusion_view.gd` | `FusionView` | 영웅 **합성** 창 — 카드 5장을 재료로 고르고 결과를 연출 |
| `hero_card.gd` | `HeroCard` | 영웅 카드 한 장 그리기(등급 색 프레임 · 속성 · 역할) |
| `hud.gd` | `Hud` | 뽑기 · 전투 · 상점 셋이 똑같이 그리는 위쪽 정보띠(탄 · 크리스탈 · 골드)와 「이 탄에 오는 몬스터」 줄 |

### 전투

| 파일 | class | 역할 |
|---|---|---|
| `battle_sim.gd` | `BattleSim` | **전투 그 자체. 그리기를 전혀 모른다.** 길 걷기, 크리스탈 깨짐, 공격 방식 일곱, 상태이상, 밀어내기. 헤드리스 자동 플레이가 이걸 그대로 돌린다 |
| `battle_screen.gd` | `BattleScreen` | 전투 화면 — 그리기와 손가락만. 오른쪽 정보판(누가 얼마나 때리나), 상성별 피해 막대, 전투 중 재배치 |
| `battlefield.gd` | `Battlefield` | 지형 재질 아틀라스(`art/terrain/biome_materials.png`) 를 테마의 몸 속성별로 잘라 준다 |
| `area_fx.gd` | `AreaFx` | 장판 · 광역 착탄 연출(`art/effects/area_attacks.png`). 표현만, 피해는 BattleSim 소유 |
| `fx.gd` | `Fx` | 이펙트 한 무더기 — 파티클 · 섬광 · 빛살 · 흔들림. 노드가 아니라 딕셔너리 배열 하나 |

### 디버그

| 파일 | class | 역할 |
|---|---|---|
| `dbg_sim.gd` | `DbgSim` | `BattleSim` 을 상속해 hp 가 깎이는 모든 자리를 기록하는 시뮬레이터. `Dbg.on` 이 아니면 곧장 `super()` |
| `debug_view.gd` | `DebugView` | 전투 화면 위 디버그 판(F3). 흐름 · 영웅 · 몬스터 · 표 탭, 멈춤 · 한 걸음. 절차는 `docs/DEBUG.md` |

---

## 4. `tests/` — 검사기 · 촬영 진입점

각 `.gd` 마다 짝 `.tscn` 이 있다(스크립트만 붙인 빈 씬. `godot --headless --path . res://tests/<이름>.tscn` 으로 돈다).
**커맨드라인 인자를 읽는 코드는 이 폴더에만 둔다.** 판정 문구는 「판정: 정상」 하나이고 `tools/verify.sh` 가 그 글자를 찾는다.

### 공통 뼈대

| 파일 | 역할 |
|---|---|
| `harness.gd` (`Harness`) | 세기(check) · 판정과 종료(finish) · 저장 보호 · 화면 누르기(tap/press) · 프레임 기다리기 · 사진(snap) · 인자 읽기 |
| `fixture.gd` (`Fixture`) | 검사·촬영이 세우는 판 — 「n탄까지 간 판」 · 「원하는 족보가 나오는 손패」 |
| `policy.gd` (`PlayPolicy`) | 「웬만큼 하는 사람」을 흉내 내는 자동 플레이어. 밸런스의 기준 실력 |

### 규칙 · 밸런스 검사

| 파일 | 무엇을 보나 |
|---|---|
| `poker_check.gd` | 족보 판정 **전수 검사** — 52장에서 5장 고르는 2,598,960가지 전부 |
| `balance_check.gd` | 자동 플레이로 100탄까지 여러 판 돌려 클리어율 · 탄별 목숨 손실 |
| `dmg_check.gd` | 「이 한 대가 왜 이 숫자인가」 — 데미지가 지나가는 다섯 마디를 따라간다 |
| `ns_check.gd` | **표와 표가 어긋나지 않는지** — 그림 · 소리 · 총구 좌표 · 무늬 · 이름 · 테마. `--strict` 면 그림 하나라도 없으면 실패 |
| `rules_check.gd` | 새 규칙 회귀 — 발판 열둘 · 중복 출전 금지 · 옛 저장 이주 · 리롤 · 합성 · 보상 |
| `formation_check.gd` | 두 입구 · 12자리 · 실시간 재배치 |
| `range_check.gd` | 사거리 — 화면과 전투가 같은 값을 쓰는가 |
| `push_check.gd` | 물 「특효」 밀어내기가 프레임 크기와 무관하게 같은 거리로 끝나는가 |
| `monster_check.gd` | 몬스터 이동 클립 · 상태이상 · 희귀 착탄 |
| `element_aoe_check.gd` | 속성 광역 5인의 실제 시트 로딩이 공격 타이밍과 피해를 지키는가 |
| `aoe_scope_check.gd` | 위를 상속. 장판(zone) 영웅 전부의 범위 검사 |
| `all_hero_sprites_check.gd` + `all_hero_sprites_contract.json` | 영웅 50명 시트가 계약(앵커 · 배율 · 총구 · hit_ms)대로 들어와 있는가 |
| `audio_check.gd` | 오디오 런타임 회귀(음악 · 효과음 켜고 실제 재생) |
| `localization_check.gd` | 한영 전환 · 언어 저장 · 서식 메시지 · 영웅 정보 |

### 화면을 실제로 눌러 보는 검사

| 파일 | 무엇을 보나 |
|---|---|
| `play_check.gd` | 타이틀 → 카드 → 전투 → 상점을 **손가락으로 눌러** 한 바퀴. 그린 자리와 눌리는 자리가 같은지 |
| `flow_check.gd` | 저장 · 보상 · 메뉴 · 거래 회귀 |
| `presentation_check.gd` | 화면 개선 회귀 — 확정 연출 · 편성 판 · 전당 탭 · 지형 그림 · 착탄 |
| `rewards_ui_check.gd` | 보상(광고) 흐름 화면을 눌러 보고 `build/` 에 사진 |
| `feedback_check.gd` | 딜러 · UI · 오디오 피드백 반영 화면 회귀 |

### 촬영 · 미리보기 (Xvfb 위에서 실제 렌더)

| 파일 | 역할 |
|---|---|
| `shot.gd` | **스크린샷 진입점.** `tools/screenshot.py` 가 부른다. `--shots title,draw:5,battle:12,…` |
| `sprite_shot.gd` | 스프라이트 시트가 엔진 안에서 실제로 도는지 찍는다 |
| `demo.gd` + `demo_caption.gd` | 소개 영상 촬영 대본과 자막. `tools/record.py` 가 부른다 |
| `all_hero_sprites_preview.gd` | 영웅 시트 재생 미리보기 → `build/all-hero-sprites/` |
| `element_aoe_preview.gd` | 광역 5인 Idle · Attack · Shot 재생 → `build/element-aoe-sprites/` |
| `dealer_refresh_preview.gd` | 딜러 · 소환 · 합성 · 야영지 UI 렌더 → `build/dealer-refresh/` |
| `ui_polish_preview.gd` | 한영 포커 · 보상 · 영웅 정보 렌더 → `build/ui-polish/` |
| `visual_refinement_preview.gd` | 희귀도 표식 · 마비 · 장판 발판 · 밀어내기 고정 픽스처 → `build/visual-refinement/` |
| `monster_preview.gd` · `rarity_preview.gd` | 몬스터 클립 · 등급 연출 미리보기 |

---

## 5. `tools/` — 생성 · 검증 · 빌드 도구

### 최상위

| 파일 | 역할 |
|---|---|
| `verify.sh` | **검증 한 곳.** 0 커맨드라인 → 0-1 무늬 → 1 표 최신 → 1-1 음원 → 2 임포트 → 3 부팅 → 4 표 정합(4-1 시트 · 4-2 흐름 · 4-3 편성 · 4-4 피해 · 4-5 몬스터) → 5 족보 → 6 화면 한 바퀴 → 7 자동 플레이 → 8 폰트 → 8-1 한영 → 9 APK. `quick` · `--skip-sprites` |
| `build_apk.sh` | JDK 17 로 APK 를 굽고 서명 · AdMob 플러그인을 확인한 뒤 `~/pokerdefense-test.apk` 를 교체 |
| `roster.json` | **캐릭터 50 · 몬스터 25 · 테마 50 의 원본 표.** id · 이름 · 역할 · 속성 · 무기 · 프롬프트 · 크기 보정(`sc`) · `holes` · `floor_prompt`. 캐릭터를 더하거나 고치려면 여기 한 곳 |
| `gen_roster.py` | `roster.json` → `core/roster.gd`. `art/anim/*/anim.json` 의 총구 · 시간도 함께 찍는다 |
| `gen_art.py` | 로컬 **Krea 2 Turbo** 로 정지 그림 생성(`--kind unit,monster,ui,theme`). **화풍 앵커가 여기 한 곳**에만 있다. 흰 배경 오려내기 · 픽셀화 후처리 |
| `reroll_art.py` | 몇 명만 후보 여러 장을 뽑아 `build/cand/` 에 두고 눈으로 고른 뒤 얹는다 |
| `style_test.py` | 화풍 후보 x 표본 캐릭터 시험 → `build/styletest/` |
| `gen_ui_refresh.py` | 야영지 UI 소재(`art/ui/refuge/`) 생성 |
| `gen_concepts.py` | `roster.json` → `tools/anim/concepts.json` (애니메이션용 무기 · 동작 · 램프 붙이기) |
| `gen_sfx.py` | 효과음을 사인파 · 잡음으로 **코드 합성**하던 도구. 2026-09-14 ElevenLabs 교체 이후 게임은 `art/sfx/` 의 생성 음원을 쓴다 |
| `gen_docparts.py` | 게임 상수에서 제출 문서용 표 · 차트 자료 → `docs/site/_matrix.html` · `_elem.html` · `_data.html` |
| `embed_shots.py` | `docs/site/*.src.html` 의 `{{IMG:…}}` 자리에 스크린샷을 WebP data URI 로 박아 `build/site/*.html` 로 |
| `screenshot.py` | **Xvfb 위에서 화면을 PNG 로** → `build/shots/`. `tests/shot.gd` 를 띄운다 |
| `record.py` | 소개 영상 녹화(`--write-movie`, 고정 fps). `tests/demo.gd` 대본 |
| `godot_env.py` | Godot · Xvfb 공통(`ROOT`, `GODOT`, `xvfb()`). 도구마다 디스플레이 번호를 다르게 |
| `gpu_guard.py` | **Krea2 · Wan · H3 가 같은 순간에 못 뜨게 하는 문지기.** 모델 올리기 직전에 `claim()` |
| `check_font.py` | 화면에 쓰는 모든 문자가 번들 폰트에 있는지(두부 방지) |
| `check_localization.py` | UI 문자열과 로스터의 한영 커버리지 |
| `verify_feedback.py` | 피드백 반영 검사 아홉 씬을 저장 보호 상태로 일괄 실행 → `build/feedback-verification/` |
| `visual_refinement_review.py` · `ui_polish_review.py` · `dealer_refresh_review.py` | 두 해상도(1280x800 · 1000x625)로 실제 렌더한 검토 이미지 묶음 |
| `build_world_design.py` | 세계관 문서 · Krea 입력 · 로컬 갤러리 빌드 (`docs/world_characters_v3.tsv` 기반) |
| `gen_world_concepts.py` | V3 세계관 50명 T포즈 원화 생성(Krea 2) → `art/concepts/last_refuge_v3/` |
| `review_world_concepts.py` · `review_world_pixel.py` | 원화 · 픽셀 변환본의 컨택트 시트와 출처 검증 |

### `tools/sprite/` — 스프라이트 파이프라인 (게임이 쓰는 공식 길)

원화 한 장 → 영상 모델로 동작 → 프레임 → 크로마키 → 96x96 도트 시트 → `art/anim/<id>/` 반입.

| 파일 | 단계 · 역할 |
|---|---|
| `run.sh` · `run50.sh` | 한 명 / 쉰 명을 원화부터 반입까지 한 번에 (`gpujob run pd-sprite tools/sprite/run50.sh`) |
| `units.py` | 대상 쉰 명 — `roster.json` 을 그대로 읽는다. 시드 · LoRA 세기 |
| `pixels.py` | **그림 규칙 한 곳** — 팔레트 · 크로마키 · 공통 크롭 · 양자화 |
| `make_ref.py` | Step 1. 마스터 원화(96 도트)와 영상 입력(512 마젠타) |
| `refine.py` | Step 1-b. 후보를 사람이 고르고(`picks.json`) 마스터를 굽는다 |
| `cutbg.py` | 배경 떼기(BiRefNet, pixelforge venv) |
| `wan_i2v.py` | Step 2. **Wan 2.2 I2V** 로 클립. 동영상을 거치지 않고 PNG 프레임으로 받는다 |
| `h3_i2v.py` | Step 2-H3. **MiniMax H3** 로 같은 꼴의 클립(`--tag _h3`) |
| `repair.py` + `repairs.json` | Step 2.5. 클립의 한 구간만 다시 생성해 끼운다(「다리 놓기」) |
| `sprite_post.py` | Step 3. 프레임 → 게임용 시트(`unit_<id>_<anim>_96x96_<n>.png`) |
| `to_game.py` | Step 4. 시트를 `art/anim/<id>/<id>_idle.png · _attack.png · anim.json` 으로 |
| `shot_sprite.py` | Step 5. 시트를 Godot 안에서 돌려 찍는다 |
| `preview.py` · `report.py` | 시트 띠 · GIF 미리보기, 12fps 로 도는 HTML 보고서 |
| `qc_game.py` | **출고된** 시트(`art/anim/`)를 잰다 — 발 높이 흔들림, 팔레트 이탈 등 |
| `readability.py` | H3 매트를 깨끗한 테두리로 다시 굽고 상세창용 초상화(`art/portraits/`)를 분리 |
| `pixellab.py` | PixelLab 클라우드 흐름(회전 · 보간)을 로컬 모델로 재현한 시범 |
| `comfy_paths.yaml` | ComfyUI 에 Wan 2.2 가중치 자리를 알려 주는 설정 |
| `element_aoe.py` · `element_aoe_preview.py` | 속성 광역 5인 — image_gen 4x3 아틀라스 → 스트립, Godot 재생 캡처 |
| `roster_pack.py` · `roster_prompts.py` · `roster_review.py` · `roster_manifest.py` · `roster_evidence.py` · `roster_preview.py` · `roster_sprite_specs.json` | 나머지 45명에 같은 스타일 적용 — 프롬프트 작성 · 아틀라스 패킹 · 원점 측정 · 기록 · 증빙 (`art/animation/roster_v1/`) |
| `monster_motion.py` · `monster_post.py` | 몬스터 — Krea 참조 자세 → H3 이동 영상 → 앞으로만 걷는 루프 시트(`art/anim/monsters/`) |
| `world_h3.py` · `world_h3_post.py` · `world_h3_audit.py` · `world_h3_bundle.py` · `world_h3_to_game.py` · `world_fx.py` · `world_matte.py` · `world_input_matte.py` | V3 픽셀 로스터 50명의 H3 회전 · Idle · Attack 테이크 생성 → 추출 · 안정화 · 감사 · 번들 · 반입, 공격 이펙트 코드 생성 (`art/animation/last_refuge_v3_pixel_h3/`) |

### `tools/anim/` — 리그 기반 구(舊) 애니메이션 파이프라인

AI 마스터 한 장에서 팔을 오려 어깨 축으로 돌려 프레임을 **코드로** 짜던 길. 결과 파일 꼴(`anim.json`)은 지금도 `core/anim.gd` 가 읽는 표준이다.

| 파일 | 역할 |
|---|---|
| `README.md` | 어떻게 돌리는가 (왜는 `docs/ART.md` 를 가리키지만 그 문서는 현재 없다) |
| `concepts.json` · `anim_fields.json` · `rig_overrides.json` | 캐릭터별 컨셉 · 애니메이션 손잡이(무기 · 동작 · 총구 · 램프) · 사람이 손으로 찍은 리그 점 |
| `gen_master.py` · `contact.py` · `contact_probe.py` · `probe.py` | 마스터 후보 생성 · 이웃과 1:1 대조 · 격자 좌표 찍기 |
| `deffect.py` · `cut_arm.py` · `autorig.py` · `rig.py` | 손 위 이펙트 떼기 · 몸통/팔 가르기 · 리그 점 자동 잡기 · 팔 회전 뼈대 |
| `fx.py` · `mkanim.py` · `build_clips.py` | 이펙트 그리기 · 동작 표대로 프레임 짜기 · 여러 명 클립 일괄 생성 후 `art/anim/` 반입 |
| `h3_sprites.py` · `ltx_clips.py` | `h3-game-sprites` 스킬 방식 / LTX2 영상 방식 시험 |

### `tools/audio/`

| 파일 | 역할 |
|---|---|
| `generate_elevenlabs.py` | ElevenLabs 로 효과음 · BGM 생성(키는 `.env`). 성공한 요청은 재사용, `--install` 로 검증된 음원을 `art/sfx/` · `art/bgm/` 에 반입 |
| `check_audio.py` | 디코딩 검사와 `art/audio-manifest.json` 기록 |
| `check_apk_audio.py` | APK 교체 전 음원 · 시각 의존성 확인 |

### `tools/blender3d/` — 3D → 도트 시험용 길 (**공식 파이프라인이 아니다**)

Blender 로우폴리 → 리깅 → 직교 툰 렌더 → 팔레트 양자화 → 시트. 「3D 로 만들면 어떤가」를 한 명으로 끝까지 돌려 견주려는 것이다.

| 파일 | 역할 |
|---|---|
| `README.md` | 실측 결과와 단계표 |
| `spec.py` | 0단계. 셀 · 프레임 · 방향 · 카메라 · 팔레트 규격 한 곳 |
| `cand_a/` · `cand_b/` · `cand_c/` · `mk/` | 모델 · 리그 · 액션 · 렌더 후보 세 벌과 정리본 |
| `post.py` · `pack.py` · `qc.py` | 후처리(공식 `pixels.py` 를 빌려 씀) · 게임 꼴 패킹 · 품질 검사 |
| `engine_check.py` · `godot/b3d_shot.*` · `dropin_test.sh` | Godot 안에서 실제 재생 · 잠깐 꽂아 `ns_check --strict` 로 확인 후 되돌리기 |
| `fixture.py` · `embed.py` · `probe_*.py` · `smoke/` · `extras/` | 시험대 · 보고서 · 기능 탐침 · 연기 검사 |

---

## 6. `art/` — 그림 · 소리 · 애니메이션 에셋

저장소에 **넣는다**(GPU 로 다시 만들 수 있지만 한 시간). PNG 옆 `.import` 는 Godot 임포트 설정이다.

### 게임이 직접 읽는 것

| 경로 | 내용 |
|---|---|
| `units/<id>.png` | 영웅 50명 정지 그림(편성 판 · 클립이 없을 때의 대체). `gen_art.py` |
| `monsters/<id>.png` | 몬스터 25종 정지 그림 |
| `portraits/<id>.png` | 영웅 상세창 전용 초상화(`readability.py`). `sources/` 에 원본과 `provenance.json` |
| `anim/<id>/` | **영웅 애니메이션** — `<id>_idle.png` · `<id>_attack.png` · `<id>_effect.png`(광역 등) + `anim.json`(칸 크기 · 기준점 · 배율 · 총구 · hit_ms · 칸별 시간). `blank brasa lugh sigrid thalassa` 다섯은 승인 원본 `*_aoe_v1_*` 도 함께 둔다 |
| `anim/monsters/<id>/` | 몬스터 이동 클립 `<id>_move.png` + `anim.json`(`movement`: walk/hop/fly …) |
| `themes/<theme>_bg.png` · `_floor.png` | 테마 50곳의 배경 · 바닥 100장. 바닥은 별도 `floor_prompt` |
| `ui/` | 카드 뒷면 · 크리스탈(앱 아이콘) · 코인 · 하트 · 타이틀 · 상점 배경 · 아레나 배경/바닥, 속성 아이콘 `el_*.png`(7장 · 32x32), 패시브 문양 `pi_*.png`(26장 · 96x96), 상태이상 그림 `fx_ice_bg/fg` · `fx_stun_bg/fg` · `fx_fire` |
| `ui/dealer/` | 마녀 딜러 `witch.png` · 그림 카드 `card_courts.png` · `manifest.json` |
| `ui/refuge/` | 야영지 UI 소재 — `camp` · `wood` · `stone` · `button` + `prompts.json` |
| `effects/area_attacks.png` | 광역 착탄 아틀라스(`game/area_fx.gd`) |
| `terrain/biome_materials.png` | 지형 재질 아틀라스 5몸 x (주변 · 길) (`game/battlefield.gd`) |
| `sfx/*.wav` | 효과음 47개(ElevenLabs). 이름은 `core/sound.gd` 표와 같아야 한다 |
| `bgm/*.ogg` | 장면별 음악 — `camp` · `ritual` · `battle` · `boss` |

### 제작 중간물 · 기록 (APK 에서 제외)

| 경로 | 내용 |
|---|---|
| `sprite/krea/` | Wan 파이프라인이 구운 시트 원본 `unit_<id>_<anim>_96x96_<n>.png`. 게임은 `anim/` 쪽을 읽는다 |
| `animation/element_aoe_v1/` | 광역 5인 image_gen 아틀라스 · 프롬프트 · `manifest.json` · 이전 승인본(`previous/`) |
| `animation/roster_v1/` | 나머지 45명 image_gen 제작 기록 — `jobs.json` · `generation-record.json` · `muzzle_map.json` · `source/` |
| `animation/last_refuge_v3_pixel_h3/` | V3 픽셀 원화 50명의 H3 테이크 검토 — 캐릭터별 `idle/ attack/ effect/` 프레임 · 시트 · webp, `_rejected/` · `_retakes/` · `_source_mattes/`, `index.html` · `effects.html` · `audit.json` |
| `concepts/last_refuge_v3/` | Krea 2 T포즈 원화 50장 + 동명 JSON(모델 · 시드 · 프롬프트) + 갤러리 `index.html` |
| `concepts/last_refuge_v3_pixel/` | 위 원화의 픽셀 변환 50장 + `prompts.jsonl` + 속성별 비교 이미지 |
| `concepts/monsters/` | 몬스터 25종 컨셉 PNG + JSON |
| `audio_sources/` | ElevenLabs 원본 음원(`elevenlabs_v1/` · `music/` · `sfx/`) |
| `audio-manifest.json` | 음원 출처 · 프롬프트 · 해시 기록 |
| `generated-assets.json` | image_gen 으로 만든 에셋(지형 · 효과 아틀라스 등)의 프롬프트 기록 |

---

## 7. `docs/` — 문서

`.gdignore` 가 있어 Godot 이 이 폴더를 스캔하지 않는다. APK 에서도 제외.

### 기준 문서

| 파일 | 역할 |
|---|---|
| `REWARDS_AND_FUSION.md` | **현재 전투 · 영웅 합성 · 보상형 광고 규칙.** README 가 「현재 규칙은 이 문서를 따른다」고 지목 |
| `DESIGN_SYSTEM.md` | 디자인 기준(`graphic_design_manager` 가 세션마다 읽음) + 픽셀아트 제작 지침 · DGX Spark 워크플로 · 작업별 기록 |
| `LOCALIZATION.md` | Kor / Eng 표시 — 언어 데이터 · 저장 · 검증 |
| `DEBUG.md` | 데미지를 눈으로 따라가기 — 에디터 F3 오버레이 · 중단점 · 헤드리스 `dmg_check` |
| `PROJECT_STRUCTURE.md` | 이 문서 |

### 변경 기록 (날짜순)

| 파일 | 내용 |
|---|---|
| `UPGRADE_2026-09-08.md` | 일시정지 · 규칙 도움말 · 저장 복구 · 보상 정산 · 광선 겹침 |
| `UPGRADE_2026-09-09.md` | 픽셀 UI · NewMap 전장 · 두 입구 · 배치 |
| `UI_READABILITY_2026-09-09.md` | 출전 6 / 배치 12 분리 · 별 희귀도 · 본문 글꼴 |
| `UI_VOC_FIXES.md` | 영웅 상세창 넘침 · 희귀도 병기 · 폰트 통일 |
| `CHARACTER_READABILITY.md` | 전투 프레임 외곽 정리 · 상세창 원화 분리 |
| `ui-refresh.md` | 2026-09-11 화면 · 전투 연출 |
| `range-and-visibility.md` | 2026-09-11 가림 수정 · 사거리 · 난이도 |
| `MONSTER_MOTION.md` | 몬스터 모션 · 초반 전투 조정 |
| `UX_REFINEMENT_2026-09-14.md` | 밀어내기 · 화면 가독성 |
| `FEEDBACK_RELEASE.md` | 2026-09-14 사용자 피드백 반영 |
| `AUDIO_REFRESH.md` | 2026-09-14 ElevenLabs 오디오 교체 |

### 세계관 · 제출 자료

| 파일 | 역할 |
|---|---|
| `world_v3_setting.md` | 세계관 · 50캐릭터 개정안 rev.3 |
| `world_characters_v3.tsv` | 캐릭터 50명 표(외형 · 기믹 · 공격 · 이야기 · 영문 프롬프트). `build_world_design.py` 입력 |
| `world_v3_art_refinements.json` | 캐릭터별 원화 프롬프트 보정 |
| `archive/pokerdefense_world_characters_v2_before_20260909.md` | 개정 전 v2 설정서 |
| `site/intro.src.html` · `design.src.html` · `making.src.html` | 제출용 웹 페이지 소스 — 소개 · 기획서 · 제작기. `embed_shots.py` 가 `build/site/` 로 굽는다 |
| `site/_base.css` | 세 페이지 공통 뼈대(색은 `core/look.gd` 팔레트 그대로) |
| `site/_data.html` · `_elem.html` · `_matrix.html` | `gen_docparts.py` 가 게임 상수에서 찍어 내는 데이터 · 상성표 · 배치 행렬 |

---

## 8. 플랫폼 · 외부 · 생성물

| 경로 | 역할 |
|---|---|
| `addons/admob/` | **Poing Studios AdMob 플러그인 5.0.0** (외부 코드). `core/ads.gd` 가 사용. `gdscript/` · `csharp/` API, `android/bin/` 미디에이션 라이브러리, `ios/`, `docs/`, `skills/` |
| `android/` | Godot 안드로이드 **gradle 빌드 템플릿**(`build/`). `.build_version` = 4.7.1.stable. `.gdignore` |
| `.codex/config.toml` | Codex 서브에이전트 활성화 |
| `.codex/agents/graphic_design_manager.toml` | 전담 그래픽 디자인 서브에이전트 역할 정의(`AGENTS.md` 가 지목) |
| `.godot/` | 에디터 캐시 · 임포트된 리소스 · UID 캐시. git 제외 |
| `build/` | **생성물 전부** (git 제외 · `.gdignore`). `shots/` 스크린샷, `sprite/` 시트 중간물, `b3d/` 3D 시험, `monster-motion/` · `readability/` · `all-hero-sprites/` 등 파이프라인 작업 폴더, `toolchains/`(jdk17 · xvfb), `godot-config/` · `admob/`(빌드 템플릿 · 플러그인), `apk/`, `site/`, `video/`, 화면 검토 폴더들(`ui-polish/` · `visual-refinement/` · `voc-review/` …)과 각 검사의 `*.log` |

---

## 9. 참고 — 문서가 가리키지만 지금 없는 파일

코드 주석과 README 가 참조하는데 작업 트리에 없는 것들이다. 그 절 번호를 찾으려면 git 이력을 본다.

| 참조 | 어디서 부르나 | 상태 |
|---|---|---|
| `CLAUDE.md` | 코드 주석 전반, README, WRAPUP | HEAD 에는 있음, 작업 트리에서 삭제됨 |
| `docs/ART.md` | `core/anim.gd`, `tools/anim/*` | 없음 |
| `docs/SPRITE.md` | README, `tools/sprite/*`, `export_presets.cfg` | 없음 |
| `docs/PIXELLAB.md` | `tools/sprite/repair.py` | 없음 |
| `chardesign.md` | README 「그림」 절 | 없음 |
| `icon.svg` | git 추적 | 작업 트리에서 삭제됨(아이콘은 `art/ui/crystal.png`) |
