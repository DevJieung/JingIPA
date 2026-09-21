#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p build/ci build/ios build/apk

checked_godot() {
    local log="$1"
    shift
    "$GODOT" --headless --path . "$@" 2>&1 | tee "$log"
    if grep -Eq 'SCRIPT ERROR|ERROR:|Parse Error|Compile Error' "$log"; then
        echo "::error::Godot reported errors; see $log"
        return 1
    fi
}

# On a fresh checkout Godot loads the configured theme font/translations before
# importing them. Bootstrap once, then require a completely clean second pass.
"$GODOT" --headless --path . --import 2>&1 | tee build/ci/import-bootstrap.log
if grep -Eq 'SCRIPT ERROR|Parse Error|Compile Error' build/ci/import-bootstrap.log; then
    exit 1
fi
checked_godot build/ci/import.log --import
export POCKER_NO_SAVE=1
for scene in flow_check localization_check ads_check; do
    checked_godot "build/ci/$scene.log" "res://tests/$scene.tscn"
    grep -q '판정: 정상' "build/ci/$scene.log"
done

checked_godot build/ci/ios-export.log --export-release iOS "$PWD/build/ios/AllInDefense.ipa"
test -s build/ios/AllInDefense.xcodeproj/project.pbxproj
test -s build/ios/AllInDefense.pck
tar -czf build/ci/ios-project.tar.gz -C build ios

checked_godot build/ci/android-export.log --export-debug "Android Test APK" "$PWD/build/apk/pokerdefense-test.apk"
apk="$PWD/build/apk/pokerdefense-test.apk"
test -s "$apk"
"$ANDROID_HOME/build-tools/36.0.0/apksigner" verify "$apk"
"$ANDROID_HOME/build-tools/36.0.0/aapt2" dump xmltree --file AndroidManifest.xml "$apk" > build/ci/manifest.txt
grep -q 'org.godotengine.plugin.v2.PoingGodotAdMobRewardedAd' build/ci/manifest.txt
grep -q 'org.godotengine.plugin.v2.PoingGodotAdMobRewardedInterstitialAd' build/ci/manifest.txt
grep -q 'com.google.android.gms.ads.APPLICATION_ID' build/ci/manifest.txt
python3 tools/audio/check_apk_audio.py "$apk"
