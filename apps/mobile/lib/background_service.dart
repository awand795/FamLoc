import 'dart:async';
import 'dart:ui';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'supabase_service.dart';

const String kForegroundChannelId = 'famloc_foreground';
const int kForegroundNotificationId = 999;

/// Inisialisasi Layanan Latar Belakang 24/7 (Android Foreground Service)
Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onBackgroundServiceStart,
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: kForegroundChannelId,
      initialNotificationTitle: '📍 FamLoc Aktif',
      initialNotificationContent: 'Menyinkronkan lokasi dan baterai keluarga...',
      foregroundServiceTypes: [AndroidForegroundType.location],
    ),
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: onBackgroundServiceStart,
      onBackground: onIosBackground,
    ),
  );
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  return true;
}

@pragma('vm:entry-point')
void onBackgroundServiceStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((_) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((_) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((_) {
    service.stopSelf();
  });

  // Inisialisasi Supabase di background isolate
  try {
    await SupabaseService.initialize();
  } catch (_) {}

  /// Mengambil data baterai & lokasi GPS, lalu mengirim ke Supabase
  Future<void> pushBackgroundLocationAndBattery() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sharingOn = prefs.getBool('famloc_sharing_on') ?? true;
      if (!sharingOn) return;

      final savedUserId = prefs.getString('famloc_user_id');
      final user = SupabaseService.currentUser;
      final userId = user?.id ?? savedUserId;
      if (userId == null || userId.isEmpty) return;

      // 1. Cek izin akses lokasi
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        return;
      }

      // 2. Baca persentase baterai HP
      int? batteryLevel;
      try {
        final b = await Battery().batteryLevel;
        batteryLevel = (b >= 0 && b <= 100) ? b : null;
      } catch (_) {}

      // 3. Ambil posisi GPS terbaru (dengan batas waktu 10 detik agar hemat daya)
      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 10),
          ),
        );
      } catch (_) {
        try {
          pos = await Geolocator.getLastKnownPosition();
        } catch (_) {}
      }

      if (pos != null) {
        final speedKmh = pos.speed > 0 ? (pos.speed * 3.6) : 0.0;

        await SupabaseService.pushLocation(
          lat: pos.latitude,
          lng: pos.longitude,
          accuracy: pos.accuracy,
          heading: pos.heading >= 0 ? pos.heading : null,
          speed: speedKmh,
          battery: batteryLevel,
          isMocked: pos.isMocked,
          overrideUserId: userId,
        );

        // Update teks notifikasi di status bar Android
        if (service is AndroidServiceInstance) {
          final battText = batteryLevel != null ? ' · 🔋 $batteryLevel%' : '';
          final spdText = speedKmh >= 15 ? ' · 🚗 ${speedKmh.round()} km/jam' : '';
          service.setForegroundNotificationInfo(
            title: '📍 FamLoc Berbagi Lokasi Aktif',
            content: 'Lokasi & status keluarga tersinkronisasi$battText$spdText',
          );
        }
      }
    } catch (e) {
      debugPrint('Error push background location: $e');
    }
  }

  // Kirim update pertama kali saat service mulai
  await pushBackgroundLocationAndBattery();

  // Jalankan interval berkala setiap 15 detik (tetap jalan saat layar mati & app diminimalkan)
  Timer.periodic(const Duration(seconds: 15), (_) async {
    await pushBackgroundLocationAndBattery();
  });

  // Dengarkan pergerakan instan dari GPS hardware saat berpindah lokasi
  try {
    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((_) async {
      await pushBackgroundLocationAndBattery();
    });
  } catch (_) {}
}
