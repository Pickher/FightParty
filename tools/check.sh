#!/usr/bin/env bash
# 中文导读：一条命令跑完全部自动测试：资源导入、规则模拟、兵种编辑器、界面冒烟、战报重放与 Excel 导入器。
# 用法：tools/check.sh [--perf]。Godot 路径用环境变量 GODOT 指定，默认在 PATH 中找 godot / godot4。
# --perf 额外运行 crowd_perf（满兵营 3 波，约 3 分钟）与 render_perf（打开渲染窗口采样 10 秒）。
# 每项日志写到 build/check-logs/；ui_smoke 会覆盖本机 user:// 下的最近阵容与战报，replay 随后重放这份战报。
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOGS="$ROOT/build/check-logs"
GODOT="${GODOT:-$(command -v godot || command -v godot4 || true)}"
PYTHON="${PYTHON:-$(command -v python3 || command -v python || true)}"
PERF=0
for arg in "$@"; do
	case "$arg" in
		--perf) PERF=1 ;;
		-h|--help) sed -n '2,5p' "$0"; exit 0 ;;
		*) echo "未知参数：$arg" >&2; exit 2 ;;
	esac
done
[ -n "$GODOT" ] || { echo "找不到 Godot：请设置 GODOT=/path/to/godot" >&2; exit 2; }
[ -n "$PYTHON" ] || { echo "找不到 Python 3：请设置 PYTHON=/path/to/python3" >&2; exit 2; }
mkdir -p "$LOGS"
failed=()

# Godot 的 --script 运行时错误不一定改变退出码，所以同时检查日志里的错误与失败标记。
run() {
	local name="$1" limit="$2" status start=$SECONDS
	shift 2
	local log="$LOGS/$name.log"
	printf '%-17s ' "$name"
	(cd "$ROOT" && timeout "$limit" "$@") >"$log" 2>&1
	status=$?
	if [ $status -eq 124 ]; then
		echo "TIMEOUT (${limit}s)  $log"
		failed+=("$name")
	elif [ $status -ne 0 ] || grep -qE 'SCRIPT ERROR|^(UI )?FAIL' "$log"; then
		echo "FAIL ($((SECONDS-start))s)  $log"
		grep -E 'SCRIPT ERROR|^(UI )?FAIL|^FAIL|Error' "$log" | head -8 | sed 's/^/    /'
		failed+=("$name")
	else
		echo "ok ($((SECONDS-start))s)  $(grep -E '^(RESULT|UI SMOKE|REPLAY|Unit editor|CROWD|RENDER PERF|Ran )' "$log" | tail -1)"
	fi
}

run import 600 "$GODOT" --headless --path . --editor --import --quit
run test_sim 900 "$GODOT" --headless --path . --script res://tests/test_sim.gd
run unit_editor 300 "$GODOT" --headless --path . --script res://tests/test_unit_editor.gd
run ui_smoke 600 "$GODOT" --headless --path . --script res://tests/ui_smoke.gd
run replay 600 "$GODOT" --headless --path . --script res://tests/replay.gd
run importer 300 "$PYTHON" -m unittest discover -s tests -p 'test_*.py'
if [ $PERF -eq 1 ]; then
	run crowd_perf 900 "$GODOT" --headless --path . --script res://tests/crowd_perf.gd
	run render_perf 300 "$GODOT" --path . --script res://tests/render_perf.gd
fi

if [ ${#failed[@]} -gt 0 ]; then
	echo "CHECK: FAIL (${failed[*]})"
	exit 1
fi
echo "CHECK: PASS"
