import 'dart:convert';

import 'package:goldprice_domain/goldprice_domain.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 五金清单的本地存储（存本机，不上传）。
class PlanStore {
  static const String _key = 'gold_plan_v1';

  static Future<GoldPlan> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_key);
    if (raw == null) return GoldPlan.weddingFive;
    try {
      return GoldPlan.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return GoldPlan.weddingFive;
    }
  }

  static Future<void> save(GoldPlan plan) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(plan.toJson()));
  }

  static Future<void> reset() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
