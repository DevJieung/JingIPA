# Limne 게임 스타일·움직임

2026-10-09. 사용자가 현재 Limne 조형을 좋게 평가하고, 움직임과 조금 더 3D 게임다운
표현을 요청했다. **승인된 체형·얼굴·장비를 유지**하면서 대기·조준·물 분사·복귀와
덜 번쩍이는 재질을 적용했다. 이번 작업에는 새 이미지 생성이나 이미지→3D 추론을 사용하지 않았다.
이전 제작 과정은 [Limne 3D 재작업 기록](LIMNE_3D_TEST.md)에 남긴다.

## 현재 표현

- 남색 단발·갈색 눈·청록 앞치마·코발트 작업복·고무장화·단일 탱크·두 호스와 노즐을 유지한다.
  머리·피부·천·고무의 반사를 낮추고 황동의 반짝임을 절제했다. 기존 albedo와 UV를 보존하되
  게임에서는 의복의 거칠기·금속성을 일정하게 두어 작은 화면에서 색과 형태가 읽히도록 했다.
- 6초 대기 루프는 호흡, 작은 몸 기울기와 손의 움직임이다. 발은 바닥에 고정한다.
  공격에서는 팔꿈치를 굽혀 노즐을 앞으로 올리고, 손목이 노즐 방향을 유지한다.
  분사 시 작은 반동을 주고 0.22초 동안 대기로 돌아온다.
- 푸른 물줄기 두 개와 작은 물방울은 실제 노즐 끝을 따른다. 기존 공격 준비 시간 `fx_w`
  이후에만 0.13초 분사하며 `fx_t/fx_w/fx_d`를 읽는다. 피해 판정·공격 시계·총구 게임 좌표·
  데이터·난수는 변경하지 않는다. 시각 물줄기의 길이는 피해 범위가 아니다.
- 본체 topology/UV는 보존했다. 기존 다섯 제어 노드와 skin bone을 유지하고
  `SkinForearmL/R`, `SkinHandL/R` 네 관절을 추가했다. 노즐은 손을, 호스는 몸통과 손을 따라간다.
  GLB에 편집 가능한 `IdleLoop`, `WaterSprayAttack` 두 클립도 포함한다.
  런타임은 현재 전투 시계에 맞는 동일 관절 pose를 사용하며 클립을 자동 재생하지 않는다.

## 산출물과 직접 검수

런타임 모델은 `art/models/limne/limne.glb`, 시각 어댑터는 `game/3d/limne_model.gd`다.
현재 native GLB SHA256은
`b0d3f0231076fecf1c7a7c8750a9e579365da6b03cea1ac42562fa83c1b29d92`다.
편집 원본은 `build/limne-game-motion/limne_game.blend`이며 제작 원본을 Git/모바일에 포함하지 않는다.
사용자가 받아들인 직전 모델·원본·코드·초상화·실제 렌더는
`build/limne-game-motion/before/`에 보존한다.

| 자료 | 현재 경로 |
| --- | --- |
| 대기→조준→분사→복귀 반복 GIF·MP4 | `build/limne-game-motion/game-review/<해상도>/motion.gif`, `motion.mp4` |
| 개별 루프와 연속 프레임 | 같은 폴더의 `idle.gif`, `attack.gif`, `idle_contact.jpg`, `attack_contact.jpg` |
| 같은 카메라의 재질 전후 비교 | 같은 폴더의 `style_before_after.jpg` |
| 실제 전투·선택·회전·확대 | `battle.png`, `battle_selected.png`, `battle_orbit.png`, `battle_motion.gif` |
| 정면·측면·후면·3/4·얼굴, 0/4/9등급·각성 | `turnaround.jpg`, `gallery_*.png`, `grades.jpg` |
| 실제 Blender 1440×1800 큰 렌더와 전후 비교 | `build/limne-game-motion/studio/` |
| 현재 모델의 11초상화 | `art/models/portraits/limne/00..09.png`, `00_awakened.png` |
| 초상화 합본·알파 검사 | `build/limne-game-motion/portraits.jpg`, `portrait-audit.json` |

Godot GL Compatibility에서 **1280×800과 1000×625 각각 121PNG, 총 242장**을 촬영했다.
대기 60프레임·공격 40프레임과 실제 12고유 영웅 전투를 포함한다.
연속 프레임에서 발 고정, 노즐의 전방 유지, 호스 연결과 복귀를 직접 확인했다.
작은 전투 화면과 카메라 회전에서도 남색 머리·청록 앞치마·탱크가 구분되며 기존 UI를 가리지 않는다.
같은 카메라 전후 비교에서 피부·머리·장화의 피규어 같은 광택이 줄었다.
새 GIF/MP4는 **실제 게임 렌더**다. 합본 MP4는 512×640, 50fps, 330프레임/6.6초이며
대기 3초→공격 시연 1.6초→대기 2초로 반복한다. 공격 시연의 프레임 표시 속도는
동작을 볼 수 있도록 실제 공격 시간보다 느리게 구성했다.

