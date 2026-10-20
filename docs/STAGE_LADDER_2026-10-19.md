# 스테이지 사다리 — 웨이브 · 정비 시간 · 정예 · 보스 통과 (2026-10-19)

사용자 결정(2026-10-19, `build/feedback-2026-10-19/PLAN.md` U3·M4·M5·M6·M11): **스테이지별로 새로 시작하고
순서대로 연다.** 스테이지 하나는 10웨이브(5웨이브 정예, 10웨이브 보스, 웨이브 사이 정비 시간)이고 약 4분이다.
깨면 다음 스테이지가 열리며 모두 100 스테이지다. 속성은 섞어서 놓는다. 테스터 의견 O4(스테이지 3~5분) ·
O5(웨이브와 정비 시간, 5/10웨이브 강적) · O10(앞 스테이지를 깨면 다음 해금)과 버그 F4(수호자 몸으로 보스를
영원히 막음)를 함께 푼다. 이 문서는 규칙 · 수치 · 저장 · 검사를 적는다. 화면(웨이브 HUD · 스테이지 카드 · 결과 ·
스테이지 선택)은 디자인 쪽 문서를 따른다. 예전 10탄 연속 판은 [STAGE_RUN_2026-10-13.md](STAGE_RUN_2026-10-13.md)
에 기록으로 남는다.

## 한 스테이지의 흐름

전장 카드 → 무료 첫 상자 → **첫 정비**(`ARENA_PREP_FIRST`) → 1웨이브 → 방어 성공 → 정비(`ARENA_PREP_SEC`) → … →
5웨이브(정예) → … → 보스 앞 정비(`ARENA_PREP_BOSS`, 끝에 보스 예고) → 10웨이브(보스 + 호위) → 보스 처치 → 돌파 연출 →
**승리**. 정비 길이는 `Balance.arena_prep(w)` 한 곳이 정한다.

- **새로 시작**: 영웅 · 대기 · 골드 · 레벨 · 별자리 · 수정 · 기술 횟수가 스테이지마다 처음부터다
  (`ArenaRun.start_run`). 첫 상자는 언제나 무료다(`summon_count` 0). 끝나지 않은(깨지도 지지도 않은) 스테이지를 새로
  시작하면 같은 시드라 같은 첫 상자다(`Save.seed_for_stage`).
- **웨이브**: 웨이브 하나는 정해진 출현 목록(`ArenaRun.wave_spawns(stage, w)`)을 `arena_wave_gap` 간격으로
  하나씩 낸다. 웨이브는 **그 웨이브의 몬스터가 모두 쓰러져야** 끝난다(방어 성공). 방어 성공 때 골드
  (`arena_wave_bonus`)를 받고 수정이 조금 찬다(`ARENA_WAVE_HEAL` + 별자리 「되살아나는 수정」). 그 순간 판이
  자동 저장된다(실시간 간격 저장 `ArenaSim.AUTOSAVE_REAL` 과 별개).
- **정비 시간**: 아무것도 나오지 않는다. 카운트다운은 창(상자 · 레벨업 · 대기 · 메뉴 · 상점)이 열린 동안 멈추고,
  「바로 시작」(`ArenaSim.skip_prep()`)으로 끝낼 수 있다. **상자와 레벨업 노드 선택은 정비 시간에만 열린다** —
  웨이브 중에 오른 레벨은 쌓였다가 정비가 시작될 때 뜬다(레벨업 팝업이 전투 중에 떠 손가락이 그것을 누르던
  F1 의 뿌리). 막힌 까닭은 `ArenaRun.summon_block()`("modal" · "wave" · "pool" · "gold")이 준다.
  공용 기술의 쿨타임은 정비 중에도 돈다.
- **정예**(5의 배수 웨이브, 보스 웨이브 제외): 그 전장 주 속성의 **육중형**(땅 위)에 `elite` 표식이 붙는다.
  체력 x`ARENA_ELITE_HP`, 처치 골드 x`ARENA_ELITE_GOLD`, 처치 경험치 x`ARENA_ELITE_XP`. 웨이브 목록의 한가운데에
  끼고 `arena_elite` 이벤트가 난다. 생김새(크기 · 테두리 · 오라)는 `StellarModels.elite` 가 한다.
