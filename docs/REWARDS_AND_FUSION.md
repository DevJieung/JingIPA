# 전투, 영웅 합성, 보상형 광고

## 현재 규칙

- 모든 영웅은 자신에게 가장 가까운 살아 있는 적을 먼저 공격한다. 장판도 그 적의 위치에 생성된다.
- 공격 장판의 점선 테두리와 시전자 주변의 장식 원을 제거했다. 실제 피해 위치에 부드러운 속성색과 캐릭터 효과 애니메이션을 표시한다.
- 발판 12곳을 모두 사용한다. 같은 캐릭터는 전장에 1명만 출전할 수 있다.
- 중복 영웅은 별도 카드로 전당에 보관한다. 공격력이나 발사 횟수는 중첩되지 않는다.
- 기존 저장 파일의 중첩 수량은 개별 영웅 카드로 복구한다.
- 배치 지도에는 캐릭터와 이름을 표시한다. 전당 카드에는 모습, 이름, 속성, 등급을 표시하며 전투 능력치는 영웅 정보에서 확인한다.
- 전장 영웅을 먼저 선택하고 전당 카드를 누르면 둘의 자리를 교환한다. 반대 순서도 가능하며 같은 캐릭터의 중복 출전은 허용하지 않는다.
- 무작위 카드 교체는 현재 손패 5장을 제외한 47장 전체에서 균등하게 뽑는다. 칸마다 고정된 더미를 사용하지 않는다.
- 무료 횟수를 소진하고 골드가 부족하면 무작위 교체 버튼이 비활성화되며, 현재 패로 족보를 확정할 수 있다.
- 카드마다 「원하는 카드」를 눌러 무늬·숫자를 직접 선택하고 「광고 보고 교체」로 시청을 완료하면 그 카드로 교체한다. 족보 확정 전에 무료 횟수·골드와 무관하게 사용할 수 있다.
- 직접 선택에서는 현재 손패 5장을 제외한 47장만 선택할 수 있다. 선택·취소만으로 손패는 바뀌지 않으며 시청 완료 보상으로만 바뀐다. 골드를 소모하지 않고 교체 횟수만 1 증가하며 유료 교체 가격은 유지한다.
- 카드 선택창은 무늬 탭 없이 4무늬 × 13장을 한 화면에 표시한다. 현재 손패·족보와 교체 후 손패·족보를 함께 비교한다.

## 5장 합성

배치 화면과 대기실의 영웅 합성에서 사용할 수 있다.
전당에서 대기 중인 카드 5장을 직접 고르면 정확히 5장을 소모하고 영웅 1장을 받는다.
전장에 등록된 출전 카드는 합성 재료로 선택하거나 소모할 수 없다. 합성 실행 단계에서도
출전 카드가 하나라도 포함된 요청은 전체를 거절하고 보유 카드와 배치를 그대로 유지한다.
합성 목록에는 전당에서 대기 중인 카드만 표시한다. 별 오름차순, 같은 별에서는
물·불·얼음·전기·무상성 순으로 정렬하며 같은 캐릭터의 복사본도 개별 선택한다.
출전 카드는 목록에서 제외한다. 원래 배치 순서는 바꾸지 않는다.

누적 희귀도는 각 재료의 등급(1~10)을 더한 값이다.
Balance.fusion_probabilities가 실제 추첨 확률을 계산한다.
누적값이 커질수록 각 상위 등급에 도달할 확률이 증가한다. 화면의 확률 설명 박스는 제거했다.

합성 결과의 등급과 관계없이 「영웅 받기」로 결과 영웅 1장을 확정하거나,
「재료 되돌리기」에서 광고 시청을 완료해 결과 영웅을 회수하고 재료 5장과 배치 위치를 복구할 수 있다.
원복 후 다시 합성해도 횟수 제한 없이 새 광고를 완료할 때마다 원복할 수 있다.
각 합성은 새 광고 시청 완료가 필요하며, 이미 받은 결과나 이전 광고의 중복 보상으로는 원복할 수 없다.
결과를 받기 전까지 다른 합성과 영웅 이동을 잠가 중복 소비나 중복 환불을 방지한다.

