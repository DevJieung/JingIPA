#!/usr/bin/env bash
# 공룡섬 실행
cd "$(dirname "$0")" || exit 1
exec godot --path . "$@"
