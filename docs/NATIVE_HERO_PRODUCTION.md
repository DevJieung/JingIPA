# 영웅 native 3D 제작 진행

대상은 기존 영웅 50명이다. 승인된 Limne의 모델·모션·11초상화는 보존하며,
나머지 49명의 실제 GLB·편집 원본·게임 재질·대기/공격과 539초상화를 제작한다.
현재 직접 검수·연결 완료는 신규49명+보존Limne=50/50, 새 초상화539/539장이다.
최종 신규49명 엔진 계약은 `integration/native-all49-final.log` 3,094건/실패0이며,
539개 PNG의 현재 모델 hash·실제 등급/각성 이름·alpha edge0와 보호Limne11장 불변은
`integration/all-hero-portrait-delivery-proof.json`에서 확인했다.
영웅50·몬스터25/575초상화를 포함한 새 서명 APK는 `/home/dgxmaruta/sd-tst.apk`다.
전체 필수 회귀와 native payload/광고/오디오/DB 제외 검사도 통과했다.
iOS는 Xcode 프로젝트/PCK export·packed 모델 검사이며 Linux에서 서명 IPA를 만들지 않았다.
기존 게임 데이터·피해·공격 시계·난수는 바꾸지 않는다. 2026-10-09 사용자가 몬스터25종도 명시적으로 포함했다. 영웅50+몬스터25 native 제작이 현재 범위다.

## 원본과 제작물

- `tools/3d/character_sources.json`: 49명의 실제 활성 sprite와 큰 원본 cell 추출 근거.
  `build/hero-native/source-contact-{1,2,3}.jpg`에서 실제 원본 전체를 확인했다.
  오래된 3D manifest/prompt와 다른 머리색·장비는 실제 활성 sprite를 우선한다.
- `tools/3d/native_visual_specs.json`: 캐릭터별 정체성·체형·공격·관절·강체/보존 영역.
  관절 `pivots`는 Godot `(x,height,z)`/높이 비율, 표면 ROI는 Blender `(x,y,height)`/높이 비율이다.
- `tools/3d/character_reference_sources.json`: 개별 내장 image_gen 래스터 참조.
  래스터 목표와 실제 native GLB를 구분한다. 여러 캐릭터를 한 이미지로 생성하지 않는다.
- `tools/3d/character_apose_sources.json`: 손·팔·장비가 몸에 닿지 않는 제작용 bind pose.
  참조 PNG·프롬프트·입력 hash는 `build/character-3d/references/<id>/`에 보존한다.
- 실제 추론은 cached TRELLIS.2+remesh+PBR이며 원시 GLB/workflow/history는
  `build/character-3d/raw*/<id>/`, Blender high/game source는 `build/character-3d/source/<id>/`다.
  대형 제작 원본은 Godot/Git/모바일에 싣지 않는다.

## 대표 검수와 확대 조건

Echo(가벼운 궁수), Brasa(넓은 장갑·후방 장비), Pip(기계 관절)를 먼저 검수한다.
새 참조로 재구성된 머리·얼굴·옷·후면 장비의 체적은 첫 pixel 입력보다 개선됐다.
대표 세 모델과 Chispa/Lind/Brigid의 실제 모션 검수가 끝났다.
첫 확대는 이 여섯 명과 추가 Phorkys/Solana/Jokull/Rhiannon/Mimic/Protea로 진행했다.
전체49명의 개별 A-pose 입력을 직접 검수·등록했고 이후 순차 실제 검수로 신규48명을 연결했다.
마지막 Dummy까지 원본 Attack 주무기·실측 총구/강체와 최종11초상화를 마쳤다.
`ready_ids`에 올린 모델만 게임 factory가 사용한다.
후보 GLB나 raw job 성공을 완성으로 표시하지 않는다.

Echo의 첫 rest 메시에서 손끝·허벅지·화살통이 한 표면으로 붙었고 공격 시
17mm edge가 0.566m로 늘어났다. 가중치만 바꾸면 바지나 손이 함께 늘어나므로
같은 디자인의 A-pose 참조를 제작하여 팔과 장비를 몸에서 분리한다.
이는 스타일 재설계가 아니라 실제 움직임을 위한 입력 조형 수정이다.

`finish_native_character.py`는 실제 generated surface의 UV/albedo를 유지하고
제한된 LOD·게임 재질·캐릭터별 skin/추가 장비 bone·편집 가능한 native clip을 만든다.
표면 연결에 따른 가중치와 캐릭터별 관절/장비 분리를 사용하며 무조건 공통 ROI를 복사하지 않는다.
`check_native_deformation.py`는 실제 Attack/Idle pose에서 짧은 edge의 폭증과 발 움직임을
기록한다. 수치가 정상이어도 직접 다각도·연속 모션 검수를 통과해야 한다.

