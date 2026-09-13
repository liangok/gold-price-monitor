#!/usr/bin/env bash
# 构建 release APK。用法: bash scripts/build-apk.sh [--debug]
#
# 提示：如果 Gradle 报「SDK directory is not writable」或要求安装某个 SDK 组件，
# 先在 Android Studio 的 SDK Manager 里装好（本项目实测需要 NDK 与 SDK Platform 36），
# 再回来跑这个脚本，最省事。
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$BASH_SOURCE")/.." && pwd)"
cd "$REPO_ROOT"

# shellcheck source=dev-env.sh
source scripts/dev-env.sh

MODE="release"
if [ "$#" -gt 0 ] && [ "$1" = "--debug" ]; then MODE="debug"; fi

echo "== 1/5 同步离线快照 =="
bash scripts/sync-assets.sh

echo "== 2/5 领域层自检（纯 Dart）=="
cd packages/goldprice_domain
dart pub get
dart run tool/verify.dart
cd "$REPO_ROOT"

echo "== 3/5 拉取依赖 =="
cd app
flutter pub get

echo "== 4/5 静态分析 =="
flutter analyze

echo "== 5/5 构建 $MODE APK =="
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
