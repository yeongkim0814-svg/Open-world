#!/bin/sh
# 헤드리스 테스트 실행 (클라우드/PC 전용 — Android 에디터에서는 불가)
# 테스트 중 런타임 오류(SCRIPT ERROR)는 해당 테스트를 조용히 중단시키므로, 로그에서 감지해 실패로 처리한다.
godot --headless --path . --import >/dev/null 2>&1
out=$(godot --headless --path . -s tests/run_tests.gd 2>&1)
code=$?
echo "$out"
if echo "$out" | grep -q "SCRIPT ERROR"; then
	echo "FAILED: 테스트 중 런타임 오류(SCRIPT ERROR) 발생 — 위 로그 확인"
	exit 1
fi
exit $code
