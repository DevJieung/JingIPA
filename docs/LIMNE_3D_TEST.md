# Limne 3D 품질 재작업

> 이 문서는 2026-10-08 조형 제작·검수 기록이다. 이후 사용자가 현재 Limne를 좋게 평가하고
> 움직임·게임 스타일을 요청했다. **현행 9bone 모션·재질·산출물·재현은
> [Limne 게임 스타일·움직임](LIMNE_MOTION_STYLE.md)**을 따른다.
> 아래 5bone 비용·SHA·공격 평가와 `build/limne-pro/` 자료는 당시 baseline이다.

2026-10-08. 사용자 확정 방향은 **원본 Limne를 살린 고급 스타일라이즈드 3D —
애니메이션·게임풍**이다. 첫 custom-mesh 테스트는 기능 계약을 통과했지만 미적 품질이
부족해 사용자가 거절했다. 삼각형 수나 자동 검사 통과를 전문적인 품질의 근거로 삼지 않는다.
현재 결과는 **편집 가능한 실제 3D 개선 실험**이다. 직전 실패작보다 조형·천 주름·장비와
재질 차이가 뚜렷해졌지만, 목표 콘셉트와 같은 전문적인 완성 품질에 도달했다고 판단하지 않는다.
큰 렌더에서 어깨/소매의 재구성 경계와 작은 눈 주변 파편이 남아 있다.

## 실제 제작 경로와 출처

1. 보존된 `art/portraits/limne.png`, `art/anim/limne/limne_idle.png`,
   `limne_attack.png`를 직접 확인했다. 남색 단발·갈색 눈·청록 앞치마·코발트 작업복·
   고무장화·물탱크·두 호스와 황동 노즐의 정체성을 유지한다.
2. 내장 image_gen으로 원본을 참조한 목표 PNG를 만들었다.
   `build/limne-pro/concept/limne_target.png`는 **AI가 생성한 래스터 품질 기준**이다.
   GLB의 렌더 이미지가 아니며 실제 3D 완성 결과로 표시하지 않는다.
3. 로컬 ComfyUI native TRELLIS.2에서 full bf16 가중치, DINOv3 ViT-L,
   1024 shape cascade, 768 UDF remesh·Taubin smoothing, 2048 PBR 베이크와
   최종 normals 경로를 실행했다. 실제 성공한 워크플로는
   `tools/3d/limne_trellis.json`, 원시 PBR GLB는
   `build/limne-pro/runtime/outputs/limne_remesh_pbr_00001.glb`다.
   추론 기록은 `runtime/inference_remesh.log`, `remesh_topology.json`에 보존한다.
4. Blender 4.0.2에서 실제 생성된 머리·의복·몸체 표면을 보존하고 UV/법선을 정리했다.
   얼굴과 목은 원본 비례에 맞는 하나의 연속 Hermite 메쉬로 새로 조형했다.
   곡면 안구·갈색 홍채·눈꺼풀·미소, 단일 원형 저수탱크·렌즈·수면·황동 엣지·나사·
   두 원형 노즐과 호스는 Blender에서 작성했다. 순수 수작업 모델 또는 AI 완성 모델로
   과장하지 않는 **실제 생성 표면과 Blender 조형의 혼합 제작**이다.
5. 최종 본체는 **원래 base-color/ORM 2048 UV를 보존**한다. 강한 LOD 축소·새 UV 베이크에서
   검은 삼각형과 atlas 손상이 발생해 그 경로를 거절했다. 현재 GLB에 별도 normal map은 없다.
   손·손목은 닫힌 피부 표면으로 다시 작성하고 허리·소매·어깨의 열린 경계를 천 표면으로 보수한다.
   장비는 절제된 공유 재질을 쓴다. 현재 본체는 고밀도이며 모바일 LOD 최적화 완료로 주장하지 않는다.
   제작용 대형 dense 메시·가중치·원본 PNG와 .blend는 `build/limne-pro/` 아래에만 보존한다.

원시 메시에는 얼굴/헤어 거침, 두 탱크의 추정 오류, 찌그러진 노즐, 경계와 법선 결함이
있었다. 원시 output과 실패한 중간 렌더는 보존하며 통과 근거로 사용하지 않는다.
거절된 첫 모델/렌더/생성기는 `build/limne-pro/rejected-v1/`에 보존했다.

## 재현과 런타임 계약

```bash
env -u DISPLAY bl -b --factory-startup --python tools/3d/finish_limne_pro.py -- \
  --input build/limne-pro/runtime/outputs/limne_remesh_pbr_00001.glb \
  --front=-y --triangles 200000 --legacy-surface-finishing
STELLARDEFENSE_NO_SAVE=1 ~/.local/bin/godot --headless --editor --import --path . --quit
python3 tools/3d/render_portraits.py --ids=limne
python3 tools/3d/limne_review.py
env -u DISPLAY bl -b build/limne-pro/source/limne_game.blend \
  --python tools/3d/render_limne_studio.py
```

