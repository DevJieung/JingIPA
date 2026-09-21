# 몬스터 모션과 초반 전투 조정

## 동작

- 전투·배치 화면의 `좌1`, `중1`, `우1` 같은 발판 글자를 제거한다. 배치 상세와 이동 알림에서도 위치 번호를 없앴다. 빈 발판의 + 표시와 클릭·드래그 영역은 유지한다.
- 초반 체력 보정을 `0.45 / 0.72`에서 `0.95 / 0.84`로 조정했다. 1~6탄 기준 기존보다 약 29~36% 높으며, 30탄부터 추가 영향은 1% 미만이다. 적 수·보상·공격 계산은 유지한다.
- 몬스터의 전체 그림을 기울이고 늘리던 `GAIT` 변형을 제거했다. 이동 클립은 시뮬레이터의 `motion_t`를 사용하며 종별 이동 속도·둔화·마비·배속을 따른다. 밀쳐내기는 클립을 역재생하지 않는다.
- 희귀도가 높을수록 탄 크기·잔광 길이·보조 빛줄기·불꽃·착탄 섬광을 단계적으로 늘린다. 기존 캐릭터별 Shot/Effect와 속성 색을 사용한다. 광선·연쇄·장판에도 등급 연출을 적용한다.
- 면역은 희귀 착탄 효과를 내지 않으며, 반감은 약한 효과를 낸다. 추가 장판 장식은 실제 피해 범위 안에 그린다. 공격력·충돌 반경은 바꾸지 않는다.

## 생성 파이프라인

25종의 기준은 `tools/roster.json`이다. 사람형은 팔을 벌린 기준 자세, 네 발 짐승은 네 다리가 드러나는 자세, 용·가오리는 날개나 지느러미를 펼친 자세를 쓴다.

1. `python3 tools/sprite/monster_motion.py concepts`: 로컬 Krea 2 Turbo, 1024×1024, 8 steps. 원화·프롬프트·시드는 `art/concepts/monsters/`에 남긴다.
2. Krea가 끝난 뒤 `python3 tools/sprite/monster_motion.py motion`: 로컬 Minimax H3, 768×768, 124프레임, 24fps, Turbo 4. 원본 프레임·MP4·입력·워크플로·생성 기록은 `build/monster-motion/<id>/`에 남긴다. 외형 변형을 줄이기 위해 첫/끝 프레임에 같은 원화를 고정하고, 마지막 복귀 구간은 게임 루프에서 제외한다. 초기 생성 중 검수에 통과한 일부는 첫 프레임만 고정한 클립이다. 실제 설정은 종별 `generation.json`과 워크플로에 기록한다.
3. `python3 tools/sprite/monster_post.py --watch`: 배경 제거, 몸통 위치 보정, 반복 가능한 순방향 구간 추출. 버섯 갓·꽃잎의 짙은 자주색과 석상 위의 분리된 수정도 보존한다. 일정한 배율로 내보내고 발을 복사하거나 시간 순서를 뒤집지 않는다. 최대 21프레임, 4032px 가로 시트로 모바일 4096px 텍스처 한도 안에 둔다. 개별 `selection.json`으로 검수 후 구간을 지정할 수 있다.
4. 게임 시트와 메타데이터는 `art/anim/monsters/<id>/`, 같은 디자인의 정지 미리보기는 `art/monsters/`에 쓴다. 생성 원본은 APK에서 제외한다.

`tools/gpu_guard.py`가 Krea와 H3의 동시 GPU 점유를 막는다. `--only id,id`로 일부만 재개할 수 있다.

검토 페이지: `build/monster-motion/index.html`. 각 종의 실제 게임 루프 WebP, 프레임 연락판, Krea 원화를 연결한다.

## 검증

- `tests/monster_check.tscn`: 다른 시작 박자, 이동·둔화·마비·밀쳐내기 시계, 면역/희귀 착탄 분기. `-- --assets`를 붙이면 25종 시트 로드와 루프 경계·비행 분류를 추가로 검사한다.
- `tools/verify.sh`: 저장·배치·피해·족보·화면 순환·자동 플레이·폰트·기존 영웅 시트 검사.
- `python3 tools/screenshot.py rarity map move shopf:14 swap:24 battle:30 --out build/monster-ui-review`: 실제 Godot 렌더링 비교.

같은 시드 24판의 첫 10탄을 기존/변경 체력으로 비교한 결과, 첫 탄 평균 시간은 13.57초→15.61초, 선두의 최대 진행도는 21.79%→27.15%였다. 초반 손실은 기존 0개에서 24판 합계 1개로 늘었다. 2~10탄은 이 표본에서 손실이 없었다. 이는 자동 플레이 표본이며 모든 플레이 방식의 난이도를 보장하지는 않는다.

최종 검증 결과:

- Krea 원화 25종과 Minimax 원본 영상 25종, 게임 루프 25종 모두 완료했다. 최종 루프는 12~21프레임이며 시트 PNG 합계는 7,321,676바이트다. 출처 해시·시트 치수·투명 배경·잘림·개별 시각 검수 기록은 `build/monster-motion/audit.json`에 있다.
- `tools/verify.sh quick` 전체 통과: 기존 영웅 시트, 저장·보상·배치·실제 피해·몬스터 모션·희귀 착탄·화면 순환·자동 플레이·폰트. 로그는 `build/monster-verify-final.log`다.
- 별도 전체 족보 2,598,960판과 엄격한 표 검사를 통과했다. 12개 시드 전체 밸런스 검사는 모든 속성의 출전 비중이 10%를 넘고 판정 정상이다. 로그는 `build/monster-poker-full.log`, `build/monster-ns-strict.log`, `build/monster-balance-full.log`다.
- 실제 Godot 렌더링 9장으로 전체 몬스터의 네 시점, 전투·배치 화면, 희귀도별 샷을 확인했다. 결과는 `build/monster-final-review/`, 로그는 `build/monster-final-render.log`다. Android 실기기 실행은 이 환경에서 검사하지 않았다.

APK 최종 경로는 항상 `/home/dgxmaruta/pokerdefense-test.apk`다. 성공한 새 빌드로만 교체한다.
