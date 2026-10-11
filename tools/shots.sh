#!/bin/sh
# 고정 시점 스크린샷. 사용: tools/shots.sh <tag> [grey|color|both|r0,r50,r100] [first_island|style_test]
# 결과: /tmp/claude-0/shots/<tag>_<view>_<mode>.png  (클라우드 세션 전용: xvfb + Mesa llvmpipe OpenGL, Compatibility)
cd "$(dirname "$0")/.." || exit 1
timeout 900 xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --resolution 1280x720 \
	-s tools/screenshot.gd -- "${1:-shot}" "${2:-both}" "${3:-first_island}" 2>&1 | grep -E "^saved|SCRIPT ERROR|ERROR: .*shader|WARNING: .*renderer"
