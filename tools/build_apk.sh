#!/usr/bin/env bash
set -euo pipefail

pocker_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
pocker_output="/home/dgxmaruta/pokerdefense-test.apk"
pocker_java="$pocker_root/build/toolchains/jdk17/bin/java"
pocker_sdk="/home/dgxmaruta/Android/SdkFlutter"
pocker_log="$pocker_root/build/android-admob.log"
pocker_config="$pocker_root/build/godot-config"
# Serialize exports because Godot and Gradle share generated project files.
exec 9> "$pocker_root/build/android-export.lock"
flock -n 9 || { echo 'Another APK export is already running.'; exit 1; }
pocker_stage="$(mktemp -d /home/dgxmaruta/.pokerdefense-build.XXXXXX)"
cleanup() {
    if [ -f "$pocker_stage/project.godot" ]; then
        cp -p -- "$pocker_stage/project.godot" "$pocker_root/project.godot"
    fi
    rm -rf -- "$pocker_stage"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
pocker_apk="$pocker_stage/pokerdefense-test.apk"

test -x "$pocker_java"
test -f "$pocker_config/godot/editor_settings-4.7.tres"
cp -p -- "$pocker_root/project.godot" "$pocker_stage/project.godot"
python3 "$pocker_root/tools/admob_config.py" --env "$pocker_root/.env" \
    --project "$pocker_root/project.godot"
XDG_CONFIG_HOME="$pocker_config" godot --headless --path "$pocker_root" \
    --export-debug "Android Test APK" "$pocker_apk" > "$pocker_log" 2>&1
cp -p -- "$pocker_stage/project.godot" "$pocker_root/project.godot"
rm -- "$pocker_stage/project.godot"
# ★ grep 이다 — rg(ripgrep)는 이 머신에 없다(Claude Code 셸 안에서만 함수로 있다).
if grep -Eq 'SCRIPT ERROR|ERROR:' "$pocker_log"; then
    tail -60 "$pocker_log"
    exit 1
fi
test -s "$pocker_apk"
"$pocker_java" -jar "$pocker_sdk/build-tools/36.0.0/lib/apksigner.jar" verify "$pocker_apk"
"$pocker_sdk/arm64-tools/aapt2" dump xmltree --file AndroidManifest.xml "$pocker_apk" \
    > "$pocker_stage/manifest.txt"
grep -q 'org.godotengine.plugin.v2.PoingGodotAdMobRewardedAd' "$pocker_stage/manifest.txt"
grep -q 'org.godotengine.plugin.v2.PoingGodotAdMobRewardedInterstitialAd' "$pocker_stage/manifest.txt"
grep -q 'com.google.android.gms.ads.APPLICATION_ID' "$pocker_stage/manifest.txt"
"$pocker_sdk/arm64-tools/aapt2" dump badging "$pocker_apk" > "$pocker_stage/badging.txt"
grep -Fq "application-label:'올인 디펜스'" "$pocker_stage/badging.txt"
grep -Fq "application-label-ko:'올인 디펜스'" "$pocker_stage/badging.txt"
grep -Fq "application-label-en:'All-in Defense'" "$pocker_stage/badging.txt"
python3 "$pocker_root/tools/admob_config.py" --env "$pocker_root/.env" \
    --apk "$pocker_apk" --manifest "$pocker_stage/manifest.txt"
python3 "$pocker_root/tools/audio/check_apk_audio.py" "$pocker_apk"
chmod 644 "$pocker_apk"
mv -f -- "$pocker_apk" "$pocker_output"
printf 'APK ready: %s\n' "$pocker_output"
