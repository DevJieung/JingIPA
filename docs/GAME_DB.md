# 게임 데이터 DB

> 2026-10-08. 게임의 표 데이터를 `data/game.db`(SQLite) 한 곳에서 관리한다.
> **게임은 DB 를 읽지 않는다.** 승인된 값만 기존 JSON · 게임 코드의 제자리에 내려가고,
> 배포물(APK · IPA)에는 DB 가 실리지 않는다.

## 흐름

```
                 status 로 확인 → 사용자 승인 → apply --approved
data/game.db ─────────────────────────────────────────────▶ tools/roster.json ─ gen_roster.py ─▶ core/roster.gd
  (원본)                                                     core/locales/ui.json · heroes.json
     ▲                                                       core/balance.gd · core/sound.gd · core/scenery.gd 의 값
     └──────────────── pull (게임 파일을 직접 고쳤을 때) ────────────┘
```

- 게임 코드의 구조는 그대로다. `Roster.UNITS` · `Balance.PASSIVES` · `core/locales/*.json` 을
  읽는 코드는 한 줄도 바뀌지 않았다.
- 코드 쪽(`core/balance.gd` 등)은 **바뀐 값의 글자만** 갈아 끼운다. 주석 · 줄 맞춤 · 소수
  자릿수(`1.90` 자리에는 `2.00`) · 밑줄(`1_000_000`)이 그대로 남는다.
- JSON 세 장(`tools/roster.json` · `core/locales/ui.json` · `heroes.json`)은 DB 에서 통째로 찍는다.

## 고치는 법

1. **DB 를 고친다.** DB Browser for SQLite 같은 도구로 열거나 SQL 로:
   ```bash
   sqlite3 data/game.db "UPDATE passives SET cost = 260 WHERE id = 'repeater'"
   ```
2. **무엇이 바뀌는지 본다.** 아무것도 쓰지 않는다.
   ```bash
   python3 tools/gamedb.py status
   ```
3. **사용자가 승인하면 내린다.** `--approved` 없이는 목록만 보여 주고 끝난다(종료 코드 2).
   ```bash
   python3 tools/gamedb.py apply --approved -m "연발 장치 값 조정"
   ```
4. `tools/verify.sh` 를 돌린다. 밸런스 숫자를 바꿨으면 `tests/balance_check` 까지.

에이전트는 2번의 목록을 사용자에게 보여 주고 승인을 받은 뒤에만 3번을 실행한다(`AGENTS.md`).

| 명령 | 하는 일 |
|---|---|
| `status` | DB 와 게임 파일의 차이를 셋으로 갈라 보여 준다. 쓰지 않는다 |
| `apply` | 내릴 목록과 바뀔 파일을 보여 준다. 쓰지 않는다 |
| `apply --approved [-m 메모]` | DB 의 값을 JSON · 게임 코드로 내리고 기록을 남긴다 |
| `pull [-m 메모]` | 게임 파일을 직접 고친 값을 DB 로 들인다 |
| `check` | `tools/verify.sh` 0-2 단계. 게임 파일이 DB 를 안 거치고 바뀌었으면 실패 |
| `log` | 내리고 들인 기록 |
| `init` | 지금 게임 파일에서 DB 를 새로 짓는다(`--force` 면 있던 DB 를 버린다) |

## 세 가지 상태

도구는 게임 파일 · DB · **마지막으로 둘을 맞췄을 때의 값**(DB 안의 `_baseline`)을 견준다.

| 상태 | 뜻 | 푸는 법 |
|---|---|---|
| 승인 대기 | DB 에서 고쳤고 게임 파일에는 아직 안 내렸다 | 승인 후 `apply --approved`. `verify.sh` 는 알림만 찍고 통과한다 |
| 파일 직접 수정 | 누가 `balance.gd` 의 숫자나 `roster.json` 을 DB 를 안 거치고 고쳤다 | `pull` 로 DB 에 들인다. `verify.sh` 가 실패로 잡는다 |
| 충돌 | 같은 값을 DB 와 게임 파일에서 서로 다르게 고쳤다 | 파일 값이 맞으면 `pull --force`, DB 값이 맞으면 `apply --approved --force` |

파일 직접 수정이나 충돌이 남아 있으면 `apply` 는 내리지 않는다. 기준이 없으면 어느 쪽이 새
값인지 알 수 없어서, 남이 코드에 고친 숫자를 `apply` 가 말없이 되돌리게 된다.

## DB 에 든 표

