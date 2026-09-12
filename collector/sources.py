#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
金价数据源采集与解析。

数据源
------
1. 上海黄金交易所 (sge.com.cn)
   大盘金价 Au99.99 完整历史日线（2016-12 至今）。
2. 证券之星 (stockstar.com)「零售金商报价」
   各大品牌金店报价，含 黄金 / 金条 / 铂金 三个品类。

本模块只依赖 Python 标准库，无需 pip install，方便在 GitHub Actions 上直接跑。
"""
from __future__ import annotations

import json
import re
import ssl
import time
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone

# 北京时间（避免依赖 tzdata）
CST = timezone(timedelta(hours=8))

UA = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
)

# 合理性区间，用于过滤解析错误 / 脏数据
MAINLAND_MIN, MAINLAND_MAX = 200.0, 5000.0      # 人民币元/克
HK_MIN, HK_MAX = 5000.0, 300000.0               # 港币元/两

SGE_DAILY_URL = "https://www.sge.com.cn/graph/Dailyhq"
STOCKSTAR_URL = "https://quote.stockstar.com/gold/salegold.shtml"

_TYPE_MAP = {"黄金": "gold", "金条": "bar", "铂金": "platinum", "白银": "silver"}


class FetchError(RuntimeError):
    """网络请求或解析失败。"""


def _http_get(url, data=None, headers=None, timeout=25, retries=3, backoff=2.0):
    """带重试的 GET，自动尝试 utf-8 / gbk / gb18030 解码。"""
    h = {"User-Agent": UA, "Accept-Language": "zh-CN,zh;q=0.9"}
    if headers:
        h.update(headers)
    last = None
    for attempt in range(1, retries + 1):
        try:
            req = urllib.request.Request(url, data=data, headers=h)
            ctx = ssl.create_default_context()
            with urllib.request.urlopen(req, timeout=timeout, context=ctx) as resp:
                raw = resp.read()
            for enc in ("utf-8", "gbk", "gb18030"):
                try:
                    return raw.decode(enc)
                except UnicodeDecodeError:
                    continue
            return raw.decode("utf-8", "ignore")
        except Exception as exc:  # noqa: BLE001
            last = exc
            if attempt < retries:
                time.sleep(backoff * attempt)
    raise FetchError("GET {} 失败: {}".format(url, last))


# --------------------------------------------------------------------------- #
# 大盘金价：上海黄金交易所
# --------------------------------------------------------------------------- #
def fetch_benchmark_history(symbol="Au99.99"):
    """返回按日期升序的日线列表 [{date, open, close, low, high}, ...]。"""
    body = _http_get(
        SGE_DAILY_URL,
        data=urllib.parse.urlencode({"instid": symbol}).encode(),
        headers={
            "Content-Type": "application/x-www-form-urlencoded",
            "Referer": "https://www.sge.com.cn/sjzx/mrhq",
        },
    )
    try:
        payload = json.loads(body)
    except json.JSONDecodeError as exc:
        raise FetchError("上金所返回的不是合法 JSON: {}".format(exc)) from exc

    rows = payload.get("time") or payload.get("data") or []
    records = []
    for row in rows:
        if not isinstance(row, (list, tuple)) or len(row) < 5:
            continue
        date = str(row[0])
        if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", date):
            continue
        try:
            rec = {
                "date": date,
                "open": float(row[1]),
                "close": float(row[2]),
                "low": float(row[3]),
                "high": float(row[4]),
            }
        except (TypeError, ValueError):
            continue
        if not (MAINLAND_MIN <= rec["close"] <= MAINLAND_MAX):
            continue
        records.append(rec)

    if not records:
        raise FetchError("上金所返回数据为空")
    records.sort(key=lambda r: r["date"])
    return records


# --------------------------------------------------------------------------- #
# 品牌金店报价：证券之星「零售金商报价」
# --------------------------------------------------------------------------- #
def _to_number(text):
    cleaned = re.sub(r"[^\d.]", "", text or "")
    if not cleaned:
        return None
    try:
        value = float(cleaned)
    except ValueError:
        return None
    return int(value) if value.is_integer() else value


def parse_brand_html(html):
    """
    解析「零售金商报价」表格。

    表格结构：品牌单元格带 rowspan，后续若干行只有 <类型, 价格, 单位>。
    """
    m = re.search(r'id="datatime"[^>]*>\s*数据时间[：:]\s*(\d{4}-\d{2}-\d{2})', html)
    if not m:
        m = re.search(r"数据时间[：:]\s*(\d{4}-\d{2}-\d{2})", html)
    data_date = m.group(1) if m else None

    collected = {}
    current = None
    for tr in re.findall(r"<tr[^>]*>(.*?)</tr>", html, re.S):
        tds = re.findall(r"<td([^>]*)>(.*?)</td>", tr, re.S)
        if not tds:
            continue

        cells = []
        for attrs, inner in tds:
            text = re.sub(r"<[^>]+>", " ", inner).replace("&nbsp;", " ")
            text = re.sub(r"\s+", " ", text).strip()
            rs = re.search(r"rowspan[^0-9]{0,3}(\d+)", attrs)
            cells.append((text, int(rs.group(1)) if rs else None))

        first_text = cells[0][0]
        is_brand = bool(first_text) and first_text not in _TYPE_MAP and (
            cells[0][1] is not None or len(cells) >= 4
        )
        if is_brand:
            current = first_text
            rest = cells[1:]
        elif first_text in _TYPE_MAP:
            rest = cells
        else:
            continue

        if current is None or len(rest) < 2:
            continue
        type_key = _TYPE_MAP.get(rest[0][0])
        if not type_key:
            continue
        price = _to_number(rest[1][0])
        if price is None:
            continue

        region = "hk" if current.startswith("香港") else "mainland"
        if region == "mainland":
            if not (MAINLAND_MIN <= price <= MAINLAND_MAX):
                continue
        elif not (HK_MIN <= price <= HK_MAX):
            continue

        entry = collected.setdefault(
            current,
            {
                "name": current,
                "region": region,
                "unit": "HKD/两" if region == "hk" else "CNY/g",
            },
        )
        entry[type_key] = price

    if not collected:
        raise FetchError("证券之星表格解析为空")

    result = list(collected.values())
    result.sort(key=lambda b: (b["region"] != "mainland", -(b.get("gold") or 0)))
    return {"date": data_date, "brands": result}


def fetch_brand_quotes():
    """抓取并解析品牌金店报价。"""
    html = _http_get(STOCKSTAR_URL)
    parsed = parse_brand_html(html)
    parsed["source"] = "证券之星 零售金商报价"
    parsed["url"] = STOCKSTAR_URL
    return parsed


# --------------------------------------------------------------------------- #
# 银行金条报价：金价查询网「各大银行/品牌金店金条价格一览表」
# --------------------------------------------------------------------------- #
HUANGJINJIAGE_BANK_URL = "http://www.huangjinjiage.cn/golden/155283.html"


def parse_bank_bar_html(html):
    """
    解析「各大银行/品牌金店金条价格一览表」。

    表格列：金条品牌 | 金条品种 | 今日价格 | 报价时间
    表头行因价格列不是「数字元/克」会被自动跳过。
    """
    m = re.search(r"更新[：:]\s*(\d{4})年(\d{1,2})月(\d{1,2})日", html)
    data_date = None
    if m:
        data_date = "{}-{:02d}-{:02d}".format(
            m.group(1), int(m.group(2)), int(m.group(3)))

    items = []
    for tr in re.findall(r"<tr[^>]*>(.*?)</tr>", html, re.S):
        cells = []
        for inner in re.findall(r"<td[^>]*>(.*?)</td>", tr, re.S):
            text = re.sub(r"<[^>]+>", " ", inner).replace("&nbsp;", " ")
            cells.append(re.sub(r"\s+", " ", text).strip())
        if len(cells) < 3:
            continue
        brand, product, price_text = cells[0], cells[1], cells[2]
        pm = re.search(r"(\d+(?:\.\d+)?)\s*元/克", price_text)
        if not pm:
            continue
        price = float(pm.group(1))
        if not (MAINLAND_MIN <= price <= MAINLAND_MAX):
            continue
        items.append({
            "name": brand,
            "product": product,
            "price": price,
            "quote_time": cells[3] if len(cells) > 3 else None,
            "is_bank": brand.endswith("银行"),
        })

    if not items:
        raise FetchError("金价查询网金条表格解析为空")
    return {"date": data_date, "items": items}


def fetch_bank_bars():
    """抓取银行与品牌金店的金条报价。"""
    html = _http_get(HUANGJINJIAGE_BANK_URL)
    parsed = parse_bank_bar_html(html)
    parsed["source"] = "金价查询网 各大银行/品牌金店金条价格一览表"
    parsed["url"] = HUANGJINJIAGE_BANK_URL
    return parsed