- **보스 웨이브**: 마지막 정비에서 남은 시간이 `ARENA_BOSS_WARNING` 이 되면 보스의 입구를 정하고 예고한다
  (`arena_boss_warning`). 웨이브가 열리면 보스가 맨 앞으로 그 입구에서 나오고, 호위 `ARENA_BOSS_ESCORT` 마리가
  뒤따른다. 사다리에서는 보스가 쓰러지면 남은 몸이 보상 없이 흩어지고, 수정이 조금 차고,
  `ARENA_CLEAR_DELAY` 의 돌파 연출(`arena_stage_clear`, `final: true`) 뒤에 스테이지가 이긴다.
- **챕터 보스**: 10의 배수 스테이지의 보스는 최종 보스 연출(보스 이벤트의 `final`)과 `ARENA_FINAL_BOSS_HP` 배수를 받는다.
- **「첫 격돌」**(패시브 `first`)은 웨이브마다 그 첫 `PASSIVE_FIRST_SEC` 초다. 스테이지의 첫 몇 초는 정비 시간이라서다.

## 보스 · 정예는 수호자에게 막히지 않는다 (F4 · M5)

- 보스와 정예는 공중 몬스터처럼 **도로만 보는 길**(`_road_nav`, `_road_segment_clear`)로 걷는다. 수호자의
  몸을 지나가지만 땅 위 목표라 모든 영웅이 때리고 장판도 맞는다. `mo.fly` 는 건드리지 않는다(대공 규칙).
- **교착 방지**: 일반 몬스터가 막힌 채 `ARENA_BLOCK_BREAK` 초 넘게 서 있으면(`mo.block_t`, 저장됨) 그 몸도
  지나간다. 한 번 넘어간 몸은 계속 지나간다(한 걸음 가고 다시 10초 서는 진동을 막는다). 마비 · 공성은 막힘이 아니다.
- 구현은 `ArenaSim._move_monsters` 의 `ghost` 한 줄이 네 곳(밀기 검사 · 막힘 검사 · 경로 계획 · 대체 걸음)에 쓰인다.
  C++(`StellarArenaNav.path_from(fly)`)과 `*_script` 참조 함수는 그대로라 네이티브 패리티가 유지된다.

## 사다리 (`ArenaRun.ladder_theme`, PLAN M11)

- 챕터 c = ceil(n/10) 은 험지 등급 ceil(c/2) 의 전장 10곳(생태 5 x 2)을 한 번씩 쓴다 — 생태 다섯을 두 바퀴,
  바퀴마다 섞은 차례다. **같은 생태가 연달아 나오지 않는다**(바퀴 · 챕터 경계 포함). STAGE 1~3(
  `ARENA_IMMUNE_STAGE` 앞)에는 면역 생태(바위 · 대지)의 전장이 없다.
- 순서는 코드의 고정 씨앗(`ArenaRun.LADDER_SEED`)으로 정한다. DB 열이 아니다. `Balance.MBODY_ORDER` 를
  바꾸면 순서가 바뀐다.
- 전장의 길은 그대로 `ArenaGeometry.layout_for_theme` 다. 판을 열 때마다 `_open_stage` 가 그 길을 고른다
  (타이틀은 기본 길로 되돌려 놓는다).
- **웨이브 구성은 스테이지마다 고정**이다(스테이지 · 웨이브 씨앗) — 다시 해도 같은 웨이브이고 입구 · 치명타 등은
  판마다 다르다. 끝없는 모드는 판 씨앗을 섞는다.
- **종 해금**(새 파티를 위한 일정): 모든 스테이지에서 1~2웨이브는 떼거리만, `ARENA_FAST_WAVE` 부터 쾌속,
  `ARENA_HEAVY_WAVE` 부터 육중 · 주술. 허용되지 않은 형은 같은 몸의 떼거리로 바뀌어 전장의 몸 비율이 지켜진다.
  `ARENA_FLY_STAGE` 전(STAGE 1)에는 공중 몬스터가 없고, `ARENA_IMMUNE_STAGE` 부터 면역 몸과 세 종 혼합,
  `ARENA_MIX_STAGE` 부터 네 종 혼합이다(`Balance.arena_kind_wave` · `arena_wave_kinds`).

## 해금 · 기록 (`core/save.gd`)

| 열쇠 | 뜻 |
|---|---|
| `[run] stage_unlocked` | 열린 가장 높은 스테이지(1부터). 깨면 다음 칸이 열린다 |
| `[run] stage_cleared` | 깬 가장 높은 스테이지(0 = 없음) |
| `[run] last_clear` | 직전에 깬 `{stage, theme}`(테마 id) — 타이틀의 「직전 클리어」 |
| `[hell] best_wave` · `squad` | Hellbound 최고 웨이브 · 마지막으로 고른 영웅(Hellbound 가 쓴다) |

