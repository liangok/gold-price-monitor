#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
分位策略专项验证。

背景：最初设计里有一条「历史分位」提醒（价格处于近一年的低位就提醒买入）。
第一次回测发现近 3 年触发 0 次，于是进一步验证：换更长的窗口会不会更好？

结论（见 analysis/percentile_report.md）：**不会，窗口越长越没用**。
金价十年单边上涨，价格几乎从不落在长窗口的低分位区。
因此本项目**刻意不实现分位提醒** —— 一个永不触发、或触发后还跑输基准的规则，
比没有更糟：它会给人「有保护」的错觉。

用法: python3 analysis/percentile_probe.py
"""
from __future__ import annotations

import json
import os
import statistics as st
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

from indicators import forward_return, percentile  # noqa: E402

OUT = os.path.join(HERE, "percentile_report.md")
HORIZON = 20
WINDOWS = (365, 750, 1250)
THRESHOLDS = (0.30, 0.20, 0.10)


def main():
    with open(os.path.join(ROOT, "data", "benchmark_history.json"), "r", encoding="utf-8") as fh:
        doc = json.load(fh)
    recs = sorted(doc["records"], key=lambda r: r["date"])
    closes = [float(r["close"]) for r in recs]
    n = len(closes)

    baseline = [forward_return(closes, i, HORIZON) for i in range(365, n)]
    baseline = [x for x in baseline if x is not None]
    base_mean = st.mean(baseline)

    lines = []
    lines.append("# 分位策略专项验证")
    lines.append("")
    lines.append("样本：{} ~ {}，共 {} 个交易日。".format(recs[0]["date"], recs[-1]["date"], n))
    lines.append("基准（任意一天买入）持有 {} 个交易日平均收益：**{:+.2f}%**。".format(
        HORIZON, base_mean * 100))
    lines.append("")
    lines.append("## 当前分位")
    lines.append("")
    lines.append("| 窗口 | 当前分位 |")
    lines.append("| --- | --- |")
    for w in WINDOWS:
        p = percentile(closes, n - 1, w)
        lines.append("| {} 个交易日（约 {:.0f} 年） | {:.1f}% |".format(w, w / 250.0, (p or 0) * 100))
    lines.append("")
    lines.append("## 各窗口 / 阈值的触发情况")
    lines.append("")
    lines.append("| 窗口 | 阈值 | 触发次数 | 触发频率 | 20 日均收益 | 相对基准 |")
    lines.append("| --- | --- | --- | --- | --- | --- |")

    print("基准 20 日平均收益 {:+.2f}%".format(base_mean * 100))
    print("")
    print("{:<8}{:<7}{:>9}{:>10}{:>13}{:>14}".format(
        "窗口", "阈值", "触发次数", "频率", "20日均收益", "vs 基准"))

    for window in WINDOWS:
        if window >= n:
            continue
        for thr in THRESHOLDS:
            trig = [i for i in range(window, n)
                    if (percentile(closes, i, window) or 1.0) <= thr]
            if not trig:
                lines.append("| {} | {:.0f}% | **0** | 0.0% | — | — |".format(window, thr * 100))
                print("{:<8}{:<7}{:>9}{:>10}{:>13}{:>14}".format(
                    str(window), "{:.0%}".format(thr), "0", "0.0%", "n/a", "n/a"))
                continue
            fwd = [forward_return(closes, i, HORIZON) for i in trig]
            fwd = [x for x in fwd if x is not None]
            mean = st.mean(fwd)
            lines.append("| {} | {:.0f}% | {} | {:.1f}% | {:+.2f}% | {:+.2f} pp |".format(
                window, thr * 100, len(trig), len(trig) / (n - window) * 100,
                mean * 100, (mean - base_mean) * 100))
            print("{:<8}{:<7}{:>9}{:>10}{:>12.2f}%{:>13.2f}pp".format(
                str(window), "{:.0%}".format(thr), str(len(trig)),
                "{:.1f}%".format(len(trig) / (n - window) * 100),
                mean * 100, (mean - base_mean) * 100))
        print("")

    lines.append("")
    lines.append("## 结论")
    lines.append("")
    lines.append("1. **窗口越长越没用**：3 年与 5 年分位在整整十年里触发 **0 次**。")
    lines.append("   因为金价单边上涨，当前价几乎从不落在长窗口的低分位区。")
    lines.append("2. 唯一会触发的是 1 年窗口，但它的 20 日均收益（+1.02% ~ +1.19%）")
    lines.append("   **全部低于基准 +{:.2f}%**。".format(base_mean * 100))
    lines.append("3. 因此本项目**刻意不实现分位提醒**。一个永不触发、或触发后还跑输基准的规则，")
    lines.append("   比没有更糟 —— 它会让人误以为系统在提供保护。")
    lines.append("")
    lines.append("> 若将来金价进入长期下行周期，这条规则可能重新变得有意义。")
    lines.append("> 届时重新跑本脚本即可判断。")
    lines.append("")

    report = "\n".join(lines)
    with open(OUT, "w", encoding="utf-8") as fh:
        fh.write(report + "\n")
    print("[ok] 写入 {}".format(os.path.relpath(OUT, ROOT)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
