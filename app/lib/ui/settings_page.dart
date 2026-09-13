import 'package:flutter/material.dart';

import '../services/alert_runner.dart';
import '../services/alert_settings.dart';
import '../services/background_worker.dart';
import '../services/notification_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  AlertSettings? _settings;
  final TextEditingController _targetController = TextEditingController();
  bool _permissionGranted = true;
  bool? _scheduled;
  String? _status;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _targetController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final settings = await AlertSettings.load();
    final granted = await NotificationService.hasPermission();
    final scheduled = await BackgroundScheduler.isScheduled();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _targetController.text = settings.targetPrice == null
          ? ''
          : settings.targetPrice!.toStringAsFixed(0);
      _permissionGranted = granted;
      _scheduled = scheduled;
    });
  }

  Future<void> _apply(AlertSettings next) async {
    await AlertSettings.save(next);
    if (next.enabled) {
      await BackgroundScheduler.enable();
    } else {
      await BackgroundScheduler.disable();
    }
    if (!mounted) return;
    setState(() => _settings = next);
    await _reload();
  }

  double? _parseTarget() {
    final text = _targetController.text.trim();
    if (text.isEmpty) return null;
    return double.tryParse(text);
  }

  Future<void> _runCheck() async {
    setState(() {
      _busy = true;
      _status = '检查中…';
    });
    try {
      final result = await runAlertCheck(notify: false);
      if (!mounted) return;
      setState(() {
        _status = result.skipped
            ? ('已跳过：' + (result.skipReason ?? ''))
            : ('数据日期 ' +
                (result.dataDate ?? '?') +
                '　大盘 ' +
                (result.close?.toStringAsFixed(2) ?? '?') +
                ' 元/克　触发 ' +
                result.triggeredCount.toString() +
                ' 条');
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = '检查失败：' + error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    return Scaffold(
      appBar: AppBar(title: const Text('提醒设置')),
      body: settings == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: <Widget>[
                Card(
                  child: Column(
                    children: <Widget>[
                      SwitchListTile(
                        value: settings.enabled,
                        title: const Text('启用提醒'),
                        subtitle: const Text('后台每 6 小时检查一次，触发时发通知'),
                        onChanged: (bool v) =>
                            _apply(settings.copyWith(enabled: v)),
                      ),
                      if (!_permissionGranted)
                        ListTile(
                          leading: const Icon(Icons.warning_amber),
                          title: const Text('通知权限未开启'),
                          subtitle: const Text('Android 13+ 需要授权才能收到提醒'),
                          trailing: FilledButton(
                            onPressed: () async {
                              final ok =
                                  await NotificationService.requestPermission();
                              if (!mounted) return;
                              setState(() => _permissionGranted = ok);
                            },
                            child: const Text('去授权'),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text('绝对目标价',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 4),
                        Text(
                          '大盘价跌到这个价以下就提醒。牛市里历史分位/均线都会失效，'
                          '绝对价位是最可靠的锚。留空表示不设。',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _targetController,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: const InputDecoration(
                            labelText: '目标价',
                            suffixText: '元/克',
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (String _) => _apply(
                            settings.copyWith(
                              targetPrice: _parseTarget(),
                              clearTarget: _parseTarget() == null,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton(
                            onPressed: () => _apply(
                              settings.copyWith(
                                targetPrice: _parseTarget(),
                                clearTarget: _parseTarget() == null,
                              ),
                            ),
                            child: const Text('保存目标价'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: SwitchListTile(
                    value: settings.includeHint,
                    title: const Text('同时提醒「回撤 / 跌破均线」'),
                    subtitle: const Text(
                        '回测显示这两类规则在 2016-2026 跑输「随便哪天买」，默认关闭以减少噪音'),
                    onChanged: (bool v) =>
                        _apply(settings.copyWith(includeHint: v)),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: <Widget>[
                      ListTile(
                        leading: const Icon(Icons.notifications_active),
                        title: const Text('发送测试通知'),
                        subtitle: const Text('用来当场验证通知是否真的能弹出来'),
                        onTap: () async {
                          await NotificationService.requestPermission();
                          await NotificationService.show(
                            id: 9001,
                            title: '测试通知',
                            body: '如果你看到这条，说明提醒通道正常。',
                          );
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.refresh),
                        title: const Text('立即检查一次'),
                        subtitle: Text(_status ?? '只预览结果，不发通知'),
                        onTap: _busy ? null : _runCheck,
                      ),
                      ListTile(
                        leading: const Icon(Icons.cleaning_services),
                        title: const Text('清除「今日已提醒」记录'),
                        subtitle: const Text('清掉后同一规则当天可以再次提醒'),
                        onTap: () async {
                          await AlertSettings.clearNotified();
                          if (!mounted) return;
                          setState(() => _status = '已清除今日提醒记录');
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            const Text('后台任务状态',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                            const Spacer(),
                            Text(
                              _scheduled == null
                                  ? '未知'
                                  : (_scheduled! ? '已排程' : '未排程'),
                              style: TextStyle(
                                color: _scheduled == true
                                    ? Theme.of(context).colorScheme.primary
                                    : null,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '通知权限：' + (_permissionGranted ? '已授权' : '未授权'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text('小米 HyperOS 必做设置',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        Text(
                          '小米的省电策略会杀后台，导致定时提醒不触发。请手动设置：\n'
                          '1. 设置 → 应用管理 → 金价监控 → 省电策略 → 无限制\n'
                          '2. 同页面 → 允许自启动\n'
                          '3. 最近任务列表里下拉本应用卡片 → 加锁\n'
                          '4. 确认通知权限已开\n\n'
                          '设置完点上面「发送测试通知」验证。若收不到，多半是被省电策略拦了。',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}