잔향 패시브는 중복 영웅을 얻을 때 합성 재료 카드 1장을 추가한다. 합성 결과에는 적용하지 않는다.

## 대기실과 누적 전과

- 새 영웅을 얻은 뒤에는 아무 카드도 자동 선택하지 않는다. 신규 표시만 유지한다.
- 전장 영웅을 전당으로 돌려보내면 선택을 해제한다.
- `Run.owned_passives`는 전체 보유, `Run.passives`는 활성 최대 3개다. 구매 시 빈 활성 칸을 채우고, 가득 차면 보유만 추가한다. 활성 전환은 무료이며 판매·차액 거래는 허용하지 않는다.
- 모든 패시브 가격을 50% 인상했다(소수 골드는 올림). 카드 무료 교체 횟수 강화는 기본 100G, 비용 증가 계수 1.65다.
- 이전 저장의 활성 패시브는 보유 목록으로도 이관한다. 신규 저장에는 보유/활성 상태를 따로 저장한다.
- 크리스탈 탭과 대기실 회복 광고를 제거했다. 게임 종료의 광고 부활은 유지한다.
- Best Player는 이번 런에서 캐릭터별로 누적한 실제 피해 1위다. 과잉 피해는 제외하고 전당 이동·합성 후에도 기록을 유지한다. 부활 시 재시작하는 탄의 피해는 체크포인트와 함께 되돌린다.
- 누적 피해 필드가 없는 이전 저장은 0부터 기록한다. 이전 전투의 수치를 추정하지 않는다.
- 타이틀의 만난 영웅 도감은 기존 `Save.seen_units`에서 발견한 영웅만 속성별, 높은 등급순으로 보여 준다. 언어는 공통 상단 버튼에서 전환한다.

## 보상형 광고

Poing Studios AdMob v5.0.0과 Godot 4.7.1용 Android 라이브러리를 포함했다.
`tools/build_apk.sh`가 프로젝트 루트 `.env`의 AdMob ID를 읽어 APK에 반영한다.
저장소의 `project.godot` 기본값은 Google 테스트 광고이며, 빌드할 때만 아래 실제 ID를 주입한다.

| 위치 | 보상 |
| --- | --- |
| 카드 뽑기 → 원하는 카드 → 광고 보고 교체 | 지정한 칸을 직접 선택한 무늬·숫자의 카드로 교체 |
| 합성 실패 결과 창 | 결과 취소 및 재료 5장 복구 |
| 게임 종료 화면 | 크리스탈 전체 복구, 무작위 최고 10등급 영웅 지원, 같은 탄 재도전 |

게임 종료 재도전은 한 판에 한 번이다. 실패한 탄의 골드·처치 수·누적 피해는 탄 시작 시점으로 되돌린다.
지원 영웅은 빈 전장 자리가 있어도 전당에 보관하며 기존 출전 영웅과 발판을 유지한다.
최고 등급 영웅의 원화·이름·등급을 획득 연출로 보여 주고, 사용자가 확인한 뒤 직접 배치한다.
확인 전 앱을 종료하면 다음 이어하기에서 획득 화면을 다시 보여 주며 보상은 중복 지급하지 않는다.

SDK의 시청 완료 콜백으로만 보상을 지급한다.
광고 로드 실패, 표시 실패, 시청 미완료, 취소에는 보상을 지급하지 않는다.
중복 콜백과 다른 탄 또는 다른 판의 오래된 요청도 거절한다.
광고를 준비하거나 시청하는 동안 게임 입력과 전투를 잠근다.
데스크톱에서는 가짜 광고 보상을 주지 않고 Android 앱에서 이용하도록 안내한다.

