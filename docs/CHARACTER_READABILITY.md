# 캐릭터 가독성 개선

`voc.jpg`의 Niamh는 실제 인물 높이 124px인 전투 idle 프레임을 상세창에서
확대하고 있었다. 투명 배경을 포함한 시트 크기는 256px여도 인물 해상도는
그보다 작다. 원본을 Nearest로 두 번 축소하면서 가는 윤곽이 끊기고, 이를
다시 확대하면 손실된 얼굴·옷·무기 디테일은 돌아오지 않는다.

전투 애니메이션과 상세창 원화를 별도로 만들었다. Niamh 상세창에는
사용자가 제공한 `ToBe.png`를 직접 배경 분리한 이미지를 적용했다.
나머지 49명은 보관된 768px 원본의 대기 자세를 사용한다.
체형을 크게 다시 디자인하는 작업은 별도의 원화 수정이 필요하다.
이번 전투 후처리는 기존 자세와 신체 비율을 유지하면서 경계를 보강한다.

## 파이프라인

```text
보관된 H3 원본 matte + 승인된 프레임 선택/발 기준점
  ├─ 전투: 원본 경계 색 정리 → 알파를 고려한 1회 면적 축소
  │        → 승인 실루엣 주변 2px 이내의 복구만 허용
  │        → 1px 외곽선 → 캐릭터별 공통 96색 → 발 영역 고정
  │        → 256×256, idle 8장 + attack 12장
  └─ 상세창: 원본 대기 자세의 투명 영역 자르기 → 최대 높이 512px
           → 투명 여백 → UI 전용 텍스처로 축소 표시

ToBe.png → BiRefNet 배경 분리 → Niamh 전용 원화 입력
```

- 투명 검정이 색 평균에 섞이지 않도록 premultiplied alpha로 축소한다.
- 경계 색 보정은 원본의 가장자리 2px에 적용한다. 옷 전체의 채도를 낮추지 않는다.
- 외곽선은 상하좌우 1px만 더한다. 팔다리·활줄 전체를 굵게 팽창시키지 않는다.
- 원본 matte에 붙은 투사체 조각을 캐릭터로 복구하지 않도록 기존 검수본의
  실루엣을 제한 영역으로 사용한다. 별도 탄/이펙트 시트는 유지한다.
- 같은 캐릭터의 모든 동작에 하나의 팔레트를 써서 프레임별 색 변화가 생기지 않게 한다.
- 전투의 크기 보정, 발 원점, 총구 좌표, 타격 시점, 재생 시간은 유지한다.
- `Art.unit_preview()`가 `art/portraits/<id>.png`를 먼저 읽는다. 전용 원화에는
  개별 선형 필터를 적용하고, 전투·UI의 기존 Nearest 기본 설정은 유지한다.
- 원화가 없으면 기존 idle 첫 프레임, 이후 정지 그림으로 대체한다.
- 상세창은 위쪽 안내 줄 일부까지 활용해 인물 표시 높이를 늘린다. 그림·설명·버튼은
  서로 겹치지 않는 영역에 둔다.

## 재실행

프로젝트 Python 환경의 Pillow, NumPy, SciPy를 사용한다. GPU 생성이나 외부 API 호출은
일반 재실행에 필요 없다. 입력은 `art/animation/last_refuge_v3_pixel_h3/`와
`art/portraits/sources/`이며, 이 입력에는 결과를 덮어쓰지 않는다.

```bash
# 3명만 미리 만들기: 게임 파일은 아직 교체하지 않음
python3 tools/sprite/readability.py --only niamh,solana,zero

# 50명 생성·검증 후 게임에 설치
python3 tools/sprite/readability.py --install

# 엔진 임포트, 원화/스프라이트 검사, 게임 회귀 검사
bash tools/verify.sh quick
```

원래 H3 설치 도구 `world_h3_to_game.py`를 다시 실행한 경우에도 뒤이어
`readability.py --install`을 실행한다. 처리된 시트를 다시 입력으로 삼지 않으므로
반복할수록 외곽선이 두꺼워지지 않는다.

