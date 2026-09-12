#!/usr/bin/env bash
# 本项目开发环境变量。用法:  source scripts/dev-env.sh
#
# 三件事：指向 Android Studio 自带的 JDK、指向 Android SDK、把本地 Flutter 加进 PATH。

# Android Studio 自带的 JDK（无需单独安装 Java）
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"

# Android SDK（由 Android Studio 安装）
export ANDROID_HOME="$HOME/Library/Android/sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"

export PATH="$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$PATH"

# 本地 Flutter SDK（下载在 tools/ 下，已加入 .gitignore）
SCRIPT_DIR="$(cd "$(dirname "$BASH_SOURCE")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
if [ -x "$REPO_ROOT/tools/flutter/bin/flutter" ]; then
  export PATH="$REPO_ROOT/tools/flutter/bin:$PATH"
  export FLUTTER_ROOT="$REPO_ROOT/tools/flutter"
fi

# 需要访问 Google 资源时手动打开（国内网络建议开启）
# export https_proxy="http://127.0.0.1:7897"
# export http_proxy="http://127.0.0.1:7897"

echo "JAVA_HOME    = $JAVA_HOME"
echo "ANDROID_HOME = $ANDROID_HOME"
if command -v flutter >/dev/null 2>&1; then
  echo "flutter      = $(command -v flutter)"
else
  echo "flutter      = 未找到（Flutter SDK 尚未下载完成？）"
fi
