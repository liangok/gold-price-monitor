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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 通知插件本身要初始化；是否真的发通知由 AlertSettings.enabled 控制。
  await NotificationService.init();

  final settings = await AlertSettings.load();
  if (settings.enabled) {
    await BackgroundScheduler.enable();
    // 启动时顺带检查一次。失败无所谓（周期任务会覆盖），所以吞掉异常。
    unawaited(Future<void>(() async {
      try {
        await runAlertCheck(notify: true);
      } catch (_) {
        // 忽略：联网失败 / 仓库未就绪等都不应影响打开 App
      }
    }));
  }

  runApp(const GoldPriceApp());
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