## 실제 게임 검수

`native_character_review.py`/`native_character_visual_preview.tscn`은 동일 native 모델을
Godot GL Compatibility에서 촬영한다. 대기24/공격40프레임, GIF/MP4, 정면/측면/후면/3/4,
등급0/4/9·각성, 12고유 영웅 전투·회전/확대와 1280×800/1000×625를 확인한다.
검수 경로는 `build/character-3d/review/<id>/<resolution>/`, report는 같은 review 폴더다.
검수 완료 hash·캐릭터별 rig 수·clip·실제 텍스처를 provenance/manifest와 연결한다.
최종 초상화는 같은 모델에서 재촬영하고 실제 알파 여백/잘림을 검사한다.
실기기 FPS는 별도 측정이며 headless 검사나 삼각형 수로 성능·미적 완성을 주장하지 않는다.

## 대표 세 모델의 현재 결과

- Echo: 54,967삼각형/10bone, 은발·두 녹색 안경·아이보리 셔츠·활·화살통.
  활 전체를 추가 강체 bone에 묶고 당기는 팔과 활을 드는 팔을 분리했다.
- Brasa: 55,522삼각형/9bone, 남색 머리·적금 갑옷·네 후방 판·가슴 화로.
  원시 재구성의 빈 화로에 Blender로 황색 기계 렌즈만 보완했다.
- Pip: 54,995삼각형/11bone, 크림 자동인형·남색 관절·주황 톱니·렌치와 칼.
  두 도구의 실제 끝단까지 강체 가중치로 정리했다.
- 각 모델은 보존 UV/1024 albedo를 사용하며 큰 반사·금속성·잔질감을 낮춘 게임 재질이다.
  실제 두 해상도 각각85PNG/오류0, 24대기/40공격 연속 프레임·GIF/MP4,
  정면/측면/후면/3/4·등급0/4/9·각성·12명 혼합 전투를 직접 검수했다.
  변형 검사11pose에서 큰 찢김0, 발 움직임 Echo/Pip0·Brasa<3µm다.
- 새 초상화는 세 모델의 각11장/총33장을 재촬영했다. 최소 알파 여백은
  Echo24px/Brasa23px/Pip26px, 4px 가장자리 검사 실패0이다.
  모션 계약은 부모의 `native-pilots.log`180건/실패0 결과로 확인했다.
  이 문단은 첫 대표 검수 당시의 기록이다. 현재 전체49명/539장 완료는 마지막 frozen 결과를 따른다.

## 추가 인간형 세 모델 검수

Chispa/Lind/Brigid는 실제 두 해상도 각85PNG/오류0, 대기·공격 연속프레임과
등급·각성·12고유 영웅 전투를 직접 확인했다. Chispa 총신은 실제 총구 축을 따라 조준하고,
Brigid의 활·현 전체는 측정한 표면에 맞춰 강체/전완 경계 가중치를 보완했다.
모션·총구·상태/RNG 계약은 `integration/native-human-wave1.log`195건/실패0이다.
세 모델의 새33초상화는 최소 여백27/28/24px·4px 가장자리 검사 실패0으로
`review/human-wave1-portrait-audit.json`에 기록했다. 현재 수정 대상539장 중66장이 갱신됐다.

## 추가 장비·기계형 여섯 모델 검수

Phorkys/Solana/Jokull/Rhiannon/Mimic/Protea는 실제 두 해상도 각85PNG/오류0,
연속동작·등급·각성·12명 전투를 직접 검수했다. Phorkys 총기/허리 탱크는 측정한
조형에 맞춰 분리 가중치와 실제 총신의 세 축 조준을 작성했고 최대 발 이동은0.1mm미만이다.
두 궁수의 활 전체·요쿨 얼음칼·미믹 손/골반·리아넌 장비 연결도 확인했다.
부모 native 계약 `integration/native-wave2.log`는366건/실패0이다.
새66초상화는 `review/wave2-portrait-audit.json` 최소 여백30/24/32/24/24/24px,
가장자리 실패0이고 현재 누적132/539장이 갱신됐다. 모바일 실기기 FPS는 미측정이다.

## 총기·중장비5 / 장비·검술8 추가 검수

