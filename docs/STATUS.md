# 项目进度交接（2026-09-12 暂停）

## 一句话状态

数据层、分析层、App **全部完成并验证**：
`flutter analyze` 与 `dart analyze` 均 **No issues found**，跨语言一致性 **98/98** 通过，
release APK 已构建（51.2MB，含离线快照）。

**GitHub 仓库已上线、Actions 已验证可自动采集并提交数据。**
**剩余仅一项需要人工完成：装到小米 13 Ultra 上验证通知真机可用。**

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

## 更新：2026-09-14 —— 真机全链路验证通过 🎉

**在小米 13 Ultra（2304FPN6DC / Android 16 / HyperOS V816）上实测通过。**

### 通过 USB 调试实测到的结果

| 检查项 | 证据 |
| --- | --- |
| App 安装并运行 | 进程存活、无崩溃 |
| **拉到实时数据** | 首页显示 939.54 元/克，**无「打包快照」提示** |
| 今日汇总页 | 渠道对比 / 大盘 / 提醒 / 品牌比价 全部正确渲染 |
| 趋势页 | 折线图 + MA60 + 区间指标（区间涨跌 +34.07%、距高点 -24.41%） |
| 工具页 | 一口价折算、预算可买克重、五金清单 |
| 提醒页 | 正确检测通知权限状态；「立即检查」返回「数据日期 2026-09-11 触发 1 条」|
| **通知真的弹出** | 系统 NotificationRecord（id=9001, channel=goldprice_alerts）|
| 通知渠道 | `NotificationChannel{mId='goldprice_alerts', mName=金价提醒, mImportance=4}` |
| 电池优化白名单 | `dumpsys deviceidle whitelist` 含 com.liangaokai.goldprice |
| **后台定时任务** | `dumpsys jobscheduler` 中有 `androidx.work...SystemJobService` |

### 修掉了一个只在真机上才暴露的严重 bug

**现象**：App 装在手机上后首页**一直转圈**，永不结束。

**诊断**（用手机自带的 curl 实测）：

| 数据源 | 手机实测 |
| --- | --- |
| raw.githubusercontent.com | **HTTPS 一直超时**（ping 通，但 HTTPS 被墙）|
| cdn.jsdelivr.net | 通，但**慢到 8.85 秒** |

而原实现的问题有两层：
1. 超时只设了 6 秒 —— 比 jsDelivr 的实际耗时还短；
2. **`client.getUrl()` 没有独立超时** —— 连接被黑洞时会永久挂起，
   于是 `Future.wait` 永不完成，界面一直转圈。

**修复**：
- 改为**顺序尝试、第一个成功即返回**
- 每个源都有**覆盖整个请求**的超时，且所有源合计不超过总预算（14s）——
  保证最坏情况也有上限，之后走离线快照
- 候选顺序按手机实测重排：
  `api.github.com`（**0.64s，且内容最新**）→ `gcore.jsdelivr.net`（3.3s）
  → `cdn.jsdelivr.net`（5.5s）→ `raw.githubusercontent.com`（常被墙）
- 顺带支持了 GitHub 内容接口的 base64 信封

另外把通知小图标从彩色启动图标换成**单色矢量图**（否则状态栏会显示成白方块）。

## 更新：2026-09-14 —— 「一键跳系统设置」按钮（保活关键）✅

### 背景

小米 HyperOS 的省电策略会杀后台，是**通知能否真的按时弹出**的最大风险点。
之前设置页只能「用文字告诉用户去改设置」，这轮改成**直接跳转**。

### 实现（原生 MethodChannel，不引入任何第三方依赖）

- `app/android/.../MainActivity.kt` —— 三个方法：
  - `isIgnoringBatteryOptimizations`：查是否已加入电池优化白名单
  - `openBatteryOptimizationSettings`：弹系统「忽略电池优化」授权框
    （失败则退到电池优化设置列表）
  - `openAutostartSettings`：**按 ComponentName 依次尝试各家 ROM 的私有自启动页**，
    小米（`com.miui.permcenter.autostart.AutoStartManagementActivity`）排在最前，
    另有华为 / OPPO / vivo 的页面；全失败退回应用详情页
