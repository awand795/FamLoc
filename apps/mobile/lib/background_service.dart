import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notification_service.dart';
import 'supabase_service.dart';

const String kForegroundChannelId = 'famloc_foreground_silent';
const int kForegroundNotificationId = 888;

/// Minta user untuk mengecualikan FamLoc dari optimasi baterai Android.
/// Ini KRITIS agar Android tidak "membunuh" foreground service saat layar mati.
/// Tanpa ini, GPS akan berhenti dalam 15–30 menit di Doze Mode.
Future<void> requestBatteryOptimizationWhitelist() async {
  if (!Platform.isAndroid) return;
  try {
    const channel = MethodChannel('eu.awanda.famloc/battery');
    // Cek dulu apakah sudah di-whitelist
    final bool isWhitelisted = await channel.invokeMethod('isIgnoringBatteryOptimizations') as bool? ?? false;
    if (!isWhitelisted) {
      await channel.invokeMethod('requestIgnoreBatteryOptimizations');
    }
  } catch (_) {
    // Fallback: abaikan jika MethodChannel belum tersedia (tidak mematikan app)
  }
}

/// Inisialisasi Layanan Latar Belakang 24/7 (Android Foreground Service)
Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  // Pastikan notification channel siap sebelum service aktif
  await NotificationService.initialize();

  // Service hanya boleh hidup bila pengguna memang masih membagikan lokasi.
  // Jangan mengubah pilihan pengguna menjadi aktif secara diam-diam.
  final prefs = await SharedPreferences.getInstance();
  final sharingOn = prefs.getBool('famloc_sharing_on') ?? false;
  if (!sharingOn) return;

  // Android membutuhkan izin "Allow all the time" untuk akses GPS ketika UI
  // ditutup. Jangan start FGS lebih dulu lalu gagal diam-diam di isolate.
  final perm = await Geolocator.checkPermission();
  if (Platform.isAndroid &&
      perm != LocationPermission.always &&
      perm != LocationPermission.whileInUse) {
    debugPrint('[BG] Service tidak dimulai: izin lokasi belum diberikan ($perm).');
    return;
  }

  // Simpan user_id aktif ke SharedPreferences jika ada.
  final user = SupabaseService.currentUser;
  if (user != null) {
    try {
      await prefs.setString('famloc_user_id', user.id);
    } catch (_) {}
  }

  // ✅ Minta whitelist battery optimization agar Android tidak membunuh service
  // saat layar mati / masuk Doze Mode
  await requestBatteryOptimizationWhitelist();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onBackgroundServiceStart,
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: kForegroundChannelId,
      initialNotificationTitle: '📍 FamLoc Berbagi Lokasi Aktif',
      initialNotificationContent: 'Menyinkronkan lokasi dan baterai keluarga...',
      foregroundServiceTypes: [AndroidForegroundType.location],
      foregroundServiceNotificationId: kForegroundNotificationId,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: onBackgroundServiceStart,
      onBackground: onIosBackground,
    ),
  );

  // Pastikan service benar-benar jalan
  final isRunning = await service.isRunning();
  if (!isRunning) {
    await service.startService();
  }
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  return true;
}

