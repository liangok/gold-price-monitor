package com.liangaokai.goldprice

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 提供「跳转到系统设置」的能力。
 *
 * 为什么要自己写原生而不是用第三方插件：只需要三个动作，
 * 自建 MethodChannel 比引入依赖更轻、也更好控制（尤其是小米的自启动页）。
 */
class MainActivity : FlutterActivity() {

    private val channelName = "com.liangaokai.goldprice/system"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "isIgnoringBatteryOptimizations" ->
                            result.success(isIgnoringBatteryOptimizations())
                        "openAppSettings" -> result.success(openAppSettings())
                        "openBatteryOptimizationSettings" ->
                            result.success(openBatteryOptimizationSettings())
                        "openAutostartSettings" -> result.success(openAutostartSettings())
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    result.error("SYSTEM_CHANNEL", error.message, null)
                }
            }
    }

    /** 是否已把本应用加入电池优化白名单（Android 6+）。 */
    private fun isIgnoringBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val power = getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return false
        return power.isIgnoringBatteryOptimizations(packageName)
    }

    /** 打开本应用的系统详情页（可设置省电策略、权限等）。 */
    private fun openAppSettings(): Boolean {
        return try {
            startActivity(
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.fromParts("package", packageName, null)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
            )
            true
        } catch (error: Exception) {
            false
        }
    }

    /**
     * 请求忽略电池优化。优先弹系统授权对话框（一次点击），
     * 失败则退到电池优化设置列表。
     */
    private fun openBatteryOptimizationSettings(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                startActivity(
                    Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                        data = Uri.fromParts("package", packageName, null)
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                )
                return true
            } catch (error: Exception) {
                // 落到下面的列表页
            }
        }
        return try {
            startActivity(
                Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
            )
            true
        } catch (error: Exception) {
            openAppSettings()
        }
    }

    /**
     * 打开「自启动管理」页。
     *
     * 这是各家 ROM 的私有页面，没有公开 API，只能按 ComponentName 逐个尝试。
     * 小米（HyperOS / MIUI）在最前面 —— 本项目的主力机型。
     * 全部失败则退回应用详情页。
     */
    private fun openAutostartSettings(): Boolean {
        val candidates = listOf(
            // 小米 / Redmi
            ComponentName(
                "com.miui.securitycenter",
                "com.miui.permcenter.autostart.AutoStartManagementActivity"
            ),
            // 华为 / 荣耀
            ComponentName(
                "com.huawei.systemmanager",
                "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"
            ),
            // OPPO / 一加 / realme
            ComponentName(
                "com.coloros.safecenter",
                "com.coloros.safecenter.permission.startup.StartupAppListActivity"
            ),
            ComponentName(
                "com.oplus.safecenter",
                "com.oplus.safecenter.startupapp.StartupAppListActivity"
            ),
            // vivo / iQOO
            ComponentName(
                "com.vivo.permissionmanager",
                "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"
            ),
        )
        for (component in candidates) {
            try {
                startActivity(
                    Intent().setComponent(component).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                )
                return true
            } catch (error: Exception) {
                // 这台机器没有这个页面，试下一个
            }
        }
        return openAppSettings()
    }
}
