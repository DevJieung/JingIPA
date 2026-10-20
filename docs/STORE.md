# 상점 — 수호자의 가호와 플랫폼 결제

> 2026-10-19: 부활권은 골드 대신 5성 영웅 하나를 데려오고, DLC 에 Hellbound(끝없는 모드)가 붙었다 —
> 규칙은 `docs/STAGE_LADDER_2026-10-19.md` 의 「부활권」 · 「Hellbound」. 아래 골드 이야기는 그 전의 기록이다.

2026-10-13 사용자 요청: 「판마다 수정 부활」을 상품으로, Google Play · App Store · Steam 을 한
코드로. 목표는 「부담 없이 결제」다.

같은 날 사용자가 과금을 줄였다: 「1~3배속 과금에서 빼줘. 그냥 부활권 3번까지 주고 각 부활마다
골드 쥐어주는 정도로 걔만 과금하는걸로.」 그래서 **배속은 누구에게나 무료**이고(처음에 넣었던
3배속 상품과 체험 판 수는 없앴다), 파는 것은 **한 번 사면 계속 쓰는 상품 하나**다.

## 상품

| id | 이름 | 효과 | 권장 가격 |
|---|---|---|---|
| `guardian` | 수호자의 가호 | 판마다 세 번까지, 수정이 깨지는 순간 절반으로 되살아나고 골드를 받는다 | ₩2,200 |

- 가격은 게임에 적지 않는다. 화면의 가격은 상점이 돌려준 현지 표시가다(`Store.price`).
- **되살아남**: 수정 체력이 0이 되는 순간 `ARENA_REVIVE_HP`(50%)로 되살아나고,
  `ARENA_REVIVE_INVULN`(5초) 동안 피해를 받지 않으며 모든 몬스터가 `ARENA_REVIVE_STUN`(2.5초)
  멎는다. 한 판에 `ARENA_REVIVE_USES`(3)번까지다(`sim.revives`, 저장됨). 네 번째로 깨지면 패배다.
- **골드**: 되살아날 때마다 `Balance.arena_revive_gold(탄)` = `ARENA_REVIVE_GOLD`(100) +
  `ARENA_REVIVE_GOLD_STEP`(10) x 탄을 받는다(1탄 110, 10탄 200). 소환 한두 번에서 세 번쯤의
  값이다. 골드를 따로 팔지는 않는다: 골드는 이 부활에 딸려 올 뿐이고 별맞춤 의식에는 현금이 닿지
  않는다.
- 가호 없이 진 결과 화면에서 사면 **그 판이 바로 이어진다**(`Arena.revive_from_defeat`). 그것이
  그 판의 첫 번째 부활이고 골드도 받는다.
- 소모품이 아니다. 「부활권」을 사서 쓰는 구조(쓸 때마다 결제)는 넣지 않았다. 그러려면 잔액을
  지킬 서버가 먼저다(아래 「상품을 더할 때」).
- 제안은 두 곳뿐이고 어느 것도 스스로 뜨지 않는다: 패배 결과 화면의 제안 한 칸, 타이틀의 상점 버튼.
- 자동 플레이 실측은 [STAGE_RUN_2026-10-13.md](STAGE_RUN_2026-10-13.md) 「실측」에 있다.

## 규칙

- **상점이 원본이다.** 보유 여부는 부팅할 때, 앱으로 돌아올 때, 구매 직후에 상점에 다시 묻는다.
  환불되면 그 답에서 빠지므로 해제도 회수된다. 저장 파일의 사본(`Save.iap_owned`)은 연결 없이
  켰을 때만 쓴다. 서버는 없다.
- **상점이 붙지 않은 빌드는 아무것도 잠그지 않는다.** 플러그인 없이 내보낸 빌드, 데스크톱 개발
  실행, 검사기에서는 `Store.has_shop()` 이 거짓이고 `Store.owns()` 는 언제나 참이다.
- **테스트 빌드의 테스트 해제**: 상점이 그 상품을 팔 수 없을 때(앱·상품이 아직 콘솔에 없을 때)
  테스트 빌드는 결제 없이 해제한다(버튼 문구 「테스트 해제」, 구매창의 「테스트 구매 초기화」).
  테스트 빌드란 디버그 익스포트(`sd-tst.apk`)이거나 프리셋의 `custom_features` 에 `store_test` 가
  있는 빌드다(`Store.test_build()`). 서명 없는 테스트 IPA 는 release 익스포트라서 iOS 프리셋에
  `store_test` 를 넣어 두었다.
  **스토어에 올릴 빌드는 release 익스포트이고 `store_test` 가 없어야 한다.** 남아 있으면 상점이
  상품을 못 주는 상황(오프라인 등)에서 결제 없이 해제하는 길이 열린다.
