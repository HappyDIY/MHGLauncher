#!/usr/bin/env bash
# 前端渲染 CPU 采样助手：自动定位已运行的 MHGLauncher 前端进程并采样。
# 用法：先用 ./release-app.command 启动应用，切到要测的页面，再运行本脚本，
# 在采样倒计时内持续滚动/点击/切换该页面。
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
seconds="${1:-20}"          # 采样时长（秒）
interval_ms="${2:-100}"     # 采样间隔（毫秒）
limit="${3:-10}"            # 整机归一化峰值上限（%），超过则脚本退出码非零

# 只匹配 Swift 前端可执行文件，排除 node 后端与本脚本自身。
pid="$(pgrep -x MHGLauncher | head -1 || true)"
if [[ -z "$pid" ]]; then
  echo "未找到运行中的 MHGLauncher 前端进程。请先运行 ./release-app.command 启动应用。" >&2
  exit 2
fi

echo "目标 PID=$pid  时长=${seconds}s  间隔=${interval_ms}ms  上限=${limit}%"
echo "现在开始在目标页面持续滚动/点击/切换……"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
  swift "$root/sample-frontend-cpu.swift" "$pid" "$seconds" "$interval_ms" "$limit"
status=$?

if [[ $status -eq 0 ]]; then
  echo "✅ 峰值在 ${limit}% 以内"
else
  echo "⚠️  峰值超过 ${limit}%（退出码 $status）——把上面 process_peak / machine_share_peak 的数字发回即可"
fi
exit $status