- 실행 도구: `tools/sprite/readability.py`
- 게임 원화: `art/portraits/<id>.png`
- Niamh 고해상도 투명 입력: `art/portraits/sources/niamh.png`
- 교체 전 전투 파일: `build/readability/baseline/<id>/`
- 검증 후 설치할 파일: `build/readability/staged/<id>/`
- 처리 보고서: `build/readability/report.json`

`ToBe.png`의 배경 분리를 다시 해야 할 때는 기존 프로젝트의 CPU 도구를 사용한다.
아래 명령으로 만든 후보는 투명도와 무기·머리카락을 확인한 뒤 입력 파일로 복사한다.

```bash
/home/dgxmaruta/pjt/pixelforge/.venv/bin/python tools/sprite/world_matte.py \
  ToBe.png build/readability/tobe-matte.png
```

이미지 생성 도구도 투명 분리 후보를 한 번 만들었으나 RGB 체크무늬 배경을 출력해
사용하지 않았다. 최종 Niamh는 사용자의 원본 색과 픽셀을 보존한 직접 분리본이다.
사용한 built-in 도구의 프롬프트와 제외 사유는
`build/readability/imagegen-trial.json`에 남겼다. CLI 이미지 생성은 사용하지 않았다.

## 확인 자료

- [전후 비교](../build/readability/comparison.png)
- [실제 상세창 확대 비교](../build/readability/ui-comparison.png)
- [50명 애니메이션 비교: 캐릭터·동작·배경 선택](../build/readability/index.html)
- [게임의 Niamh 상세창](../build/readability/after/info_niamh.png)
- [1000×625 Niamh 상세창](../build/readability/phone/info_niamh.png)
- [전투 화면](../build/readability/after/battle12.png)

## 검증 결과

- 50명, 전투 1,000프레임 처리. 시트 크기, 투명도, 팔레트, 파일 해시, 잘림,
  전용 원화의 실제 알파와 엔진 임포트 검사: 지적 사항 0명.
- idle/attack 사이 발 높이 차이: 50명 모두 0px. 프레임별 발 영역 픽셀도 일치.
- 교체 전 메타데이터와 대조: 50명의 크기, 발 원점, 총구 좌표, 공격 타이밍 동일.
  별도 shot/effect 시트는 기존 해시와 일치.
- Niamh 재실행: 메타데이터, idle/attack, 전용 원화의 해시가 모두 동일.
- `bash tools/verify.sh quick`: 스프라이트 검사를 포함해 전체 통과. 자동 밸런스 검사는
  빠른 모드의 4판 표본이며, 전체 12판 검사는 이번 이미지 변경에서 수행하지 않았다.
- 엔진의 50명 원화 경로·개별 필터·세 가지 크기의 프레임 경계·원화 누락 대체 검사 통과.
  기존 상세창 텍스트/소개문 검사도 오류 0건, 소개문 최소 글꼴 17px.
- 실제 Godot 촬영: 1280×800 상세창 50명 및 목록/전투 2장,
  1000×625 Niamh/Zero/Protea 상세창 및 목록/전투 5장.
- APK 빌드·서명·ZIP 무결성 검사 성공. 전용 원화 50장이 APK에 포함되어 있고
  고해상도 입력 폴더 및 `ToBe.png`는 제외됨을 확인했다.
- 실제 Android 기기에 설치하여 터치·성능을 확인하는 검사는 수행하지 않았다.

APK: `/home/dgxmaruta/pokerdefense-test.apk` (105,507,116 bytes).
빌드와 무결성 검사가 성공한 파일만 이 고정 경로에 교체했다.
SHA-256: `d13946551d7a887b590e763238db94d48c1c785ed3010ced3b2bafe43729f5c9`.

로그: `build/readability-verify.log`, `build/readability-sprite-qc.log`,
`build/readability-layout.log`, `build/readability-shots.log`,
`build/readability-phone.log`, `build/readability-apk.log`.
