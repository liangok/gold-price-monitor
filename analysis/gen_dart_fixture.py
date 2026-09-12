#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成 Dart 端口的一致性测试夹具。

用 Python 参考实现算出真实数据上的指标值，写入
packages/goldprice_domain/test/fixtures/indicators_reference.json，
再由 Dart 测试读取并断言结果与 Python 完全一致 —— 用来捕捉端口转录错误。

用法: python3 analysis/gen_dart_fixture.py
"""
from __future__ import annotations

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

from indicators import compute_latest, rsi_series  # noqa: E402

WINDOW = 520
OUT = os.path.join(
    ROOT, "packages", "goldprice_domain", "test", "fixtures", "indicators_reference.json"
)


def main():
    with open(os.path.join(ROOT, "data", "benchmark_history.json"), "r", encoding="utf-8") as fh:
        doc = json.load(fh)
    recs = sorted(doc["records"], key=lambda r: r["date"])
    dates = [r["date"] for r in recs][-WINDOW:]
    closes = [float(r["close"]) for r in recs][-WINDOW:]

    ind = compute_latest(closes)
    rsi = rsi_series(closes, 14)

    samples = {}
    for i in (14, 50, 100, 250, WINDOW - 1):
        if 0 <= i < len(rsi) and rsi[i] is not None:
            samples[str(i)] = rsi[i]

    fixture = {
        "note": "由 analysis/gen_dart_fixture.py 自动生成，请勿手工修改",
        "window": WINDOW,
        "dates": dates,
        "closes": closes,
        "expected": {
            "sma20": ind["ma"][20],
            "sma60": ind["ma"][60],
            "drawdown90": ind["drawdown"],
            "percentile365": ind["percentile"],
            "rsi14_last": ind["rsi"],
            "change_pct": ind["change_pct"],
            "rsi14_samples": samples,
        },
    }

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as fh:
        json.dump(fixture, fh, ensure_ascii=False, indent=1)
        fh.write("\n")

    print("[ok] 写入 {}".format(os.path.relpath(OUT, ROOT)))
    print("     样本 {} 天  {} -> {}".format(len(closes), dates[0], dates[-1]))
    e = fixture["expected"]
    print("     sma20={:.6f} sma60={:.6f}".format(e["sma20"], e["sma60"]))
    print("     drawdown90={:.8f} percentile365={:.8f}".format(e["drawdown90"], e["percentile365"]))
    print("     rsi14_last={:.8f} change_pct={:.8f}".format(e["rsi14_last"], e["change_pct"]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