위 명령은 당시 표면 finishing 재현이다. 현재 `build_limne.py`는 승인된 .blend에서
스타일·9bone 모션을 만드는 entry이며 원시 `--input`을 받지 않는다. 옛 finishing은
`--legacy-surface-finishing`을 명시해야 실행할 수 있다. 현재 모델을 유지할 때는
이 옛 표면 명령 대신 [현재 재현](LIMNE_MOTION_STYLE.md)을 사용한다.
조형·표면 정리는 `finish_limne_pro.py`, `limne_surface_finish.py`, `limne_local_polish.py`가 담당한다.
실패한 atlas 실험 `limne_bake.py`는 기본 경로에서 실행하지 않으며, 파괴적인 축소/재베이크는
명시적인 `--experimental-atlas-rebuild` 없이는 실행하지 못한다.
편집 가능한 high/game 원본은 `build/limne-pro/source/limne_{high,game}.blend`,
런타임은 `art/models/limne/limne.glb`다. `art/models/limne/provenance.json`에 기록한다.

`StellarModels.hero(unit,grade)`는 Limne 및 Limne 각성 수호자에서 GLB를 읽는다.
root metadata `identity`, `grade`, `model_source`와 직접 자식
`Body/ArmL/ArmR/LegL/LegR`, 발 Y0·얼굴 -Z·높이 1.63을 유지한다.
다섯 pivot의 transform을 `game/3d/limne_model.gd`가 다섯 Skeleton3D bone의
absolute local pose로 옮긴다. 본체와 두 호스는 연속 skin이고, 호스 양 끝의 가중치는
몸통/팔에 이어진다. 매 프레임 메쉬·재질을 생성하지 않는다.
등급 0~9·각성 장식과 LRU96, 나머지 49명, 게임 데이터·RNG·피해 시점은 보존한다.
Godot가 textureless 홍채 재질의 `COLOR_0` 사용을 꺼서 갈색 홍채가 흰색으로 보였던
문제는 `LimneModel`의 해당 재질 설정으로 보정했다. 피부 정점 색은 이미 활성화되어 있었다.
GLB 원시 색 데이터와 기하를 바꾸지 않고 갈색 홍채와 절제된 clearcoat를 적용한다.

새 공격 타이밍·팔꿈치 관절·얼굴 표정 애니메이션은 추가하지 않았다. 기존 팔 올리기
transform을 그대로 따른다. 실제 공격 프레임에서 호스와 장비 간섭을 별도로 확인한다.

## 검수 자료와 진행 상태

최종 자료 경로는 `build/limne-pro/studio/`와
`build/limne-pro/game-review/{1280x800,1000x625}/`다.

| 자료 | 확인 항목 |
| --- | --- |
| studio `three_quarter/front/side/back/face_closeup.png` | 실제 .blend의 큰 렌더, 얼굴·헤어·천·장비·접지 |
| game `comparison.jpg` | 원본 2D·idle·사용자가 거절한 v1·현재 실제 GLB |
| `target_vs_actual.jpg` | AI 래스터 기준과 실제 게임 GLB를 명확히 구분 |
| `turnaround.jpg`, `gallery_*.png` | 실제 Godot 정면·측면·후면·3/4·얼굴 확대 |
| `grades.jpg` | 등급 0/4/9·각성 |
| `idle/attack_contact.jpg`, `idle/attack.gif` | 각 12연속 프레임·발/몸체/호스 연결 |
| `formation/battle/battle_selected/battle_orbit.png` | 12고유 영웅 혼합 전투·선택·회전·확대 |
| `battle_motion_contact.jpg`, `battle_motion.gif` | 실제 전투 8프레임 |

실제 .blend의 1440×1800 정면/측면/후면/3/4/얼굴 확대를 촬영하고 직접 확인했다.
`studio/comparison.jpg`, `studio/target_vs_actual.jpg`는 원본/거절된 v1/현재 실제 모델과
AI 래스터 목표의 차이를 그대로 보여 준다. `art/models/portraits/limne/00..09.png`와
`00_awakened.png` 11장은 최종 모델과 홍채 보정을 사용해 다시 촬영했다.
`portraits-final.log`는 11 heroes/0 monsters이며 나머지 49명·몬스터 이미지를 다시 저장하지 않았다.
홍채 보정과 새 PNG import 이후 두 해상도에서 각각 45PNG, 총 90장을 다시 촬영했다.
정면/측면/후면/3/4·얼굴·등급·12프레임 idle/attack·12고유 영웅 실제 전투/선택/회전·확대와
8프레임 실제 전투 자료를 직접 확인했다. `game-review/report.json`은 두 크기 render_errors=0이며
최종 verbose `render.log`에도 ERROR/누수/리소스 참조 오류가 없다. 11초상화 alpha 여백 검사는
최소 27px, 실패 0이다(`build/limne-pro/portrait-audit.json`).
기능 전체 quick 회귀(100탄 자동 플레이 포함)는 root가 통과했고
`build/limne-pro/integration/verify.log`에 기록했다. 최종 모델 계약 134건(홍채 회귀 포함)과
전체 모델·등급·캐시 2,628건 검사는 root의 `integration/*-final.log`를 따른다.

