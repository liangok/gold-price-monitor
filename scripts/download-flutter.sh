#!/usr/bin/env bash
# 分片并行下载 Flutter SDK（镜像支持 Range，多连接显著提速）。
set -u
URL="https://mirrors.cloud.tencent.com/flutter/flutter_infra_release/releases/stable/macos/flutter_macos_3.47.4-stable.zip"
SIZE=2261358207
CHUNKS=8
PARTS="tools/parts"
mkdir -p "$PARTS"
unset https_proxy http_proxy all_proxy 2>/dev/null || true

CHUNK=$(( (SIZE + CHUNKS - 1) / CHUNKS ))
PIDS=""
for i in $(seq 0 $((CHUNKS - 1))); do
  START=$(( i * CHUNK ))
  END=$(( START + CHUNK - 1 ))
  if [ "$END" -ge "$SIZE" ]; then END=$(( SIZE - 1 )); fi
  IDX=$(printf "%02d" "$i")
  curl -s -L --retry 5 --retry-delay 3 -r "$START-$END" -o "$PARTS/part_$IDX" "$URL" &
  PIDS="$PIDS $!"
done

FAIL=0
for p in $PIDS; do
  if ! wait "$p"; then FAIL=1; fi
done
echo "chunks finished (fail=$FAIL)"
ls -la "$PARTS"

if [ "$FAIL" -ne 0 ]; then
  echo "有分片失败，保留 parts 以便排查"
  exit 1
fi

cat "$PARTS"/part_* > tools/flutter.zip
GOT=$(wc -c < tools/flutter.zip | tr -d ' ')
echo "assembled size=$GOT expected=$SIZE"
if [ "$GOT" != "$SIZE" ]; then
  echo "大小不匹配，保留 zip 以便排查"
  exit 1
fi

rm -rf "$PARTS"
echo '--- unzipping ---'
unzip -q -o tools/flutter.zip
rm -f tools/flutter.zip
echo '--- unzipped ---'
ls tools/
if [ -d tools/flutter/bin/cache/dart-sdk ]; then
  echo 'bundled dart-sdk OK'
else
  echo 'no bundled dart-sdk'
fi
