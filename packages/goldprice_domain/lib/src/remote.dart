/// 数据来源地址构造 + 取数策略。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// owner / repo 改成你自己的 GitHub 仓库（见 README）。
class RepoConfig {
  final String owner;
  final String repo;
  final String branch;

  const RepoConfig({
    required this.owner,
    required this.repo,
    this.branch = 'main',
  });

  /// 同一份文件的多个候选地址。
  ///
  /// raw 在前、jsDelivr 在后，但**顺序不是决定性的** —— 真正的选择逻辑在
  /// [fetchFreshest]：并发请求、按数据自带的时间戳取较新的那份。
  List<String> urlsFor(String path) => <String>[
        'https://raw.githubusercontent.com/$owner/$repo/$branch/$path',
        'https://cdn.jsdelivr.net/gh/$owner/$repo@$branch/$path',
      ];

  List<String> get latestUrls => urlsFor('data/latest.json');
  List<String> get benchmarkHistoryUrls => urlsFor('data/benchmark_history.json');
  List<String> get brandHistoryUrls => urlsFor('data/brand_history.json');
  List<String> get bankBarHistoryUrls => urlsFor('data/bank_bar_history.json');
  List<String> get userConfigUrls => urlsFor('config/user.json');
}

/// 一次成功拉取的结果。
class FetchedData {
  final String text;
  final String? url;
  final String? stamp;

  const FetchedData({required this.text, this.url, this.stamp});
}

/// 取出数据自带的生成时间。
///
/// 采集器写的是 generated_at，历史文件写的是 updated_at。
/// 两个都是 ISO 8601 字符串，可以直接按字典序比较新旧。
String? dataStamp(String text) {
  try {
    final decoded = jsonDecode(text);
    if (decoded is Map<String, dynamic>) {
      final value = decoded['generated_at'] ?? decoded['updated_at'];
      if (value is String && value.isNotEmpty) return value;
    }
  } catch (_) {
    // 不是合法 JSON，当作没有时间戳
  }
  return null;
}

/// 并发请求所有候选地址，返回「数据时间戳最新」的那一份。
///
/// 为什么不按顺序取第一个（这才是关键）：
/// jsDelivr 对分支引用有 **12 小时** 的 CDN 缓存（实测响应头
/// `cache-control: public, max-age=604800, s-maxage=43200`，加随机查询串也穿不透）。
/// 本项目的数据每天只更新一两次，若以 jsDelivr 为准，可能一整天都在显示旧价格。
/// 而 raw.githubusercontent 是实时的，但在国内经常不通。
/// 两者各有所长，所以并发取、按数据自带时间戳比新旧 —— 既保证新鲜，又保证可达。
///
/// 每个请求各自超时，因此整体等待不会超过 [timeout]。
Future<FetchedData> fetchFreshest(
  List<String> urls, {
  Duration timeout = const Duration(seconds: 6),
}) async {
  if (urls.isEmpty) {
    throw StateError('没有候选地址');
  }
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final results = await Future.wait(
      urls.map((String url) => _fetchOne(client, url, timeout)),
    );
    FetchedData? best;
    for (final result in results) {
      if (result == null) continue;
      if (best == null) {
        best = result;
        continue;
      }
      final stamp = result.stamp;
      if (stamp == null) continue;
      final bestStamp = best.stamp;
      if (bestStamp == null || stamp.compareTo(bestStamp) > 0) {
        best = result;
      }
    }
    if (best != null) return best;
    throw StateError('全部候选地址都拉取失败');
  } finally {
    client.close(force: true);
  }
}

Future<FetchedData?> _fetchOne(
  HttpClient client,
  String url,
  Duration timeout,
) async {
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close().timeout(timeout);
    if (response.statusCode != 200) return null;
    final text = await response.transform(utf8.decoder).join();
    return FetchedData(text: text, url: url, stamp: dataStamp(text));
  } catch (_) {
    return null;
  }
}