- `app/lib/services/system_channel.dart` —— Dart 侧封装
- 设置页新增三个按钮 + **电池优化状态实时显示**，
  并用 `WidgetsBindingObserver` 在**从系统设置页返回时自动刷新状态**
- 清单新增 `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`（仅个人侧载使用，不上架）

### 验证证据

```
aapt2 dump badging → uses-permission: REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
classes.dex 内含字符串：
  com.liangaokai.goldprice/system
  com.miui.permcenter.autostart
  isIgnoringBatteryOptimizations / openAutostartSettings / openBatteryOptimizationSettings
flutter analyze → No issues found
```

## 更新：2026-09-14 凌晨 —— 仓库上线 + 修复一个重要 bug ✅

### 1. GitHub 仓库已上线，Actions 端到端跑通

仓库：https://github.com/liangok/gold-price-monitor （public）

**实测证据：**
- 运行结果：`采集金价数据 | event=push | conclusion=success`
- **工作流成功把数据提交回仓库**：`7649a6d data: 更新金价数据 2026-09-13`
- 说明工作流里显式声明的 `permissions: contents: write` 生效，
  **不需要另外去改 Settings 里的 Workflow permissions**
- 采集时间表：每天北京时间 **10:40** 与 **16:00** 自动跑，也可在 Actions 页手动触发

> 小提示：首次 push 没有触发工作流，第二次 push（改动了 collector / workflow 路径）正常触发。

### 2. ⚠️ 修复了一个会导致「一整天显示旧价格」的 bug

**现象**：检查线上数据时发现 jsDelivr 返回的是旧版本。

**根因**（实测响应头）：
```
cache-control: public, max-age=604800, s-maxage=43200
```
`s-maxage=43200` = **12 小时 CDN 缓存**。而原实现把 jsDelivr 放在首选，
意味着这个每日更新的 App 可能**一整天都在显示昨天的金价**。
实测加随机查询串也穿不透缓存（连续 3 次都返回旧版本）。

**修复**：不再按顺序取第一个，改为**并发请求两个源，
按数据自带的 generated_at / updated_at 取较新的那份**。
逻辑放进领域层 `fetchFreshest()`（App 与后台提醒共用），并补了单元测试。

**实证验证**（`dart run tool/check_sources.dart`）：
```
raw      = 2026-09-13T22:13:42+08:00   （实时）
jsDelivr = 2026-09-13T22:04:43+08:00   （落后 9 分钟）
fetchFreshest 选中 = 2026-09-13T22:13:42+08:00   ← 正确选了较新的
```

若 raw 在国内不通，仍会自动用 jsDelivr（可能略旧但可达）；
提醒侧还有 72 小时新鲜度保护，不会基于陈旧数据误报。

### 3. 新增诊断工具

`packages/goldprice_domain/tool/check_sources.dart` —— 随时查看两个源各自的数据
时间戳以及最终选中哪一个。

## 更新：2026-09-13 深夜（三）—— 自定义应用图标 ✅

之前 App 用的是 **Flutter 默认 logo**，装到手机上很像「半成品」。这轮换成自绘图标。

### 做法

`scripts/gen_icon.py` —— **不依赖任何第三方库**（本机没有 Pillow）：
手写 PNG 编码器（zlib + IHDR/IDAT/IEND），在 1024×1024 上绘制硬边图形，
再用 macOS 自带 `sips` 缩到各密度（放大→缩小天然抗锯齿）。

设计：深色渐变底 + 金色上行折线 + 末端高亮点，一眼能看出「金价走势」。

### 产出

- 传统图标 `mipmap-*/ic_launcher.png`：48 / 72 / 96 / 144 / 192 px
- **自适应图标**前景 `mipmap-*/ic_launcher_foreground.png`：108 / 162 / 216 / 324 / 432 px
- `mipmap-anydpi-v26/ic_launcher{,_round}.xml`（现代 Android 用这个，会自动裁切/遮罩）
- `values/colors.xml`（自适应背景色 #10131A）

### 验证

