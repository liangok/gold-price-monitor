import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:goldprice_domain/goldprice_domain.dart';

/// 只读数据仓库。
///
/// 取数优先级：
///   1. 网络（并发请求 raw 与 jsDelivr，取**数据时间戳较新**的那份，
///      原因见 domain 包 `fetchFreshest` 的注释：jsDelivr 有 12 小时 CDN 缓存）
///   2. **打包进 APK 的离线快照**（assets/data/）
///   3. 内存缓存
///
/// 加第 2 级的原因：仓库没建好、或临时断网时界面依然能用，
/// 不会只显示一句「拉取失败」。界面会据此提示「当前为打包快照」。
class GoldRepository {
  final RepoConfig repo;
  final Map<String, String> _cache = <String, String>{};
  final Map<String, String> _usedSource = <String, String>{};
  final Set<String> _bundled = <String>{};

  GoldRepository(this.repo);

  /// 最近一次成功取数的来源，便于界面上标注。
  String? sourceOf(String key) => _usedSource[key];

  /// 是否至少有一项数据来自打包快照。
  bool get usingBundledData => _bundled.isNotEmpty;

  Future<String> _get(
    String key,
    List<String> candidates,
    String assetPath,
  ) async {
    // 1. 网络：并发取较新的那份
    try {
      final fetched = await fetchFreshest(candidates);
      _cache[key] = fetched.text;
      _usedSource[key] = fetched.url ?? 'network';
      _bundled.remove(key);
      return fetched.text;
    } catch (_) {
      // 落到离线快照
    }

    // 2. 打包快照
    try {
      final bundled = await rootBundle.loadString(assetPath);
      _cache[key] = bundled;
      _usedSource[key] = assetPath;
      _bundled.add(key);
      return bundled;
    } catch (_) {
      // 落到内存缓存
    }

    // 3. 内存缓存
    final cached = _cache[key];
    if (cached != null) return cached;

    throw StateError('拉取 $key 失败：网络与离线快照都不可用');
  }

  Future<LatestSnapshot> loadLatest() {
    return _get('latest', repo.latestUrls, 'assets/data/latest.json')
        .then(LatestSnapshot.decode);
  }

  Future<BenchmarkHistory> loadBenchmarkHistory() {
    return _get('benchmark', repo.benchmarkHistoryUrls,
            'assets/data/benchmark_history.json')
        .then(BenchmarkHistory.decode);
  }

  /// 用户配置（预算 / 渠道假设 / 提醒阈值），与采集脚本共用同一份。
  Future<Map<String, dynamic>> loadUserConfig() async {
    final text =
        await _get('config', repo.userConfigUrls, 'assets/data/user.json');
    return jsonDecode(text) as Map<String, dynamic>;
  }
}
