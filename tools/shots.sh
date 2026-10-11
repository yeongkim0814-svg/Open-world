#!/bin/sh
# 고정 시점 스크린샷 4곳 × (회복 전/후). 사용: tools/shots.sh <tag> [grey|color|both]
# 결과: /tmp/claude-0/shots/<tag>_<view>_<grey|color>.png  (클라우드 세션 전용: xvfb + lavapipe Vulkan)
cd "$(dirname "$0")/.." || exit 1
timeout 900 xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver vulkan --resolution 1280x720 \
	-s tools/screenshot.gd -- "${1:-shot}" "${2:-both}" 2>&1 | grep -E "^saved|SCRIPT ERROR|ERROR: .*shader" 
