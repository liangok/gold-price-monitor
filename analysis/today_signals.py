#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
当日信号参考实现 —— 在终端预览 App 首页会显示什么。

这是 App (Flutter/Dart) 策略引擎的语义基准：Dart 实现必须与这里的结果一致。
指标算法见 analysis/indicators.py，阈值来自 config/user.json。

用法: python3 analysis/today_signals.py
"""
from __future__ import annotations

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

from indicators import compute_latest  # noqa: E402


def load_json(path):
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def fmt(value, digits=2, suffix=""):
    return "n/a" if value is None else "{:.{d}f}{s}".format(value, d=digits, s=suffix)


def wcwidth(text):
    """粗略计算终端显示宽度：CJK 字符算 2 列。"""
    return sum(2 if ord(ch) > 0x2E80 else 1 for ch in text)


def pad(text, width):
    return text + " " * max(0, width - wcwidth(text))


def main():
    cfg = load_json(os.path.join(ROOT, "config", "user.json"))
    hist = load_json(os.path.join(ROOT, "data", "benchmark_history.json"))
    latest = load_json(os.path.join(ROOT, "data", "latest.json"))

    recs = sorted(hist["records"], key=lambda r: r["date"])
    dates = [r["date"] for r in recs]
    closes = [float(r["close"]) for r in recs]

    ind = compute_latest(closes)
    alerts_cfg = cfg["alerts"]

    print("=" * 62)
    print("  GoldPrice 今日信号   （数据日期 {}）".format(latest.get("data_date")))
    print("=" * 62)

    # ---------- 大盘状态 ----------
    print()
    print("【大盘 Au99.99】  {}".format(dates[ind["index"]]))
    print("  收盘价      {} 元/克".format(fmt(ind["close"])))
    print("  日涨跌      {}".format(fmt((ind["change_pct"] or 0) * 100, 2, "%")))
    print("  MA20 / MA60 {} / {}".format(
        fmt(ind["ma"].get(20)), fmt(ind["ma"].get(60))))
    print("  距90日高点  {}".format(fmt((ind["drawdown"] or 0) * 100, 2, "%")))
    print("  近1年分位   {}".format(fmt((ind["percentile"] or 0) * 100, 1, "%")))
    print("  RSI14       {}".format(fmt(ind["rsi"], 1)))

    # ---------- 提醒 ----------
    print()
    print("【提醒】判定阈值来自 config/user.json")
    results = []

    tp = alerts_cfg.get("target_price")
    if tp:
        hit = ind["close"] <= tp
        results.append(("绝对目标价 <= {} 元/克".format(tp), hit, "核心",
                        "现价 {} 元/克".format(fmt(ind["close"]))))
    else:
        results.append(("绝对目标价", False, "核心", "未设置（建议设置：牛市里分位/均线都会失效）"))

    dd = alerts_cfg.get("daily_drop_pct")
    if dd:
        hit = ind["change_pct"] is not None and ind["change_pct"] <= -dd / 100.0
        results.append(("单日跌幅 >= {}%".format(dd), hit, "核心",
                        "今日 {}，10年回测20日收益 +1.96%".format(fmt((ind["change_pct"] or 0) * 100, 2, "%"))))

    ro = alerts_cfg.get("rsi_oversold")
    if ro:
        hit = ind["rsi"] is not None and ind["rsi"] < ro
        results.append(("RSI14 < {}".format(ro), hit, "核心",
                        "当前 {}，10年回测20日收益 +3.02%（最优）".format(fmt(ind["rsi"], 1))))

    dw = alerts_cfg.get("drawdown_pct")
    if dw:
        hit = ind["drawdown"] is not None and ind["drawdown"] <= -dw / 100.0
        results.append(("距90日高点回撤 >= {}%".format(dw), hit, "仅提示",
                        "当前 {}，历史上跑输基准".format(fmt((ind["drawdown"] or 0) * 100, 2, "%"))))

    mw = alerts_cfg.get("ma_window")
    if mw and ind["ma"].get(mw):
        hit = ind["close"] < ind["ma"][mw]
        results.append(("收盘 < MA{}".format(mw), hit, "仅提示",
                        "MA{} = {}，历史上跑输基准".format(mw, fmt(ind["ma"][mw]))))

    for name, hit, level, note in results:
        mark = "[已触发]" if hit else "[  --  ]"
        print("  {} {} [{}]  {}".format(mark, pad(name, 26), level, note))

    triggered = [r for r in results if r[1]]
    print()
    if triggered:
        print("  >>> 当前有 {} 条触发，建议关注".format(len(triggered)))
    else:
        print("  >>> 当前无触发。这是常态 —— 回测显示最好的信号 10 年只出现 39 次。")

    # ---------- 渠道对比（本项目的第一价值） ----------
    ch = cfg["channel_assumptions"]
    budget = cfg["budget_cny"]
    target = cfg["target_grams"]
    bench = float(latest["benchmark"]["close"])

    mainland = [b for b in latest["brands"] if b.get("region") == "mainland"
                and isinstance(b.get("gold"), (int, float))]
    cheapest = min(mainland, key=lambda b: b["gold"])

    channels = []
    bs = ch["brand_store"]
    channels.append(("{}(最低价)".format(cheapest["name"]),
                     cheapest["gold"], None, bs["labor_per_gram"]))
    sb = ch["shuibei"]
    channels.append(("深圳水贝", bench, sb["benchmark_markup"], sb["labor_per_gram"]))
    bb = ch["bank_bar_diy"]
    channels.append(("银行金条+打金", bench, bb["bar_markup"], bb["labor_per_gram"]))

    print()
    print("【渠道对比】预算 {} 元 / 目标 {} 克    大盘基准 {} 元/克".format(
        budget, target, fmt(bench)))
    print("  {:<16}{:>10}{:>12}{:>12}{:>12}".format("渠道", "克价", "{}克总价".format(target), "预算可买", "vs最好"))
    best_cost = None
    rows = []
    for name, base, markup, labor in channels:
        cost = base + (markup or 0) + labor
        rows.append((name, cost, target * cost, budget / cost))
        best_cost = cost if best_cost is None else min(best_cost, cost)
    for name, cost, total, grams in rows:
        diff = cost - best_cost
        print("  {}{:>10.2f}{:>12.0f}{:>12.1f}{:>12}".format(
            pad(name, 18), cost, total, grams, "基准" if diff == 0 else "+{:.0f}元/克".format(diff)))

    worst = max(rows, key=lambda r: r[1])
    best = min(rows, key=lambda r: r[1])
    save = worst[2] - best[2]
    print()
    print("  >>> 买 {} 克：{} 需 {:.0f} 元，{} 需 {:.0f} 元，差 {:.0f} 元（{:.0f}%）".format(
        target, worst[0], worst[2], best[0], best[2], save, save / worst[2] * 100))
    print("  >>> 这比任何择时策略的收益量级都大得多（择时约几个百分点）。")
    print("  >>> 渠道参数为假设值，可在 config/user.json 中调整。")
    print()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
