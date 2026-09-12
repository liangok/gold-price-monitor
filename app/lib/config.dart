import 'package:goldprice_domain/goldprice_domain.dart';

/// ⚠️ 改成你自己的 GitHub 仓库（创建步骤见 README「开启 GitHub 自动采集」）。
///
/// App 只读这个仓库里的 data/*.json —— 由 GitHub Actions 每日采集并提交。
const String kGithubOwner = 'YOUR_GITHUB_USERNAME';
const String kGithubRepo = 'gold-price-monitor';
const String kGithubBranch = 'main';

const RepoConfig appRepoConfig = RepoConfig(
  owner: kGithubOwner,
  repo: kGithubRepo,
  branch: kGithubBranch,
);
