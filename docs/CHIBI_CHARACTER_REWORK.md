# 큰 얼굴·짧은 체형 캐릭터 개편

2026-10-07 사용자 요청: 얄상한 캐릭터들을 짜리몽땅하게, 얼굴을 크게 만들어 작은
스프라이트에서도 특징이 보이게 한다. 영웅 50명·몬스터 25종·안내자 1명 전체를 교체했다.
합성 수호자는 `base_id`의 같은 새 원화를 재사용한다.

## 제작 기준과 계약

- 기존 캐릭터 원본을 built-in imagegen으로 직접 편집했다. 영웅은 약 2.6등신, 큰 머리와
  넓은 몸통·짧고 두꺼운 팔다리를 기준으로 기존 머리색·복장·장비·속성을 보존했다.
- 대기·공격과 별도 원화는 같은 편집 원본에서 추출한다. 원화는 고해상도 원본 픽셀을
  사용하고, 전투 시트만 Nearest 축소·공통 96색·이진 알파로 정리한다. 기본 Nearest와
  원화 전용 필터 예외는 바꾸지 않았다.
- 영웅 idle 8장/attack 12장, 몬스터 기존 13~25장, 모든 프레임 시간·loop·hit_frame·hit_ms와
  월드 스케일은 유지했다. 몬스터는 새 이동 8포즈를 기존 시간표에 순방향으로 배치한다.
- 넓은 무기를 자르지 않도록 필요한 경우 캔버스만 확장한다. 영웅 발 원점은 기본
  `(128,224)`, Marea `(138,224)`, Brasa `(143,224)`, Sigrid `(146,224)`이다.
  총구는 새 공격 원본의 발사점에서 다시 측정하고 현재 발 원점 기준으로 환산했다.
  명시적 계약은 `tests/chibi_sprites_contract.json`, 원본 측정점은
  `tools/sprite/chibi_landmarks.json`에 있다. 기존 shot/effect 그림은 유지했다.
- 안내자 `art/ui/dealer/witch.png`도 같은 비례로 수정했다. `SummonArt.GUIDE_CENTER`
  `(628,625)`와 반경 `260`은 새 얼굴과 달 장식을 담고 카드 든 손을 제외하는 크롭이다.

## 파일과 재현

- `art/chibi-manifest.json`: 76종의 입력·프롬프트·생성 출력과 현재 251개 PNG/75개 메타데이터의
  전체 경로·SHA-256. 최초 Limne 표본의 프롬프트는 요약임을 명시했고 이후 프롬프트는 전문이다.
- `art/animation/chibi_v1/source/`: 76종 편집 원본 및 생성 JSON. `previous/`에는 교체 전 원본을
  보존했다. 이 대용량 입력 폴더는 Git 제외 대상이며 최종 게임 PNG와 manifest만 배포한다.
- `tools/sprite/chibi_pack.py`: 알파 정리·행/열 분리·공통 팔레트·발 정렬·원화 추출.
  기존 사용자 로스터 변경을 보존하기 위해 로스터를 자동 재생성하지 않는다.
- `tools/sprite/chibi_report.py`: 76종 누락·파일 해시·규격·투명도·잘림·동작 계약 검사와
  전체 목록/전후 비교 합본 생성. `tests/chibi_preview.tscn`은 실제 Godot 캐릭터·UI 촬영용이다.

```bash
python3 tools/sprite/chibi_report.py
python3 tools/sprite/qc_game.py --json build/chibi-review/qc-heroes.json
python3 tools/chibi_design_review.py
python3 tools/sprite/roster_preview.py --ids brasa,sigrid,marea,glaukos,caden,dummy,finn,snorri,jokull,helga,lugh,grey --group chibi-full-battle
```

원본 보관 폴더가 있는 환경에서만 재패킹한다. PNG를 바꿨다면 Godot 임포트와 총구 데이터
동기화·계약 검사 후 빌드한다. 이전 `readability.py --install`, H3/roster 패커로 덮어쓰지 않는다.

## 검수 결과

- 자체 전수 검사: 76종 누락 없음, 배우 1,436프레임 정상. 영웅 50명 sprite QC 지적 0명,
  발 높이 편차 최대 1px. 몬스터 25종 모두 서로 다른 이동 포즈 8개를 포함한다.
- 부모 통합 검사: 영웅 계약 2,085건, 장판 공격 118건, 몬스터 검사 9건 모두 통과했다.
- 1280×800/1000×625 실제 Godot에서 전체 영웅·몬스터 16장 연속 프레임, 한국어/영문
  안내자·12명 편성·영웅 카드·넓은 장비 5명 상세창을 촬영했다. 큰 얼굴/무기 식별,
  대기와 공격 사이 체형·발 정렬, 초상화 크롭과 작은 화면 텍스트·버튼 영역을 직접 확인했다.
- 넓은 장비 영웅으로 12자리를 채운 실제 전투에서도 얼굴·별·도로·전투 UI 읽힘을 확인했다.
  물리 Android 기기의 터치·성능 검사는 수행하지 않았다.

검수 자료:

- `build/chibi-review/before-after.png`, `heroes.png`, `monsters.png`
- `build/chibi-review/coverage.json`, `qc-heroes.json`, `qc-heroes.log`
- `build/chibi-review/{1280x800,1000x625}/`: `heroes_00..15.png`, `monsters_00..15.png`,
  `heroes.gif`, `monsters.gif`, `*_motion_row_*.png`, `ko_guide.png`, `en_guide.png`,
  `*_formation_full.png`, `*_cards.png`, `*_detail_*.png`
- `build/all-hero-sprites/chibi-full-battle/{1280x800,1000x625}/battle_00..13.png`

새 `chibi_preview`의 두 해상도 실행은 모두 정상 종료했다. 기존 roster preview는 캡처 완료 후
종료 시 리소스 정리 경고가 있었으며 `build/chibi-review/full-battle.log`에 그대로 남겼다.