@pragma('vm:entry-point')
void onBackgroundServiceStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  if (service is AndroidServiceInstance) {
    // ✅ PENTING: Langsung set sebagai foreground service di awal startup
    // (Tidak menunggu event dari UI — supaya service selalu punya notifikasi persistent)
    await service.setAsForegroundService();
    service.setForegroundNotificationInfo(
      title: '📍 FamLoc Aktif',
      content: 'Menginisialisasi layanan lokasi...',
    );

    // Listener opsional dari UI jika perlu toggle mode
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

  // Inisialisasi notifikasi & Supabase di background isolate
  try {
    await NotificationService.initialize();
  } catch (_) {}

  try {
    await SupabaseService.initialize();
  } catch (_) {}

  // State memori di background service
  List<PlaceZone> cachedPlaces = [];
  DateTime lastPlacesFetch = DateTime.fromMillisecondsSinceEpoch(0);
  String? lastMyPlace; // Tempat saya saat ini
  final Map<String, String> familyPlaces = {}; // userId -> placeName
  final Set<String> alertedSpeedUsers = {};
  final Set<String> alertedLowBatteryUsers = {}; // 🔋 Anti-spam notifikasi baterai lemah
  DateTime lastHeartbeat = DateTime.fromMillisecondsSinceEpoch(0);
  String? lastRingAlertId; // ✅ Track ID ring alert agar tidak dering berulang setiap 8 detik
  const distCalc = Distance();

  // Muat state geofence tersimpan dari SharedPreferences agar tidak trigger ulang saat service restart
  try {
    final prefs = await SharedPreferences.getInstance();
    lastMyPlace = prefs.getString('saved_last_place_self');
  } catch (_) {}

  /// Muat daftar tempat (geofence) dari Supabase
  Future<void> refreshPlaces() async {
    try {
      final places = await SupabaseService.getPlaces();
      if (places.isNotEmpty) {
        cachedPlaces = places;
        lastPlacesFetch = DateTime.now();
      }
    } catch (_) {}
  }

  // Muat tempat pertama kali
  await refreshPlaces();

  /// Handler untuk setiap koordinat GPS saya yang baru
  Future<void> handleMyLocation(Position pos) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sharingOn = prefs.getBool('famloc_sharing_on') ?? true;
      if (!sharingOn) return;

      final savedUserId = prefs.getString('famloc_user_id');
      final user = SupabaseService.currentUser;
      final userId = user?.id ?? savedUserId;
      if (userId == null || userId.isEmpty) return;

      // 1. Baca baterai
      int? batteryLevel;
      try {
        final b = await Battery().batteryLevel;
        batteryLevel = (b >= 0 && b <= 100) ? b : null;
      } catch (_) {}

      final speedKmh = pos.speed > 0 ? (pos.speed * 3.6) : 0.0;

      // 2. Push ke database Supabase via RPC update_location_background
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
      lastHeartbeat = DateTime.now();

      // 3. Update notifikasi di status bar
      if (service is AndroidServiceInstance) {
        final battText = batteryLevel != null ? ' · 🔋 $batteryLevel%' : '';
        final spdText = speedKmh >= 10 ? ' · 🚗 ${speedKmh.round()} km/jam' : '';
        service.setForegroundNotificationInfo(
          title: '📍 FamLoc Berbagi Lokasi Aktif',
          content: 'Terhubung realtime$battText$spdText',
        );
      }

      // 4. Evaluasi Geofencing Diri Sendiri (HANYA SEKALI SAJA SAAT TIBA / BERANGKAT)
      if (cachedPlaces.isNotEmpty) {
        final myPos = LatLng(pos.latitude, pos.longitude);
        String? currentPlace;
        String currentIcon = '🏠';

        for (final p in cachedPlaces) {
          final d = distCalc.as(LengthUnit.Meter, myPos, LatLng(p.lat, p.lng));
          if (d <= p.radius) {
            currentPlace = p.name;
            currentIcon = p.icon;
            break;
          }
        }

        final nowMs = DateTime.now().millisecondsSinceEpoch;

        if (currentPlace != null && currentPlace != lastMyPlace) {
          // Hanya beri notifikasi jika belum pernah di-notif dalam 60 menit terakhir untuk tempat yang sama
          final lastAlertTime = prefs.getInt('last_alert_self_$currentPlace') ?? 0;
          if (nowMs - lastAlertTime > 60 * 60 * 1000) {
            await prefs.setInt('last_alert_self_$currentPlace', nowMs);
            lastMyPlace = currentPlace;
            await prefs.setString('saved_last_place_self', currentPlace);

            NotificationService.showGeofenceNotification(
              name: 'Anda',
              placeName: currentPlace,
              isArriving: true,
              icon: currentIcon,
              eventTime: DateTime.now(),
            );

            try {
              await SupabaseService.client.from('place_events').insert({
                'user_id': userId,
                'place_name': currentPlace,
                'event_type': 'arrived',
                'icon': currentIcon,
              });
              await SupabaseService.sendGeofencePush(
                placeName: currentPlace,
                isArriving: true,
                icon: currentIcon,
              );
            } catch (_) {}
          } else {
            lastMyPlace = currentPlace;
          }
        } else if (currentPlace == null && lastMyPlace != null && lastMyPlace!.isNotEmpty) {
          // Cek buffer hysteresis (radius + 150m) agar tidak bouncing akibat deviasi GPS di gedung
          bool stillNear = false;
          for (final p in cachedPlaces) {
            if (p.name == lastMyPlace) {
              final d = distCalc.as(LengthUnit.Meter, myPos, LatLng(p.lat, p.lng));
              if (d <= p.radius + 150) {
                stillNear = true;
                break;
              }
            }
          }

          if (!stillNear) {
            final departedPlace = lastMyPlace!;
            lastMyPlace = null;
            await prefs.remove('saved_last_place_self');

            NotificationService.showGeofenceNotification(
              name: 'Anda',
              placeName: departedPlace,
              isArriving: false,
              icon: '🚗',
              eventTime: DateTime.now(),
            );

            try {
              await SupabaseService.client.from('place_events').insert({
                'user_id': userId,
                'place_name': departedPlace,
                'event_type': 'departed',
                'icon': '🚗',
              });
              await SupabaseService.sendGeofencePush(
                placeName: departedPlace,
                isArriving: false,
                icon: '🚗',
              );
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      debugPrint('Error handleMyLocation: $e');
    }
  }

  // A. GPS Hardware Stream (Mode Navigasi Cepat: update tiap 2 meter / 3 detik saat berkendara)
  // CATATAN: Tidak pakai foregroundNotificationConfig geolocator karena kita SUDAH punya
  // foreground service dari flutter_background_service (notif id 888).
  // Dua FGS lokasi paralel = boros baterai & memicu Android/OEM membunuh service lebih cepat.
  LocationSettings locationSettings;
  if (defaultTargetPlatform == TargetPlatform.android) {
    locationSettings = AndroidSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 3,
      intervalDuration: const Duration(seconds: 4),
      forceLocationManager: false,
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: '📍 FamLoc Berbagi Lokasi Aktif',
        notificationText: 'Menyinkronkan lokasi secara realtime...',
        enableWakeLock: true,
        setOngoing: true,
      ),
    );
  } else {
    locationSettings = const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 3,
    );
  }

  try {
    Geolocator.getPositionStream(locationSettings: locationSettings).listen(
      (Position pos) async {
        await handleMyLocation(pos);
      },
      onError: (e) {
        // KRITIS: Jangan biarkan error GPS mematikan Dart isolate!
        debugPrint('[BG] GPS Stream error (non-fatal, continuing): $e');
      },
      cancelOnError: false,
    );
  } catch (e) {
    debugPrint('[BG] Error initializing getPositionStream: $e');
  }

  // B. Loop Berkala Latar Belakang (Jalan setiap 20 detik)
  // Menjaga agar saat HP diam / layar terkunci:
  // 1. Koordinat & baterai tetap ter-push
  // 2. Mendeteksi pergerakan & kedatangan keluarga (Ibu memonitor Awanda sampai Kantor)
  Timer.periodic(const Duration(seconds: 20), (_) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sharingOn = prefs.getBool('famloc_sharing_on') ?? true;
      if (!sharingOn) return;

      final savedUserId = prefs.getString('famloc_user_id');
      final user = SupabaseService.currentUser;
      final userId = user?.id ?? savedUserId;
      if (userId == null || userId.isEmpty) return;

      final now = DateTime.now();

      // Refresh places tiap 2 menit
      if (cachedPlaces.isEmpty || now.difference(lastPlacesFetch).inMinutes >= 2) {
        await refreshPlaces();
      }

      // 1. Heartbeat posisi sendiri jika stream GPS sedang hening (HP diam > 15 detik)
      if (now.difference(lastHeartbeat).inSeconds >= 15) {
        Position? pos;
        try {
          pos = await Geolocator.getCurrentPosition(
            locationSettings: defaultTargetPlatform == TargetPlatform.android
                ? AndroidSettings(
                    accuracy: LocationAccuracy.high,
                    timeLimit: const Duration(seconds: 8),
                    forceLocationManager: true,
                  )
                : const LocationSettings(
                    accuracy: LocationAccuracy.high,
                    timeLimit: Duration(seconds: 8),
                  ),
          );
        } catch (_) {
          try {
            pos = await Geolocator.getLastKnownPosition();
          } catch (_) {}
        }

        if (pos != null) {
          await handleMyLocation(pos);
        }
      }

      // 2. Monitoring Anggota Keluarga (Pemberitahuan Tiba SEKALI SAJA)
      List<FamilyMemberLocation> family = [];
      try {
        family = await SupabaseService.getFamilyLocations(currentUserId: userId);
      } catch (e) {
        debugPrint('[BG] Error getFamilyLocations (non-fatal): $e');
      }
      final nowMs = DateTime.now().millisecondsSinceEpoch;

      for (final f in family) {
        String? fZone;
        String fIcon = '🏠';
        final fPos = LatLng(f.lat, f.lng);

        for (final p in cachedPlaces) {
          final d = distCalc.as(LengthUnit.Meter, fPos, LatLng(p.lat, p.lng));
          if (d <= p.radius) {
            fZone = p.name;
            fIcon = p.icon;
            break;
          }
        }

        final isFirstObservation = !familyPlaces.containsKey(f.userId);
        final prevZone = familyPlaces[f.userId];

        if (isFirstObservation) {
          // Saat pertama kali terhubung: catat posisi awal keluarga tanpa spam notifikasi
          familyPlaces[f.userId] = fZone ?? '';
        } else if (fZone != null && fZone != prevZone && fZone.isNotEmpty) {
          // Cek cooldown 60 menit agar tidak berulang
          final alertKey = 'last_alert_fam_${f.userId}_$fZone';
          final lastAlertTime = prefs.getInt(alertKey) ?? 0;

          if (nowMs - lastAlertTime > 60 * 60 * 1000) {
            await prefs.setInt(alertKey, nowMs);
            familyPlaces[f.userId] = fZone;

            // NOTIFIKASI KELUARGA TELAH TIBA DI TEMPAT TUJUAN (Hanya sekali!)
            NotificationService.showGeofenceNotification(
              name: f.name,
              placeName: fZone,
              isArriving: true,
              icon: fIcon,
              eventTime: DateTime.now(),
            );
          } else {
            familyPlaces[f.userId] = fZone;
          }
        } else if (fZone == null && prevZone != null && prevZone.isNotEmpty) {
          // Cek buffer hysteresis (radius + 150m) sebelum menyatakan keluarga meninggalkan tempat
          bool stillNear = false;
          for (final p in cachedPlaces) {
            if (p.name == prevZone) {
              final d = distCalc.as(LengthUnit.Meter, fPos, LatLng(p.lat, p.lng));
              if (d <= p.radius + 150) {
                stillNear = true;
                break;
              }
            }
          }

          if (!stillNear) {
            final departedZone = prevZone;
            familyPlaces[f.userId] = '';

            NotificationService.showGeofenceNotification(
              name: f.name,
              placeName: departedZone,
              isArriving: false,
              icon: '🚗',
              eventTime: DateTime.now(),
            );
          }
        }

        // 🔋 Notifikasi Baterai Lemah Keluarga (< 20%) — sekali per HP sampai baterai naik
        if (f.battery != null && f.battery! < 20) {
          if (!alertedLowBatteryUsers.contains(f.userId)) {
            alertedLowBatteryUsers.add(f.userId);
            NotificationService.showBatteryNotification(name: f.name, battery: f.battery!);
          }
        } else {
          alertedLowBatteryUsers.remove(f.userId);
        }

        // Peringatan Kecepatan Tinggi Keluarga (> 80 km/jam)
        if (f.speed != null && f.speed! >= 80) {
          if (!alertedSpeedUsers.contains(f.userId)) {
            alertedSpeedUsers.add(f.userId);
            NotificationService.showSpeedNotification(
              name: f.name,
              speed: f.speed!.round(),
              isSelf: false,
            );
          }
        } else {
          alertedSpeedUsers.remove(f.userId);
        }
      }

      // 3. Cek Ring Alert Aktif (Deringkan HP jika diminta keluarga)
      // ✅ Hanya trigger sekali per alert (bukan setiap 8 detik!)
      try {
        final ringAlerts = await SupabaseService.getActiveRingAlertsForMe();
        if (ringAlerts.isNotEmpty) {
          final ring = ringAlerts.first;
          if (ring.id != lastRingAlertId) {
            lastRingAlertId = ring.id;
            NotificationService.showRingDeviceNotification(senderName: ring.senderName);
          }
        } else {
          // Reset jika tidak ada ring alert aktif lagi
          lastRingAlertId = null;
        }
      } catch (_) {}
    } catch (e) {
      debugPrint('Error periodic background loop: $e');
    }
  });
}
