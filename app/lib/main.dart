import 'package:flutter/material.dart';

import 'config.dart';
import 'data/repository.dart';
import 'ui/home_page.dart';
import 'ui/trend_page.dart';

void main() {
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
  void dispose() {
    _repository.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: <Widget>[
          HomePage(repository: _repository),
          TrendPage(repository: _repository),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (int i) => setState(() => _index = i),
        destinations: const <NavigationDestination>[
          NavigationDestination(icon: Icon(Icons.today), label: '今日'),
          NavigationDestination(icon: Icon(Icons.show_chart), label: '趋势'),
        ],
      ),
    );
  }
}
