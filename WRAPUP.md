# WRAPUP — 작업을 마칠 때

이 순서 그대로. 하나라도 깨졌으면 push 하지 말고 보고할 것.

## 1. 검증

```bash
tools/verify.sh
```

`전부 통과` 가 나와야 한다. 급할 때는 `tools/verify.sh quick`(개구리 전체 검사 생략,
약 3분)을 쓰되, **push 전에는 반드시 전체를 한 번 돌린다.**

기대값:
- 전역 이름 규칙: 이상 없음
- 화면에 쓰는 모든 문자가 폰트에 있습니다
- 자동 생성 7~200탄: **마릿수부족 0건, 가림한계이탈 0건**
- 자동 테스트: **30탄까지 진행**
- 손전등 찾기: **축한계이탈 0건, 어둠속탭 0건, 먹힌탭 0곳, 플레이실패 0건** (`판정: 정상`)
- 참참참: **못읽을버릇 0건, 플레이실패 0건** (`판정: 정상`)
- 세션 상한: **구간마다 같은 방 수** (미취학 `[4, 4]` · 초등 `[7, 7]`) — `[4, 1]` 이면
  쉼표가 아니라 자물쇠다 (규칙 30)
- 개구리: **검사 159000개 이상 / 실패 0개**
- 셸에 가드 없는 `await ....finished` 없음 (규칙 16)
- iOS Xcode 프로젝트 · Android APK 둘 다 ok

## 2. 화면을 고쳤으면 그림도 새로

```bash
~/.local/bin/godot --headless --path . res://tests/dino_dump.tscn -- --dump
python3 tools/dino/render_preview.py
python3 tools/screenshot.py hub:0 torch:1 cham:1 title:0 map:0      # Xvfb 로 실제 촬영
python3 tools/theme/gen_theme.py --icons                            # 아이콘을 고쳤으면
```

**눈으로 한 번 봐라.** 무언가가 가려지거나 겹치는 문제는 테스트로 안 잡힌다.

## 3. APK 굽기 (매번)

```bash
mkdir -p build/android && ~/.local/bin/godot --headless --path . \
    --export-debug "Android Test APK" "$PWD/build/android/rogame-test.apk"
cp build/android/rogame-test.apk ~/rogame-test.apk
```

답변 끝에 내려받는 방법까지 적을 것:

```bash
scp dgxmaruta@<호스트>:~/rogame-test.apk .
adb install -r rogame-test.apk
```

- `cannot connect to daemon at tcp:5037` 은 폰이 안 붙어 있어서 나는 것이라 오류가 아니다.
  `[ DONE ] export` 와 `Signed` 가 보이면 성공.
- **APK 가 안 나오면 조용히 넘어가지 말고 왜 실패했는지 말할 것.**

## 4. 커밋 & push

```bash
git add -A && git commit -m "..." && git push
```

`git push` 는 다시 묻지 말고 하라 — 이 문서가 그 허락이다.
단, 1번이 하나라도 깨졌으면 push 하지 말고 보고할 것.

원격은 **<https://github.com/DevJieung/JingIPA>** (`origin`, 퍼블릭) 하나다.
자격증명은 `~/.ghtoken` (600) 의 fine-grained 토큰이고, 전역 git 설정의
`credential.https://github.com.helper` 가 그 파일을 읽어 넘긴다. 그래서 그냥 `git push`
하면 된다. `github.com` 에만 걸려 있어 다른 호스트로는 안 샌다.

- ⚠ **토큰을 화면에 찍지 마라.** git·curl 출력은 반드시 걸러라:
  `... 2>&1 | sed 's/github_pat_[A-Za-z0-9_]*/<토큰>/g'`
- 인증이 실패하면 **먼저 토큰부터** 본다 (없거나 만료). 헬퍼만 따로 시험할 수 있다:
  `printf 'protocol=https\nhost=github.com\n\n' | git credential fill`
  토큰이 죽었으면 **사용자에게 본인 터미널에서** 갈아 달라고 요청한다 —
  `read -rs T && printf '%s' "$T" > ~/.ghtoken && chmod 600 ~/.ghtoken && unset T`
  (이 세션에서 붙여넣으면 대화 기록에 남는다. 실제로 한 번 그렇게 노출돼 폐기했다.)
- 이 셸에는 터미널이 없다(`tty` 없음). 게다가 물려받은 `GIT_ASKPASS` 가 죽은 VS Code
  소켓을 가리켜 `ECONNREFUSED` 로 즉사한다 — **대화형 로그인은 원천적으로 불가능**하고
  파일 기반 헬퍼가 유일한 길이다.

## 5. 아이폰용 IPA 굽기 (아이폰에 넣을 때만)

