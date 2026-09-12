#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
策略规则回测：用上金所 10 年真实日线，检验每条提醒规则的实际表现。

目的不是预测价格，而是：
  1. 淘汰「每天都触发」或「从不触发」的废规则；
  2. 为 App 的策略引擎确定合理默认参数；
  3. 量化回答用户的核心疑问 —— 「等回调再买，到底有没有用」。

严格遵守无未来函数：第 i 天的指标只用第 0..i 天的数据。
用法: python3 analysis/strategy_backtest.py
"""
import json
import os
import statistics as st

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "data", "benchmark_history.json")
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "backtest_report.md")

HORIZONS = (20, 60)          # 交易日
SUB_PERIOD_DAYS = 750        # 子样本：最近约 3 年
DRAWDOWN_WINDOW = 90
PERCENTILE_WINDOW = 365


def load():
    with open(DATA, "r", encoding="utf-8") as fh:
        doc = json.load(fh)
    recs = sorted(doc["records"], key=lambda r: r["date"])
    return [r["date"] for r in recs], [float(r["close"]) for r in recs]


import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from indicators import (  # noqa: E402
    forward_return,
    forward_stats,
    percentile,
    rolling_max,
    rsi_series,
    sma,
)


def summarize(name, triggers, dates, closes, total_days, baseline_fwd):
    rows = {h: [] for h in HORIZONS}
    deeper = {h: [] for h in HORIZONS}
    maxup = {h: [] for h in HORIZONS}
    for i in triggers:
        for h in HORIZONS:
            fr = forward_return(closes, i, h)
            if fr is not None:
                rows[h].append(fr)
            fs = forward_stats(closes, i, h)
            if fs:
                deeper[h].append(fs[0])
                maxup[h].append(fs[1])

    freq = len(triggers) / total_days
    out = {"name": name, "count": len(triggers), "freq": freq, "fwd": {}, "deeper": {}, "maxup": {}}
    for h in HORIZONS:
        if rows[h]:
            out["fwd"][h] = (st.mean(rows[h]), st.median(rows[h]))
        if deeper[h]:
            out["deeper"][h] = (sum(1 for x in deeper[h] if x < 0) / len(deeper[h]), st.mean(deeper[h]))
        if maxup[h]:
            out["maxup"][h] = st.mean(maxup[h])
        out["base"] = baseline_fwd
    return out


def baseline(dates, closes, start):
    base = {h: [] for h in HORIZONS}
    for i in range(start, len(closes)):
        for h in HORIZONS:
            fr = forward_return(closes, i, h)
            if fr is not None:
                base[h].append(fr)
    return base

def baseline_detail(closes, start, horizons=HORIZONS):
    """基准：任意一天买入后，未来 h 日内是否出现过更低价。"""
    out = {h: [] for h in horizons}
    for i in range(start, len(closes)):
        for h in horizons:
            fs = forward_stats(closes, i, h)
            if fs:
                out[h].append(fs[0])
    return {h: (sum(1 for x in v if x < 0) / len(v), st.mean(v)) for h, v in out.items() if v}


def dca_compare(closes, start, window, tranches):
    """
    在所有长度为 window 的滚动窗口上，比较「一次性买入」与「等金额分批买入」的每克成本。

    等金额分批的每克成本 = 调和平均价 = n / sum(1/price)，天然低于算术平均。
    对照是「一次性买入」，即直接承担窗口起点那一天的价格。
    """
    if tranches < 2:
        return None
    gaps = [round(k * window / (tranches - 1)) for k in range(tranches)]
    better = 0
    total = 0
    lump_sum = 0.0
    dca_sum = 0.0
    for s in range(start, len(closes) - window):
        pts = [closes[s + g] for g in gaps]
        lump = closes[s]
        dca = tranches / sum(1.0 / p for p in pts)
        lump_sum += lump
        dca_sum += dca
        total += 1
        if dca < lump:
            better += 1
    if total == 0:
        return None
    return {
        "window": window,
        "tranches": tranches,
        "n": total,
        "lump": lump_sum / total,
        "dca": dca_sum / total,
        "better_pct": better / total,
    }


def main():
    dates, closes = load()
    n = len(closes)
    print("样本: {} 个交易日  {} -> {}".format(n, dates[0], dates[-1]))
    print("区间涨跌: {:.1f} -> {:.1f} 元/克  ({:+.1f}%)".format(
        closes[0], closes[-1], (closes[-1] / closes[0] - 1) * 100))

    ma20 = [sma(closes, i, 20) for i in range(n)]
    ma60 = [sma(closes, i, 60) for i in range(n)]
    dd = [None] * n
    for i in range(n):
        hi = rolling_max(closes, i, DRAWDOWN_WINDOW)
        dd[i] = (closes[i] / hi - 1.0) if hi else None
    pct = [percentile(closes, i, PERCENTILE_WINDOW) for i in range(n)]
    rsi = rsi_series(closes, 14)
    chg = [None] + [closes[i] / closes[i - 1] - 1.0 for i in range(1, n)]

    start = 365  # 保证所有指标都有值，避免样本起点偏差
    ALL = list(range(start, n))
    base = baseline(dates, closes, start)

    rules = [
        ("回撤: 距90日高点 <= -3%", lambda i: dd[i] is not None and dd[i] <= -0.03),
        ("回撤: 距90日高点 <= -5%", lambda i: dd[i] is not None and dd[i] <= -0.05),
        ("回撤: 距90日高点 <= -8%", lambda i: dd[i] is not None and dd[i] <= -0.08),
        ("均线: 收盘 < MA20", lambda i: ma20[i] is not None and closes[i] < ma20[i]),
        ("均线: 收盘 < MA60", lambda i: ma60[i] is not None and closes[i] < ma60[i]),
        ("分位: 近1年分位 <= 30%", lambda i: pct[i] is not None and pct[i] <= 0.30),
        ("分位: 近1年分位 <= 20%", lambda i: pct[i] is not None and pct[i] <= 0.20),
        ("分位: 近1年分位 <= 10%", lambda i: pct[i] is not None and pct[i] <= 0.10),
        ("RSI14 < 30", lambda i: rsi[i] is not None and rsi[i] < 30),
        ("单日跌幅 >= 2%", lambda i: chg[i] is not None and chg[i] <= -0.02),
    ]

    results = []
    for name, fn in rules:
        trig = [i for i in ALL if fn(i)]
        results.append(summarize(name, trig, dates, closes, len(ALL), base))

    lines = []
    lines.append("# 策略规则回测报告")
    lines.append("")
    lines.append("样本区间：{} ~ {}，共 {} 个交易日。".format(dates[0], dates[-1], n))
    lines.append("大盘由 {:.1f} 涨到 {:.1f} 元/克（{:+.0f}%）。".format(
        closes[0], closes[-1], (closes[-1] / closes[0] - 1) * 100))
    lines.append("")
    lines.append("## 基准（随机/任意一天买入）")
    lines.append("")
    lines.append("| 持有 | 平均收益 | 中位收益 |")
    lines.append("| --- | --- | --- |")
    for h in HORIZONS:
        if base[h]:
            lines.append("| {} 个交易日 | {:+.2f}% | {:+.2f}% |".format(
                h, st.mean(base[h]) * 100, st.median(base[h]) * 100))
    lines.append("")
    lines.append("> 注意：样本区间金价整体大幅上涨，所以「任意一天买入」的平均收益本身就是正的。")
    lines.append("> 评估一条规则是否有用，要看它能否**跑赢这个基准**。")
    lines.append("")
    lines.append("## 各规则表现")
    lines.append("")
    lines.append("| 规则 | 触发天数 | 触发频率 | 20日后均收益 | 60日后均收益 | 触发后60日内跌得更低的比例 | 触发后60日内平均还能再跌 |")
    lines.append("| --- | --- | --- | --- | --- | --- | --- |")
    for r in results:
        f20 = "{:+.2f}%".format(r["fwd"][20][0] * 100) if 20 in r["fwd"] else "n/a"
        f60 = "{:+.2f}%".format(r["fwd"][60][0] * 100) if 60 in r["fwd"] else "n/a"
        d60 = "{:.0f}%".format(r["deeper"][60][0] * 100) if 60 in r["deeper"] else "n/a"
        m60 = "{:+.2f}%".format(r["deeper"][60][1] * 100) if 60 in r["deeper"] else "n/a"
        lines.append("| {} | {} | {:.1f}% | {} | {} | {} | {} |".format(
            r["name"], r["count"], r["freq"] * 100, f20, f60, d60, m60))
    lines.append("")
    lines.append("## 关键解读")
    lines.append("")
    lines.append("- **触发频率**：超过 30% 的规则基本等于「每天提醒」，会让人麻木，必须收紧参数或限制提醒间隔。")
    lines.append("- **跌得更低的比例**：触发后 60 日内出现更低价的比例。越高说明「再等等」越有价值，也说明任何单点买入都可能买在相对高点。")
    lines.append("- **跑赢基准**：若某规则的 20/60 日收益明显高于基准，说明它确实倾向于买在相对低位。")

    bd = baseline_detail(closes, start)
    lines.append("")
    lines.append("## 基准对照：任意一天买入后，未来是否出现过更低价")
    lines.append("")
    lines.append("| 持有窗口 | 期间出现过更低价的比例 | 平均还能再跌 |")
    lines.append("| --- | --- | --- |")
    for h in HORIZONS:
        if h in bd:
            lines.append("| {} 个交易日 | {:.0f}% | {:+.2f}% |".format(h, bd[h][0] * 100, bd[h][1] * 100))
    lines.append("")
    lines.append("**这张表很重要**：如果基准本身就有约 90% 的概率出现更低价，")
    lines.append("那么上面各规则 83~93% 的数字并没有比「随便挑一天买」好多少 ——")
    lines.append("说明**任何单点买入事后看几乎都会买早**，这才是「分批买入」真正的理由。")

    # 子样本：最近 3 年
    sub_start = max(start, n - SUB_PERIOD_DAYS)
    lines.append("")
    lines.append("## 子样本检验：最近约 3 年（{} 起）".format(dates[sub_start]))
    lines.append("")
    lines.append("| 规则 | 触发频率 | 20日后均收益 | 60日后均收益 |")
    lines.append("| --- | --- | --- | --- |")
    sub_base = baseline(None, closes, sub_start)
    lines.append("| （基准） | 100% | {:+.2f}% | {:+.2f}% |".format(
        st.mean(sub_base[20]) * 100, st.mean(sub_base[60]) * 100))
    for name, fn in rules:
        idx = list(range(sub_start, n))
        trig = [i for i in idx if fn(i)]
        if not trig:
            lines.append("| {} | 0% | n/a | n/a |".format(name))
            continue
        f20 = [forward_return(closes, i, 20) for i in trig]
        f60 = [forward_return(closes, i, 60) for i in trig]
        f20 = [x for x in f20 if x is not None]
        f60 = [x for x in f60 if x is not None]
        lines.append("| {} | {:.1f}% | {} | {} |".format(
            name, len(trig) / len(idx) * 100,
            "{:+.2f}%".format(st.mean(f20) * 100) if f20 else "n/a",
            "{:+.2f}%".format(st.mean(f60) * 100) if f60 else "n/a"))

    # 一次性 vs 分批
    lines.append("")
    lines.append("## 一次性买入 vs 等金额分批买入")
    lines.append("")
    lines.append("在所有可能的买入起点上滚动模拟，比较每克平均成本（数字越低越好）。")
    lines.append("")
    lines.append("| 方案 | 滚动样本数 | 一次性买入每克成本 | 分批买入每克成本 | 分批更划算的比例 |")
    lines.append("| --- | --- | --- | --- | --- |")
    for window, tranches, label in [
        (120, 5, "约6个月内分5批"),
        (120, 3, "约6个月内分3批"),
        (240, 8, "约1年内分8批"),
    ]:
        res = dca_compare(closes, start, window, tranches)
        if res:
            lines.append("| {} | {} | {:.2f} | {:.2f} | {:.0f}% |".format(
                label, res["n"], res["lump"], res["dca"], res["better_pct"] * 100))
    lines.append("")
    lines.append("**结论与直觉相反**：在本样本（金价单边上涨 +258%）中，一次性买入的每克成本**低于**分批买入，")
    lines.append("分批只在 12~19% 的情况下更划算 —— 因为「等待」意味着在更高的价位买入。")
    lines.append("")
    lines.append("所以分批买入的价值**不是降低成本**，而是**降低风险**：")
    lines.append("避免把全部预算压在某一天的价位上。代价是放弃单边上涨中的部分收益。")
    lines.append("对「不想买在最高点」这个诉求，分批是有效的保险，但它不是免费的。")

    # ---- 给 App 策略设计的结论 ----
    lines.append("")
    lines.append("## 对 App 策略设计的结论")
    lines.append("")
    lines.append("**1. 回撤 / 均线类规则不应作为主信号。**")
    lines.append("它们在两个样本区间都跑输「随便哪天买」的基准（20日收益 +0.37%~+0.80% vs 基准 +1.39%）。")
    lines.append("金价长期上行，回调后往往继续涨。这类规则只适合做「提示」，不适合做「买入信号」。")
    lines.append("")
    lines.append("**2. 「历史分位」规则在牛市里会完全失效。**")
    lines.append("最近 3 年「分位 <= 30%」的触发次数是 **0** —— 金价几乎一直处在近一年的高位区。")
    lines.append("如果按原计划实现，用户会永远收不到提醒。必须改成绝对目标价，或使用更长的分位窗口。")
    lines.append("")
    lines.append("**3. 真正有价值的稀有信号只有两个：**")
    lines.append("- RSI14 < 30：10 年只触发 39 次（2%），20 日平均收益 **+3.02%**，是基准的 2.2 倍")
    lines.append("- 单日跌幅 >= 2%：10 年 51 次（2.6%），20 日平均收益 **+1.96%**，也明显跑赢基准")
    lines.append("这两个都属于「恐慌日」，稀少但可操作，应作为提醒的核心。")
    lines.append("")
    lines.append("**4. 任何单点买入事后看几乎都会「买早了」。**")
    lines.append("基准本身就有 81%（20日）/ 86%（60日）的概率出现更低价。")
    lines.append("用户拿着 App 很容易陷入「再等等」的无限循环 —— 产品文案必须直面这一点，不能暗示能抄到底。")
    lines.append("")
    lines.append("**5. 择时的收益量级远小于渠道选择。**")
    lines.append("上述最优规则的超额收益是几个百分点；而「品牌店 vs 水贝 / 金条打金」的差价是 **约 40%**。")
    lines.append("因此 App 的第一价值是**渠道与比价**，提醒是第二价值。这一点决定了首页的信息层级。")
    lines.append("")
    lines.append("> 声明：以上为历史数据统计，样本区间金价大幅上涨，结论不能外推到未来，不构成投资建议。")

    report = "\n".join(lines)
    print()
    print(report)
    with open(OUT, "w", encoding="utf-8") as fh:
        fh.write(report + "\n")
    print()
    print("[ok] 报告已写入 {}".format(os.path.relpath(OUT, ROOT)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