- 모두 형을 보고 읽고, 없거나 깨졌으면 기본값이다. `_load_checked` 의 필수 키가 아니다(옛 파일도 그대로 읽힌다).
- 예전 `best_stage` · `clears` 는 해금으로 옮기지 않는다 — 모두 STAGE 1부터다. `clears` 는 스테이지를 이길 때마다
  오르고(`record_run`), `best_stage` 는 더는 갱신하지 않는다.
- `ArenaRun.end_run(won)` → `Save.record_stage(stage, theme_id, won)`(이기면 해금 · 최고 · 직전 클리어) →
  `Save.record_run`(평생 합계 · 파일).
- 시작: `start_run(seed, stage_no)` — `stage_no` 0 이면 다음 해금 스테이지. 잠긴 스테이지도 열린다(도구 · 봇).
  화면은 `can_play(n)` 으로 거른다. `retry()` 는 같은 스테이지, `next_stage()` 는 깬 뒤 다음 스테이지.
- 검사는 STELLARDEFENSE_NO_SAVE=1 에서도 개발자의 실제 저장을 읽으므로, `Harness.require_no_save()` 가 사다리
  기록을 STAGE 1 로 되돌린다.

## 수치 (`core/balance.gd`, DB tuning — 2026-10-19 LA4 봇 실측으로 맞춘 값, 아래 「실측」)

| 값 | 지금 | 뜻 |
|---|---|---|
| `ARENA_LADDER` · `ARENA_WAVES` · `ARENA_ELITE_EVERY` | 100 · 10 · 5 | 스테이지 수 · 웨이브 수 · 정예 간격 |
| `ARENA_PREP_FIRST` · `ARENA_PREP_SEC` · `ARENA_PREP_BOSS` | 6.0 · 6.0 · 8.0 | 첫 정비 · 웨이브 사이 정비 · 보스 웨이브 앞 정비(초, 끝 4초가 예고) |
| `ARENA_ROAD_PACE` | 1600 | 긴 길 걸음 보정: 가장 긴 길 / 1600 배 빨리 걷는다(코일 1.86 · 나선 · 갈래 1.44 · 바람개비 1.02 · 칼날 1). `PATH_SPEED` 는 그대로 |
| `ARENA_WAVE_SIZE` · `_STEP` | 4 · 0.6 | 웨이브의 일반 몬스터 수(1~9웨이브 4·5·5·6·6·7·8·8·9) |
| `ARENA_WAVE_GAP` · `_MIN` | 0.7 · 0.35 | 웨이브 안 출현 간격(1웨이브 → 마지막 웨이브) |
| `ARENA_WAVE_HP_STEP` | 0.12 | 웨이브마다 체력 +12%(10웨이브 2.08배) |
| `ARENA_LADDER_HP_FROM` · `_POW` | 8.0 · 0.57 | 사다리 경사 (STAGE / 8)^0.57, STAGE 8 까지 1(10 → 1.14 · 25 → 1.91 · 50 → 2.84 · 100 → 4.22배). 옛 `ARENA_LADDER_HP_GROW`(1.010 지수)는 없앴다 |
| `ARENA_ELITE_HP` · `_GOLD` · `_XP` | 2.5 · 5.0 · 5.0 | 정예 배수 |
| `ARENA_WAVE_BONUS` · `_STEP` | 10 · 2 | 방어 성공 골드(1~9웨이브 합 180) |
| `ARENA_WAVE_HEAL` | 0.03 | 방어 성공 때 수정 회복 |
| `ARENA_BOSS_ESCORT` · `ARENA_LADDER_BOSS_HP` | 6 · 0.5 | 보스 호위 수 · 보스 체력 배수(STAGE 1 보스 1,183) |
| `ARENA_BLOCK_BREAK` | 10.0 | 교착 방지(초) |
| `ARENA_LADDER_GOLD` · `_STEP` | 3.0 · 0.0 | 처치 골드 밑값(평평한 경제) |
| `ARENA_LADDER_XP` · `_STEP` | 1.2 · 0.0 | 처치 경험치 배수(9웨이브까지 레벨 약 7) |
| `ARENA_FAST_WAVE` · `ARENA_HEAVY_WAVE` | 3 · 5 | 종 해금 웨이브 |
| `ARENA_FLY_STAGE` · `ARENA_IMMUNE_STAGE` · `ARENA_MIX_STAGE` | 2 · 4 · 41 | 공중 · 면역 몸(세 종) · 네 종 혼합이 시작되는 스테이지 |

