#!/bin/bash
set -e
cd "$(dirname "$0")"

echo "==> 停止旧进程..."
pkill -f CCStatus 2>/dev/null || true
sleep 0.5

echo "==> 编译..."
swiftc \
  Sources/CCStatus/main.swift \
  Sources/CCStatus/AppDelegate.swift \
  Sources/CCStatus/SessionMonitor.swift \
  Sources/CCStatus/StatusLightView.swift \
  Sources/CCStatus/StatusLightWindow.swift \
  Sources/CCStatus/MenuBarIcon.swift \
  -o cc-status \
  -framework AppKit \
  -framework Foundation \
  -framework ServiceManagement \
  -swift-version 5
echo "==> 编译成功 ✓"

echo "==> 打包 App Bundle..."
rm -rf CCStatus.app
mkdir -p CCStatus.app/Contents/MacOS CCStatus.app/Contents/Resources
cp cc-status CCStatus.app/Contents/MacOS/
cp Sources/CCStatus/Info.plist CCStatus.app/Contents/

# 与 CI 一致：ad-hoc 签名，不加 --options runtime
# 不用 Hardened Runtime，让 AppleScript 走普通 TCC 流程触发系统授权弹窗
codesign --force --deep --sign - CCStatus.app
echo "==> 打包成功 ✓"

echo "==> 启动..."
nohup ./CCStatus.app/Contents/MacOS/cc-status > /tmp/cc-status.log 2>&1 &
sleep 1

echo "==> 检查进程..."
pgrep -la cc-status || echo "未找到进程"
echo ""
echo "==> 完成！查看日志: tail -f /tmp/cc-status.log"
