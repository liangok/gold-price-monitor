#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
当日信号参考实现 —— 在终端预览 App 首页会显示什么。

这是 App (Flutter/Dart) 策略引擎的语义基准：Dart 实现必须与这里的结果一致。
指标算法见 analysis/indicators.py，提醒规则见 analysis/alerts.py，
阈值来自 config/user.json。

用法: python3 analysis/today_signals.py
"""
from __future__ import annotations

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

from alerts import ORDER, evaluate_alerts  # noqa: E402
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

    print("=" * 62)
    print("  GoldPrice 今日信号   （数据日期 {}）".format(latest.get("data_date")))
    print("=" * 62)

    # ---------- 大盘状态 ----------
    print()
    print("【大盘 Au99.99】  {}".format(dates[ind["index"]]))
    print("  收盘价      {} 元/克".format(fmt(ind["close"])))
    print("  日涨跌      {}".format(fmt((ind["change_pct"] or 0) * 100, 2, "%")))
    print("  MA20 / MA60 {} / {}".format(fmt(ind["ma"].get(20)), fmt(ind["ma"].get(60))))
    print("  距90日高点  {}".format(fmt((ind["drawdown"] or 0) * 100, 2, "%")))
    print("  近1年分位   {}".format(fmt((ind["percentile"] or 0) * 100, 1, "%")))
    print("  RSI14       {}".format(fmt(ind["rsi"], 1)))

    # ---------- 提醒 ----------
    print()
    print("【提醒】判定阈值来自 config/user.json")
    alerts = evaluate_alerts(ind, cfg["alerts"])
    for key in ORDER:
        item = alerts[key]
        mark = "[已触发]" if item["triggered"] else "[  --  ]"
        level = "核心" if item["level"] == "core" else "仅提示"
        print("  {} {} [{}]  {}".format(mark, pad(item["name"], 26), level, item["detail"]))

    hits = sum(1 for k in ORDER if alerts[k]["triggered"])
    print()
    if hits:
        print("  >>> 当前有 {} 条触发，建议关注".format(hits))
    else:
        print("  >>> 当前无触发。这是常态 —— 回测显示最好的信号 10 年只出现 39 次。")

    # ---------- 渠道对比（本项目的第一价值） ----------
    ch = cfg["channel_assumptions"]
    budget = cfg["budget_cny"]
    target = cfg["target_grams"]
    bench = float(latest["benchmark"]["close"])

    mainland = [b for b in latest["brands"]
                if b.get("region") == "mainland" and isinstance(b.get("gold"), (int, float))]
    cheapest = min(mainland, key=lambda b: b["gold"])

    channels = []
    bs = ch["brand_store"]
    channels.append(("{}(最低价)".format(cheapest["name"]),
                     cheapest["gold"], None, bs["labor_per_gram"]))
    sb = ch["shuibei"]
    channels.append(("深圳水贝", bench, sb["benchmark_markup"], sb["labor_per_gram"]))

    bb = ch["bank_bar_diy"]
    bank_stat = (latest.get("bank_bars") or {}).get("stats")
    if bank_stat and bank_stat.get("min"):
        bank_base = bank_stat["min"]["price"]
        bank_markup = None
        bank_note = "实时最低银行金条：{} {} 元/克".format(
            bank_stat["min"]["name"], bank_stat["min"]["price"])
    else:
        bank_base = bench
        bank_markup = bb["benchmark_markup"]
        bank_note = "缺实时报价，回退为「大盘 + {}」假设".format(bb["benchmark_markup"])
    channels.append(("银行金条+打金", bank_base, bank_markup, bb["labor_per_gram"]))

    print()
    print("【渠道对比】预算 {} 元 / 目标 {} 克    大盘基准 {} 元/克".format(
        budget, target, fmt(bench)))
    header = "  {}{:>10}{:>12}{:>12}{:>12}".format(
        pad("渠道", 18), "克价", "{}克总价".format(target), "预算可买", "vs最好")
    print(header)

    rows = []
    best_cost = None
    for name, base, markup, labor in channels:
        cost = base + (markup or 0) + labor
        rows.append((name, cost, target * cost, budget / cost))
        best_cost = cost if best_cost is None else min(best_cost, cost)

    for name, cost, total, grams in rows:
        diff = cost - best_cost
        print("  {}{:>10.2f}{:>12.0f}{:>12.1f}{:>12}".format(
            pad(name, 18), cost, total, grams,
            "基准" if diff == 0 else "+{:.0f}元/克".format(diff)))

    worst = max(rows, key=lambda r: r[1])
    best = min(rows, key=lambda r: r[1])
    save = worst[2] - best[2]
    print()
    print("  >>> 买 {} 克：{} 需 {:.0f} 元，{} 需 {:.0f} 元，差 {:.0f} 元（{:.0f}%）".format(
        target, worst[0], worst[2], best[0], best[2], save, save / worst[2] * 100))
    print("  >>> 这比任何择时策略的收益量级都大得多（择时约几个百分点）。")
    print("  >>> " + bank_note)
    print("  >>> 水贝与其他参数可在 config/user.json 中调整。")
    print()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
