#!/usr/bin/env bash
# stellar_native (addons/stellar_native) — the C++ kernels, built with godot-cpp.
#
#   tools/native/build.sh            this machine's Linux library (tests, the editor)
#   tools/native/build.sh android    the arm64-v8a library the APK ships
#   tools/native/build.sh all        both
#
# godot-cpp is fetched once at the pinned commit into build/native/godot-cpp (not in Git).
# Needs scons (uv tool install scons / pipx install scons), g++ for Linux and the Android
# NDK of docs/MOBILE_BUILDS.md (ANDROID_HOME, NDK_VERSION) for Android.
set -euo pipefail
cd "$(dirname "$0")/../.."

GODOT_CPP_COMMIT=2bb1acf6f8ae1ce96ac7b9ba3a10b499c59c49ec
GODOT_CPP_DIR=build/native/godot-cpp
JOBS="${JOBS:-$(nproc)}"
NDK_VERSION="${NDK_VERSION:-28.2.13676358}"
ANDROID_HOME="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/SdkFlutter}}"

what="${1:-linux}"
case "$what" in
	linux|android|all) ;;
	*) echo "usage: tools/native/build.sh [linux|android|all]"; exit 2 ;;
esac
command -v scons > /dev/null || { echo "scons is missing (uv tool install scons)"; exit 1; }

mkdir -p build/native
if [ ! -f "$GODOT_CPP_DIR/.stellar_commit" ] || [ "$(cat "$GODOT_CPP_DIR/.stellar_commit")" != "$GODOT_CPP_COMMIT" ]; then
	echo "fetching godot-cpp $GODOT_CPP_COMMIT"
	rm -rf "$GODOT_CPP_DIR"
	mkdir -p "$GODOT_CPP_DIR"
	git -C "$GODOT_CPP_DIR" init -q
	git -C "$GODOT_CPP_DIR" fetch -q --depth 1 https://github.com/godotengine/godot-cpp.git "$GODOT_CPP_COMMIT"
	git -C "$GODOT_CPP_DIR" checkout -q FETCH_HEAD
	test "$(git -C "$GODOT_CPP_DIR" rev-parse HEAD)" = "$GODOT_CPP_COMMIT"
	echo "$GODOT_CPP_COMMIT" > "$GODOT_CPP_DIR/.stellar_commit"
fi

if [ "$what" = linux ] || [ "$what" = all ]; then
	case "$(uname -m)" in
		x86_64) arch=x86_64 ;;
		aarch64|arm64) arch=arm64 ;;
		*) echo "unsupported host architecture $(uname -m)"; exit 1 ;;
	esac
	scons -C native -j"$JOBS" platform=linux arch="$arch" target=template_release build_profile=build_profile.json
	test -s "addons/stellar_native/bin/libstellar_native.linux.template_release.$arch.so"
fi
if [ "$what" = android ] || [ "$what" = all ]; then
	test -d "$ANDROID_HOME/ndk/$NDK_VERSION" || { echo "Android NDK $NDK_VERSION not found under $ANDROID_HOME/ndk"; exit 1; }
	ANDROID_HOME="$ANDROID_HOME" scons -C native -j"$JOBS" platform=android arch=arm64 target=template_release ndk_version="$NDK_VERSION" build_profile=build_profile.json
	test -s addons/stellar_native/bin/libstellar_native.android.template_release.arm64.so
fi
echo "stellar_native ready: $what"