- 구매 결과는 `ok` · `cancelled` · `pending`(승인 대기: 나중에 승인되면 자동으로 열린다) ·
  `failed` · `unavailable` 다섯 가지다. 응답이 없는 결제창은 180초 뒤 실패로 정리한다.

## 구조

```
게임 코드 ── Store.owns / price / buy / restore ──▶ core/store.gd (오토로드 Store)
                                                      │  부팅 때 있는 엔진 싱글턴으로 하나를 고른다
                 GodotGooglePlayBilling ─────────────▶ core/store/play.gd   (Play Billing 9)
                 IOSInAppPurchase ───────────────────▶ core/store/apple.gd  (StoreKit 2)
                 Steam ──────────────────────────────▶ core/store/steam.gd  (본편 포함 또는 DLC)
```

| 파일 | 책임 |
|---|---|
| `core/store.gd` | 상품 표, 보유·가격·구매 상태, 테스트 해제, 저장 사본 |
| `core/store/play.gd` | Play Billing: 연결·재시도, 상품 조회, 구매, 승인(acknowledge), 보유 조회 |
| `core/store/apple.gd` | StoreKit 2: 상품, 구매, 현재 보유, 앱 밖 승인·환불 수신, `AppStore.sync` 복원 |
| `core/store/steam.gd` | GodotSteam: 초기화, 본편 포함 또는 DLC 보유, 오버레이로 상점 열기 |
| `game/store_view.gd` | 구매창(타이틀과 전장이 같이 쓴다). 화면 설계와 상태별 모습은 [UI_STAGE_STORE.md](UI_STAGE_STORE.md) |
| `addons/GodotGooglePlayBilling/` | 공식 Godot Play Billing 플러그인 3.3.0 (Billing Library 9.1.0) |
| `ios/plugins/ios-in-app-purchase/` | hrk4649/godot_ios_plugin_iap 0.4.0 (Godot 4.7용 빌드, StoreKit 2, iOS 15+) |

상품의 상점 ID는 `core/store.gd` 의 `PRODUCTS` 한 곳에 있다. Google 과 Apple 은 같은 문자열을
쓴다: `stellardefense.guardian`. 저장 파일에 남아 있을 수 있는 예전 상품 ID(`speed3`)는 읽을 때
버린다.

## 플랫폼별로 할 일

코드와 플러그인은 들어 있다. 아래는 각 스토어 콘솔에서 사람이 해야 하는 일이다.

### Google Play

1. Play Console 에 패키지 `com.devjieung.stellardefense` 로 앱을 만들고 결제 프로필을 설정한다.
2. 수익 창출 > 인앱 상품에서 **일회성 상품** 하나를 위 상품 ID 그대로 만들고 활성화한다.
   (상품을 만들려면 Billing 라이브러리가 든 빌드를 내부 테스트 트랙에 한 번 올려야 한다.)
3. 라이선스 테스터로 계정을 등록하면 디버그 서명 `sd-tst.apk` 로도 실제 결제 흐름을 시험할 수 있다.
4. 스토어 제출용은 release 익스포트의 AAB(`gradle_build/export_format=1`)와 릴리스 키가 필요하다.
   지금 프리셋은 디버그 테스트 APK 그대로다(결제 없는 「테스트 해제」가 되는 빌드).
- Play Billing 라이브러리가 `INTERNET` · `ACCESS_NETWORK_STATE` · `com.android.vending.BILLING`
  권한을 병합한다. `tools/ci/check_no_ads.py` 는 이 셋만 허용하고 광고 권한·SDK 와 그 밖의 권한은
  여전히 거부하며, 결제 권한이 빠진 APK 도 실패로 본다.
- 구매는 3일 안에 승인(acknowledge)하지 않으면 Google 이 환불한다. `play.gd` 가 구매 완료와 보유
  조회 때마다 미승인 구매를 승인한다.

### App Store

1. App Store Connect 에서 유료 앱 계약·세금·계좌를 마친다. 수수료 15%는 Small Business Program 에
   **가입해야** 적용된다.
2. 앱의 인앱 구입에 **비소모성(Non-Consumable)** 상품 하나를 위 상품 ID 그대로 만든다. 첫 인앱
   상품은 앱 버전과 함께 심사에 올린다.
3. 구매 복원 버튼은 구매창에 있다(`AppStore.sync`). 심사 요건이다.
4. 서명 없는 IPA 나 AltStore 설치로는 결제가 동작하지 않는다(그 빌드에서는 「테스트 해제」로
   흐름만 볼 수 있다). 유료 개발자 계정으로 서명한 빌드와 샌드박스 계정 또는 TestFlight 로 시험한다.
5. App Store Connect 에 올릴 빌드는 iOS 프리셋의 `custom_features` 에서 `store_test` 를 지우고
   `STELLARDEFENSE_IOS_EXPORT_METHOD` 를 `app-store-connect` 로 둔다.
