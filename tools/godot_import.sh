#!/usr/bin/env bash
# Godot 리소스 임포트(GLB·텍스처·셰이더)를 한 번에 하나만 돌린다.
# 여러 작업자가 동시에 --import 를 돌리면 .godot/imported 가 서로 덮인다.
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-$HOME/.local/bin/godot}"
mkdir -p build
exec 9> build/godot-import.lock
flock 9
STELLARDEFENSE_NO_SAVE=1 timeout --signal=TERM --kill-after=20 900 \
	"$GODOT" --headless --editor --import --path . --quit "$@"
