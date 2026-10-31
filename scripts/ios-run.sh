#!/usr/bin/env bash
# 编译 iOS 端 → 装进模拟器 → 启动。
# 改完 Swift 代码直接跑它，省掉在 Xcode 里按 ⌘R。
# 用法：bash scripts/ios-run.sh [模拟器 UDID]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJ="$ROOT/BizSnap"
BUNDLE="com.newking.bizsnap"
FALLBACK_DEVICE="468BD99B-D181-4685-9B17-655F4027B0BF" # iPhone 17 / iOS 26.5

# 优先用当前已启动的模拟器，没有就用默认那台并启动它
DEVICE="${1:-}"
if [ -z "$DEVICE" ]; then
  DEVICE="$(xcrun simctl list devices booted 2>/dev/null | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' | head -1 || true)"
fi
if [ -z "$DEVICE" ]; then
  DEVICE="$FALLBACK_DEVICE"
  xcrun simctl boot "$DEVICE" 2>/dev/null || true
fi

cd "$PROJ"
# 新增/删除文件后 pbxproj 要重生成，这一步很快，每次都跑
xcodegen generate >/dev/null

LOG="$(mktemp -t bizsnap-build)"
if ! xcodebuild -project BizSnap.xcodeproj -scheme BizSnap \
  -destination "id=$DEVICE" -configuration Debug build >"$LOG" 2>&1; then
  echo "编译失败："
  grep -E "error:" "$LOG" | head -20
  exit 1
fi

APP="$(find "$HOME/Library/Developer/Xcode/DerivedData" -maxdepth 5 \
  -path "*Build/Products/Debug-iphonesimulator/BizSnap.app" 2>/dev/null | head -1)"
if [ -z "$APP" ]; then
  echo "找不到构建产物 BizSnap.app"
  exit 1
fi

xcrun simctl terminate "$DEVICE" "$BUNDLE" >/dev/null 2>&1 || true
xcrun simctl install "$DEVICE" "$APP"
xcrun simctl launch "$DEVICE" "$BUNDLE"
