#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
提醒规则判定 —— Python 参考实现。

与 Dart 端 packages/goldprice_domain/lib/src/strategy.dart 的 evaluateAlerts
一一对应；每条规则有稳定的 key，供跨语言一致性测试断言。
"""
from __future__ import annotations

CORE = "core"
HINT = "hint"

# 展示顺序，也是 Dart 端的顺序
ORDER = ("target_price", "daily_drop", "rsi", "drawdown", "ma")


def _pct(value):
    return "n/a" if value is None else "{:.2f}%".format(value * 100)


def evaluate_alerts(ind, cfg):
    """
    ind: indicators.compute_latest(...) 的返回值
    cfg: {"target_price", "daily_drop_pct", "rsi_oversold", "drawdown_pct", "ma_window"}

    返回 {key: {"name", "level", "triggered", "detail"}}
    """
    out = {}

    target = cfg.get("target_price")
    if target is None:
        out["target_price"] = {
            "name": "绝对目标价", "level": CORE, "triggered": False,
            "detail": "未设置。牛市里分位和均线都会失效，建议设一个绝对价位当锚。",
        }
    else:
        out["target_price"] = {
            "name": "绝对目标价 <= {:.0f} 元/克".format(target), "level": CORE,
            "triggered": ind["close"] <= target,
            "detail": "现价 {:.2f} 元/克".format(ind["close"]),
        }

    drop = cfg["daily_drop_pct"]
    change = ind["change_pct"]
    out["daily_drop"] = {
        "name": "单日跌幅 >= {:.1f}%".format(drop), "level": CORE,
        "triggered": change is not None and change <= -drop / 100.0,
        "detail": "今日 {}，10 年回测 20 日收益 +1.96%".format(_pct(change)),
    }

    oversold = cfg["rsi_oversold"]
    rsi = ind["rsi"]
    out["rsi"] = {
        "name": "RSI14 < {:.0f}".format(oversold), "level": CORE,
        "triggered": rsi is not None and rsi < oversold,
        "detail": "当前 {}，10 年回测 20 日收益 +3.02%（最优）".format(
            "n/a" if rsi is None else "{:.1f}".format(rsi)),
    }

    threshold = cfg["drawdown_pct"]
    drawdown = ind["drawdown"]
    out["drawdown"] = {
        "name": "距 {} 日高点回撤 >= {:.0f}%".format(ind["drawdown_window"], threshold),
        "level": HINT,
        "triggered": drawdown is not None and drawdown <= -threshold / 100.0,
        "detail": "当前 {}，历史上跑输基准，仅供参考".format(_pct(drawdown)),
    }

    window = cfg["ma_window"]
    ma = ind["ma"].get(window)
    out["ma"] = {
        "name": "收盘 < MA{}".format(window), "level": HINT,
        "triggered": ma is not None and ind["close"] < ma,
        "detail": "n/a" if ma is None else "MA{} = {:.2f}，历史上跑输基准".format(window, ma),
    }

    return out
