#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
技术指标计算 —— 本项目内唯一的指标语义定义。

App (Flutter/Dart) 实现策略引擎时必须严格对齐本文件，尤其是三点：
  1. 第 i 天的指标只使用第 0..i 天的数据（严禁未来函数）
  2. RSI 使用 Wilder 平滑，不是简单移动平均
  3. 「分位数」= 窗口内小于等于当前价的天数占比
"""
from __future__ import annotations


def sma(vals, i, n):
    """第 i 天的 n 日简单移动平均；数据不足返回 None。"""
    if i + 1 < n:
        return None
    return sum(vals[i - n + 1 : i + 1]) / n


def rsi_series(vals, n=14):
    """Wilder 平滑 RSI 序列。"""
    out = [None] * len(vals)
    if len(vals) <= n:
        return out
    gain = loss = 0.0
    for k in range(1, n + 1):
        d = vals[k] - vals[k - 1]
        gain += max(d, 0.0)
        loss += max(-d, 0.0)
    ag, al = gain / n, loss / n
    out[n] = 100.0 if al == 0 else 100.0 - 100.0 / (1.0 + ag / al)
    for k in range(n + 1, len(vals)):
        d = vals[k] - vals[k - 1]
        ag = (ag * (n - 1) + max(d, 0.0)) / n
        al = (al * (n - 1) + max(-d, 0.0)) / n
        out[k] = 100.0 if al == 0 else 100.0 - 100.0 / (1.0 + ag / al)
    return out


def rolling_max(vals, i, window):
    """第 i 天往前 window 天的最大值；数据不足返回 None。"""
    if i + 1 < window:
        return None
    return max(vals[i - window + 1 : i + 1])


def percentile(vals, i, window):
    """当前价在近 window 天中的分位（0~1）。"""
    if i + 1 < window:
        return None
    w = vals[i - window + 1 : i + 1]
    cur = vals[i]
    return sum(1 for v in w if v <= cur) / len(w)


def forward_return(vals, i, h):
    """第 i 天买入后持有 h 个交易日的收益率。"""
    if i + h >= len(vals):
        return None
    return vals[i + h] / vals[i] - 1.0


def forward_stats(vals, i, h):
    """第 i 天之后 h 个交易日内的 (最低点相对跌幅, 最高点相对涨幅)。"""
    if i + h >= len(vals):
        return None
    window = vals[i + 1 : i + h + 1]
    if not window:
        return None
    return min(window) / vals[i] - 1.0, max(window) / vals[i] - 1.0


def compute_latest(vals, drawdown_window=90, percentile_window=365,
                   rsi_n=14, ma_windows=(20, 60)):
    """计算最后一天的全部指标，供当日信号判断使用。"""
    if not vals:
        return None
    i = len(vals) - 1
    hi = rolling_max(vals, i, drawdown_window)
    return {
        "index": i,
        "close": vals[i],
        "change_pct": (vals[i] / vals[i - 1] - 1.0) if i >= 1 else None,
        "drawdown": (vals[i] / hi - 1.0) if hi else None,
        "drawdown_window": drawdown_window,
        "percentile": percentile(vals, i, percentile_window),
        "percentile_window": percentile_window,
        "rsi": rsi_series(vals, rsi_n)[i],
        "ma": {w: sma(vals, i, w) for w in ma_windows},
    }