```
aapt2 dump badging → application: label='金价监控' icon='res/BW.xml'   ← 已指向自适应图标
aapt2 dump resources → mipmap/ic_launcher 与 mipmap/ic_launcher_foreground
                       各 5 个密度均已打进 APK
```

## 更新：2026-09-13 深夜（二）—— lint 清零 + 新增工具页 ✅

### 1. lint 全部清理完毕

`flutter analyze` 从 **62 条** → **No issues found**；`dart analyze`（领域层）同样干净。

主要是 60 条 `prefer_interpolation_to_compose_strings`（字符串拼接 → 插值）
与 2 条 `prefer_final_fields`。顺带修掉了过程中新引入的
7 条 `unnecessary_brace_in_string_interps`。

### 2. 新增「工具」页（底部导航第 3 项）

- **一口价折算克价（防坑）**：输入总价与克重，算出真实克价，
  并与大盘价、当日品牌首饰金均价对比，给出「严重偏贵 / 偏贵 / 略贵 / 划算」判定。
  复用了领域层里已有测试覆盖的 `evaluateOnePrice`。
- **预算能买多少克**：输入预算，实时显示品牌店 / 水贝 / 银行金条打金三条路线各能买多少克。

### 3. 采集器回归验证

隔一天重跑采集，两个数据源均正常：品牌金价与银行金条已更新到 **2026-09-13**。
（9/12、9/13 是周六日，上金所无行情，大盘仍是 9/11 收盘的 939.54。）

## 更新：2026-09-13 深夜 —— 通知栏提醒已完成 ✅

目标里的「**按策略发送手机通知栏提醒**」这一项，代码写完并构建验证通过。

### 新增文件

- `lib/services/notification_service.dart` —— 通知封装（含 Android 13+ 运行时授权）
- `lib/services/alert_settings.dart` —— 提醒设置存本机（SharedPreferences），
  并实现「同一规则同一天只提醒一次」的去重
- `lib/services/alert_runner.dart` —— 拉行情 → 判定策略 → 发通知
- `lib/services/background_worker.dart` —— WorkManager 每 6 小时后台检查
- `lib/ui/settings_page.dart` —— 新增「提醒」标签页：
  开关 / 目标价 / 发送测试通知 / 立即检查 / 小米保活说明

### 两个刻意的设计决定

1. **提醒只基于真实网络数据，绝不使用离线快照**。
   用打包快照判定可能因数据陈旧而误报。
2. **数据新鲜度保护**：`latest.json` 的 `generated_at` 超过 **72 小时** 未更新就跳过提醒，
   避免采集端挂掉后还在用旧行情发通知。

另外：回撤 / 均线属于「仅提示」，默认**不发通知**（回测里跑输基准，噪音大），
单独给了开关。

### Android 侧改动

- 开启 **desugaring**（`flutter_local_notifications` 的硬性要求，
  见 `app/android/app/build.gradle.kts` 的 `isCoreLibraryDesugaringEnabled` 与 `coreLibraryDesugaring`）
- 清单补 `RECEIVE_BOOT_COMPLETED`（重启后让 WorkManager 重新排程）

### 验证证据

```
uses-permission: name='android.permission.INTERNET'
uses-permission: name='android.permission.RECEIVE_BOOT_COMPLETED'
uses-permission: name='android.permission.POST_NOTIFICATIONS'
uses-permission: name='android.permission.VIBRATE'
uses-permission: name='android.permission.WAKE_LOCK'
uses-permission: name='android.permission.ACCESS_NETWORK_STATE'
application-label:'金价监控'

合并清单里已包含 WorkManager 组件：
  androidx.work.impl.background.systemjob.SystemJobService
  androidx.work.impl.background.systemalarm.RescheduleReceiver
  androidx.work.impl.WorkManagerInitializer

APK: 51.1MB，flutter analyze 0 error / 0 warning，flutter test 通过
```

### ⚠️ 仍需真机验证（我这边做不到）

- 通知能否真的弹出来（建议先点设置页的「发送测试通知」）
- WorkManager 在小 米 HyperOS 上能否按时唤醒 —— 这是小米最容易拦的地方

### 关于目标里的「分位」策略 —— 刻意不实现（有证据）

