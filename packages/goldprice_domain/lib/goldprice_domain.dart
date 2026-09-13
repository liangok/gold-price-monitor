/// 金价监控 App 的纯 Dart 领域层。
///
/// 设计意图：
///   - 不依赖 Flutter，因此可以用 dart test 独立、快速地验证核心逻辑；
///   - 算法必须与 Python 参考实现 analysis/indicators.py 语义一致，
///     一致性由 test/indicators_test.dart 对照真实数据断言。
library;

export 'src/channels.dart';
export 'src/five_piece.dart';
export 'src/indicators.dart';
export 'src/macro.dart';
export 'src/models.dart';
export 'src/remote.dart';
export 'src/strategy.dart';
