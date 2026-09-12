/// 数据来源地址构造。
///
/// 采集结果托管在 GitHub 仓库，App 只读。国内访问 raw.githubusercontent.com
/// 经常超时，因此把 jsDelivr CDN 放在首位、raw 作为回退，两者内容一致。
///
/// owner / repo 需要改成你自己的 GitHub 仓库（见 README）。
library;

class RepoConfig {
  final String owner;
  final String repo;
  final String branch;

  const RepoConfig({
    required this.owner,
    required this.repo,
    this.branch = 'main',
  });

  /// 返回同一份文件的多个候选地址，按推荐顺序排列。
  List<String> urlsFor(String path) => <String>[
        'https://cdn.jsdelivr.net/gh/$owner/$repo@$branch/$path',
        'https://raw.githubusercontent.com/$owner/$repo/$branch/$path',
      ];

  List<String> get latestUrls => urlsFor('data/latest.json');
  List<String> get benchmarkHistoryUrls => urlsFor('data/benchmark_history.json');
  List<String> get brandHistoryUrls => urlsFor('data/brand_history.json');
  List<String> get bankBarHistoryUrls => urlsFor('data/bank_bar_history.json');
  List<String> get userConfigUrls => urlsFor('config/user.json');
}
