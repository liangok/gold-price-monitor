import 'dart:async';

import 'package:flutter/material.dart';

import 'config.dart';
import 'data/repository.dart';
import 'services/alert_runner.dart';
import 'services/alert_settings.dart';
import 'services/background_worker.dart';
import 'services/notification_service.dart';
import 'ui/home_page.dart';
import 'ui/settings_page.dart';
import 'ui/tools_page.dart';
import 'ui/trend_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // ⚠️ 先启动界面，再做插件初始化 —— 这两件事必须解耦。
  //
  // 踩过的坑：原先在 runApp 之前 await 了通知插件与 WorkManager 的初始化，
  // 结果只要其中任何一步抛异常或迟迟不返回，runApp 就永远执行不到，
  // 表现为**白屏 + 系统提示「应用无响应」**（主线程其实空闲，只是在等 Future）。
  runApp(const GoldPriceApp());

  unawaited(_bootstrap());
}

/// 开屏之后的后台初始化。
///
/// 每一步都独立 try/catch：任何一步失败只影响对应功能，绝不影响 App 打开。
Future<void> _bootstrap() async {
  try {
    // 通知插件本身要初始化；是否真的发通知由 AlertSettings.enabled 控制。
    await NotificationService.init();
  } catch (_) {
    // 通知初始化失败不影响其它功能
  }

  bool enabled;
  try {
    enabled = (await AlertSettings.load()).enabled;
  } catch (_) {
    return;
  }
  if (!enabled) return;

  try {
    await BackgroundScheduler.enable();
  } catch (_) {
    // 后台排程失败不影响前台使用
  }

  try {
    // 启动时顺带检查一次策略。周期任务也会覆盖，所以失败无所谓。
    await runAlertCheck(notify: true);
  } catch (_) {
    // 联网失败 / 仓库未就绪等都不应影响打开 App
  }
}

class GoldPriceApp extends StatelessWidget {
  const GoldPriceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '金价监控',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFFB8860B),
      ),
      home: const RootShell(),
    );
  }
}

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;
  final GoldRepository _repository = GoldRepository(appRepoConfig);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: <Widget>[
          HomePage(repository: _repository),
          TrendPage(repository: _repository),
          ToolsPage(repository: _repository),
          const SettingsPage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (int i) => setState(() => _index = i),
        destinations: const <NavigationDestination>[
          NavigationDestination(icon: Icon(Icons.today), label: '今日'),
          NavigationDestination(icon: Icon(Icons.show_chart), label: '趋势'),
          NavigationDestination(icon: Icon(Icons.calculate), label: '工具'),
          NavigationDestination(icon: Icon(Icons.notifications), label: '提醒'),
        ],
      ),
    );
  }
}
