#!/usr/bin/env bash
# 安装并启动 App，然后抓取相关日志。
# 用法: bash scripts/install-apk.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$BASH_SOURCE")/.." && pwd)"
cd "$REPO_ROOT"

# shellcheck source=dev-env.sh
source scripts/dev-env.sh >/dev/null

ADB="$ANDROID_HOME/platform-tools/adb"
APK="$REPO_ROOT/app/build/app/outputs/flutter-apk/app-release.apk"
PKG="com.liangaokai.goldprice"

if [ ! -f "$APK" ]; then
  echo "找不到 APK：$APK"
  echo "请先运行: bash scripts/build-apk.sh"
  exit 1
fi

STATE="$("$ADB" devices | sed -n '2p' | awk '{print $2}')"
if [ -z "$STATE" ]; then STATE="未连接"; fi

if [ "$STATE" != "device" ]; then
  echo "手机未就绪，当前状态：$STATE"
  if [ "$STATE" = "unauthorized" ]; then
    echo
    echo "需要在手机上点「允许 USB 调试」。若没弹窗："
    echo "  1. 保持手机解锁、亮屏"
    echo "  2. 设置 → 更多设置 → 开发者选项 → 撤销 USB 调试授权"
    echo "  3. 重新插拔数据线，弹窗会出现"
  fi
  exit 1
fi

echo "== 1/3 安装 =="
"$ADB" install -r "$APK"

echo "== 2/3 启动 =="
"$ADB" shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || \
  "$ADB" shell am start -n "$PKG/.MainActivity"

echo "== 3/3 抓取日志（10 秒）=="
"$ADB" logcat -c || true
sleep 10
"$ADB" logcat -d -v brief 2>/dev/null \
  | grep -i -E "goldprice|flutter|workmanager|Notification|WM-|AndroidRuntime" \
  | tail -40 || echo "（没有匹配到相关日志）"
