/// 数据源实时性诊断。
///
/// 对比 raw.githubusercontent 与 jsDelivr 各自返回的数据时间戳，并打印
/// fetchFreshest 最终选中了哪一个 —— 用来验证「按时间戳取较新那份」的逻辑，
/// 以及确认 jsDelivr 的 CDN 缓存到底落后多少。
///
/// 用法: dart run tool/check_sources.dart
library;

import 'package:goldprice_domain/goldprice_domain.dart';

Future<void> main() async {
  const RepoConfig repo = RepoConfig(
    owner: 'liangok',
    repo: 'gold-price-monitor',
  );
  final List<String> urls = repo.latestUrls;

  print('候选地址：');
  for (final String u in urls) {
    print('  ' + u);
  }
  print('');

  for (final String u in urls) {
    try {
      final FetchedData one = await fetchFreshest(<String>[u]);
      print('单个源: ' + (one.stamp ?? '(无时间戳)'));
      print('        ' + u);
    } catch (error) {
      print('单个源失败: ' + u);
      print('        ' + error.toString());
    }
  }

  print('');
  try {
    final FetchedData best = await fetchFreshest(urls);
    print('fetchFreshest 选中: ' + (best.stamp ?? '(无时间戳)'));
    print('                   ' + (best.url ?? '?'));
  } catch (error) {
    print('fetchFreshest 失败: ' + error.toString());
  }
}