`game-review/report.json`은 두 크기 모두 `render_errors=0`이다.
최종 verbose `render.log`와 초상화 로그에 ERROR/종료 참조 오류가 없다.
초상화는 11 heroes/0 monsters로 촬영했으며 알파 최소 여백은 23px, 잘림 0장이다.
기존 촬영 도구의 종료 음악 참조 정리는 테스트 fixture에만 적용했고 게임 오디오를 수정하지 않았다.

## 연동·비용

`StellarModels.hero()`의 metadata·직접 자식 `Body/ArmL/ArmR/LegL/LegR`, 발 Y0·얼굴 -Z,
높이 1.63, 0~9등급·각성과 LRU96을 유지한다. `StellarWorld.sync_heroes`의 Limne 시각 분기만
`animate_visual(time, fx_t, fx_w, battle)`를 호출한다. 나머지 49명의 시각 pose는 그대로다.
공개 확인 함수는 `spray_strength()`와 `nozzle_transform(side)`다.

물줄기·물방울의 mesh/재질/노드는 초기화할 때 한 번 만들고 매 프레임 transform·가시성·
shader uniform만 바꾼다. 공유 topology를 사용하며 매 프레임 mesh/재질을 생성하지 않는다.
본체는 StandardMaterial3D, 분사만 경량 `water_spray.gdshader`로 GL Compatibility에서 동작한다.

| 비용 | 현재 수치 |
| --- | --- |
| native GLB | 173,032삼각형·63메쉬/68 primitives·22재질·2개 embedded 2048 이미지·1 skin/9 bone |
| native 파일 크기 | 17,091,528바이트 |
| runtime 본체+숨겨진 분사 노드 | 174,280삼각형·79메쉬·24재질 |
| 추가 분사 표현 | 2물줄기+14물방울, +1,248삼각형·2재질 |

root의 모션/모델 계약 검사 **174건/실패 0**, 전체 모델·등급·캐시 **2,628건/실패 0**을 통과했다.
대기 루프 경계, 공격 release/recovery, 발 고정, 네 방향 노즐 정렬, 인스턴스별 관절 독립,
프레임 간 자원 재사용 및 전투/저장/난수 보존을 검사한다.
실행 로그와 모바일 결과는 `build/limne-game-motion/integration/`에 기록하며 패키징은 root가 맡는다.

최종 Android 빌드는 `/home/dgxmaruta/sd-tst.apk`로 교체했다(324,341,441바이트,
SHA256 `01ad550c4c3034ccacd5e78398ff537674620e7b7becbdfc88115a8e35dab8b1`).
서명·광고·오디오·DB 제외·550초상화·분사 shader 검사와 현재 imported GLB payload 일치 검사를
통과했다. iOS는 `build/limne-game-motion/ios/stellardefense.xcodeproj`와
`stellardefense.pck`를 만들고 9관절·분사 shader·실제 boot 검사를 통과했다.
파일 hash와 검수 report는 `integration/artifact-manifest.json`에 고정했다.

## 재현과 한계

현재 재현 entry는 승인된 .blend를 입력으로 쓰는 `tools/3d/build_limne.py`다.
옛 원시 GLB finishing은 명시적인 `--legacy-surface-finishing` 없이는 현재 애니메이션 모델을
덮어쓰지 못한다. 새 재구성·베이크·표면 절단 없이 승인된 조형에서 작업을 이어간다.

```bash
env -u DISPLAY bl -b --factory-startup --python tools/3d/build_limne.py
STELLARDEFENSE_NO_SAVE=1 ~/.local/bin/godot --headless --editor --import --path . --quit
python3 tools/3d/render_portraits.py --ids=limne
python3 tools/3d/limne_review.py
env -u DISPLAY LIMNE_STUDIO_OUTPUT=build/limne-game-motion/studio \
  bl -b build/limne-game-motion/limne_game.blend --python tools/3d/render_limne_studio.py
```

본체는 여전히 고밀도이며 모바일 LOD를 새로 만들지는 않았다. 원래 표면 맵에 구워진 일부
질감·하이라이트는 남지만 런타임 반사를 절제했다. 표정·눈 깜빡임·보행은 이번 범위에 없다.
Android 실기기 FPS·발열·육안 검수는 수행하지 않았다. 로컬 iOS 산출물은 Xcode project/PCK이며
서명 IPA와 구분한다. APK는 성공한 새 빌드로만 `/home/dgxmaruta/sd-tst.apk`를 교체한다.
