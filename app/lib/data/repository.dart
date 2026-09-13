import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:goldprice_domain/goldprice_domain.dart';

/// 只读数据仓库。
///
/// 取数优先级：
///   1. jsDelivr CDN（国内相对稳定）
///   2. raw.githubusercontent.com
///   3. **打包进 APK 的离线快照**（assets/data/）
///   4. 内存缓存
///
/// 加第 3 级的原因：仓库还没建好、或临时断网时，界面依然能用，
/// 不会只显示一句「拉取失败」。界面会据此提示「当前为打包快照」。
class GoldRepository {
  final RepoConfig repo;
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12);
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
    Object? lastError;
    for (final url in candidates) {
      try {
        final request = await _client.getUrl(Uri.parse(url));
        final response =
            await request.close().timeout(const Duration(seconds: 15));
        if (response.statusCode != 200) {
          lastError = 'HTTP ' + response.statusCode.toString();
          continue;
        }
        final text = await response.transform(utf8.decoder).join();
        _cache[key] = text;
        _usedSource[key] = url;
        _bundled.remove(key);
        return text;
      } catch (error) {
        lastError = error;
      }
    }

    // 网络全部失败 → 回退到打包进 APK 的快照
    try {
      final bundled = await rootBundle.loadString(assetPath);
      _cache[key] = bundled;
      _usedSource[key] = assetPath;
      _bundled.add(key);
      return bundled;
    } catch (_) {
      // 忽略，继续尝试内存缓存
    }

    final cached = _cache[key];
    if (cached != null) {
      return cached;
    }
    throw StateError('拉取 ' + key + ' 失败：' + lastError.toString());
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

  void dispose() => _client.close(force: true);
}