캡처 도구는 verbose 실제 로그를 사용한다. 이전 비verbose 종료 오류의 원인은 미확정이었다.
이번 1000×625 verbose 촬영 종료에서 Ogg 음악 playback 4개/리소스 2개의 참조가 실제로
재현되어 `game-review/1000x625/render-exit-audio-failed.log`를 보존했다.
촬영 fixture의 종료 직전에 AudioStreamPlayer를 stop하고 stream을 비운 뒤 재촬영했다.
실제 게임 음악 코드는 변경하지 않았으며 일반 런타임 누수 완전 해결을 주장하지 않는다.
중간 실패 모델·베이크·촬영 로그도 통과 자료로 대체하지 않고 보존한다.

## 비용과 한계

원시 remesh PBR GLB는 178,385삼각형이다. cleaning/추가 조형 뒤 비용은
provenance와 실제 Godot `model_geometry.json`에 별도로 기록한다.
원시 정리 이후 local polish 전의 retained surface는 127,093삼각형이며,
최종 GLB 전체는 **173,032삼각형·63메쉬/68 primitives·22재질·2개 embedded 2048 이미지·1 skin/5 bone**,
17,555,644바이트다. local polish 이전 retained 수치는 최종 전체 수치와 구분한다.
최종 GLB SHA256은 `37a0ca04bf96048f4d72fb44d68b1c6bebccd69a4faebf05316cffd6449b41b8`다.
메쉬·재질·삼각형 수는 제작 비용 정보이며 미적 품질이나 GPU draw call/FPS의 증거가 아니다.

큰 스튜디오 렌더의 남은 결함은 어깨/소매의 톱니 경계, 천 보수부의 색/윤곽 차이,
눈꺼풀/눈 주변의 작은 검은 삼각형, 일부 헤어 표면 눌림과 뒷옷 거침이다.
단일뷰 자동 재구성과 반복적인 좌표 절단만으로 전문적인 retopology를 대체할 수 없었다.
전체 메시 winding 재계산이 nonmanifold 원시 표면의 다른 영역을 뒤집는 가능성도 확인됐으며,
이를 확정 원인이나 완전 해결로 주장하지 않는다. 보존된 coherent UV/PBR 결과를 비교 대상으로
고정했다. 최종 아티스트 수작업 retopology와 모바일 LOD는 아직 남은 작업이다.
공격은 기존 팔 transform의 큰 회전을 유지한다. 연속 프레임에서 호스 양 끝은 이어지지만,
절정 포즈의 소매 변형과 노즐 방향은 새 캐릭터를 위한 완성형 조준 애니메이션이 아니다.
피해/총구의 게임 좌표와 실제 타이밍은 변경하지 않았다.

Android 실기기 FPS·발열·육안 검수는 수행하지 않았다. 단일뷰 재구성의 뒷면·가려진 손은
자동 생성만으로 확정할 수 없어 조형 수정과 실제 여러 시점 검수가 필요하다.
게임은 GL Compatibility라 고품질 오프라인 유리 굴절과 같은 비용의 표현을 약속하지 않는다.
게임은 투명 렌즈·수면·금속/고무/천의 절제된 PBR 차이와 원시 2K 표면 맵을 사용한다.
APK·iOS 패키징·최종 전체 기능 검사는 메인 담당의 범위다.
root의 최종 검사와 빌드는 `build/limne-pro/integration/verification.json`에 남았다.
홍채 회귀 포함 134/0, 전체 모델 2,628/0, iOS PCK/boot/DB 제외 및 Android 서명·패키지 검사를
통과했고 APK는 `/home/dgxmaruta/sd-tst.apk`로 교체했다. 로컬 iOS 결과는 Xcode project/PCK이며
서명된 IPA를 로컬에서 만들었다고 주장하지 않는다. 전체 quick 회귀 로그는 최종 표면 보수 전
같은 골격 어댑터에서 실행한 결과이고, 최종 산출물은 해당 모델/패키지 검사로 별도 확인했다.