### `.env` → 앱 설정 → 광고 위치

| 환경 변수 | Godot 설정 | 사용 위치 / 요청 종류 |
| --- | --- | --- |
| `ADMOB_APP_ID` | `admob/general/android/app_id` | AndroidManifest.xml의 `com.google.android.gms.ads.APPLICATION_ID` |
| `ADMOB_REWARD_CARD_CHANGE_ID` | `rewards/android/card_change_unit_id` | 원하는 카드 직접 선택 → 광고 보고 교체 (`card`) |
| `ADMOB_REWARD_MERGE_RESTORE_ID` | `rewards/android/merge_restore_unit_id` | 모든 미확정 합성 결과 → 재료 복구 (`fusion_undo`) |
| `ADMOB_REWARD_REVIVE_ID` | `rewards/android/revive_unit_id` | 게임 종료 → 부활·재도전 (`continue`) |
| `ADMOB_REWARD_CRYSTAL_ID` (선택) | `rewards/android/crystal_unit_id` | 이전 회복 API 호환용. 현재 화면에서는 요청하지 않음 |
| `ADMOB_TEST_DEVICE_IDS` (선택) | `rewards/android/test_device_ids` | 디버그 APK의 SDK 테스트 기기 등록. 쉼표로 구분한 32자리 기기 ID |

`ADMOB_APP_ID`는 `ca-app-pub-숫자16자리~숫자10자리`, 광고 단위 ID는 `ca-app-pub-숫자16자리/숫자10자리` 형식이다.
필수 네 값의 누락·잘못된 형식·중복 키는 빌드를 중단한다. 테스트 ID로 조용히 대체하지 않는다.

