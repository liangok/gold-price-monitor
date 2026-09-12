#!/usr/bin/env bash
# 构建 release APK。用法: bash scripts/build-apk.sh [--debug]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$BASH_SOURCE")/.." && pwd)"
cd "$REPO_ROOT"

# shellcheck source=dev-env.sh
source scripts/dev-env.sh

MODE="release"
if [ "$#" -gt 0 ] && [ "$1" = "--debug" ]; then MODE="debug"; fi

echo "== 1/4 领域层自检（纯 Dart）=="
cd packages/goldprice_domain
dart pub get
dart run tool/verify.dart
cd "$REPO_ROOT"

echo "== 2/4 拉取依赖 =="
cd app
flutter pub get

echo "== 3/4 静态分析 =="
flutter analyze

echo "== 4/4 构建 $MODE APK =="
if [ "$MODE" = "release" ]; then
  flutter build apk --release
  APK="build/app/outputs/flutter-apk/app-release.apk"
else
  flutter build apk --debug
  APK="build/app/outputs/flutter-apk/app-debug.apk"
fi

echo
echo "构建完成: app/$APK"
echo "安装到手机: adb install -r \"app/$APK\""
