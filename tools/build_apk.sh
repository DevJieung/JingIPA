#!/usr/bin/env bash
set -euo pipefail

stellar_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
stellar_output="/home/dgxmaruta/stellardefense-test.apk"
stellar_java="$stellar_root/build/toolchains/jdk17/bin/java"
stellar_sdk="/home/dgxmaruta/Android/SdkFlutter"
stellar_log="$stellar_root/build/android-admob.log"
stellar_config="$stellar_root/build/godot-config"
# Serialize exports because Godot and Gradle share generated project files.
exec 9> "$stellar_root/build/android-export.lock"
flock -n 9 || { echo 'Another APK export is already running.'; exit 1; }
stellar_stage="$(mktemp -d /home/dgxmaruta/.stellardefense-build.XXXXXX)"
cleanup() {
    if [ -f "$stellar_stage/project.godot" ]; then
        cp -p -- "$stellar_stage/project.godot" "$stellar_root/project.godot"
    fi
    rm -rf -- "$stellar_stage"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
stellar_apk="$stellar_stage/stellardefense-test.apk"

test -x "$stellar_java"
test -f "$stellar_config/godot/editor_settings-4.7.tres"
cp -p -- "$stellar_root/project.godot" "$stellar_stage/project.godot"
python3 "$stellar_root/tools/admob_config.py" --env "$stellar_root/.env" \
    --project "$stellar_root/project.godot"
XDG_CONFIG_HOME="$stellar_config" godot --headless --path "$stellar_root" \
    --export-debug "Android Test APK" "$stellar_apk" > "$stellar_log" 2>&1
cp -p -- "$stellar_stage/project.godot" "$stellar_root/project.godot"
rm -- "$stellar_stage/project.godot"
# ★ grep 이다 — rg(ripgrep)는 이 머신에 없다(Claude Code 셸 안에서만 함수로 있다).
if grep -Eq 'SCRIPT ERROR|ERROR:' "$stellar_log"; then
    tail -60 "$stellar_log"
    exit 1
fi
test -s "$stellar_apk"
"$stellar_java" -jar "$stellar_sdk/build-tools/36.0.0/lib/apksigner.jar" verify "$stellar_apk"
"$stellar_sdk/arm64-tools/aapt2" dump xmltree --file AndroidManifest.xml "$stellar_apk" \
    > "$stellar_stage/manifest.txt"
grep -q 'org.godotengine.plugin.v2.PoingGodotAdMobRewardedAd' "$stellar_stage/manifest.txt"
grep -q 'org.godotengine.plugin.v2.PoingGodotAdMobRewardedInterstitialAd' "$stellar_stage/manifest.txt"
grep -q 'com.google.android.gms.ads.APPLICATION_ID' "$stellar_stage/manifest.txt"
"$stellar_sdk/arm64-tools/aapt2" dump badging "$stellar_apk" > "$stellar_stage/badging.txt"
grep -Fq "application-label:'스텔라 디펜스'" "$stellar_stage/badging.txt"
grep -Fq "application-label-ko:'스텔라 디펜스'" "$stellar_stage/badging.txt"
grep -Fq "application-label-en:'Stellar Defense'" "$stellar_stage/badging.txt"
python3 "$stellar_root/tools/admob_config.py" --env "$stellar_root/.env" \
    --apk "$stellar_apk" --manifest "$stellar_stage/manifest.txt"
python3 "$stellar_root/tools/audio/check_apk_audio.py" "$stellar_apk"
# 게임 데이터 DB(data/game.db)는 원본일 뿐 폰에 싣지 않는다 — 실렸으면 APK 를 교체하지 않는다.
python3 "$stellar_root/tools/ci/check_no_db.py" "$stellar_apk"
python3 "$stellar_root/tools/ci/check_stellar_assets.py" "$stellar_apk"
chmod 644 "$stellar_apk"
mv -f -- "$stellar_apk" "$stellar_output"
printf 'APK ready: %s\n' "$stellar_output"
