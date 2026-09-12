#!/usr/bin/env bash
# 断点续传补齐 Flutter SDK 的分片下载。
#
# 第一轮暴露出问题：腾讯镜像会中途掐断长连接，导致分片大小不一、任务提前结束。
# 因此这里逐个分片记录已下载字节数，只请求剩余区间，并加上「限速重试」：
# 一旦速度长时间低于 20KB/s 就主动断开换一次连接。
set -u

URL="https://mirrors.cloud.tencent.com/flutter/flutter_infra_release/releases/stable/macos/flutter_macos_3.47.4-stable.zip"
SIZE=2261358207
CHUNKS=8
PARTS="tools/parts"
unset https_proxy http_proxy all_proxy 2>/dev/null || true

mkdir -p "$PARTS"
CHUNK=$(( (SIZE + CHUNKS - 1) / CHUNKS ))

# 计算第 i 个分片应有的字节数
want_bytes() {
  local i=$1
  local start=$(( i * CHUNK ))
  local end=$(( start + CHUNK - 1 ))
  if [ "$end" -ge "$SIZE" ]; then end=$(( SIZE - 1 )); fi
  echo $(( end - start + 1 ))
}

have_bytes() {
  local idx
  idx=$(printf "%02d" "$1")
  if [ -f "$PARTS/part_$idx" ]; then
    stat -f%z "$PARTS/part_$idx"
  else
    echo 0
  fi
}

for attempt in $(seq 1 60); do
  ALL_DONE=1
  for i in $(seq 0 $(( CHUNKS - 1 ))); do
    WANT=$(want_bytes "$i")
    HAVE=$(have_bytes "$i")
    if [ "$HAVE" -ge "$WANT" ]; then continue; fi
    ALL_DONE=0
    IDX=$(printf "%02d" "$i")
    START=$(( i * CHUNK ))
    END=$(( START + CHUNK - 1 ))
    if [ "$END" -ge "$SIZE" ]; then END=$(( SIZE - 1 )); fi
    FROM=$(( START + HAVE ))
    echo "attempt $attempt  chunk $IDX  $HAVE/$WANT  requesting $FROM-$END"
    curl -s -L --retry 2 --retry-delay 2 \
      --speed-limit 20000 --speed-time 30 \
      -r "$FROM-$END" "$URL" >> "$PARTS/part_$IDX" || true
  done
  if [ "$ALL_DONE" -eq 1 ]; then
    echo "所有分片已补齐"
    break
  fi
done

echo '--- 分片校验 ---'
OK=1
for i in $(seq 0 $(( CHUNKS - 1 ))); do
  WANT=$(want_bytes "$i")
  HAVE=$(have_bytes "$i")
  IDX=$(printf "%02d" "$i")
  echo "part_$IDX  $HAVE / $WANT"
  if [ "$HAVE" -ne "$WANT" ]; then OK=0; fi
done

if [ "$OK" -ne 1 ]; then
  echo "仍有分片不完整，保留 parts"
  exit 1
fi

echo '--- 拼接 ---'
cat "$PARTS"/part_* > tools/flutter.zip
GOT=$(wc -c < tools/flutter.zip | tr -d ' ')
echo "assembled=$GOT expected=$SIZE"
if [ "$GOT" -ne "$SIZE" ]; then
  echo "大小不匹配"
  exit 1
fi

rm -rf "$PARTS"
echo '--- 解压 ---'
unzip -q -o tools/flutter.zip
rm -f tools/flutter.zip
echo '--- 完成 ---'
ls tools/
if [ -d tools/flutter/bin/cache/dart-sdk ]; then
  echo 'bundled dart-sdk OK'
  tools/flutter/bin/cache/dart-sdk/bin/dart --version
else
  echo 'no bundled dart-sdk'
fi
