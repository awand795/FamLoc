package eu.awanda.famloc

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * BootReceiver — Otomatis restart FamLoc Background Service setelah HP reboot.
 * Tanpa ini, foreground service yang sudah berjalan akan berhenti saat HP restart
 * dan tidak akan aktif lagi kecuali user membuka aplikasi secara manual.
 *
 * Cara kerja:
 * 1. Android menerima BOOT_COMPLETED setelah sistem selesai boot
 * 2. BootReceiver dijalankan oleh sistem
 * 3. BootReceiver memanggil startForegroundService() untuk menghidupkan kembali
 *    id.flutter.flutter_background_service.BackgroundService
 * 4. flutter_background_service menjalankan onBackgroundServiceStart() di Dart isolate
 */
class BootReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "FamLocBootReceiver"
        private const val BACKGROUND_SERVICE_CLASS =
            "id.flutter.flutter_background_service.BackgroundService"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        Log.i(TAG, "onReceive: action=$action")

        if (action == Intent.ACTION_BOOT_COMPLETED ||
            action == "android.intent.action.QUICKBOOT_POWERON" ||
            action == "com.htc.intent.action.QUICKBOOT_POWERON"
        ) {
            try {
                val serviceClass = Class.forName(BACKGROUND_SERVICE_CLASS)
                val serviceIntent = Intent(context, serviceClass)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(serviceIntent)
                } else {
                    context.startService(serviceIntent)
                }
                Log.i(TAG, "Background service started after boot.")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start background service after boot: ${e.message}")
            }
        }
    }
}