- 체력: `arena_hp(stage, rank, wave) = wave_hp(1, rank) x ARENA_HP_SCALE x arena_ladder_hp(stage) x (1 + 0.12 x (wave-1))`,
  `arena_ladder_hp(stage) = max(1, (stage / ARENA_LADDER_HP_FROM)^ARENA_LADDER_HP_POW)`.
  정예 `arena_elite_hp`, 보스 `arena_ladder_boss_hp`(챕터 보스는 `ARENA_FINAL_BOSS_HP` 곱).
- 경제: 한 스테이지의 10웨이브 전까지 시작 60 + 처치 약 210 + 방어 성공 180 ≈ 450 G — 지금 값으로 유료 상자 약 5개.
  스테이지마다 새로 시작하므로 사다리 끝까지 같다(`tests/arena_check` 가 ±20% 로 본다).
- 예전 연속 판의 값(`ARENA_BOSS_AT` · `ARENA_STAGES` · `ARENA_STAGE_*` · `ARENA_SPAWN_*` · `ARENA_POPULATION_START`)은
  지우지 않고 쓰지 않는다. `ARENA_POPULATION_MAX` 는 끝없는 모드의 웨이브 크기 상한으로 남는다.

## 실측 (2026-10-19 LA4, `tests/arena_balance_check`)

봇은 보통 사람보다 조금 못한 사람이다: 정비 중 살 수 있는 상자를 사고(4웨이브부터 스킬 하나 값은 남김) 무료 다시 뽑기로
상자 등급 +1 을 노린다, 대공이 없는데 공중 몬스터가 오면 대공 카드, 아니면 별 많은 카드. 레벨업은 고정 목록(공격 · 속도 ·
치명). 웨이브 중에는 별빛 폭발을 몰린 곳 · 아무도 못 때리는 몸(면역 · 대공 없는 공중) · 정예 · 보스에 누른 자리로,
서리는 수정이 위협받을 때, 방벽은 보스가 수정을 칠 때 쓴다(급하지 않으면 상자 반 개 값은 남김). 영웅은 길이 광장에 닿는
자리에 서고 놀고 있으면 수정에 가까운 몬스터 쪽으로 걷는다 — 길 중간에서 막는 사람보다 웨이브가 길다(시간은 위쪽 추정).
정비는 바로 넘기고(전투 결과는 같다) 표의 「스테이지 시간」은 정비를 다 기다린 시간(첫 6 + 6 x 8 + 보스 앞 8초)을
더한 값, 「창 포함」은 전장 카드 3초 · 노드 3초 · 상자(연출 실측 2.7초, 다시 뽑기마다 1.6초, 최대 7.5초)를 더 얹은 값이다.
판마다 시드가 같으면 결과도 같다.

```
godot --headless --path . res://tests/arena_balance_check.tscn -- --runs 24 --stages 1,2,3,5,10,15,20,25,30,35,40,45,50,55,60,70,80,90,95,100 --report
  --dlc (부활권 · 무료 다시 뽑기 3) · --uses 1 (ARENA_REVIVE_USES 가 1이라면) · --speed 1.2 (몬스터가 1.2배 빠르다면)
  --blast-r 160 (ARENA_BLAST_RADIUS 가 160이라면) · --hell 3|4 --max-wave 120 (Hellbound) · --rows (병합용 한 줄 JSON)
```

「LA3 값」은 체력 1.010 지수 · 정비 8/6 · 출현 1.0/0.5, 「1차」는 LA4 첫 값(멱 0.60 · 정비 6/4/7 · 길 보정 없음),
「지금」은 길 보정(1600) · 정비 6/6/8 · 멱 0.57 이다(판마다 24판, DLC 없음, 같은 봇).

