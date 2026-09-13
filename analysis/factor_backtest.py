#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
买点评估里每个因子的**预测力回测**。

为什么必须做：App 的「买点评估」给每个因子打分。打分的**方向**不能凭直觉 ——
本项目已经吃过一次亏（回撤/均线看着像买点，回测里却跑输基准）。

语义约定（关键）：
    因子得分为正 = 「**现在买入**历史上相对更有利」= 该条件下前向收益**高于**基准。

因此回测只需要看：某个条件下买，前向收益是高于还是低于「随便哪天买」。

数据：
  - 上海金：data/benchmark_history.json
  - 美债  ：.toolhome/ust/{year}.csv（美国财政部官方）
  - 美元指数 / 伦敦金现 / 人民币：新浪财经（脚本内实时拉取）

用法：
    python3 analysis/factor_backtest.py
"""
from __future__ import annotations

import csv
import glob
import json
import os
import statistics
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "collector"))

from sources import fetch_sina_history  # noqa: E402

UST_DIR = os.path.join(ROOT, ".toolhome", "ust")
GOLD = os.path.join(ROOT, "data", "benchmark_history.json")
OUNCE = 31.1034768
LOOKBACK = 20
FORWARDS = (20, 60)


def load_gold():
    with open(GOLD, encoding="utf-8") as fh:
        doc = json.load(fh)
    records = doc["records"] if isinstance(doc, dict) and "records" in doc else doc
    records.sort(key=lambda r: r["date"])
    return records


def load_ust():
    rows = []
    for path in sorted(glob.glob(os.path.join(UST_DIR, "*.csv"))):
        with open(path, newline="", encoding="utf-8") as fh:
            for rec in csv.DictReader(fh):
                raw = rec.get("Date")
                if not raw:
                    continue
                try:
                    month, day, year = raw.split("/")
                    rows.append({
                        "date": "{}-{:02d}-{:02d}".format(year, int(month), int(day)),
                        "y2": float(rec["2 Yr"]),
                    })
                except (ValueError, KeyError):
                    continue
    rows.sort(key=lambda r: r["date"])
    return rows


def align_by_date(target_dates, source_rows, fields):
    """把源序列按「当日或之前最近值」对齐到目标日期，避免前视。"""
    out, cursor = [], -1
    for date in target_dates:
        while cursor + 1 < len(source_rows) and source_rows[cursor + 1]["date"] <= date:
            cursor += 1
        if cursor >= 0 and source_rows[cursor]["date"] <= date:
            out.append(source_rows[cursor])
        else:
            out.append(None)
    return out


def report(title, values, closes, buckets, unit=""):
    """values[i] 是第 i 天可用的因子值（None 表示不可用）。"""
    print("=" * 66)
    print(title)
    print("=" * 66)
    for horizon in FORWARDS:
        base, rows = [], []
        for i in range(len(closes)):
            if i + horizon >= len(closes):
                continue
            ret = closes[i + horizon] / closes[i] - 1
            base.append(ret)
            if i < len(values) and values[i] is not None:
                rows.append((values[i], ret))
        if not base:
            continue
        base_mean = statistics.mean(base)
        print("  前向 {} 日｜基准（随便哪天买）{:+.2f}%  胜率 {:.1f}%  样本 {}".format(
            horizon, base_mean * 100,
            sum(1 for x in base if x > 0) / len(base) * 100, len(base)))
        for label, test in buckets:
            picked = [ret for val, ret in rows if test(val)]
            if len(picked) < 20:
                print("    {:<24} 样本不足({})".format(label, len(picked)))
                continue
            mean = statistics.mean(picked)
            win = sum(1 for x in picked if x > 0) / len(picked) * 100
            edge = (mean - base_mean) * 100
            sign = "✔ 优于基准" if edge > 0 else "✘ 差于基准"
            print("    {:<24} {:>5}天  {:+.2f}%  胜率{:>5.1f}%  相对基准 {:+5.2f}pp  {}".format(
                label, len(picked), mean * 100, win, edge, sign))
        print()


def main():
    records = load_gold()
    dates = [r["date"] for r in records]
    closes = [r["close"] for r in records]

    # ---------- 因子 1：美债 2 年期近 20 日变动 ----------
    ust = align_by_date(dates, load_ust(), ("y2",))
    dy2 = []
    for i in range(len(dates)):
        if i >= LOOKBACK and ust[i] and ust[i - LOOKBACK]:
            dy2.append((ust[i]["y2"] - ust[i - LOOKBACK]["y2"]) * 100)
        else:
            dy2.append(None)
    report("因子 1：美债 2 年期近 20 个交易日变动（bp）", dy2, closes, [
        ("大幅下行 < -25bp", lambda v: v < -25),
        ("小幅下行 -25~-8bp", lambda v: -25 <= v < -8),
        ("基本持平 -8~+8bp", lambda v: -8 <= v <= 8),
        ("小幅上行 +8~+25bp", lambda v: 8 < v <= 25),
        ("大幅上行 > +25bp", lambda v: v > 25),
    ])

    # ---------- 因子 2：美元指数近 20 日变动 ----------
    dxy = fetch_sina_history("forex", "DINIW")
    dxy_al = align_by_date(dates, dxy, ("close",))
    ddxy = []
    for i in range(len(dates)):
        if i >= LOOKBACK and dxy_al[i] and dxy_al[i - LOOKBACK]:
            ddxy.append(dxy_al[i]["close"] / dxy_al[i - LOOKBACK]["close"] - 1)
        else:
            ddxy.append(None)
    report("因子 2：美元指数近 20 日涨跌幅", ddxy, closes, [
        ("大幅走弱 < -2%", lambda v: v < -0.02),
        ("小幅走弱 -2~-0.5%", lambda v: -0.02 <= v < -0.005),
        ("基本走平 -0.5~+0.5%", lambda v: -0.005 <= v <= 0.005),
        ("小幅走强 +0.5~+2%", lambda v: 0.005 < v <= 0.02),
        ("大幅走强 > +2%", lambda v: v > 0.02),
    ])

    # ---------- 因子 3：国内金料价差 ----------
    xau = align_by_date(dates, fetch_sina_history("futures", "XAU"), ("close",))
    cny = align_by_date(dates, fetch_sina_history("forex", "fx_susdcny"), ("close",))
    spread = []
    for i in range(len(dates)):
        if xau[i] and cny[i] and cny[i]["close"] > 0:
            intl = xau[i]["close"] * cny[i]["close"] / OUNCE
            spread.append(closes[i] - intl)
        else:
            spread.append(None)
    report("因子 3：国内金价 - 国际金价换算（元/克）", spread, closes, [
        ("国内明显便宜 < -12", lambda v: v < -12),
        ("国内略便宜 -12~-4", lambda v: -12 <= v < -4),
        ("基本持平 -4~+4", lambda v: -4 <= v <= 4),
        ("国内略贵 +4~+12", lambda v: 4 < v <= 12),
        ("国内明显贵 > +12", lambda v: v > 12),
    ])

    return 0


if __name__ == "__main__":
    sys.exit(main())
