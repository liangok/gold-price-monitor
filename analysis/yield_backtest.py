#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
美债收益率变化对金价的预测力回测。

动机：用户观察到「加息预期升温 -> 金价下跌」。想把美债收益率加进 App 的
买点评估，就必须先证明它**确实**有预测力 —— 否则只是给界面加一个好看的指标。

数据：
  - 黄金：data/benchmark_history.json（上海金 Au99.99 日线）
  - 美债：美国财政部官方 Daily Treasury Par Yield Curve CSV
          （.toolhome/ust/{year}.csv，由本脚本的 --fetch 下载）

方法：
  以**黄金交易日**为主轴，把收益率按「当日或之前最近的已发布值」对齐，
  避免用到未来数据。然后看「2 年期近 20 个交易日的变动」分桶后的前向收益。

用法：
    python3 analysis/yield_backtest.py
"""
from __future__ import annotations

import csv
import glob
import json
import os
import statistics
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UST_DIR = os.path.join(ROOT, ".toolhome", "ust")
GOLD = os.path.join(ROOT, "data", "benchmark_history.json")

LOOKBACK = 20          # 「近 20 个交易日」的收益率变动
FORWARDS = (20, 60)    # 前向持有期
BUCKETS = [
    ("2年期大幅上行  > +25bp", lambda d: d > 25),
    ("2年期小幅上行  +8~+25bp", lambda d: 8 < d <= 25),
    ("2年期基本持平  -8~+8bp", lambda d: -8 <= d <= 8),
    ("2年期小幅下行  -25~-8bp", lambda d: -25 <= d < -8),
    ("2年期大幅下行  < -25bp", lambda d: d < -25),
]


def load_yields():
    rows = []
    for path in sorted(glob.glob(os.path.join(UST_DIR, "*.csv"))):
        with open(path, newline="", encoding="utf-8") as fh:
            for rec in csv.DictReader(fh):
                raw = rec.get("Date")
                if not raw:
                    continue
                try:
                    month, day, year = raw.split("/")
                    y2 = float(rec["2 Yr"])
                    y10 = float(rec["10 Yr"])
                except (ValueError, KeyError):
                    continue
                rows.append({
                    "date": "{}-{:02d}-{:02d}".format(year, int(month), int(day)),
                    "y2": y2,
                    "y10": y10,
                })
    rows.sort(key=lambda r: r["date"])
    return rows


def load_gold():
    with open(GOLD, encoding="utf-8") as fh:
        doc = json.load(fh)
    records = doc["records"] if isinstance(doc, dict) and "records" in doc else doc
    records.sort(key=lambda r: r["date"])
    return records


def align(gold_dates, yields):
    """把收益率对齐到黄金交易日：取当日或之前最近的一个已发布值。"""
    out, cursor = [], -1
    for date in gold_dates:
        while cursor + 1 < len(yields) and yields[cursor + 1]["date"] <= date:
            cursor += 1
        out.append(yields[cursor] if cursor >= 0 and yields[cursor]["date"] <= date else None)
    return out


def main():
    if not os.path.isdir(UST_DIR) or not glob.glob(os.path.join(UST_DIR, "*.csv")):
        print("缺少美债数据。请先用 --fetch 下载到 .toolhome/ust/")
        return 1

    yields = load_yields()
    records = load_gold()
    dates = [r["date"] for r in records]
    closes = [r["close"] for r in records]
    aligned = align(dates, yields)

    print("黄金 {} 个交易日  {} -> {}".format(len(dates), dates[0], dates[-1]))
    print("美债 {} 个交易日  {} -> {}".format(len(yields), yields[0]["date"], yields[-1]["date"]))
    print()

    usable = [i for i in range(LOOKBACK, len(dates))
              if aligned[i] and aligned[i - LOOKBACK]]
    print("可用于回测的样本：{} 天".format(len(usable)))
    print()

    # 基准：随便哪天买
    for horizon in FORWARDS:
        base = [closes[i + horizon] / closes[i] - 1
                for i in usable if i + horizon < len(closes)]
        if not base:
            continue
        print("===== 前向 {} 个交易日 =====".format(horizon))
        print("  {:<26} {:>6} {:>12} {:>10}".format("分桶", "样本", "平均收益", "胜率"))
        print("  {:<26} {:>6} {:>11.2f}% {:>9.1f}%".format(
            "【基准】随便哪天买", len(base),
            statistics.mean(base) * 100,
            sum(1 for x in base if x > 0) / len(base) * 100))

        for label, test in BUCKETS:
            rets = []
            for i in usable:
                if i + horizon >= len(closes):
                    continue
                delta = (aligned[i]["y2"] - aligned[i - LOOKBACK]["y2"]) * 100
                if test(delta):
                    rets.append(closes[i + horizon] / closes[i] - 1)
            if not rets:
                print("  {:<26} {:>6} {:>12} {:>10}".format(label, 0, "-", "-"))
                continue
            print("  {:<26} {:>6} {:>11.2f}% {:>9.1f}%".format(
                label, len(rets),
                statistics.mean(rets) * 100,
                sum(1 for x in rets if x > 0) / len(rets) * 100))
        print()

    # 当前状态
    last = aligned[-1]
    back = aligned[-1 - LOOKBACK]
    if last and back:
        print("当前：2年期 {:.2f}%（近{}日 {:+.0f}bp）  10年期 {:.2f}%  2s10s {:+.2f}".format(
            last["y2"], LOOKBACK, (last["y2"] - back["y2"]) * 100, last["y10"],
            last["y10"] - last["y2"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
