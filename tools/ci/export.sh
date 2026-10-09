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
export STELLARDEFENSE_NO_SAVE=1
python3 tools/gamedb.py check
python3 tools/gen_roster.py --check
python3 tools/check_localization.py
python3 -m unittest discover -s tests -p test_check_no_ads.py
for scene in arena_check arena_camera_check arena_route_check arena_pose_check arena_play_check stellar_identity_check stellar_gameplay_check 3d/stellar_render_check limne_model_check native_hero_check native_monster_check formation_check free_placement_check rite_check reroll_check flow_check rules_check progression_check wave_scaling_check course_check localization_check no_ads_check; do
    log="build/ci/${scene//\//-}.log"
    checked_godot "$log" "res://tests/$scene.tscn"
    grep -q '판정: 정상' "$log"
done

checked_godot build/ci/ios-export.log --export-release iOS "$PWD/build/ios/StellarDefense.ipa"
test -s build/ios/StellarDefense.xcodeproj/project.pbxproj
test -s build/ios/StellarDefense.pck
# The data DB (data/game.db) is authoring-only and must never ship.
python3 tools/ci/check_no_db.py build/ios/StellarDefense.pck
checked_godot build/ci/stellar-pack.log --main-pack "$PWD/build/ios/StellarDefense.pck" --script "$PWD/tools/ci/check_stellar_pack.gd"
checked_godot build/ci/stellar-packed-boot.log --main-pack "$PWD/build/ios/StellarDefense.pck" --quit-after 90
tar -czf build/ci/ios-project.tar.gz -C build ios

checked_godot build/ci/android-export.log --export-debug "Android Test APK" "$PWD/build/apk/sd-tst.apk"
apk="$PWD/build/apk/sd-tst.apk"
test -s "$apk"
"$ANDROID_HOME/build-tools/36.0.0/apksigner" verify "$apk"
"$ANDROID_HOME/build-tools/36.0.0/aapt2" dump xmltree --file AndroidManifest.xml "$apk" > build/ci/manifest.txt
python3 tools/ci/check_no_ads.py "$apk" --manifest build/ci/manifest.txt
python3 tools/audio/check_apk_audio.py "$apk"
python3 tools/ci/check_no_db.py "$apk"

python3 tools/ci/check_stellar_assets.py "$apk"