| STAGE | 길 | 승률 LA3 값 → 1차 → 지금 | 지금 DLC(부활 3 · 1) | 스테이지 시간 1차 → 지금 | 창 포함(지금) | 상자 · 스킬 골드(지금, 이긴 판) |
|---|---|---|---|---|---|---|
| 1 | 바람개비 | 100 → 100 → **96%** | 100 · 100% | 3:55 → 3:56 | 4:47 | 5.6 · 65 G |
| 2 | 바람개비 | 96 → 96 → **96%** | 100 · 100% | 3:40 → 3:55 | 4:47 | 5.4 · 91 G |
| 3 | 갈래 | 100 → 100 → **100%** | 100 · 100% | 3:22 → 3:16 | 4:03 | 5.5 · 88 G |
| 5 | 갈래 | 96 → 96 → **88%** | 96 · 88% | 3:28 → 3:19 | 4:07 | 5.2 · 103 G |
| 10 | 코일 | 100 → 100 → **100%** | 100 · 96% | 4:43 → 3:52 | 4:41 | 5.0 · 127 G |
| 15 | 바람개비 | 100 → 100 → **100%** | 100 · 100% | 4:22 → 4:25 | 5:12 | 5.1 · 116 G |
| 20 | 코일 | 100 → 100 → **100%** | 100 · 100% | 4:44 → 4:03 | 4:53 | 5.4 · 90 G |
| 25 | 코일 | 96 → 75 → **75%** | 96 · 79% | 5:07 → 4:00 | 4:47 | 5.1 · 106 G |
| 30 | 나선 | 100 → 83 → **67%** | 100 · 92% | 5:35 → 4:30 | 5:10 | 5.4 · 107 G |
| 35 | 갈래 | 100 → 83 → **67%** | 100 · 100% | 4:27 → 3:47 | 4:30 | 5.2 · 124 G |
| 40 | 바람개비 | 88 → 71 → **62%** | 100 · 96% | 4:55 → 4:31 | 5:14 | 5.2 · 133 G |
| 45 | 나선 | 88 → 67 → **46%** | 96 · 71% | 5:25 → 3:28 | 4:16 | 5.3 · 122 G |
| 50 | 코일 | 100 → 54 → **42%** | 79 · 58% | 7:26 → 4:43 | 5:17 | 5.1 · 157 G |
| 55 | 칼날 | 75 → 8 → **29%** | 88 · 54% | 3:25 → 3:24 | 4:02 | 5.1 · 126 G |
| 60 | 나선 | 79 → 50 → **33%** | 100 · 71% | 5:30 → 4:50 | 5:24 | 5.1 · 131 G |
| 70 | 나선 | 88 → 50 → **46%** | 100 · 96% | 5:23 → 4:27 | 5:02 | 5.1 · 135 G |
| 80 | 갈래 | 83 → 38 → **29%** | 100 · 83% | 5:08 → 3:34 | 3:58 | 4.7 · 174 G |
| 90 | 나선 | 75 → 33 → **29%** | 100 · 96% | 3:55 → 3:34 | 4:01 | 4.9 · 154 G |
| 95 | 바람개비 | 50 → 12 → **21%** | 100 · 79% | 3:19 → 3:20 | 3:41 | 4.6 · 176 G |
| 100 | 나선 | 67 → 29 → **17%** | 100 · 96% | 4:06 → 3:02 | 3:21 | 5.2 · 125 G |

| 구간 | 목표 | LA3 값 | 1차(LA4) | 지금 | 지금 DLC(부활 3 · 1) |
|---|---|---|---|---|---|
| 1~10 | ≥ 90% | 98% | 98% | **96%** | 99 · 97% |
| 20~30 | 약 70~80% | 99% | 86% | **81%** | 99 · 90% |
| 45~55 | 약 40~60% | 88% | 43% | **39%** | 88 · 61% |
| 90~100 | 약 10~25% | 64% | 25% | **22%** | 100 · 90% |

이긴 판의 스테이지 시간(전투 + 정비 전부, 1배속) 중앙값: 1차 4:36 → 지금 4:05, 긴 길(코일 · 나선) 5:27 → 4:22. 창 포함(지금, 상자 2.7~7.5초 모형) 4:55, 긴 길 5:06. 이긴 판의 상자 5.2개 · 스킬 골드 112 G.

- 길 모양이 난이도를 크게 가른다: 칼날(짧은 길 넷)은 몬스터가 네 쪽에서 곧장 와서 가장 어렵고(STAGE 55 29%), 코일
  (길 하나)은 걸음 보정 전에는 막기 쉽고 길었다(STAGE 50 7분 26초 → 4분 43초).
- 걷는 시간이 웨이브 길이의 바닥이다: 떼거리(PATH_SPEED 82)가 광장 앞까지 걷는 데 보정 전 칼날 10초 · 바람개비 18초 ·
  나선 · 갈래의 긴 길 26초 · 코일 34초 → 보정 후 긴 길 모두 약 18초.
- DLC 의 부활권은 부활마다 5성 영웅을 데려와 사다리를 거의 지지 않게 만든다(부활 3회 98%, 1회여도 88%).
- `--blast-r 160`(폭발 반경 110 → 160 제안)은 전체 승률을 약 2%p 올린다(1차 값에서).

