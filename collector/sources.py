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

import csv
import io
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


# --------------------------------------------------------------------------- #
# 宏观因子：伦敦金现 / 美元指数 / 人民币汇率
#
# 用来判断「当前对买家是顺风还是逆风」。全部是**数值序列**，不需要任何 AI ——
# 判断规则写在 App 的领域层里，权重与依据都可见、可测试。
#
# 数据源用新浪财经（实测最稳，国内与 GitHub Actions 上都通）：
#   - 实时值：hq.sinajs.cn
#   - 日线历史：vip.stock…（外汇）/ stock2…（国际期货），可回溯多年
#
# 换过两个源：东财 kline 密集请求后会被掐连接；stooq / Yahoo 分别被
# JS 挑战与限流挡住。伦敦金用**现货**而不是 COMEX 期货 —— 算「国内贵了多少」
# 时期货基差（实测约 1%）会直接把结论带偏。
# --------------------------------------------------------------------------- #
SINA_HEADERS = {"Referer": "https://finance.sina.com.cn"}

# (key, 实时代码, 名称, 历史类型, 历史代码)
MACRO_SERIES = (
    ("gold_spot", "hf_XAU", "伦敦金现", "futures", "XAU"),
    ("dxy", "DINIW", "美元指数", "forex", "DINIW"),
    ("usdcny", "fx_susdcny", "在岸人民币", "forex", "fx_susdcny"),
)


#: 当前使用的宏观序列键。采集端据此清理「已经停用的旧源」残留。
MACRO_KEYS = tuple(item[0] for item in MACRO_SERIES) + ("us2y", "us10y")


def _sina_extract_quoted(text):
    start = text.find('"')
    end = text.rfind('"')
    if start < 0 or end <= start:
        return None
    return text[start + 1:end]


def fetch_sina_live(codes):
    """一次抓多个实时值，返回 {代码: 原始字段串}。"""
    body = _http_get("https://hq.sinajs.cn/list=" + ",".join(codes),
                     headers=SINA_HEADERS)
    out = {}
    for m in re.finditer(r'hq_str_([A-Za-z0-9_]+)="([^"]*)"', body):
        out[m.group(1)] = m.group(2)
    if not out:
        raise FetchError("新浪实时行情为空")
    return out


def fetch_sina_history(kind, code):
    """抓新浪日线历史，返回按日期升序的 [{date, close}, ...]。"""
    if kind == "forex":
        url = ("https://vip.stock.finance.sina.com.cn/forex/api/jsonp.php/"
               "var%20_k=/NewForexService.getDayKLine?symbol=" + code)
    else:
        url = ("https://stock2.finance.sina.com.cn/futures/api/jsonp.php/"
               "var%20_k=/GlobalFuturesService.getGlobalFuturesDailyKLine?symbol=" + code)
    body = _http_get(url, headers=SINA_HEADERS)

    points = []
    if kind == "forex":
        # 形如：date,open,close,high,low,|date,open,close,high,low,|…
        payload = _sina_extract_quoted(body)
        if not payload:
            raise FetchError("新浪日线格式异常: " + code)
        for chunk in payload.split("|"):
            parts = chunk.split(",")
            if len(parts) < 3:
                continue
            try:
                points.append({"date": parts[0], "close": float(parts[2])})
            except ValueError:
                continue
    else:
        start = body.find("[")
        end = body.rfind("]")
        if start < 0 or end <= start:
            raise FetchError("新浪日线格式异常: " + code)
        try:
            raw = json.loads(body[start:end + 1])
        except json.JSONDecodeError as exc:
            raise FetchError("新浪日线解析失败: " + code) from exc
        for item in raw:
            try:
                points.append(
                    {"date": str(item["date"]), "close": float(item["close"])})
            except (KeyError, TypeError, ValueError):
                continue

    if len(points) < 2:
        raise FetchError("新浪日线为空: " + code)
    points.sort(key=lambda p: p["date"])
    return points


TREASURY_CSV_URL = (
    "https://home.treasury.gov/resource-center/data-chart-center/interest-rates/"
    "daily-treasury-rates.csv/{year}/all"
    "?type=daily_treasury_yield_curve&field_tdr_date_value={year}&page&_format=csv"
)


def fetch_us_treasury_yields(years=None):
    """
    抓**美国财政部官方**的国债收益率曲线（日度，含 2 年期与 10 年期）。

    为什么用它而不是别的：
      - 官方一手数据，无需 key，GitHub Actions 上稳定可达
      - 有完整历史（回测就是用它做的，见 analysis/yield_backtest.py）
      - 2 年期是「美联储预期」最直接的度量：近 20 个交易日变动在回测里
        对金价前向收益有明确、单调的信号（下行时前向 60 日 +7.53% vs 基准 +3.49%）
    同日取**前一年 + 当年**，避免跨年时凑不满 20 日回看窗口。
    """
    if years is None:
        this_year = datetime.now(CST).year
        years = (this_year - 1, this_year)

    points = []
    errors = []
    for year in years:
        try:
            body = _http_get(TREASURY_CSV_URL.format(year=year))
        except FetchError as exc:
            errors.append("{}: {}".format(year, exc))
            continue
        for row in csv.DictReader(io.StringIO(body)):
            raw = row.get("Date")
            if not raw:
                continue
            try:
                month, day, year_part = raw.split("/")
                points.append({
                    "date": "{}-{:02d}-{:02d}".format(
                        year_part, int(month), int(day)),
                    "y2": float(row["2 Yr"]),
                    "y10": float(row["10 Yr"]),
                })
            except (ValueError, KeyError):
                continue

    if len(points) < 2:
        raise FetchError("财政部收益率曲线为空：" + " | ".join(errors))
    points.sort(key=lambda p: p["date"])
    return points


def fetch_macro():
    """
    抓取宏观因子：实时值 + 日线历史。

    允许部分失败 —— 少一条不影响其它，也不该让采集整体失败。
    """
    series = {}
    errors = []

    live = {}
    try:
        live = fetch_sina_live([code for _, code, _, _, _ in MACRO_SERIES])
    except FetchError as exc:
        errors.append("实时值: {}".format(exc))

    for key, live_code, name, kind, hist_code in MACRO_SERIES:
        try:
            points = fetch_sina_history(kind, hist_code)
        except FetchError as exc:
            errors.append("{}: {}".format(key, exc))
            continue

        value = points[-1]["close"]
        raw = live.get(live_code)
        if raw:
            try:
                value = float(raw.split(",")[0])
            except (ValueError, IndexError):
                pass
        series[key] = {
            "name": name,
            "date": points[-1]["date"],
            "value": value,
            "points": points,
        }
        time.sleep(1.2)  # 对新浪也保持礼貌

    try:
        ust = fetch_us_treasury_yields()
        series["us2y"] = {
            "name": "美债2年",
            "date": ust[-1]["date"],
            "value": ust[-1]["y2"],
            "points": [{"date": p["date"], "close": p["y2"]} for p in ust],
        }
        series["us10y"] = {
            "name": "美债10年",
            "date": ust[-1]["date"],
            "value": ust[-1]["y10"],
            "points": [{"date": p["date"], "close": p["y10"]} for p in ust],
        }
    except FetchError as exc:
        errors.append("us_treasury: {}".format(exc))

    if not series:
        raise FetchError("全部宏观序列都抓取失败：" + " | ".join(errors))
    return {"series": series, "errors": errors}
