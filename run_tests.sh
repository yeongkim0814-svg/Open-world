#!/bin/sh
# 헤드리스 테스트 실행 (클라우드/PC 전용 — Android 에디터에서는 불가)
godot --headless --path . --import >/dev/null 2>&1
godot --headless --path . -s tests/run_tests.gd
