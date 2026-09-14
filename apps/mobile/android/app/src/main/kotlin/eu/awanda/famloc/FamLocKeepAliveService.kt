package eu.awanda.famloc

import android.app.AlarmManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.SystemClock
import android.util.Log
import androidx.core.content.ContextCompat

/**
 * FamLocKeepAliveService — Kunci persistensi latar belakang (Co Fit Style).
 *
 * Mengapa Co Fit tetap hidup walau dihapus dari Recent Apps?
 * 1. Menggunakan START_STICKY sehingga sistem Android otomatis merekrut ulang proses jika dimatikan.
 * 2. Mengimplementasikan onTaskRemoved() yang langsung menjadwalkan kebangkitan kembali lewat AlarmManager
 *    saat pengguna membuang (swipe) aplikasi dari Recent Apps.
 * 3. Menghidupkan kembali Flutter BackgroundService jika terhenti.
 */
class FamLocKeepAliveService : Service() {

    companion object {
        private const val TAG = "FamLocKeepAlive"
        private const val BG_SERVICE_CLASS = "id.flutter.flutter_background_service.BackgroundService"

        fun start(context: Context) {
            try {
                val intent = Intent(context, FamLocKeepAliveService::class.java)
                context.startService(intent)
                Log.i(TAG, "FamLocKeepAliveService started successfully")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start keepalive service: ${e.message}")
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.i(TAG, "onStartCommand -> START_STICKY active")
        // Pastikan juga BackgroundService utama tetap berjalan
        ensureBackgroundServiceRunning()
        return START_STICKY
    }

    private fun ensureBackgroundServiceRunning() {
        try {
            val serviceClass = Class.forName(BG_SERVICE_CLASS)
            val bgIntent = Intent(applicationContext, serviceClass)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ContextCompat.startForegroundService(applicationContext, bgIntent)
            } else {
                startService(bgIntent)
            }
        } catch (e: Exception) {
            Log.e(TAG, "ensureBackgroundServiceRunning error: ${e.message}")
        }
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        Log.i(TAG, "onTaskRemoved: Pengguna menghapus FamLoc dari Recent Apps! Menjadwalkan respawn...")
        scheduleRestart()
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        Log.i(TAG, "onDestroy: Service dihentikan sistem -> Menjadwalkan respawn otomatis...")
        scheduleRestart()
        super.onDestroy()
    }

    private fun scheduleRestart() {
        try {
            val restartIntent = Intent(applicationContext, FamLocKeepAliveService::class.java)
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
            val pendingIntent = PendingIntent.getService(
                applicationContext,
                889,
                restartIntent,
                flags
            )
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.ELAPSED_REALTIME_WAKEUP,
                    SystemClock.elapsedRealtime() + 1000,
                    pendingIntent
                )
            } else {
                alarmManager.set(
                    AlarmManager.ELAPSED_REALTIME_WAKEUP,
                    SystemClock.elapsedRealtime() + 1000,
                    pendingIntent
                )
            }
            Log.i(TAG, "Restart scheduled successfully in 1000ms")
        } catch (e: Exception) {
            Log.e(TAG, "scheduleRestart error: ${e.message}")
        }
    }
}