Ceniza/Kari/Vidarr/Igni/Volcan과 Shift/Thalassa/Snorri/Morrigan/Blank/Candela/Sigrid/Helga는
두 크기 각85PNG, 연속 대기/공격·등급/각성·12고유 영웅 전투를 직접 검수했다.
Kari의 왼손 두 총구, Ceniza의 오른손 압력 분사구는 실제 메시의 축을 측정해 조준한다.
Blender `rotation_xyz`를 Godot 기본 YXZ로 읽은 효과 방향 오류는 XYZ를 명시해 수정했다.
최종17종의 부모 계약은 `integration/native-ready17-socket-fix.log`1042건/실패0이다.
변경 효과는 `review/release-xyz/`8연속 방출 프레임과 실제 전투를 별도로 촬영·직접 확인했다.
장비형8의 게임 검수는 `review/<id>/<resolution>/`, 합본은 `build/hero-native/caster8-*`다.
이번13명143초상화를 같은 frozen 모델로 촬영해 총275장이다.
알파 여백 검사는 `review/weapon-wave3-portrait-audit.json`과
`review/caster-wave4-portrait-audit.json`에 기록한다. 림네11장은 변경하지 않는다.
Finn은 재구성된 cuff/hip 연결이 모션에서 늘어나, 기존 근거를 보존하며 분리된 자세를
`finn_separated_reference_sources.json`/`references-retry/finn/`에 새로 준비했다.
통계상 찢김이 없어도 실제 무기·옷·관절 검수를 통과하기 전에는 ready에 넣지 않는다.

## 최신 후반 모델·장비 검수

Lugh/Galene/Zero/Phantom/Caden/Estoque/Nerea/Glaukos, Finn/Marea/Grey/Carmen/Conor/Brian,
Niamh/Saeta/Keto/Null/Isa/Eira와 Triton/Frosti/Donn도 두 해상도 각각85PNG·오류0,
실제 연속동작·다각도·등급/각성·12영웅 전투를 직접 검수해 게시했다.
Finn의 cuff/hip 연결은 원본을 보존한 `raw-finn-separated-v4` 입력에서 복구했다.
궁수는 실제 낮은 활 끝을 부츠와 구분해 전체 무기 강체를 묶고 옷·손 접합을 확인했다.

Triton/Frosti는 원본의 등 장착 포를 유지한 `artillery` 타입이다.
`physical_axis`는 실제 root-rest 포구 축이고 발사 시에만 그 포구 바깥6cm에서 짧은 압력 효과를
표시한다. 몸에 고정된 포를 손에 든 총처럼 돌리거나 게임 탄도·공격 시계를 바꾸지 않는다.
Donn의 큰 금속 팔/손과 뒤 세 cartridge는 연속된 가중치로 보수했다.
Bow6 기술계약354/0, 포병/Donn262/0, 최신66+33초상화 audit의 잘림0을 기록했다.
총기·핀6의 기술계약은440/0이며 원본/검수/raw/native/편집 source SHA 체인이 별도로 검증된다.

Dummy는 활성 idle에서 손이 비어 있어 원형에서 주무기가 누락됐다. 실제 Attack cell의
긴 목재 stock·scope rifle과 고정 hip sidearm을 함께 보존한 하나의 bounded 분리 자세 참조를
`dummy_primary_rifle_reference_sources.json`에 기록했다. 이전 실패 자료를 덮지 않고
`raw-dummy-primary-rifle-v4`에서 실제 총구/축과 강체 가중치를 맞춰 최종 실제 검수 후 연결했다.
실패한 초기 후보와 현재 frozen 모델은 각각 별도 출처/SHA로 보존한다.

## 영웅 전체 frozen 결과

신규49명은 각각 실제 두 해상도85PNG/오류0와 연속동작·다각도·등급·각성·12영웅
전투 검수 후 ready로 연결했다. 보호된 기존 Limne를 포함해50/50 모델이 연결된다.
`review/all49-portrait-audit.json`은 신규539PNG의 실제 알파 잘림0·개별이미지SHA·최종
GLB SHA를 연결하며 Limne11장은 변경하지 않는다. Dummy 마지막11장 최소여백30px다.
Dummy의 원본 rifle 발사축/실제 이벤트 계약은81/0이다. 전체75모델 산출물 완료는
몬스터25 검수·25초상화·41몬스터+12영웅 밀도검수와 부모의 전체통합/빌드 후 판정한다.

편집 원본의 휴대성은 `integration/hero-editable-texture-audit.json`에서
49명의 high/game98파일을 읽기 전용으로 확인했다. 원본 SHA 변경0·문제0이며
실제 텍스처 픽셀과 packed payload를 확인했다. 이는 조형·실기기 성능 판정과 구분한다.
