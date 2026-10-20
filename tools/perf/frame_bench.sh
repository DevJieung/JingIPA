#!/usr/bin/env bash
# Frame cost of the live arena by part (tests/perf/arena_frame_bench.gd, docs/PERF_NATIVE.md).
#
#   tools/perf/frame_bench.sh [stage] [frames]      default: stage 10, 2400 frames (40 s)
#
# Needs a display with a GPU: the login session's Xorg (:1, NVIDIA) when it is up, else
# this fails (Xvfb's software GL would measure the renderer, not the scripts). The game
# runs on the phone-class A725 cores (taskset) at a fixed 60 Hz step as fast as it can.
set -euo pipefail
cd "$(dirname "$0")/../.."
GODOT="${GODOT:-$HOME/.local/bin/godot}"
stage="${1:-10}"
frames="${2:-2400}"
auth="/run/user/$(id -u)/gdm/Xauthority"
if [ ! -f "$auth" ] || ! DISPLAY=:1 XAUTHORITY="$auth" xdpyinfo > /dev/null 2>&1; then
	echo "no GPU display at :1 (login session Xorg); see docs/PERF_NATIVE.md"; exit 1
fi
DISPLAY=:1 XAUTHORITY="$auth" STELLARDEFENSE_NO_SAVE=1 \
	taskset -c "${BENCH_CORES:-0-4,10-14}" "$GODOT" --path . --disable-vsync --fixed-fps 60 --max-fps 0 \
	--audio-driver Dummy --resolution 320x200 res://tests/perf/arena_frame_bench.tscn -- --stage "$stage" --frames "$frames" 2>&1 \
	| grep -v '^$' | grep -A20 '^BENCH\|SCRIPT ERROR'
