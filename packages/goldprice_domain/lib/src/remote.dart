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

  /// 候选地址，**顺序是按国内手机实测排的**：
  ///
  /// 1. \`api.github.com\` 内容接口  —— 实测 0.64s，且内容最新（不走 raw CDN）
  /// 2. \`gcore.jsdelivr.net\`      —— 实测 3.3s（CDN，分支引用有 12h 缓存）
  /// 3. \`cdn.jsdelivr.net\`        —— 实测 5.5s（同上，稍慢）
  /// 4. \`raw.githubusercontent.com\` —— 内容最新，但**国内 HTTPS 实测被墙（一直超时）**
  ///
  /// 之所以不再用「并发 + 比时间戳」：raw 被墙时会一直挂到超时，
  /// 并发等全部返回会让用户白等十几秒。顺序尝试 + 硬超时上限才稳。
  List<String> urlsFor(String path) => <String>[
        'https://api.github.com/repos/$owner/$repo/contents/$path?ref=$branch',
        'https://gcore.jsdelivr.net/gh/$owner/$repo@$branch/$path',
        'https://cdn.jsdelivr.net/gh/$owner/$repo@$branch/$path',
        'https://raw.githubusercontent.com/$owner/$repo/$branch/$path',
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

/// 依次尝试候选地址，**第一个成功就返回**。
///
/// 两个关键保障：
///   - 每个源都有**整体**超时（不只是连接超时）—— 否则被墙的地址（连接建立后
///     再无响应）会让请求永久挂起，界面就一直转圈。
///   - 所有源合计不超过 [totalBudget] —— 保证最坏情况也有上限，之后走离线快照。
Future<FetchedData> fetchFreshest(
  List<String> urls, {
  Duration totalBudget = const Duration(seconds: 14),
  Duration perSource = const Duration(seconds: 8),
}) async {
  if (urls.isEmpty) {
    throw StateError('没有候选地址');
  }
  final DateTime deadline = DateTime.now().add(totalBudget);
  Object? lastError;

  for (final String url in urls) {
    final Duration remaining = deadline.difference(DateTime.now());
    if (remaining.isNegative) break;
    final Duration budget = remaining < perSource ? remaining : perSource;
    try {
      final FetchedData? result = await _fetchOne(url, budget);
      if (result != null) return result;
    } catch (error) {
      lastError = error;
    }
  }
  throw StateError('全部候选地址都拉取失败：$lastError');
}

Future<FetchedData?> _fetchOne(String url, Duration budget) async {
  final HttpClient client = HttpClient()..connectionTimeout = budget;
  try {
    return await _fetchOneInner(client, url).timeout(budget);
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

Future<FetchedData?> _fetchOneInner(HttpClient client, String url) async {
  final HttpClientRequest request = await client.getUrl(Uri.parse(url));
  // GitHub 内容接口要求带 Accept 头，否则部分场景返回 403
  request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
  final HttpClientResponse response = await request.close();
  if (response.statusCode != 200) return null;
  final String raw = await response.transform(utf8.decoder).join();
  final String text = _unwrapGitHubApi(raw);
  return FetchedData(text: text, url: url, stamp: dataStamp(text));
}

/// GitHub 内容接口把文件包在 base64 信封里，这里拆出来。
/// 不是信封就原样返回。
String _unwrapGitHubApi(String text) {
  try {
    final Object? decoded = jsonDecode(text);
    if (decoded is Map<String, dynamic> &&
        decoded['encoding'] == 'base64' &&
        decoded['content'] is String) {
      final String cleaned =
          (decoded['content'] as String).replaceAll(RegExp(r'\s'), '');
      return utf8.decode(base64Decode(cleaned));
    }
  } catch (_) {
    // 不是信封
  }
  return text;
}
