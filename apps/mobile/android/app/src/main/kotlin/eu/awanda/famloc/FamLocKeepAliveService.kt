package eu.awanda.famloc

import android.app.AlarmManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import androidx.core.content.ContextCompat

/**
 * FamLocKeepAliveService — Kunci persistensi latar belakang (Co Fit Style).
 *
 * Mengapa Co Fit tetap hidup walau HP tidak dipakai / layar mati?
 * 1. CPU WakeLock (PARTIAL_WAKE_LOCK): Menjaga CPU tetap berjalan saat layar mati sehingga
 *    Dart isolate, event loop, dan koneksi internet tidak membeku (freeze).
 * 2. AlarmManager Periodic Heartbeat (ELAPSED_REALTIME_WAKEUP):
 *    Setiap 30 detik membangunkan CPU secara hardware untuk memastikan service tidak tidur.
 * 3. START_STICKY & onTaskRemoved() respawn: Menghidupkan kembali service jika dibuang dari Recent Apps.
 */
class FamLocKeepAliveService : Service() {

    companion object {
        private const val TAG = "FamLocKeepAlive"
        private const val BG_SERVICE_CLASS = "id.flutter.flutter_background_service.BackgroundService"
        private const val ACTION_HEARTBEAT = "eu.awanda.famloc.ACTION_HEARTBEAT"
        private const val HEARTBEAT_INTERVAL_MS = 30000L // 30 detik

        private var wakeLock: PowerManager.WakeLock? = null

        fun start(context: Context) {
            try {
                val intent = Intent(context, FamLocKeepAliveService::class.java)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    // Start service biasa
                    context.startService(intent)
                } else {
                    context.startService(intent)
                }
                Log.i(TAG, "FamLocKeepAliveService start requested")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start keepalive service: ${e.message}")
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        acquireWakeLock()
        scheduleNextHeartbeat()
    }

    private fun acquireWakeLock() {
        if (wakeLock == null) {
            try {
                val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
                wakeLock = powerManager.newWakeLock(
                    PowerManager.PARTIAL_WAKE_LOCK,
                    "FamLoc::KeepAliveWakeLock"
                ).apply {
                    setReferenceCounted(false)
                    acquire()
                }
                Log.i(TAG, "KeepAlive WakeLock acquired! CPU will NOT freeze during idle/screen-off.")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to acquire WakeLock: ${e.message}")
            }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        acquireWakeLock()

        if (intent?.action == ACTION_HEARTBEAT) {
            Log.v(TAG, "Heartbeat tick received from AlarmManager")
        }

        // Pastikan BackgroundService utama tetap berjalan
        ensureBackgroundServiceRunning()

        // Jadwalkan detak jantung berikutnya (30 detik)
        scheduleNextHeartbeat()

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

    private fun scheduleNextHeartbeat() {
        try {
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val intent = Intent(applicationContext, FamLocKeepAliveService::class.java).apply {
                action = ACTION_HEARTBEAT
            }
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
            val pendingIntent = PendingIntent.getService(
                applicationContext,
                888,
                intent,
                flags
            )

            val triggerAt = SystemClock.elapsedRealtime() + HEARTBEAT_INTERVAL_MS
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.ELAPSED_REALTIME_WAKEUP,
                    triggerAt,
                    pendingIntent
                )
            } else {
                alarmManager.set(
                    AlarmManager.ELAPSED_REALTIME_WAKEUP,
                    triggerAt,
                    pendingIntent
                )
            }
        } catch (e: Exception) {
            Log.e(TAG, "scheduleNextHeartbeat error: ${e.message}")
        }
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        Log.i(TAG, "onTaskRemoved: Pengguna menghapus FamLoc dari Recent Apps! Menjadwalkan respawn...")
        scheduleRestart()
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        Log.i(TAG, "onDestroy: Service dihentikan -> Menjadwalkan respawn otomatis...")
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
        } catch (e: Exception) {
            Log.e(TAG, "scheduleRestart error: ${e.message}")
        }
    }
}
