import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:goldprice_domain/goldprice_domain.dart';

/// 只读数据仓库。
///
/// App 不直接抓第三方网页，只读我们自己 GitHub 仓库里的采集结果。
/// 每个文件都有多个候选地址（jsDelivr CDN 优先，raw.githubusercontent 回退），
/// 全部失败时退回内存缓存 —— 保证界面永远有东西可显示。
class GoldRepository {
  final RepoConfig repo;
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12);
  final Map<String, String> _cache = <String, String>{};
  final Map<String, String> _usedSource = <String, String>{};

  GoldRepository(this.repo);

  /// 最近一次成功拉取的地址，用于界面上标注数据来源。
  String? sourceOf(String key) => _usedSource[key];

  Future<String> _get(String key, List<String> candidates) async {
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
        return text;
      } catch (error) {
        lastError = error;
      }
    }
    final cached = _cache[key];
    if (cached != null) {
      return cached;
    }
    throw StateError('拉取 ' + key + ' 失败：' + lastError.toString());
  }

  Future<LatestSnapshot> loadLatest() async {
    return LatestSnapshot.decode(await _get('latest', repo.latestUrls));
  }

  Future<BenchmarkHistory> loadBenchmarkHistory() async {
    return BenchmarkHistory.decode(
        await _get('benchmark', repo.benchmarkHistoryUrls));
  }

  /// 用户配置（预算 / 渠道假设 / 提醒阈值），App 与采集脚本共用同一份。
  Future<Map<String, dynamic>> loadUserConfig() async {
    final text = await _get('config', repo.userConfigUrls);
    return jsonDecode(text) as Map<String, dynamic>;
  }

  void dispose() => _client.close(force: true);
}
