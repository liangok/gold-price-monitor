#!/usr/bin/env bash
# 本项目开发环境变量。用法:  source scripts/dev-env.sh
#
# 背景：Flutter / pub / Gradle / Dart 遥测默认都会写 $HOME 下的
# ~/.config、~/.pub-cache、~/.gradle、~/.dart-tool。在受限沙箱里这些写入会被拒绝。
# 因此：能写 $HOME 时按常规走（不干扰 adb 密钥等），不能写时自动把 HOME 与
# 各类缓存重定向到仓库内的 .toolhome/，环境保持自包含。

SCRIPT_DIR="$(cd "$(dirname "$BASH_SOURCE")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ORIGINAL_HOME="$HOME"

# Android Studio 自带的 JDK（无需单独安装 Java）
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"

# Android SDK（由 Android Studio 安装）—— 必须用重定向前的 HOME 计算
export ANDROID_HOME="$ORIGINAL_HOME/Library/Android/sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"

export TOOL_HOME="$REPO_ROOT/.toolhome"
mkdir -p "$TOOL_HOME"

# 探测能否写 $HOME；不能写则整体重定向到仓库内
if mkdir -p "$ORIGINAL_HOME/.dsh_write_probe" 2>/dev/null; then
  rmdir "$ORIGINAL_HOME/.dsh_write_probe" 2>/dev/null || true
else
  export HOME="$TOOL_HOME/home"
fi

export XDG_CONFIG_HOME="$TOOL_HOME/config"
export PUB_CACHE="$TOOL_HOME/pub-cache"
export GRADLE_USER_HOME="$TOOL_HOME/gradle"
export ANDROID_USER_HOME="$TOOL_HOME/android"
export DART_SUPPRESS_ANALYTICS="true"
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$PUB_CACHE" "$GRADLE_USER_HOME" "$ANDROID_USER_HOME"

# 本地 Flutter SDK（下载在 tools/ 下，已加入 .gitignore）
if [ -x "$REPO_ROOT/tools/flutter/bin/flutter" ]; then
  export PATH="$REPO_ROOT/tools/flutter/bin:$PATH"
  export FLUTTER_ROOT="$REPO_ROOT/tools/flutter"
fi

export PATH="$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$PATH"

# 需要访问 Google / pub.dev / Maven 时手动打开
# export https_proxy="http://127.0.0.1:7897"
# export http_proxy="http://127.0.0.1:7897"

echo "JAVA_HOME    = $JAVA_HOME"
echo "ANDROID_HOME = $ANDROID_HOME"
echo "HOME         = $HOME"
echo "TOOL_HOME    = $TOOL_HOME"
if command -v flutter >/dev/null 2>&1; then
  echo "flutter      = $(command -v flutter)"
else
  echo "flutter      = 未找到"
fi
