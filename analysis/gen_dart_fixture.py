#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成 Dart 端口的一致性测试夹具。

用 Python 参考实现算出真实数据上的指标值与提醒判定，写入
packages/goldprice_domain/test/fixtures/indicators_reference.json，
再由 Dart 自检脚本 packages/goldprice_domain/tool/verify.dart 读取并断言
结果与 Python 完全一致 —— 用来捕捉端口转录错误。

用法: python3 analysis/gen_dart_fixture.py
"""
from __future__ import annotations

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

from alerts import evaluate_alerts  # noqa: E402
from indicators import compute_latest, rsi_series  # noqa: E402

WINDOW = 520
OUT = os.path.join(
    ROOT, "packages", "goldprice_domain", "test", "fixtures", "indicators_reference.json"
)

BASE_CFG = {
    "target_price": None,
    "daily_drop_pct": 2.0,
    "rsi_oversold": 30.0,
    "drawdown_pct": 8.0,
    "ma_window": 60,
}

# 每个变体都刻意覆盖「触发 / 不触发」两个分支
VARIANTS = {
    "default": {},
    "target_above": {"target_price": 1000.0},
    "target_below": {"target_price": 900.0},
    "drop_loose": {"daily_drop_pct": 1.0},
    "drop_tight": {"daily_drop_pct": 5.0},
    "rsi_loose": {"rsi_oversold": 50.0},
    "rsi_tight": {"rsi_oversold": 30.0},
    "ma20": {"ma_window": 20},
    "ma60": {"ma_window": 60},
    "drawdown_loose": {"drawdown_pct": 5.0},
    "drawdown_tight": {"drawdown_pct": 15.0},
}


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

    alert_variants = {}
    for name, override in VARIANTS.items():
        cfg = dict(BASE_CFG)
        cfg.update(override)
        res = evaluate_alerts(ind, cfg)
        alert_variants[name] = {
            "config": cfg,
            "triggered": {k: bool(res[k]["triggered"]) for k in res},
        }

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
        "alert_variants": alert_variants,
    }

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as fh:
        json.dump(fixture, fh, ensure_ascii=False, indent=1)
        fh.write("\n")

    print("[ok] 写入 {}".format(os.path.relpath(OUT, ROOT)))
    print("     样本 {} 天  {} -> {}".format(len(closes), dates[0], dates[-1]))
    e = fixture["expected"]
    print("     sma20={:.6f} sma60={:.6f}".format(e["sma20"], e["sma60"]))
    print("     drawdown90={:.8f} percentile365={:.8f}".format(
        e["drawdown90"], e["percentile365"]))
    print("     rsi14_last={:.8f} change_pct={:.8f}".format(e["rsi14_last"], e["change_pct"]))
    print("     提醒变体 {} 组".format(len(alert_variants)))
    for name in ("default", "target_above", "drop_loose", "rsi_loose", "ma20"):
        print("       {:<16} {}".format(name, alert_variants[name]["triggered"]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