### Hellbound (봇, DLC, 스쿼드 limne · chispa · lind · brigid · pip · phorkys)

| 스쿼드 | LA3 값(체력 x2.0 고정 · 방어 성공 골드가 웨이브 번호대로) | 지금(x3.0, 웨이브마다 x1.10 · 골드는 묶음 안 자리 · 10웨이브마다 기술 횟수 다시 참) — 부활 3 · 1회 |
|---|---|---|
| 4성 위주(4성 4 · 3성 1 · 5성 1) | 80웨이브 상한까지 수정 피해 0 | 도달 웨이브 중앙값 32 (25~38) · 28 (16~35) |
| 3성 위주(3성 4 · 2성 1 · 4성 1) | 80웨이브 상한까지 | 27 (14~30) · 22 (10~27) |

## 공통 스킬 — 골드 · 판정 · 조준 (F5 · PLAN M7 · M8)

- 쓸 때마다 고정 골드: 별빛 폭발 `ARENA_BLAST_GOLD`(30) · 서리 파동 `ARENA_FREEZE_GOLD`(40) · 수정 방벽
  `ARENA_WARD_GOLD`(50). 별자리 효과 열쇠 `skill_gold`(곱, 지금 파는 노드는 없음)가 깎는다(`ArenaSim.skill_cost`).
  골드는 효과가 난 **뒤에 한 번** 빠지고 판이 저장된다. 거절된 사용은 아무것도 쓰지 않는다.
- 판정은 `ArenaSim.skill_state(id)` 한 곳이다. `cast_skill` 은 이것으로만 정하고, HUD 는 이것으로 「준비 완료」 ·
  비용 · 막힌 까닭을 그린다. 돌려주는 것: `block` · `ready` · `cost` · `cooldown` · `max_cooldown` · `uses_left` · `uses_max`.
  `block` 의 차례 — `inactive`(판이 끝났거나 안 돌거나 창이 열림) → `prep`(정비 중: 대상도 피해도 없어 골드를 아낀다) →
  `clearing`(돌파 연출) → `cooldown` → `spent`(스테이지당 횟수를 다 씀) → `no_target`(폭발 · 서리인데 몬스터가 없음) →
  `gold`. 빈 글자면 쓸 수 있다.
- 별빛 폭발은 `cast_skill("blast", at)` 의 `at`(누른 곳)에 떨어진다. 판 밖(`ArenaGeometry.contains` 거짓)은 거절한다.
  반경 `blast_radius()` = `ARENA_BLAST_RADIUS` x 별자리 `blast_r` 이고, 몸 가장자리가 반경에 닿는 몬스터(거리 ≤ 반경 +
  몸 반경)를 모두 때린다. `at` 을 주지 않으면(`Vector2.INF`) 수정에 가장 가까운 몬스터에 떨어진다(자동 플레이 · 검사).
  서리 · 방벽은 `at` 을 보지 않는다.

## 부활권 (DLC, D2)

- DLC(`Store.GUARDIAN`, `ArenaRun.dlc()`)가 있으면 스테이지마다 `ARENA_REVIVE_USES` 번, 소울 스톤이 깨지는 순간
  `ARENA_REVIVE_HP` 로 되살아나 `ARENA_REVIVE_INVULN` 초 무적, 충격파로 몬스터 `ARENA_REVIVE_STUN` 초 정지.
- **골드는 주지 않는다.** 대신 5성(`TIER_MAX`) 영웅 하나가 합류한다(`ArenaRun.grant_revive_hero`): 판의 시드와
  스테이지로 정한 후보(`revive_candidate()` — 전장 카드 동안 모델을 미리 불러 둘 수 있다)가 판에 없으면 그 영웅,
  있으면 판의 rng 로 판에 없는 다른 영웅. 자리가 있으면 필드, 없으면 벤치. 모두 와 있으면 5성 아래 가장 낮은
  영웅이 5성이 되고, 모두 5성이면 아무도 오지 않는다. 도감 · 최고 등급에 센다. 결과는 `revive_gift`
  `{unit, tier, where, slot}`(저장된다).
- 틱 안에서 깨지면(몬스터 이동 중) 영웅은 그 틱이 끝난 뒤 합류한다(`_flush_revive`) — 날아가던 탄과 출처 번호를
  틱 한가운데서 바꾸지 않는다. 틱 밖(패배 화면에서 산 직후 `revive_from_defeat`, 검사)이면 바로 온다.