| 표 | 내용 | 내려가는 곳 | 줄 더하기 · 빼기 |
|---|---|---|---|
| `units` | 영웅 50 — 이름 · 역할 · 성향 · 방식 · 무기 · 속성 · 크기 보정 · 설명 · 프롬프트 · 한영 소개문 | `tools/roster.json` → `core/roster.gd`, `core/locales/heroes.json` | 된다 |
| `art_tiers` | 원화 격 10 | `tools/roster.json` | 된다 |
| `monsters` | 몬스터 25 | `tools/roster.json` → `core/roster.gd` | 된다 |
| `themes` · `theme_weights` | 테마 50 · 몸 분포 250 · 지형 모티프 | `tools/roster.json` → `core/roster.gd`, `core/scenery.gd` 의 `MAP_MOTIFS` | 된다 |
| `arts` | 화면 그림 47 | `tools/roster.json` → `core/roster.gd` | 된다 |
| `strings` | UI 문구 ko 20 · en 611 | `core/locales/ui.json` | 된다 |
| `passives` · `passive_effects` | 패시브 26 과 효과 값 | `core/balance.gd` 의 `PASSIVES` | 된다(줄 차례는 못 바꾼다) |
| `upgrades` | 상점 능력치 7 | `core/balance.gd` 의 `UPGRADES` | 된다(새 id 는 코드가 알아야 동작한다) |
| `sfx_gaps` | 효과음 최소 간격 28 | `core/sound.gd` 의 `GAP` | 된다 |
| `tuning` | 숫자 상수 80 (`START_GOLD` · `HP_GROW` …). `doc` 열은 코드 주석에서 옮긴 설명 | `core/balance.gd` 의 `const` | 값만 |
| `hero_tiers` | 등급 10칸의 공격력 · 공속 | `TIER_ATK` · `TIER_RATE` | 값만 |
| `elements` · `bodies` · `affinity` | 공격 속성 5 · 몸 5 · 상성(약점/저항/면역) | `ELEM` · `MBODY` | 값만(상성은 `affinity` 줄로 바꾼다) |
| `profiles` · `weapons` · `roles` | 성향 4 · 무기 사거리 5 · 역할 4 | `PROFILE` · `PROFILE_RANGE` · `WEAPON_RANGE` · `ROLE` | 값만 |
| `bullets` · `bullet_params` | 공격 방식 7 과 방식별 손잡이 | `BULLET` | 값만 |
| `statuses` · `monster_kinds` | 상태이상 3 · 몬스터 형 5 | `STATUS` · `MKIND` | 값만 |
| `rite_gates` · `theme_rank_hp` | 의식 문 너비 5 · 테마 체력 배수 6 | `RITE_GATE` · `THEME_RANK_HP` | 값만 |
| `_meta` · `_baseline` · `_approvals` | 도구가 쓰는 표 | — | 손대지 않는다 |

- 「값만」인 표는 **줄을 코드가 정한다.** 속성을 하나 더하려면 그것을 다루는 코드가 먼저
  있어야 하므로, 코드에 줄을 만든 뒤 `pull` 로 DB 에 들인다. DB 에서 먼저 더하면 `apply` 가
  거절한다.
- 줄의 자리는 `sort` 열이다. 사이에 끼우려면 소수를 쓴다(`7.5`).
- 정수 칸에 소수, 색 칸에 `#RRGGBB` 가 아닌 값, 없는 속성 · 몸 · 역할을 가리키는 줄은 DB 가
  넣는 순간 거절한다. 형(정수/실수)은 코드가 정한 것을 따른다.
- 테마의 몸 분포는 몸 다섯을 다 적고 합이 1.0 이어야 한다(`status` · `apply` 가 본다).

## 알아둘 것

- **DB 는 git 에 넣는다.** 바이너리라 diff 가 안 보이므로, 무엇이 바뀌었는지는 내려간
  JSON · 코드의 diff 와 `python3 tools/gamedb.py log` 로 본다.
- `tools/roster.json` 은 DB 에서 처음 내릴 때 화면 그림 2건의 키 차례가 한 번 정리된다
  (값은 같다). 그것을 읽는 그림 · 스프라이트 도구는 그대로 쓴다.
- GUI 도구는 외래키 검사를 꺼 둔 채 여는 경우가 있다. `status` · `apply` 가 다시 검사한다.
- `init --force` 는 DB 를 게임 파일에서 다시 짓는다. 승인 대기 변경과 기록이 사라진다.
- 내리는 도중 실패하면(예: `gen_roster.py` 오류) 쓴 파일을 전부 원래대로 돌려놓는다.

## 배포물에서 빼기

DB 는 만드는 쪽의 원본이라 폰에 싣지 않는다. 세 겹으로 막는다.

1. `data/.gdignore` — Godot 이 이 폴더를 보지 않는다.
2. `export_presets.cfg` 의 `exclude_filter` 에 `data/*` · `*.db` (Android · iOS 둘 다).
3. `tools/ci/check_no_db.py` — 구운 APK · IPA · PCK 를 열어 SQLite 파일이 있으면 실패.
   `tools/build_apk.sh` · `tools/ci/export.sh` · `tools/ci/build_ipa.sh` 가 부른다.

## DB 에 넣지 않은 것

| 무엇 | 까닭 |
|---|---|
| 화면 좌표 · 색 팔레트(`core/look.gd`) · 전장 좌표(`ROUTE_POINTS` 등) | 디자인 · 배치 영역이다 |
| `core/balance.gd` 밖의 코드 상수(전투 시뮬레이터의 조준 값 · 화면 연출 시간 · 광고 대기 시간 등) | 그 코드 한 곳에서만 쓰는 값이다. 표로 다루려면 `tools/gamedb.py` 의 `SPECS` 에 한 줄을 더한다 |
| `art/anim/*/anim.json` | 스프라이트 시트와 짝인 파이프라인 산출물이다 |
| 플레이어 저장 `user://save.cfg` | 폰에서 쓰는 파일이다 |
| 합성 수호자 이름 5개(`tools/gen_roster.py`) · 그림 높이표(`tools/gen_art.py`) | 도구 코드 안의 값이다 |