目标描述里列了「目标价 / 回撤 / 均线 / 分位」。前三个都已实现，
**「分位」经过专项验证后被刻意排除**，可复现：python3 analysis/percentile_probe.py

| 窗口 | 当前分位 | 10 年内触发 | 触发后 20 日收益 vs 基准 |
| --- | --- | --- | --- |
| 1 年 | 55.1% | 165 次 | +1.02% ~ +1.19%（基准 +1.39%，跑输） |
| 3 年 | 78.1% | **0 次** | — |
| 5 年 | 86.9% | **0 次** | — |

**窗口越长越没用**：金价十年单边上涨，价格几乎从不落在长窗口的低分位区。
一个永不触发、触发后还跑输基准的规则比没有更糟 —— 会让人误以为有保护。

结论：不实现。若将来金价进入长期下行周期，重跑该脚本即可重新评估。

### 已知未做

- ~~49 条 info 级 lint~~ → **已全部清零**（见下方最新更新）
- GitHub 仓库仍未创建（见下一节）

## 更新：2026-09-13 晚 —— APK 已构建成功 ✅

**产物：`app/build/app/outputs/flutter-apk/app-release.apk`（46.8MB）**

今天解决了三个问题：

1. **NDK 版本不一致**：你装的是 `30.0.16248370`，Flutter 默认要 `28.2.13676358`。
   已在 `app/android/app/build.gradle.kts` 里显式对齐到本机版本（项目无原生代码，任意版本均可）。
2. **缺 Android SDK Platform 36**：本机只有 `android-37.0`，Gradle 已自动装上 36。
3. **⚠️ release 包缺 INTERNET 权限（关键 bug）**：
   Flutter 模板只把 `INTERNET` 放进 debug / profile 清单，**不会进入 release 包**，
   正式版装到手机上会完全无法联网。已在 `app/android/app/src/main/AndroidManifest.xml` 补上，
   并用 `aapt2 dump badging` 验证通过。

另外：
- 应用名改为「**金价监控**」
- 新增**离线快照**：`data/*.json` 与 `config/user.json` 会被复制到 `app/assets/data/`
  一起打进 APK；网络拉不到时自动回退，首页显示提示。
  （`scripts/sync-assets.sh`，已接进 `scripts/build-apk.sh` 第一步）

### 验证证据

```
package: name='com.liangaokai.goldprice' versionCode='1' versionName='0.1.0'
uses-permission: name='android.permission.INTERNET'
application-label:'金价监控'
minSdkVersion:'24'  targetSdkVersion:'36'  compileSdkVersion='36'
APK 内含 assets/data/{latest,benchmark_history,brand_history,bank_bar_history,user}.json
```

### 仍然待办

- **GitHub 仓库还没建**：`liangok/gold-price-monitor` 返回 404（SSH 探测 Repository not found）。
  remote 已配好、SSH 已认证为 `liangok`，仓库建好后 `git push -u origin main` 即可。
- 通知栏提醒 + 小米 HyperOS 保活引导（未开始）
- 35 条 info 级 lint（不影响运行）

## 更新：2026-09-13（第二次排查）

停掉 Gradle 守护进程后，把 `ndkVersion` 从 `app/android/app/build.gradle.kts` 去掉，
错误**从「安装失败」变成**：

```
NDK not configured. Download it with SDK manager.
Preferred NDK version is '28.2.13676358'.
```

**结论：这个 NDK 是 AGP 9.1 在配置阶段就强制的，不是我们项目需要** ——
项目里没有任何 `externalNativeBuild` / `jniLibs` / 原生代码。

所以：**装好 NDK 就能过，代码不用改。** 已把 `build.gradle.kts` 恢复成
Flutter 模板标准写法（`ndkVersion = flutter.ndkVersion`）。

**要装的版本：`28.2.13676358`**（Flutter 与 AGP 都指定这个）。

装完验证：

```
cd app/android && ./gradlew --stop
cd ../.. && bash scripts/build-apk.sh
```

> 如果 Android Studio 只提供其它版本，改 `app/android/app/build.gradle.kts` 里的
> `ndkVersion` 与之对齐即可（或把那行去掉，让 AGP 用它自己的首选版本）。

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
