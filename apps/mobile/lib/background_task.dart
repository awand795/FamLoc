import 'dart:ui';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notification_service.dart';
import 'supabase_service.dart';

const String taskName = 'famlocPushLocation';

/// Entry point untuk background isolate — wajib top-level function.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    // Workmanager membuat Dart isolate baru. Tanpa dua baris ini, plugin seperti
    // SharedPreferences, Geolocator, Supabase, dan local notifications tidak
    // terdaftar sehingga seluruh fallback gagal (sebelumnya error-nya tertelan).
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();

    switch (task) {
      case taskName:
        await _pushLocationBackground();
        return true;
      default:
        return false;
    }
  });
}

/// Dijalankan Workmanager tiap ~15 menit WALAU APP DITUTUP TOTAL.
///
/// Tugas:
/// 1. Ambil posisi & push ke Supabase (heartbeat lokasi minimal).
/// 2. WATCHDOG: hidupkan kembali FlutterBackgroundService jika dibunuh sistem/OEM.
/// 3. Cek SOS aktif & baterai lemah keluarga → notif darurat walau service mati.
Future<void> _pushLocationBackground() async {
  try {
    await NotificationService.initialize();
    final prefs = await SharedPreferences.getInstance();
    final sharingOn = prefs.getBool('famloc_sharing_on') ?? false;
    if (!sharingOn) return;

    // 1. WATCHDOG: Cek dan hidupkan kembali FlutterBackgroundService jika mati
    try {
      final service = FlutterBackgroundService();
      final isRunning = await service.isRunning();
      if (!isRunning) {
        await service.startService();
      }
    } catch (_) {}

    final permission = await Geolocator.checkPermission();
    // Periodic work tidak boleh mengambil GPS dengan izin "saat digunakan".
    // Pada Android, task ini dijalankan saat UI tidak terlihat.
    if (permission != LocationPermission.always) {
      return;
    }

    // 2. Heartbeat posisi terakhir ke Supabase
    Position? pos;
    try {
      pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
    } catch (_) {
      try {
        pos = await Geolocator.getLastKnownPosition();
      } catch (_) {}
    }
    if (pos != null) {
      try {
        await SupabaseService.initialize();
        final user = SupabaseService.currentUser;
        if (user != null) {
          await SupabaseService.pushLocation(
            lat: pos.latitude,
            lng: pos.longitude,
            accuracy: pos.accuracy,
            heading: pos.heading >= 0 ? pos.heading : null,
            isMocked: pos.isMocked,
          );
        }
      } catch (_) {}
    }

    // 3. Notifikasi darurat keluarga saat service utama mati:
    //    SOS aktif + baterai lemah (hasil polling terakhir oleh service, tersimpan di prefs)
    try {
      await SupabaseService.initialize();
      final user = SupabaseService.currentUser;
      if (user != null) {
        final myId = user.id;

        // 3a. SOS aktif dari keluarga → notif darurat
        final alerts = await SupabaseService.getActiveSosAlerts();
        for (final a in alerts) {
          final key = 'bg_sos_alerted_${a.id}';
          if (prefs.getBool(key) != true) {
            await prefs.setBool(key, true);
            await NotificationService.showSosNotification(
              name: a.name,
              lat: a.lat,
              lng: a.lng,
            );
          }
        }

        // 3b. Baterai lemah keluarga (< 20%) → notif sekali per kejadian
        final family = await SupabaseService.getFamilyLocations(currentUserId: myId);
        for (final f in family) {
          if (f.battery != null && f.battery! < 20) {
            final key = 'bg_lowbatt_alerted_${f.userId}_${f.battery}';
            if (prefs.getBool(key) != true) {
              await prefs.setBool(key, true);
              await NotificationService.showBatteryNotification(name: f.name, battery: f.battery!);
            }
          }
        }

        // Bersihkan flag SOS lama (alert sudah non-aktif) agar biaya penyimpanan kecil
        final keys = prefs.getKeys().where((k) => k.startsWith('bg_sos_alerted_')).toList();
        final activeIds = alerts.map((a) => a.id).toSet();
        for (final k in keys) {
          final id = k.substring('bg_sos_alerted_'.length);
          if (!activeIds.contains(id)) await prefs.remove(k);
        }
      }
    } catch (_) {}
  } catch (_) {}
}

/// Inisialisasi Workmanager.
Future<void> initBackgroundTask() async {
  await Workmanager().initialize(
    callbackDispatcher,
  );

  await Workmanager().registerPeriodicTask(
    taskName,
    taskName,
    frequency: const Duration(minutes: 15),
    constraints: Constraints(
      networkType: NetworkType.connected,
    ),
    initialDelay: const Duration(seconds: 30),
  );
}

/// Mulai background sharing.
Future<void> startBackgroundSharing() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('famloc_sharing_on', true);
  await initBackgroundTask();
}

/// Hentikan background sharing.
Future<void> stopBackgroundSharing() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('famloc_sharing_on', false);
  await Workmanager().cancelAll();
}
