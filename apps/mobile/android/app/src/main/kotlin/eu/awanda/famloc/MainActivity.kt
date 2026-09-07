package eu.awanda.famloc

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val BATTERY_CHANNEL = "eu.awanda.famloc/battery"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // MethodChannel untuk battery optimization whitelist
        // Dipanggil dari background_service.dart saat inisialisasi
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BATTERY_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isIgnoringBatteryOptimizations" -> {
                        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                        val packageName = applicationContext.packageName
                        val isIgnoring = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            pm.isIgnoringBatteryOptimizations(packageName)
                        } else {
                            true // Android < 6.0: tidak ada Doze Mode
                        }
                        result.success(isIgnoring)
                    }

                    "requestIgnoreBatteryOptimizations" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val packageName = applicationContext.packageName
                            val intent = Intent().apply {
                                action = android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
                                data = Uri.parse("package:$packageName")
                                // Flags agar bisa dibuka dari background context
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            try {
                                startActivity(intent)
                                result.success(true)
                            } catch (e: Exception) {
                                // Beberapa vendor memblokir intent ini — fallback ke Settings umum
                                try {
                                    val fallbackIntent = Intent(
                                        android.provider.Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS
                                    ).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
                                    startActivity(fallbackIntent)
                                    result.success(true)
                                } catch (e2: Exception) {
                                    result.error("UNAVAILABLE", "Cannot open battery settings: ${e2.message}", null)
                                }
                            }
                        } else {
                            result.success(false) // Tidak perlu di Android < 6
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }
}