이 머신은 aarch64 라 IPA 를 못 굽는다. **GitHub Actions 의 맥 러너**가 굽는다.
푸시가 끝났으면 실행을 걸고 결과까지 확인한다. **약 2분**이면 끝난다
(우분투에서 Xcode 프로젝트 73초 + 맥에서 `xcodebuild` 46초).

⚠ **토큰을 `curl -H "Authorization: Bearer $T"` 로 넘기지 마라.** 그러면 토큰이
**프로세스 인자**에 올라가서 `ps` · `pgrep -af` 로 이 머신의 누구에게나 보인다
(실제로 물렸다 — 진행 상황을 보려고 `pgrep -af` 를 쳤다가 토큰이 통째로 찍혔고
그 토큰을 폐기해야 했다). 아래 `gh_api` 처럼 **stdin 으로** 넘겨라.
`git push` 쪽은 안전하다 — credential 헬퍼가 파일을 읽어 git 의 stdin 으로 준다.

```bash
# 토큰을 명령 인자에 올리지 않는 GitHub API 호출
gh_api() {  # gh_api <URL> [curl 옵션...]
  local url="$1"; shift
  printf 'header = "Authorization: Bearer %s"\n' "$(cat "$HOME/.ghtoken")" \
    | curl -sS --config - "$@" "$url"
}
API=https://api.github.com/repos/DevJieung/JingIPA

# (1) 실행을 건다 — 204 면 성공 (응답 본문이 없고 run id 도 안 온다)
gh_api "$API/actions/workflows/ios.yml/dispatches" -w "\nHTTP %{http_code}\n" \
  -X POST -H "Accept: application/vnd.github+json" \
  -d '{"ref":"main","inputs":{"build_type":"release"}}'

# (2) 그래서 방금 걸린 실행을 목록에서 찾는다 (몇 초 걸린다)
sleep 8
RUN=$(gh_api "$API/actions/runs?per_page=1" \
      | python3 -c "import json,sys;print(json.load(sys.stdin)['workflow_runs'][0]['id'])")
echo "run id = $RUN"

# (3) 끝날 때까지 기다린다
#     ★ foreground sleep 은 이 하네스에서 막혀 있다 — run_in_background 로 돌려라
until [ "$(gh_api "$API/actions/runs/$RUN" \
    | python3 -c 'import json,sys;print(json.load(sys.stdin)["status"])')" = completed ]; do
  sleep 20
done
gh_api "$API/actions/runs/$RUN" \
  | python3 -c "import json,sys;d=json.load(sys.stdin);print(d['status'],d['conclusion'],d['html_url'])"
```

실패했으면 잡·스텝별로 어디서 죽었는지 본다:

```bash
gh_api "$API/actions/runs/$RUN/jobs" | python3 -c "
import json,sys
for j in json.load(sys.stdin)['jobs']:
    print('[%s] %s/%s' % (j['name'], j['status'], j['conclusion']))
    for st in j['steps']: print('   ', st['conclusion'], st['name'])"
```

워크플로가 실패 원인을 `$GITHUB_STEP_SUMMARY` 에 `error:` 줄과 마지막 60줄로 남기게
돼 있으니, 그것도 실행 화면 맨 위에서 읽을 수 있다.

**초록불만 보고 넘어가지 마라 — 받아서 안을 연다.** 이 머신에는 화면이 없으므로
IPA 가 제대로 됐는지 확인할 방법이 이것뿐이다. 41MB 라 내려받는 데 2분이 넘을 수 있으니
**background 로 돌려라**:

```bash
cd "$(mktemp -d)"
ID=$(gh_api "$API/actions/runs/$RUN/artifacts" \
     | python3 -c "import json,sys;print([a['id'] for a in json.load(sys.stdin)['artifacts'] if a['name'].startswith('rogame-ipa')][0])")
gh_api "$API/actions/artifacts/$ID/zip" -L -o art.zip
unzip -q art.zip && unzip -q ./*.ipa -d ipa
python3 -c "
import plistlib
d = plistlib.load(open('ipa/Payload/DinoIsland.app/Info.plist','rb'))
for k in ['CFBundleIdentifier','CFBundleName','CFBundleShortVersionString',
          'MinimumOSVersion','UIDeviceFamily','UISupportedInterfaceOrientations']:
    print('%-30s %s' % (k, d[k]))"
file ipa/Payload/DinoIsland.app/DinoIsland
ls ipa/Payload/DinoIsland.app/_CodeSignature 2>/dev/null || echo "서명 없음 (Secrets 없으면 정상)"
```