- 최소 iOS 를 15.0 으로 올렸다(StoreKit 2). 프리셋의 `plugins/IOSInAppPurchase=true` 가 플러그인을
  Xcode 프로젝트에 넣는다. 플러그인 때문에 빌드가 막히면 이 줄을 `false` 로 바꾸면 결제 없는
  빌드가 된다(그 빌드는 아무것도 잠그지 않는다).

### Steam

- 권장: **유료 본편에 포함**(`Store.STEAM_INCLUDED = true`, 기본값). 결제는 Steam 상점이
  맡으므로 게임 안에서는 가호가 언제나 보유로 나온다(Steam 판은 누구나 판마다 세 번 되살아난다).
- 무료로 내려면 `STEAM_INCLUDED` 를 `false` 로 바꾸고 `PRODUCTS` 의 `steam_dlc` 에 DLC 의 앱 ID 를
  적는다. 구매 버튼은 Steam 오버레이로 그 DLC 의 상점 페이지를 열고, 보유는
  `Steam.isDLCInstalled` 로 확인한다.
- `Steam` 싱글턴은 GodotSteam 이 준다. 익스포트 프리셋 「Steam Windows」「Steam Linux」의
  `custom_template/release` 에 GodotSteam 익스포트 템플릿(Godot 4.7 용)을 지정하거나 GodotSteam
  GDExtension 을 넣어 내보낸다. 기본 템플릿으로 내보내면 Steam 이 없는 빌드(상점 없음)가 된다.
- 개발 중에는 실행 파일 옆에 `steam_appid.txt` 를 둔다. 앱 ID 를 코드로 주려면 `STEAM_APP_ID`.
- 데스크톱 조작: 방향키 · WASD · 게임패드 왼쪽 스틱/십자키로 선택한 영웅을 움직인다. 버튼은
  마우스로 누른다.

## 확인한 것과 못 한 것

확인함(2026-10-13, 이 저장소에서 실행):
- `tests/store_check.tscn` 94건: 상점 없는 빌드, 보유·환불·오프라인 사본, 배속이 무료인 것,
  가호(자동 부활 · 패배 화면 구매 뒤 이어하기 · 판마다 세 번 · 부활마다 골드 · 저장과 예전 저장
  읽기), 그리고 세 백엔드를 실제 플러그인과 같은 신호·메서드를 가진 대역으로 구동(구매 · 취소 ·
  승인 대기 · 환불 · 복원 · 재연결).
- 플러그인을 넣은 디버그 APK 익스포트: 플러그인 등록(`org.godotengine.plugin.v2.GodotGooglePlayBilling`),
  Billing 클래스, 권한 넷(위 셋 + 앱 자체 수신자 권한)을 병합 매니페스트에서 확인.
- iOS Xcode 프로젝트 익스포트(리눅스에서 프로젝트만): `ios-in-app-purchase.xcframework` 와
  `StoreKit.framework` 가 프로젝트에 들어가고, 플러그인 초기화가 생성 코드에 연결되고, 배포 대상이
  iOS 15.0 인 것을 확인.
- 「Steam Linux」「Steam Windows」 프리셋이 기본 템플릿으로 내보내지고, 그 꾸러미가 오류 없이
  부팅되는 것(Steam 없이, 즉 상점 없는 빌드로)을 확인.

확인하지 못함:
- **실제 결제.** Play Console · App Store Connect · Steamworks 에 앱과 상품이 등록돼 있지 않아
  어느 스토어에서도 결제창을 띄워 보지 못했다. 세 백엔드는 플러그인 문서와 소스의 계약대로 썼고
  대역으로만 돌렸다.
- **iOS 빌드와 실기기 실행.** 이 환경에는 Mac 이 없어 Xcode 빌드(IPA)까지는 못 돌렸다. 다음
  푸시의 CI 가 처음으로 플러그인을 링크한다. 플러그인 바이너리는 제3자가 Godot 4.7 용으로 빌드한
  것이다. 첫 실기기 실행에서 확인이 필요하다.
- **Steam 빌드 실행.** GodotSteam 템플릿과 Steam 클라이언트 없이 프리셋과 백엔드 코드만 넣었다.

## 검사

```bash
STELLARDEFENSE_NO_SAVE=1 godot --headless --path . res://tests/store_check.tscn
python3 -m unittest discover -s tests -p test_check_no_ads.py
```

`tools/verify.sh` 4-2 단계와 CI(`tools/ci/export.sh`)가 `store_check` 를 돌린다.

## 상품을 더할 때

`core/store.gd` 의 `PRODUCTS` 에 한 줄, `core/locales/ui.json` 에 `store.<id>.name` · `.desc`
(DB 로 들이기: `python3 tools/gamedb.py pull`), 그리고 그 상품을 묻는 자리에 `Store.owns("<id>")`.
소모성 상품은 이 구조에 없다. 넣으려면 잔액을 지킬 서버가 먼저다.
