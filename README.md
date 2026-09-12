# GoldPrice · 结婚五金金价监控

每天自动采集 **大盘金价** 与 **各大品牌金店首饰报价**，为 Android App 提供今日汇总、历史趋势与买入提醒的数据底座。

## 为什么需要跟踪两套金价

买结婚五金时，真正要付的钱由两部分构成：

| 价格 | 当前水平（2026-09-12） | 说明 |
| --- | --- | --- |
| 大盘金价（上金所 Au99.99） | 939.54 元/克 | 金条、黄金 ETF 的定价基准 |
| 品牌首饰金（周大福/周生生等） | 1280 ~ 1313 元/克 | 高出大盘 **约 39%**（品牌溢价 + 工费） |
| 品牌投资金条 | 1122 ~ 1161 元/克 | 比首饰金便宜约 150 元/克 |

结论：同样 7.5 万预算，在品牌店大约能买 **55 克**，走水贝 / 银行金条打金路线能买约 **75 克**。
本项目把两套价格全部记录下来，帮你判断「现在贵不贵」以及「在哪儿买更划算」。

## 数据源

| 数据 | 来源 | 说明 |
| --- | --- | --- |
| 大盘金价 Au99.99 日线 | 上海黄金交易所 sge.com.cn | 2016-12 至今，2363 个交易日 |
| 品牌金店报价 | 证券之星「零售金商报价」 | 12 个大陆品牌 + 6 个香港品牌，含 黄金 / 金条 / 铂金 |

两套数据都**不需要 API Key**，采集脚本**只依赖 Python 标准库**，无需 pip install。

## 目录结构

```
GoldPrice/
├── collector/                  # 数据采集（Python，零依赖）
│   ├── sources.py              #   数据源抓取与解析
│   └── collect.py              #   主脚本：抓取 + 合并 + 生成 JSON
├── data/                       # 采集产出（Git 即数据库，自动积累历史）
│   ├── latest.json             #   今日汇总，App 首页直接消费
│   ├── benchmark_history.json  #   大盘日线（2016-12 至今）
│   └── brand_history.json      #   品牌报价历史（每天追加一条）
├── app/                        # Flutter App（开发中）
└── .github/workflows/collect.yml  # 每日定时采集
```

## 本地运行

```bash
python3 collector/collect.py
```

输出：

```
[ok] 大盘 Au99.99: 本次 2363 条 / 累计 2363 条 / 最新 2026-09-11 收 939.54
[ok] 品牌报价: 18 家（大陆 12） / 数据日期 2026-09-12
========== 今日摘要 ==========
大盘 Au99.99  2026-09-11 收盘 939.54 元/克
品牌首饰金    12 家 | 最低 中国黄金 1280 | 最高 老凤祥 1313 | 均价 1307.42 元/克
首饰金溢价    均价高出大盘 367.88 元/克（39.2%）
```

## 开启 GitHub 自动采集

1. 把本目录推送到 GitHub 仓库（例如 `gold-price-monitor`）。
2. 进入仓库 **Settings → Actions → General → Workflow permissions**，选择 **Read and write permissions** 并保存。
   （否则 Actions 无法把采集到的数据提交回仓库）
3. 进入 **Actions** 标签页，选择「采集金价数据」工作流，点 **Enable workflow**。
4. 之后每天北京时间 **10:40** 与 **16:00** 自动采集并提交；也可以在 Actions 页面手动 `Run workflow`。

## 数据结构

### data/latest.json —— App 首页

```json
{
  "data_date": "2026-09-12",
  "benchmark": { "symbol": "Au99.99", "date": "2026-09-11", "close": 939.54, "unit": "CNY/g" },
  "brands": [
    { "name": "周大福", "region": "mainland", "unit": "CNY/g", "gold": 1312, "bar": 1156 },
    { "name": "菜百首饰", "region": "mainland", "unit": "CNY/g", "gold": 1300, "bar": 1122, "platinum": 610 }
  ],
  "brand_stats": {
    "gold": { "min": {"name": "中国黄金", "price": 1280}, "max": {"name": "老凤祥", "price": 1313}, "avg": 1307.42, "spread": 33 },
    "bar":  { "min": {"name": "菜百首饰", "price": 1122}, "max": {"name": "老凤祥", "price": 1161}, "avg": 1150.8, "spread": 39 }
  },
  "premium": { "benchmark_close": 939.54, "brand_gold_avg": 1307.42, "amount": 367.88, "pct": 0.3916 }
}
```

- `brand_stats.*.min/max` 直接给出「今天哪家最便宜 / 最贵」，App 不需要自己算。
- `premium` 是首饰金相对大盘的溢价，是判断「现在买首饰是否划算」的核心指标。
- 香港品牌 `unit` 为 `HKD/两`（1 两 = 37.429 克），App 默认只展示大陆品牌。

### data/benchmark_history.json

```json
{
  "symbol": "Au99.99",
  "unit": "CNY/g",
  "records": [
    { "date": "2016-12-19", "open": 262.45, "close": 262.76, "low": 262.02, "high": 263.50 }
  ]
}
```

### data/brand_history.json

```json
{
  "records": [
    { "date": "2026-09-12", "brands": [ { "name": "周大福", "gold": 1312, "bar": 1156 } ] }
  ]
}
```

## 开发路线图

- [x] 采集层：大盘金价 + 品牌报价 + 每日自动积累历史
- [ ] Flutter App 骨架（Kotlin/Compose 之外的跨平台选择，兼顾以后给 iPhone 用）
- [ ] 今日汇总页：大盘价 + 品牌比价 + 渠道对比（品牌店 / 水贝 / 金条打金）
- [ ] 历史趋势页：30天 / 90天 / 1年 / 3年曲线 + 均线 + 历史分位
- [ ] 策略引擎：目标价、回撤、跌破均线、分位提醒
- [ ] 通知栏提醒 + 小米 HyperOS 后台保活引导
- [ ] 五金预算计算器 + 「一口价」折算克价防坑工具

## 免责声明

数据来自第三方公开网页，仅供个人参考，**不构成任何投资建议**。金价受多种因素影响，
任何策略都无法预测价格最低点，本项目只提供规则化提醒与分批买入辅助。
