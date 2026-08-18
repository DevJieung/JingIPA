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
- 개구리: **검사 159000개 이상 / 실패 0개**
- iOS Xcode 프로젝트 · Android APK 둘 다 ok

## 2. 화면을 고쳤으면 그림도 새로

```bash
~/.local/bin/godot --headless --path . res://tests/dino_dump.tscn -- --dump
python3 tools/dino/render_preview.py
python3 tools/screenshot.py hub:0 map:0 battle:8      # 허브·개구리는 Xvfb 로 실제 촬영
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
- **`/home/dgxmaruta/pjt/dino` 와 `/home/dgxmaruta/pjt/mathgame` 을 지우지 마라.**
  두 APK 가 git 어디에도 없어서, 통합 앱에 회귀가 생겼을 때 아이가 돌아갈 수 있는
  유일한 실행본이다. 몇 주 지나 안정되면 `~/attic/` 으로 옮겨라 — `rm -rf` 말고.
- **릴리스 키스토어는 아직 없다.** 서명은 `~/.local/share/godot/keystores/debug.keystore`
  하나이고 2053년까지 유효하다. 저장소 밖에만 있으니 백업을 확인할 것.
