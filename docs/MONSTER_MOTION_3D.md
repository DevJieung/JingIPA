# 몬스터 3D 모션 (대기·보행·회전·피격·사망·등장·수정 포위 공격)

2026-10-10 사용자 요청 "프로덕션 수준의 캐릭터 움직임"에 따라 25종 native 몬스터의 움직임을
재제작한 기준이다. 기하·UV·가중치·뼈 배치는 바꾸지 않았고, 클립 세트와 런타임 어댑터만 새로 만들었다.
데이터·판정·난수·저장은 건드리지 않는다. 월드 쪽 계약은 `game/3d/stellar_world.gd`(부모 소유)가 정한다.

## 파일

| 역할 | 경로 |
| --- | --- |
| 체형별 안무 라이브러리(Blender) | `tools/3d/monster_motion.py` |
| 클립 재작성 CLI(편집 원본 `game.blend` → GLB → provenance/manifest/specs) | `tools/3d/author_monster_motion.py` |
| 신규 몬스터 피니셔(같은 라이브러리로 클립 작성) | `tools/3d/finish_native_monster.py` |
| 모션 파라미터(체형 기본값 → 종류 보정 → 몬스터별 `motion` 블록) | `tools/3d/native_monster_specs.json` |
| 런타임 어댑터(샘플링·블렌드·반응 레이어) | `game/3d/native_monster_model.gd` |
| 런타임 파라미터(`motion` 행: cycle/death/spawn/hover/turn_rate/turn_max/bank) | `art/models/native_monsters.json` |
| 변형·루프 이음 검사(4클립) | `tools/3d/check_native_monster_deformation.py` |
| 계약 검사 | `tests/native_monster_check.gd` |
| 연속 프레임 촬영 | `tests/3d/native_monster_visual_preview.gd`, `tools/3d/native_monster_review.py` |

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
  사망 중 상태 고리 3종은 숨기고 `animate_visual`은 무시한다. 모두 월드 상한 1.6s 안에 끝난다.
- 리소스: 생성 뒤 노드·메시·재질을 만들지 않는다. 피벗은 GLB의 `CreatureRig` 노드다
  (루트 position/rotation.z는 월드가 쓴다).

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