- `ARENA_REVIVE_GOLD` · `ARENA_REVIVE_GOLD_STEP` · `arena_revive_gold` 는 지우지 않고 쓰지 않는다.

## Hellbound (DLC 끝없는 모드, D3 · U4 · M10)

- 열림: `ArenaRun.can_hellbound()` = DLC 가 있고 도감에 만난 영웅이 있음.
- 고르기: `ArenaRun.hellbound_pool()` = 도감(`Save.seen_units`)의 영웅을 표 차례로 `{unit, tier}`. 등급은 그 영웅의
  최고 등급(`Save.best_of`; 기록이 없으면 1성 `JewelBox.tier_of(1)`).
- 시작: `start_hellbound(ids, seed := 0)` — 겹치지 않는 1..`ARENA_HELL_SQUAD`(6) id. 틀리면 거짓이고 아무것도 바뀌지
  않는다. 전장은 시드로 고른 4~5등급 하나, 스쿼드가 최고 등급으로 판에 서고 **무료 첫 상자는 없다**(`summon_count` 1 —
  전장 카드 다음은 바로 첫 정비). 보석상자 · 별자리 · 스킬 · 부활권은 스테이지와 같다. `stage` 는
  `ARENA_HELL_BASE_STAGE`(60)로 둔다(골드 · 경험치 표의 자리).
- 웨이브: `waves_total()` 0 — 마지막 웨이브가 없고 10의 배수가 보스, 그 밖의 5의 배수가 정예, 보스가 쓰러져도 판이
  이어진다(호위까지 잡으면 보통의 방어 성공). 체력은 웨이브 w 를 사다리 `arena_hell_stage(w)` = 60 + 2 x (w-1) 탄으로,
  웨이브 안 상승은 `arena_hell_ramp_wave(w)`(10웨이브마다 1부터 다시)로 보고 `arena_hell_hp(w)` = `ARENA_HELL_HP`(3.0) x
  `ARENA_HELL_HP_GROW`(1.10)^(w-1)를 곱한다 — 상자 · 별자리가 쌓여 파티가 계속 커지므로 웨이브마다 곱으로 오른다.
  공용 기술의 스테이지당 횟수는 10웨이브 묶음(보스 웨이브)을 막을 때마다 다시 찬다(`arena_skill_refill` 이벤트). 수
  (상한 `ARENA_POPULATION_MAX - 2`) · 종 혼합도 웨이브 번호로 오른다. 방어 성공 골드는 묶음 안 자리(`arena_hell_ramp_wave`)로
  준다(번호대로면 끝없이 불어난다).
- 끝: 소울 스톤이 부서지면(부활권을 다 쓴 뒤) 패배. 기록은 `Save.hell_best_wave`(닿은 최고 웨이브 — 웨이브를 막을 때마다와
  패배 때 쓴다, 정비 중이면 막은 웨이브, `ArenaSim.wave_reached()`)와 `Save.hell_squad`(마지막에 고른 id). 사다리 해금 · 직전 클리어 · 최고
  스테이지(`best_wave`)는 건드리지 않고 처치 수만 평생 기록에 더한다. `retry()` 는 같은 스쿼드로 새 판,
  `next_stage()` 는 없다. `stage_preview` 는 `hell: true` · `final: false`.

## 이벤트 (시각 쪽이 받는다)

| `t` | 내용 |
|---|---|
| `arena_wave` | `wave` · `total`(0 = 끝없음) · `elite` · `boss`. 웨이브가 열림 |
| `arena_wave_clear` | `wave` · `gold`(방어 성공 골드) · `prep`(다음 정비 초) · `heal`(찬 수정) |
| `arena_elite` | `p` · `sid`. 정예가 나옴 |
| `arena_boss_warning` · `arena_boss` | 예전과 같고 `final` 은 챕터 보스 |
| `arena_stage_clear` | 예전과 같다. 사다리에서는 언제나 `final: true`(그 뒤 승리) |
| `arena_heal` | 방어 성공 회복(`heal_crystal`) |
| `arena_blast` · `arena_freeze` · `arena_ward` | `p`(폭발은 떨어진 곳) · `r`(폭발은 별자리까지 곱한 반경) · `cost`(쓴 골드) |
| `arena_revive` | `p` · `r` · `sec` · `stun` · `left` 에 더해 `unit`(id, 아무도 안 오면 "") · `tier`(-1) · `where`("field" · "bench"). `gold` 없음 |
| `arena_skill_refill` | `p` · `wave`. Hellbound 의 10웨이브 묶음을 막아 공용 기술 횟수가 다시 참 |