카드 교체는 `RewardedAdLoader`(일반 보상형), 합성 복구와 부활은 `RewardedInterstitialAdLoader`(보상형 전면광고)를 사용한다. 광고 단위의 콘솔 형식과 로더가 일치해야 한다. Google 테스트 ID도 각 형식에 맞춰 분리했다. [Google 보상형 전면광고 문서](https://developers.google.com/admob/android/rewarded-interstitial)

선택 환경 변수 `ADMOB_REWARD_CARD_CHANGE_FORMAT`, `ADMOB_REWARD_MERGE_RESTORE_FORMAT`, `ADMOB_REWARD_REVIVE_FORMAT`으로 형식을 명시할 수 있다. 값은 `rewarded` 또는 `rewarded_interstitial`만 허용한다. 기본값은 카드 `rewarded`, 나머지 두 개 `rewarded_interstitial`이며 APK 검사에서 ID와 형식을 함께 확인한다.

- `tools/admob_config.py`: `.env`를 실행하지 않고 허용한 키만 파싱한다. APK의 매니페스트와 `project.binary` 값이 설정과 일치하는지 검사한다.
- `tools/build_apk.sh`: 동시 빌드를 잠그고 `project.godot`을 백업한 뒤 설정을 주입한다. 내보내기 성공·실패 및 INT/TERM 종료 시 원본을 복원한다. `.env` 자체는 APK에 넣지 않는다.
- `core/ads.gd`: 보상 종류별 광고 단위 선택, SDK 초기화, 테스트 기기 설정, 광고 로드·표시·시청 완료 콜백을 처리한다. 이전 종류의 광고 및 취소·시간초과 요청은 폐기하고, 캐시가 50분을 넘으면 다시 로드한다.
- 첫 카드 광고는 타이틀부터 미리 불러온다. 사용자가 요청한 광고의 Google 네트워크 오류(2)·일시적 SDK 오류(0)는 1.5초 뒤 한 번만 재시도한다. 원래 선택을 보존하고 재시도를 포함해 45초 안에 종료하며, 취소하면 예약된 재시도도 폐기한다. 광고 재고 없음(3/9)·설정 오류(1/8)는 즉시 실패로 처리하고 백그라운드 재요청은 30초 뒤부터 허용한다. 실제 광고 단위를 테스트 광고로 대체하지 않는다.
- 카드 선택 UI의 `Ads.request_reward("card", {"slot": ..., "card": ..., "expected": ...})`, `game/fusion_view.gd`의 `Ads.request_reward("fusion_undo", ...)`, `game/over_screen.gd`의 `Ads.request_reward("continue")`가 위 설정으로 연결된다.
- `core/run.gd`의 `can_choose_card()`·`card_choice_allowed()`가 슬롯·카드·현재 손패를 검사하고, `reward_allowed()`·`apply_ad_reward()`가 최종 조건 검사와 보상 지급을 담당한다. 광고 서비스는 판·탄·슬롯 교체 횟수를 캡처하므로 이전 상태의 콜백으로 카드를 다시 바꿀 수 없다.

### 기기에서 테스트

1. `bash tools/build_apk.sh` 실행 후 `/home/dgxmaruta/pokerdefense-test.apk`를 설치한다. `.env`를 바꾸면 다시 빌드해야 한다.
2. 자체 광고 단위 ID로 테스트할 때는 AdMob 콘솔에 기기를 테스트 기기로 등록하거나, SDK 로그에 나온 기기 ID를 `ADMOB_TEST_DEVICE_IDS`에 넣고 다시 빌드한다. Google 광고의 **Test Ad** 표시를 확인한다. [Google 테스트 광고 안내](https://developers.google.com/admob/android/test-ads)
3. 카드 뽑기의 원하는 카드 선택, 합성 결과의 재료 복구, 게임 종료 화면의 부활을 각각 실행한다. 시청 완료와 중간 종료를 구분해 보상을 확인한다. 합성은 재료 복구 후 다시 합성하고 새 광고를 완료해 여러 번 원복되는지 확인한다.
4. 광고가 안 뜨면 `adb logcat -s godot Ads`로 `AdMob initialized`, `AdMob loading reward`, `AdMob reward ready`, `AdMob earned reward`를 확인한다. `AdMob load failed` JSON에는 `kind/format/code/domain/message`, 제공되는 경우 원인 오류·응답 ID·중개 광고망별 오류가 남는다. 화면에서도 네트워크 오류, 광고 재고 없음, 사용 불가, 시간초과를 구분한다. ID 형식 검증은 계정 승인·광고 단위 활성화·광고 재고까지 보장하지 않는다.
5. 실제 SDK의 Google 오류 3은 요청이 도달했지만 광고가 반환되지 않았다는 뜻이다. 새 앱/광고 단위는 보통 최대 1시간 준비가 필요할 수 있으며 AdMob의 앱 준비 상태도 확인한다. 기존의 동일한 실패 문구만으로는 실제 오류 3이었는지 단정할 수 없다. [Google 오류 코드](https://developers.google.com/admob/android/reference/com/google/android/gms/ads/AdRequest), [광고 미표시 진단](https://support.google.com/admob/answer/9469204?hl=en)

플러그인 공식 안내: [Poing Studios 보상형 광고](https://poingstudios.github.io/godot-admob-plugin/latest/ad_formats/rewarded/)

### 실제 미송출 로그 수집

현재 APK는 로드 실패의 SDK 원문을 이미 기록한다. `tools/diagnose_ads.py`는 연결된 폰에서
이 게임 프로세스의 `godot`·`Ads`·충돌 로그만 읽고 최근 오류를 요약한다.

1. 폰에서 개발자 옵션의 USB 디버깅을 켠다. 작업 컴퓨터에 데이터 USB 케이블로 연결하고
   폰에 뜨는 USB 디버깅 허용 창을 확인한다.
2. 게임을 실행하고 아래 명령을 실행한다. 수집 중 광고 버튼을 누르고 실패 안내까지 기다린다.

   ```bash
   python3 tools/diagnose_ads.py --seconds 60
   ```

3. `build/admob-diagnostics/admob.log`와 `summary.txt`에서 `code/domain/message`,
   제공된 `cause/response_id/adapter_errors`를 확인한다. 이미 실패를 재현했다면
   `--seconds 60` 없이 실행해 남아 있는 로그만 수집해도 된다. 게임을 재시작하면
   프로세스가 바뀌므로 수집을 다시 시작한다.
4. 기기가 여러 대면 `--serial`, adb 경로가 자동 탐색되지 않으면 `--adb`를 지정한다.
   다른 컴퓨터에서 받은 로그는 `python3 tools/diagnose_ads.py --log 경로`로 해석한다.

Google 오류 1은 잘못된 요청, 2는 네트워크 오류, 3은 광고 미반환이다.
다른 광고망의 같은 숫자를 Google 코드로 해석하지 않는다. 오류 3만으로 앱 승인 문제라고
확정하지 말고 원문과 콘솔 상태를 대조한다. SDK 테스트 기기 설정 후 **Test Ad**가 뜨는지
비교하면 테스트 요청과 실제 광고 공급 문제를 나누어 조사할 수 있다. 테스트 광고 성공이
운영 광고 공급을 보장하지는 않는다. [Google 로드 오류 안내](https://developers.google.com/admob/android/ad-load-errors),
[테스트 광고 설정](https://developers.google.com/admob/android/test-ads)

## 확인 및 빌드

- tests/rules_check.tscn: 카드 교체, 12인 편성, 중복 제한, v7 저장 이관, 합성 확률과 환불, 게임 오버 재도전. 합성은 배치·대기실에서 등급 상승·동일·하락·최고 등급 결과의 연속 12회 원복과 저장 복구, 이전 결과의 중복 환불 거절을 검사한다.
- tests/ads_check.tscn: 가짜 SDK로 광고 종류별 ID 전달, 캐시 교체·만료, 취소·시간초과, 로드·표시 실패, 시청 완료·중복·오래된 콜백, 네트워크 실패 후 복구·재시도 한도·재시도 중 취소·오류 분류를 검사한다. 같은 판에서 합성·새 광고 시청·원복을 연속 12회 반복하며 성공 결과의 원복, 취소·미완료·로드 실패 후 재시도도 검사한다. 실제 광고 서버 호출 검사는 아니다.
- `python3 -m unittest discover -s tests -p test_admob_config.py`: 환경 변수 파싱·형식 검증·설정 주입 검사.
- tests/run_stats_check.tscn: 누적 실피해·과잉 피해 제외·Best Player·저장 이관·부활 롤백 및 전체 패시브 보유를 검사한다.
- tests/camp_refresh_preview.tscn: 한영 대기실·합성·선택 상태·패시브·도감·Best Player 및 공통 언어 버튼의 실제 렌더링과 입력을 검사한다.
- `python3 tools/card_choice_review.py`: 카드 직접 선택 UI의 47장 선택 가능·손패 중복 차단·광고 요청·취소·보상 반영·오래된 상태를 검사하고, 1280×800 / 1000×625 한국어·영어 화면을 촬영한다.
- 개발 검사에서는 POCKER_NO_SAVE=1로 사용자 저장 파일을 보호한다.
- 실제 Android 기기의 광고 로드와 시청 완료는 별도 기기 확인이 필요하다.
- APK 산출물은 항상 /home/dgxmaruta/pokerdefense-test.apk에 성공한 새 빌드로만 교체한다.
- 이 머신의 Gradle 빌드는 build/toolchains/jdk17과 ARM용 aapt2 실행 래퍼를 사용한다.
- 임시 Godot 설정은 build/godot-config에 두며 사용자 전역 Java/Android SDK 설정은 변경하지 않는다.
- tools/build_apk.sh는 새 임시 폴더에서 빌드하고 스크립트 오류, APK 서명, AdMob 매니페스트를 확인한 뒤 고정 산출물을 교체한다.
