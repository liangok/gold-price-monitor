#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
金价数据采集主脚本。

用法:
    python3 collector/collect.py

产出（写入仓库 data/ 目录，供 Android App 直接读取）:
    data/latest.json            今日汇总：大盘金价 + 品牌报价 + 统计 + 溢价
    data/benchmark_history.json 大盘金价 Au99.99 完整日线（2016-12 至今）
    data/brand_history.json     品牌金店报价历史（每天追加一条）
    data/macro.json             宏观因子（国际金价 / 美元指数 / 人民币汇率）

设计原则：单个数据源失败不影响整体；已有历史数据永不丢失。
"""
from __future__ import annotations

import json
import os
import sys
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from sources import (  # noqa: E402
    CST,
    FetchError,
    fetch_benchmark_history,
    fetch_bank_bars,
    fetch_brand_quotes,
    fetch_macro,
    MACRO_KEYS,
)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_DIR = os.path.join(ROOT, "data")
SCHEMA_VERSION = 1


def now_cst():
    return datetime.now(CST).isoformat(timespec="seconds")


def load_json(path, default):
    if not os.path.exists(path):
        return default
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except (json.JSONDecodeError, OSError) as exc:
        print("[warn] 读取 {} 失败，使用默认值: {}".format(path, exc))
        return default


def save_json(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(obj, fh, ensure_ascii=False, indent=1)
        fh.write("\n")
    os.replace(tmp, path)
    print("[ok] 写入 {}".format(os.path.relpath(path, ROOT)))


def pct_change(points, n):
    """近 n 个点的涨跌幅（n 从末尾往前数）。"""
    if len(points) < 2:
        return None
    base = points[max(0, len(points) - n)]["close"]
    if not base:
        return None
    return round(points[-1]["close"] / base - 1.0, 5)


def dict_stat(prices):
    """对 {名称: 价格} 求最小值/最大值/均值/极差。"""
    if not prices:
        return None
    values = list(prices.values())
    lo_key = min(prices, key=lambda k: prices[k])
    hi_key = max(prices, key=lambda k: prices[k])
    return {
        "min": {"name": lo_key, "price": prices[lo_key]},
        "max": {"name": hi_key, "price": prices[hi_key]},
        "avg": round(sum(values) / len(values), 2),
        "spread": round(max(values) - min(values), 2),
        "count": len(values),
    }


def main():
    bench_doc = load_json(
        os.path.join(DATA_DIR, "benchmark_history.json"),
        {
            "schema_version": SCHEMA_VERSION,
            "symbol": "Au99.99",
            "name": "上海黄金交易所 Au99.99",
            "unit": "CNY/g",
            "source": "sge.com.cn",
            "updated_at": None,
            "records": [],
        },
    )
    brand_doc = load_json(
        os.path.join(DATA_DIR, "brand_history.json"),
        {
            "schema_version": SCHEMA_VERSION,
            "source": "证券之星 零售金商报价",
            "updated_at": None,
            "records": [],
        },
    )

    bank_doc = load_json(
        os.path.join(DATA_DIR, "bank_bar_history.json"),
        {
            "schema_version": SCHEMA_VERSION,
            "source": "金价查询网 各大银行/品牌金店金条价格一览表",
            "updated_at": None,
            "records": [],
        },
    )

    ok = 0

    # -------- 1. 大盘金价 -------- #
    try:
        fresh = fetch_benchmark_history("Au99.99")
        merged = {r["date"]: r for r in bench_doc.get("records", [])}
        for rec in fresh:
            merged[rec["date"]] = rec
        records = [merged[d] for d in sorted(merged)]
        bench_doc["records"] = records
        bench_doc["updated_at"] = now_cst()
        ok += 1
        print(
            "[ok] 大盘 Au99.99: 本次 {} 条 / 累计 {} 条 / 最新 {} 收 {}".format(
                len(fresh), len(records), records[-1]["date"], records[-1]["close"]
            )
        )
    except FetchError as exc:
        print("[warn] 大盘金价采集失败，沿用已有数据: {}".format(exc))

    # -------- 2. 品牌报价 -------- #
    brands = []
    brand_date = None
    try:
        quotes = fetch_brand_quotes()
        brand_date = quotes["date"]
        brands = quotes["brands"]
        days = {r["date"]: r for r in brand_doc.get("records", [])}
        days[brand_date] = {"date": brand_date, "brands": brands}
        brand_doc["records"] = [days[d] for d in sorted(days)]
        brand_doc["updated_at"] = now_cst()
        ok += 1
        mainland = [b for b in brands if b["region"] == "mainland"]
        print("[ok] 品牌报价: {} 家（大陆 {}） / 数据日期 {}".format(
            len(brands), len(mainland), brand_date))
    except FetchError as exc:
        print("[warn] 品牌报价采集失败，沿用已有数据: {}".format(exc))
        if brand_doc.get("records"):
            last = brand_doc["records"][-1]
            brand_date = last["date"]
            brands = last["brands"]

    # -------- 3. 银行金条报价 -------- #
    bank_items = []
    bank_date = None
    try:
        bars = fetch_bank_bars()
        bank_date = bars["date"]
        bank_items = bars["items"]
        days = {r["date"]: r for r in bank_doc.get("records", [])}
        days[bank_date] = {"date": bank_date, "items": bank_items}
        bank_doc["records"] = [days[d] for d in sorted(days)]
        bank_doc["updated_at"] = now_cst()
        ok += 1
        n_bank = len([b for b in bank_items if b["is_bank"]])
        print("[ok] 银行金条: {} 条（其中银行 {} 家） / 数据日期 {}".format(
            len(bank_items), n_bank, bank_date))
    except FetchError as exc:
        print("[warn] 银行金条采集失败，沿用已有数据: {}".format(exc))
        if bank_doc.get("records"):
            last = bank_doc["records"][-1]
            bank_date = last["date"]
            bank_items = last["items"]

    if ok == 0 and not bench_doc.get("records") and not brands:
        print("[error] 没有任何可用数据")
        return 1

    bench_records = bench_doc.get("records", [])
    last_bench = bench_records[-1] if bench_records else None

    # -------- 3.5 宏观因子 -------- #
    macro_doc = load_json(
        os.path.join(DATA_DIR, "macro.json"),
        {
            "schema_version": SCHEMA_VERSION,
            "source": "东方财富",
            "updated_at": None,
            "series": {},
        },
    )
    macro_series = macro_doc.get("series", {})
    try:
        macro = fetch_macro()
        # 合并而不是覆盖：某条序列这次没抓到，要保留上次的值，
        # 否则一次网络抖动就会把已有因子抹掉（这正是本项目一直坚持的原则）。
        merged = dict(macro_series)
        for key, rec in macro["series"].items():
            points = rec.get("points") or []
            merged[key] = {
                "name": rec["name"],
                "date": rec["date"],
                "value": rec["value"],
                "chg20_pct": pct_change(points, 20),
                "chg30_pct": pct_change(points, 30),
                "history_points": len(points),
            }
        # 合并是为了保留旧值，但已停用的源要清掉
        macro_series = {k: v for k, v in merged.items() if k in MACRO_KEYS}
        macro_doc["series"] = macro_series
        if macro.get("errors"):
            print("[warn] 部分宏观序列失败（沿用旧值）: "
                  + " | ".join(macro["errors"]))
        macro_doc["updated_at"] = now_cst()
        ok += 1
        parts = []
        for key in ("dxy", "usdcny", "gold_spot"):
            rec = macro_series.get(key)
            if rec:
                parts.append("{} {} ({:+.2f}% 近20日)".format(
                    rec["name"], rec["value"], (rec["chg20_pct"] or 0) * 100))
        print("[ok] 宏观因子: " + " | ".join(parts))
    except FetchError as exc:
        print("[warn] 宏观因子采集失败，沿用已有数据: {}".format(exc))

    # -------- 4. 统计与溢价 -------- #
    mainland = [b for b in brands if b.get("region") == "mainland"]
    golds = {b["name"]: b["gold"] for b in mainland if isinstance(b.get("gold"), (int, float))}
    bars = {b["name"]: b["bar"] for b in mainland if isinstance(b.get("bar"), (int, float))}
    plats = {b["name"]: b["platinum"] for b in mainland if isinstance(b.get("platinum"), (int, float))}

    benchmark_ref = None
    if bench_records and brand_date:
        benchmark_ref = next((r for r in reversed(bench_records) if r["date"] == brand_date), None)
    if benchmark_ref is None:
        benchmark_ref = last_bench

    premium = None
    if benchmark_ref and golds:
        avg_gold = round(sum(golds.values()) / len(golds), 2)
        base = benchmark_ref["close"]
        premium = {
            "benchmark_date": benchmark_ref["date"],
            "benchmark_close": base,
            "brand_gold_avg": avg_gold,
            "brand_gold_min": min(golds.values()),
            "brand_gold_max": max(golds.values()),
            "amount": round(avg_gold - base, 2),
            "pct": round((avg_gold - base) / base, 4),
        }

    latest = {
        "schema_version": SCHEMA_VERSION,
        "generated_at": now_cst(),
        "data_date": brand_date,
        "benchmark": dict(
            {"symbol": "Au99.99", "name": "上海黄金交易所 Au99.99",
             "unit": "CNY/g", "source": "sge.com.cn"},
            **(last_bench or {}),
        ),
        "brands": brands,
        "brand_stats": {
            "gold": dict_stat(golds),
            "bar": dict_stat(bars),
            "platinum": dict_stat(plats),
        },
        "bank_bars": {
            "date": bank_date,
            "unit": "CNY/g",
            "items": bank_items,
            "stats": dict_stat({
                b["name"]: b["price"] for b in bank_items if b.get("is_bank")
            }),
        },
        "premium": premium,
    }

    save_json(os.path.join(DATA_DIR, "benchmark_history.json"), bench_doc)
    save_json(os.path.join(DATA_DIR, "brand_history.json"), brand_doc)
    save_json(os.path.join(DATA_DIR, "bank_bar_history.json"), bank_doc)
    save_json(os.path.join(DATA_DIR, "macro.json"), macro_doc)
    save_json(os.path.join(DATA_DIR, "latest.json"), latest)

    # -------- 4. 打印摘要 -------- #
    print("")
    print("========== 今日摘要 ==========")
    if last_bench:
        print("大盘 Au99.99  {} 收盘 {:.2f} 元/克".format(last_bench["date"], last_bench["close"]))
    if golds:
        gs = latest["brand_stats"]["gold"]
        print("品牌首饰金    {} 家 | 最低 {} {} | 最高 {} {} | 均价 {} 元/克".format(
            gs["count"], gs["min"]["name"], gs["min"]["price"],
            gs["max"]["name"], gs["max"]["price"], gs["avg"]))
    if bars:
        bs = latest["brand_stats"]["bar"]
        print("品牌金条      {} 家 | 最低 {} {} | 最高 {} {} | 均价 {} 元/克".format(
            bs["count"], bs["min"]["name"], bs["min"]["price"],
            bs["max"]["name"], bs["max"]["price"], bs["avg"]))
    if premium:
        print("首饰金溢价    均价高出大盘 {:.2f} 元/克（{:.1f}%）".format(
            premium["amount"], premium["pct"] * 100))
    bs = latest["bank_bars"]["stats"]
    if bs:
        print("银行金条      {} 家 | 最低 {} {} | 最高 {} {} | 均价 {} 元/克".format(
            bs["count"], bs["min"]["name"], bs["min"]["price"],
            bs["max"]["name"], bs["max"]["price"], bs["avg"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
