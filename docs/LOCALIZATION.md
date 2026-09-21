# 한영 표시

모든 화면 우측 상단의 `KOR / ENG` 두 버튼으로 언어를 고른다. 선택된 언어는 금색으로 강조한다. 기본값은 한국어다. 선택은 기존 저장 파일의
`opt.language`에 저장되며 진행 중인 판과 평생 기록을 보존한다. 이전 저장에 언어가
없거나 지원하지 않는 값이면 한국어로 연다.

앱 표시 이름은 한국어 `올인 디펜스`, 영어 `All-in Defense`다. Android/iOS 시스템 언어별 이름은 `project.godot`의 `application/config/name_localized`에서 지정하고, 게임 안 제목은 `I18n`을 따라 즉시 바뀐다. 기존 설치 업데이트와 저장 호환을 위해 패키지/번들 식별자와 저장 디렉터리는 유지한다. APK 산출물 이름도 사용자 지정 고정 경로를 유지한다.

## 데이터와 표시

- `core/i18n.gd`: `I18n` 자동 로드, 언어 선택·저장 연결과 번역 캐시.
- `core/locales/ui.json`: 한국어 원문과 영어 번역, 기존 영어 표기의 한국어 변환.
- `core/locales/heroes.json`: 50명 영웅의 짧은 한영 컨셉 소개.
- 이름은 기존 `Roster.UNITS`의 `ko / en`을 그대로 사용한다. ID는 번역하지 않는다.
- `Look`은 문자열을 번역한 뒤 폭·줄바꿈을 계산하고 그린다. 잘린 문자열을 번역하지 않는다.
- `SummonArt.hero_info`가 소환·합성·대기실 상세의 소개 구조를 공유한다.

동적 문구는 이미 값이 들어간 문자열을 `I18n.t`에 전달한다. 카탈로그 키에는 기존
`%d`, `%s`, `%.2f` 형식을 쓰고 번역에는 `{0}`, `{1}`처럼 인자 번호를 쓴다.
예: `명중 시 %.1f초 동안 이동속도 %s%% 감소` → `Hits slow by {1}% for {0}s`.
게임 숫자와 저장 데이터는 번역하지 않는다. 두 JSON 파일은 APK 내보내기 필터에 포함한다.

## 확인

```bash
python3 tools/check_localization.py
python3 tools/check_font.py
POCKER_NO_SAVE=1 godot --headless --path . res://tests/localization_check.tscn
python3 tools/ui_polish_review.py
```

첫 검사는 게임 코드의 번역 누락과 영웅 데이터·문구 인자를 확인한다. 두 번째는 번역
파일까지 포함해 번들 글꼴의 글리프를 검사한다. 언어 회귀 검사는 설정 복구, 동적 문구,
실제 Kor/Eng 버튼, 대기실 정보 열기·닫기와 배경 입력 차단을 확인한다.
시각 검수는 실제 Godot에서 1280×800 / 1000×625 화면을 한영으로 촬영한다.
`I18n.audit_enabled`를 켜면 영어 화면의 미번역 문자열이 `I18n.missing`에 기록된다.

APK는 성공한 새 파일로만 `/home/dgxmaruta/pokerdefense-test.apk`를 교체한다.
