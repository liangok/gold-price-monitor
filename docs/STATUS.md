# 项目进度交接（2026-09-12 暂停）

## 一句话状态

数据层与分析层**已完成并验证**；App 界面代码已写完、静态分析 0 error、跨语言一致性测试 98/98 通过。
**只剩最后一步：构建 APK 时被「NDK 安装」卡住。**

## 一、已完成并验证

### 1. 数据采集（可用，零第三方依赖）

| 数据 | 来源 | 规模 |
| --- | --- | --- |
| 大盘 Au99.99 日线 | 上海黄金交易所 | 2016-12 至今 2363 个交易日 |
| 品牌金店报价 | 证券之星「零售金商报价」 | 12 个大陆品牌 + 6 个香港品牌（黄金/金条/铂金） |
| 银行金条报价 | 金价查询网 | 11 家银行（最低建行 955.80，最高中行 962.93） |

- GitHub Actions 每天北京时间 10:40 与 16:00 自动采集并提交
- 单源失败会保留旧数据；重复运行不产生重复记录（均已实测）
- 采集入口：`collector/collect.py`

### 2. 策略回测（结论已回灌设计）

用 10 年真实数据回测（`analysis/backtest_report.md`），**推翻了最初的直觉设计**：

- 回撤 / 均线类规则**跑输**「随便哪天买」（20 日 +0.37%~+0.80%，基准 +1.39%）
- 「历史分位」规则近 3 年触发 **0 次**，已从设计中移除
- 真正有价值的是稀有恐慌信号：RSI14<30（10 年 39 次，20 日 +3.02%）、单日跌幅≥2%（51 次，+1.96%）
- 分批买入在本样本中平均成本**更高**（单边上涨），它的价值是降风险，不是省钱
- 择时收益只有几个百分点，而渠道差价约 **40%**

### 3. 领域层（纯 Dart，可独立测试）

`packages/goldprice_domain/`，不依赖 Flutter，也不依赖任何第三方包。

```
dart run tool/verify.dart
→ 全部通过：98 项断言，Dart 领域层与 Python 参考实现一致。
```

覆盖：数据模型、技术指标（与 `analysis/indicators.py` 逐值对齐）、提醒规则（11 组参数变体）、
渠道对比、一口价折价、数据源地址构造。

### 4. App 界面（`app/`）

- 今日页：**渠道对比（首屏）** → 大盘金价 → 提醒 → 品牌比价
- 趋势页：30 天 ~ 全部曲线、MA60、区间指标
- v1 刻意**零第三方依赖**：用 `dart:io` 发请求、`CustomPainter` 画图
- `flutter analyze`：0 error / 0 warning（35 条 info 级样式提示待清理）
- `flutter test`：通过
- 数据源配置在 `app/lib/config.dart` —— **待填你的 GitHub 用户名 / 仓库名**

### 5. 工具链（都在仓库内，已 gitignore）

- `tools/flutter`：Flutter 3.47.4（x64 版，在 M3 上走 Rosetta，已验证可用）
- `.toolhome/`：Gradle 9.3.1 与 pub 缓存约 1.8G —— **明天不用重下**
- `scripts/dev-env.sh`：自动接上 Android Studio 的 JDK 25 与 Android SDK
  （还会探测 `$HOME` 是否可写，不可写时自动把缓存收进仓库）

## 二、当前卡点：构建 APK 时 NDK 安装失败

现象：

```
flutter build apk --release
→ Failed to install SDK components: ndk;28.2.13676358
   The SDK directory is not writable (/Users/liangaokai/Library/Android/sdk)
```

已排查出的原因：

1. Gradle 9.3.1 + AGP 9.1.0 在**配置阶段**就要求 NDK 28.2.13676358。
2. Flutter 插件源码里并没有给 app 赋值 ndkVersion（只有读取），
   所以从 `app/android/app/build.gradle.kts` 删掉 `ndkVersion = flutter.ndkVersion` **没有用**（已试过，已还原）。
3. 安装目标 `~/Library/Android/sdk` 在工作区之外，被文件沙箱拒绝。
4. 申请更高权限重试后**仍然失败** —— 很可能是 Gradle 守护进程是在受限沙箱下启动的，
   没有继承新权限。

## 三、明天从这里开始（按推荐顺序）

### 方案 1：用 Android Studio 图形界面装 NDK（最稳，推荐）

Android Studio → Settings → Languages & Frameworks → Android SDK → **SDK Tools**
→ 勾选 **NDK (Side by side)**（版本 28.2.13676358）→ Apply。

装完后重启 Gradle 守护进程再构建：

```
cd app/android && ./gradlew --stop
cd ../.. && bash scripts/build-apk.sh
```

### 方案 2：命令行安装

先补上 `cmdline-tools`（Android Studio 默认不带），再：

```
sdkmanager "ndk;28.2.13676358"
```

### 方案 3：让 Gradle 装到仓库内的 SDK 副本

把 `ANDROID_HOME` 指向工作区里的 SDK 副本（只 symlink platforms/build-tools 等只读部分），
`ndk/` 留成真实可写目录，Gradle 就能自己装 NDK，完全不需要额外权限。

> 若 NDK 装好后仍报错，先 `./gradlew --stop` 再试，排除守护进程缓存。

## 四、需要你提供

1. **GitHub 用户名 + 仓库名**（填进 `app/lib/config.dart`）
2. 确认仓库设为 **public** —— App 靠 jsDelivr / raw.githubusercontent 免密钥读取
3. 手机端：把仓库搭好后，进 GitHub 的 Settings → Actions → General →
   Workflow permissions 选 **Read and write permissions**

## 五、常用命令

```
source scripts/dev-env.sh          # 接上 JDK / Android SDK / Flutter
python3 collector/collect.py       # 手动跑一次采集
python3 analysis/today_signals.py  # 终端预览 App 首页会显示什么
python3 analysis/gen_dart_fixture.py   # 改了指标/策略后重新生成测试夹具
bash scripts/build-apk.sh          # 领域层自检 → 分析 → 构建 APK
```

## 六、尚未开始

- 通知栏提醒（需要 `flutter_local_notifications` + `workmanager`）
- 小米 HyperOS 后台保活引导页
- 把一口价折算、预算计算器接进界面
- 清理 35 条 info 级 lint
- 打包 release APK 并安装到小米 13 Ultra
