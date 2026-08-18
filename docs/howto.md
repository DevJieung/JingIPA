# 개구리 용사 — 내 컴퓨터에서 실행하기

이 폴더는 **Godot 프로젝트 원본**입니다. Godot 편집기로 열어서 바로 실행할 수 있습니다.
(빌드된 실행 파일이 아니라 소스입니다. 그래서 Godot 을 먼저 설치해야 합니다.)

게임 화면은 **가로 태블릿 1280×800** 기준입니다. 세로로 열어도 배치가 알아서 바뀝니다.

---

## 1. Godot 4.7.1 설치

**반드시 4.7.x 버전**이어야 합니다. 이 프로젝트는 4.7 기능을 씁니다
(`project.godot` 의 `config/features` 에 `"4.7"` 이 박혀 있습니다).

- 다운로드: <https://godotengine.org/download/archive/4.7.1-stable/>
- 또는 GitHub 릴리스: <https://github.com/godotengine/godot/releases/tag/4.7.1-stable>

받을 파일은 **Godot Engine (표준 버전)** 입니다.
`.NET` / `Mono` 버전은 **필요 없습니다** (이 프로젝트에 C# 코드가 없습니다).

| OS | 받을 파일 | 비고 |
|---|---|---|
| Windows | `Godot_v4.7.1-stable_win64.exe.zip` | 압축 풀면 exe 하나. 설치 과정 없음 |
| macOS | `Godot_v4.7.1-stable_macos.universal.zip` | 아래 ★ 참고 |
| Linux | `Godot_v4.7.1-stable_linux.x86_64.zip` | 압축 푼 뒤 `chmod +x` |

★ **macOS**: 처음 실행하면 "확인되지 않은 개발자" 경고가 뜹니다.
Godot.app 을 **우클릭 → 열기** 로 한 번만 열어주면 이후로는 그냥 열립니다.
(그래도 막히면 `시스템 설정 → 개인정보 보호 및 보안` 맨 아래 **"확인 없이 열기"**)

---

## 2. 이 압축 파일 풀기

`frogwarrior.zip` 을 풀면 `frogwarrior/` 폴더가 나옵니다.
경로에 **한글이나 공백이 없는 곳**에 두는 걸 권합니다 (예: `C:\godot\frogwarrior`, `~/projects/frogwarrior`).

---

## 3. Godot 에서 열기

1. Godot 을 실행하면 **프로젝트 매니저**가 뜹니다.
2. 오른쪽 위 **가져오기(Import)** 버튼 클릭.
3. 방금 푼 폴더 안의 **`project.godot`** 파일을 선택 → **가져오기 후 편집(Import & Edit)**.

> 처음 열 때 하단에 "리소스 가져오는 중(Importing)" 진행 막대가 20~60초쯤 돕니다.
> 폰트·그림·소리를 캐시로 굽는 과정이고, **한 번만** 합니다.
> 이때 만들어지는 `.godot/` 폴더는 캐시라서 지워도 다시 생깁니다.

> ⚠️ **처음 열 때 출력창에 이런 빨간 줄 4개가 뜹니다. 정상입니다.**
> ```
> ERROR: Cannot open file 'res://.godot/imported/Jua-Regular.ttf-....fontdata'
> ERROR: Error loading custom project font 'res://assets/fonts/Jua-Regular.ttf'
> ```
> 한글 폰트(Jua)를 굽기 **전에** 테마가 그 폰트를 먼저 찾아서 나는 순서 문제입니다.
> 임포트가 끝나면 사라집니다. 다만 이 상태에서 바로 실행하면 **한글이 네모(□)로 나올 수 있으니**,
> 임포트 막대가 끝난 뒤 **편집기를 한 번 껐다 켜고** 실행하세요. 그 뒤로는 다시 안 납니다.

---

## 4. 실행

편집기가 열리면 오른쪽 위 **▶ (재생)** 버튼 또는 **F5**.

- 창은 가로 **1000 × 625** 로 뜹니다 (게임 해상도는 1280×800, 자동으로 맞춰 보여줍니다).
- 조작은 **마우스 클릭(= 탭)** 하나뿐입니다. 드래그·더블클릭 없습니다.
- 종료는 **F8** 또는 창 닫기.

첫 화면은 로딩 → 타이틀 → 지도 → 탄 선택 → 전투 순서입니다.

전투 화면은 **왼쪽이 '보는 곳'(문제와 블록 설명), 오른쪽이 '고르는 곳'(답 4개)** 입니다.

---

## 5. 자주 겪는 문제

| 증상 | 원인과 해결 |
|---|---|
| 글자가 전부 네모(□)로 깨짐 | ① 방금 처음 임포트한 직후라면 편집기를 껐다 켜세요 (위 ⚠️ 참고). ② 그래도 그러면 Godot 버전이 4.7 이 아닐 가능성이 큽니다. |
| "This project was last edited in a newer version" | Godot 이 4.7.1 보다 낮습니다. 4.7.1 을 받으세요. |
| 열자마자 오류가 쏟아짐 | 임포트가 안 끝난 상태입니다. 편집기를 닫았다 다시 여세요. `.godot/` 폴더를 지우고 다시 열면 확실합니다. |
| 화면이 검거나 그림이 안 보임 | 렌더러가 바뀌었을 수 있습니다. `프로젝트 설정 → 렌더링 → 렌더링 방법`이 **`gl_compatibility`** 여야 합니다. Forward+ 로 바꾸지 마세요. |
| 창이 세로로 뜸 | `프로젝트 설정 → 표시 → 창` 의 viewport 가 1280×800 인지 확인하세요. |
| 소리가 안 남 | 시스템 출력 장치 문제입니다. 게임 안에 음소거 토글이 있습니다. |

---

## 6. (선택) 자동 검증 돌려보기

프로젝트가 제대로 풀렸는지 확인하고 싶다면, 폴더 안에서:

```bash
# Windows (PowerShell) — Godot exe 경로는 각자 맞게
& "C:\godot\Godot_v4.7.1-stable_win64.exe" --headless --path . res://tests/test_runner.tscn

# macOS
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/test_runner.tscn

# Linux
./Godot_v4.7.1-stable_linux.x86_64 --headless --path . res://tests/test_runner.tscn
```

문제 생성 규칙, 가로/세로 배치 불변식, 기호 정렬, 번역 누락 등을 전부 훑습니다.
5~10분 걸리고, 마지막 줄에 통과 여부가 나옵니다.

---

## 7. (선택) 안드로이드/iOS 로 내보내기

`export_presets.cfg` 에 Android(APK/AAB), iOS, Web 프리셋이 들어 있습니다.
다만 **서명 키(keystore)와 인증서는 보안상 이 압축에 넣지 않았습니다.**
직접 내보내려면 `docs/build-android.md`, `docs/build-ios.md` 를 보고 본인 키를 새로 만들어 지정하세요.

또한 편집기 메뉴 **편집기 → 내보내기 템플릿 관리 → 다운로드** 로 4.7.1 템플릿을 한 번 받아야 합니다.

---

## 이 압축에 들어있지 않은 것

의도적으로 뺐습니다 (`tools/make_zip.py` 가 매번 걸러냅니다).

- `.godot/` — 임포트 캐시. **서명 비밀번호(`export_credentials.cfg`)가 들어있어서** 제외했습니다. 열면 자동 생성됩니다.
- `.certs/` — 개발용 자체 서명 인증서(개인 키).
- `build/` — 이전 익스포트 결과물. 필요하면 다시 내보내면 됩니다.

## 더 읽을거리

- [`README.md`](README.md) — 게임이 무엇이고 왜 이렇게 만들었는지
- [`docs/architecture.md`](docs/architecture.md) — 설계 근거
- [`CLAUDE.md`](CLAUDE.md) — 코드 고칠 때 깨면 안 되는 규칙들
