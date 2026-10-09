# 작업 완료 검사

기능·디자인 작업 후 다음 검증을 마친다. 현재 규칙은 `AGENTS.md`,
`docs/DESIGN_SYSTEM.md`, `docs/GAME_DB.md`, `docs/MOBILE_BUILDS.md`를 따른다.

1. `python3 tools/gamedb.py status`로 데이터 변경을 확인한다. DB 변경은 목록을
   사용자에게 보여 주고 승인받은 뒤에만 `apply --approved`로 내린다.
2. `tools/verify.sh` 전체를 실행해 `전부 통과`를 확인한다. 작업 중에는 `quick`으로
   좁혀 볼 수 있지만 최종적으로 전체 검증을 수행한다. 실패 로그는
   `build/verify-failure/`에 남으며, 실패를 성공으로 보고하지 않는다.
3. 디자인 담당이 실제 Godot 렌더링을 1280×800과 1000×625에서 확인한다.
   한영 텍스트, 버튼 상태·터치, 모달 겹침, 3D 모델과 움직임을 검수한다.
   `tests/arena_visual_review.py`가 현재 연속 전장의 검수 경로다.
4. APK는 `tools/build_apk.sh`로 생성한다. 서명, 광고 SDK/권한 부재, DB 제외,
   3D 에셋·오디오 포함 검사가 모두 성공한 파일만 `/home/dgxmaruta/sd-tst.apk`로 교체한다.
5. Git diff에서 관련 변경만 확인하고 진행 중인 사용자 작업·원본을 보존한다.
   `.env`, 인증서, SDK, 로컬 캐시와 생성용 대용량 원본을 추가하지 않는다.
6. `stellardefense` 전용 브랜치에 반영한다. 워크플로를 바꿨다면 `main`에는
   `.github/workflows/stellardefense.yml`만 동기화해 기존 게임을 보존한다.
   푸시 후 APK와 IPA 동시 빌드 결과를 확인하고, 미완료/실패는 정확히 알린다.

최종 전달에는 변경 내용, 실제 실행한 검사, APK 고정 경로, 남은 검증 한계를 적는다.
Android/iOS 실기기에서 실행하지 않았다면 실제 기기 검수로 표현하지 않는다.
