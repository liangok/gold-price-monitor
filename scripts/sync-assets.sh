#!/usr/bin/env bash
# 把仓库里的最新数据同步成 App 的离线快照（会被打包进 APK）。
#
# 用途：即使手机拉不到 GitHub（仓库没建好 / 断网），App 也能显示数据。
# 每次构建前跑一次即可，见 scripts/build-apk.sh。
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$BASH_SOURCE")/.." && pwd)"
DEST="$REPO_ROOT/app/assets/data"

mkdir -p "$DEST"
cp "$REPO_ROOT/data/latest.json"              "$DEST/latest.json"
cp "$REPO_ROOT/data/benchmark_history.json"   "$DEST/benchmark_history.json"
cp "$REPO_ROOT/data/brand_history.json"       "$DEST/brand_history.json"
cp "$REPO_ROOT/data/bank_bar_history.json"    "$DEST/bank_bar_history.json"
cp "$REPO_ROOT/data/macro.json"               "$DEST/macro.json"
cp "$REPO_ROOT/config/user.json"              "$DEST/user.json"

echo "已同步离线快照到 app/assets/data/（$(du -sh "$DEST" | cut -f1)）"
