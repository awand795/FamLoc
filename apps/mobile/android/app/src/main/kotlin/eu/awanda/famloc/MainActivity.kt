package eu.awanda.famloc

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

class MainActivity : FlutterActivity() {

    companion object {
        private const val BATTERY_CHANNEL = "eu.awanda.famloc/battery"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BATTERY_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getDeviceManufacturer" -> {
                        result.success(Build.MANUFACTURER.lowercase())
                    }

                    "isIgnoringBatteryOptimizations" -> {
                        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                        val packageName = applicationContext.packageName
                        val isIgnoring = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            pm.isIgnoringBatteryOptimizations(packageName)
                        } else {
                            true
                        }
                        result.success(isIgnoring)
                    }

                    "requestIgnoreBatteryOptimizations" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val packageName = applicationContext.packageName
                            val intent = Intent().apply {
                                action = Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
                                data = Uri.parse("package:$packageName")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            try {
                                startActivity(intent)
                                result.success(true)
                            } catch (e: Exception) {
                                try {
                                    val fallbackIntent = Intent(
                                        Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS
                                    ).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
                                    startActivity(fallbackIntent)
                                    result.success(true)
                                } catch (e2: Exception) {
                                    result.error("UNAVAILABLE", "Cannot open battery settings: ${e2.message}", null)
                                }
                            }
                        } else {
                            result.success(false)
                        }
                    }

                    "openVivoBatterySettings" -> {
                        // Khusus Vivo/iQOO: Manajemen Konsumsi Daya Latar Belakang Tinggi
                        val packageName = applicationContext.packageName
                        val intents = listOf(
                            Intent().apply {
                                component = ComponentName("com.vivo.abe", "com.vivo.abe.feature.mone.ui.battery.BatteryWhiteListActivity")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            },
                            Intent().apply {
                                component = ComponentName("com.iqoo.secure", "com.iqoo.secure.ui.phoneoptimize.BgStartUpManager")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            },
                            Intent().apply {
                                component = ComponentName("com.iqoo.secure", "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            },
                            Intent().apply {
                                component = ComponentName("com.vivo.permissionmanager", "com.vivo.permissionmanager.activity.BgStartUpManagerActivity")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            },
                            Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            },
                            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                data = Uri.parse("package:$packageName")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                        )

                        var opened = false
                        for (intent in intents) {
                            try {
                                startActivity(intent)
                                opened = true
                                break
                            } catch (_: Exception) {
                                continue
                            }
                        }
                        result.success(opened)
                    }

                    "openAutostartSettings" -> {
                        // Mulai Otomatis (Autostart) untuk Vivo, Xiaomi, Oppo, Realme, Samsung, Huawei
                        val packageName = applicationContext.packageName
                        val intents = listOf(
                            // Vivo / iQOO
                            Intent().apply {
                                component = ComponentName("com.iqoo.secure", "com.iqoo.secure.safeguard.PurviewTabActivity")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            },
                            Intent().apply {
                                component = ComponentName("com.vivo.permissionmanager", "com.vivo.permissionmanager.activity.PurviewTabActivity")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            },
                            Intent().apply {
                                component = ComponentName("com.iqoo.secure", "com.iqoo.secure.ui.phoneoptimize.SoftwareManagerActivity")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            },
                            // Xiaomi / MIUI
                            Intent().apply {
                                component = ComponentName("com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            },
                            // Oppo / Realme
                            Intent().apply {
                                component = ComponentName("com.coloros.safecenter", "com.coloros.safecenter.permission.startup.StartupAppListActivity")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            },
                            Intent().apply {
                                component = ComponentName("com.oppo.safe", "com.oppo.safe.permission.startup.StartupAppListActivity")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            },
                            Intent().apply {
                                component = ComponentName("com.coloros.safecenter", "com.coloros.safecenter.startupapp.StartupAppListActivity")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            },
                            // Samsung
                            Intent().apply {
                                component = ComponentName("com.samsung.android.lool", "com.samsung.android.sm.ui.battery.BatteryActivity")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            },
                            // Huawei
                            Intent().apply {
                                component = ComponentName("com.huawei.systemmanager", "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            },
                            // Fallback ke info detail aplikasi
                            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                data = Uri.parse("package:$packageName")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                        )

                        var opened = false
                        for (intent in intents) {
                            try {
                                startActivity(intent)
                                opened = true
                                break
                            } catch (_: Exception) {
                                continue
                            }
                        }
                        result.success(opened)
                    }

                    "openAppDetailsSettings" -> {
                        try {
                            val packageName = applicationContext.packageName
                            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                data = Uri.parse("package:$packageName")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("UNAVAILABLE", "Cannot open app settings: ${e.message}", null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }
}