기대값: `com.devjieung.dinoisland` · `DinoIsland` · `14.0` · `[1, 2]`(아이폰+아이패드) ·
`Mach-O 64-bit arm64`. **`_CodeSignature` 가 없는 것이 정상**이다 — 서명 Secrets 를
안 넣었으면 서명 없는 IPA 로 나오고, Sideloadly/AltStore 로 직접 서명해 넣는다.

받는 곳은 실행 화면 맨 아래 **Artifacts → `rogame-ipa-<번호>`** (40MB, 30일 보관).
답변에 그 주소를 적어라.

### 토큰 권한 — 이것 때문에 두 번 막혔다

fine-grained 토큰, JingIPA 하나만, **셋 다** 필요하다:

| 권한 | 없으면 |
|---|---|
| **Contents** (RW) | 아예 push 가 안 된다 |
| **Workflows** (RW) | `.github/workflows/*` 를 건드리는 **푸시가 통째로 거부된다** (`refusing to allow a Personal Access Token to create or update workflow ... without workflow scope`) — 다른 파일까지 같이 막힌다 |
| **Actions** (RW) | 위 (1) 이 `403 Resource not accessible by personal access token` 으로 막힌다. 사람이 Actions 탭에서 직접 눌러야 한다 |

⚠ 저장소 API 가 돌려주는 `permissions: {admin: true, ...}` 는 **계정의 역할**이지
토큰의 범위가 아니다. 토큰이 admin 이라는 뜻으로 읽지 마라.

### 서명된 IPA 로 올라가려면

Secrets 넷(`IOS_TEAM_ID` · `IOS_P12_BASE64` · `IOS_P12_PASSWORD` ·
`IOS_MOBILEPROVISION_BASE64`) + Variables 셋을 저장소에 넣으면 워크플로가 알아서
서명 경로로 간다. 순서는 [`docs/ios-signing.md`](docs/ios-signing.md).
태그를 올리면(`git tag v1.0.0 && git push origin v1.0.0`) Releases 에 IPA 가 붙는다.

---

## 절대 잊으면 안 되는 것

- **기존 두 앱(`com.example.dinofind` / `com.example.frogwarrior`)을 폰에서 지우지 마라.**
  통합 앱은 패키지가 달라 나란히 깔린다. 아이의 진짜 기록은 아직 그 두 앱 안에만 있고,
  패키지가 다르면 코드로 읽을 방법이 원천적으로 없다.
- **폰이 붙어 있을 때 옛 기록을 꺼내 둬라.** 두 APK 다 디버그 서명이라 `run-as` 가 먹는다.

  ```bash
  export PATH="$PATH:$HOME/Android/Sdk/platform-tools"
  mkdir -p ~/backup-before-rogame/kid-save
  adb exec-out run-as com.example.dinofind    cat files/dino_save.cfg \
      > ~/backup-before-rogame/kid-save/dino_save.cfg
  adb exec-out run-as com.example.frogwarrior cat files/save.json \
      > ~/backup-before-rogame/kid-save/save.json
  test -s ~/backup-before-rogame/kid-save/save.json || echo "!! 백업 실패"
  ```

  꺼낸 뒤 통합 앱에 넣으려면 (통합 앱도 디버그 APK 일 때):

  ```bash
  adb shell run-as com.devjieung.dinoisland sh -c 'cat > files/save.json' \
      < ~/backup-before-rogame/kid-save/save.json
  adb shell run-as com.devjieung.dinoisland sh -c 'cat > files/dino_save.cfg' \
      < ~/backup-before-rogame/kid-save/dino_save.cfg
  ```

  통합 앱이 첫 실행에서 이 둘을 읽어 v3 로 옮긴다. **원본은 지우지 않는다.**
- **`~/backup-before-rogame/JingIPA-old-41863049.bundle` 을 지우지 마라.** JingIPA 는
  2026-08-20 에 force push 로 갈아엎기 전까지 **다른 프로젝트**(개구리 용사 standalone)를
  담고 있었고, 그 저장소 전체가 이 번들 하나에만 남아 있다 (`git clone <번들>` 로 복원).
- **`/home/dgxmaruta/pjt/dino` 와 `/home/dgxmaruta/pjt/mathgame` 을 지우지 마라.**
  두 APK 가 git 어디에도 없어서, 통합 앱에 회귀가 생겼을 때 아이가 돌아갈 수 있는
  유일한 실행본이다. 몇 주 지나 안정되면 `~/attic/` 으로 옮겨라 — `rm -rf` 말고.
- **릴리스 키스토어는 아직 없다.** 서명은 `~/.local/share/godot/keystores/debug.keystore`
  하나이고 2053년까지 유효하다. 저장소 밖에만 있으니 백업을 확인할 것.