## 저장 (`ArenaValidation.SAVE_V` 5)

- 판: `stage` 1..`ARENA_LADDER`, `theme_index` 는 유효한 번호이기만 하면 된다(도구가 고를 수 있다). `themes` 배열은 없다.
- sim: `wave_no` · `in_prep` · `prep_t`(가장 긴 정비 이하) · `wave_t` · `wave_spawned`(정비 중이면 0). `spawn_t` 는 목록을 다
  내보내면 마지막 간격에서 멈춘다(LA4 전에는 0 아래로 내려가 그때의 저장이 검사에 걸렸다 — 그런 저장도 받아 준다). 웨이브 목록은 저장하지 않는다 —
  복구할 때 `wave_spawns` 가 같은 목록을 다시 낸다. 몬스터: 선택 키 `elite`(bool) · `block_t`(≥0).
- **튜닝 값에 묶인 수는 고정된 큰 상한으로만 본다**(2026-10-19 교차 점검): 스테이지 · 웨이브 · 나온 수 · 정비 시간 ·
  부활 횟수 · 카드 수 · 스쿼드 수 · 성장 포인트 · 노드 · 강화 단계 · 수명. DB 값이 바뀌어도 하던 판이 무효가 되지 않고,
  복구가 지금의 상한으로 맞춘다(`ArenaRun.restore` · `ArenaSim.restore_arena`). 그래도 검사에 걸리는 판은
  `Save._load_checked` 가 **그 판만 버리고** 평생 기록 · 해금 · 도감 · Hellbound 기록 · 설정은 지킨다(전에는 파일째 거부해
  백업도 같은 판으로 걸리면 기본값이 저장되어 기록이 지워졌다).
- 끝나지 않은 스테이지의 시드: `Save.stage_seeds`(`[run] stage_seeds`, {스테이지: 시드}). `start_run(0, n)` 은 그 시드로
  열고(같은 무료 첫 상자), 깨거나 지면(`end_run`) 지운다.
- **판 4(웨이브 이전) 저장은 이어 할 수 없다.** 하던 판만 버리고 평생 기록과 설정은 남는다(`ArenaValidation.outdated`).
  이후 단계의 새 키는 판 5 안의 선택 키로 더한다.
- 판 5 의 선택 키(LA3): `hell`(bool) · `squad`(아는 id, 겹침 없이 `ARENA_HELL_SQUAD` 이하, Hellbound 면 비지 않음) ·
  `revive_gift` `{u, t, where, slot}`(판에 있는 영웅 · 0..`TIER_MAX` · field/bench · slot ≥ 0). `mode` 는 그대로 `"arena"`.

## 검사 · 도우미

- `tests/arena_wave_check`(새로 만듦: 웨이브 흐름 · 정예 · 보스 · 정비 관문 · 보스/정예 통과 · 교착 방지 · 웨이브 저장 ·
  사다리 · 끝없는 모드), `tests/arena_check`(스테이지 한 판 · 보스 · 웨이브 시계 · 사다리 곡선 · 경제).
  두 검사 모두 `tools/verify.sh` 4-2 와 CI(`tools/ci/export.sh`)에 등록되어 있다.
- `tests/arena_skill_check`(공통 스킬의 골드 · `skill_state` 차례 · 거절은 아무것도 안 씀 · 조준 폭발 · 저장),
  `tests/hellbound_check`(DLC 관문 · 도감 스쿼드 · 무료 상자 없음 · 끝없는 웨이브와 체력 · 저장 · 다시 하기 · 기록),
  `tests/store_check` 의 부활 절(골드 없음 · 5성 영웅 · 필드/벤치 · 모두 와 있을 때 · 저장 · 패배 화면 구매)도 같은 곳에 있다.
- 도우미: `ArenaSim.begin_wave(n)`(n 웨이브를 지금 엶) · `jump_to_boss()`(보스 웨이브 정비의 끝 — 예전
  `elapsed = ARENA_BOSS_AT - 0.02` 자리) · `skip_prep()`. `_spawn_t = 1e9` 는 여전히 출현을 멈춘다.
- 옛 이름 호환(미리보기 · 벤치만): `ArenaRun.stage_themes`(이 판의 사다리 사본) · `stage_spawns` · `advance_stage`.
  새 코드는 `choose_theme` · `wave_spawns` · `next_stage` 를 쓴다.
