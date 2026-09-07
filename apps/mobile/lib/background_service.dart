import 'dart:async';
import 'dart:ui';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notification_service.dart';
import 'supabase_service.dart';

const String kForegroundChannelId = 'famloc_foreground';
const int kForegroundNotificationId = 888;

/// Inisialisasi Layanan Latar Belakang 24/7 (Android Foreground Service)
Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  // Pastikan notification channel siap sebelum service aktif
  await NotificationService.initialize();

  // Simpan user_id aktif ke SharedPreferences jika ada
  final user = SupabaseService.currentUser;
  if (user != null) {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('famloc_user_id', user.id);
      await prefs.setBool('famloc_sharing_on', true);
    } catch (_) {}
  }

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
  bool isFirstSelfGeofenceCheck = true;
  final Map<String, String> familyPlaces = {}; // userId -> placeName
  final Set<String> alertedSpeedUsers = {};
  DateTime lastHeartbeat = DateTime.fromMillisecondsSinceEpoch(0);
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

        if (isFirstSelfGeofenceCheck) {
          // Saat pertama kali jalan: catat posisi sekarang tanpa memunculkan notifikasi
          isFirstSelfGeofenceCheck = false;
          lastMyPlace = currentPlace;
          if (currentPlace != null) {
            await prefs.setString('saved_last_place_self', currentPlace);
          }
        } else if (currentPlace != null && currentPlace != lastMyPlace) {
          // Hanya beri notifikasi jika belum pernah di-notif dalam 15 menit terakhir untuk tempat yang sama
          final lastAlertTime = prefs.getInt('last_alert_self_$currentPlace') ?? 0;
          if (nowMs - lastAlertTime > 15 * 60 * 1000) {
            await prefs.setInt('last_alert_self_$currentPlace', nowMs);
            lastMyPlace = currentPlace;
            await prefs.setString('saved_last_place_self', currentPlace);

            NotificationService.showGeofenceNotification(
              name: 'Anda',
              placeName: currentPlace,
              isArriving: true,
              icon: currentIcon,
            );

            try {
              await SupabaseService.client.from('place_events').insert({
                'user_id': userId,
                'place_name': currentPlace,
                'event_type': 'arrived',
                'icon': currentIcon,
              });
            } catch (_) {}
          } else {
            lastMyPlace = currentPlace;
          }
        } else if (currentPlace == null && lastMyPlace != null && lastMyPlace!.isNotEmpty) {
          // Cek buffer hysteresis (radius + 40m) agar tidak bouncing akibat deviasi GPS di gedung
          bool stillNear = false;
          for (final p in cachedPlaces) {
            if (p.name == lastMyPlace) {
              final d = distCalc.as(LengthUnit.Meter, myPos, LatLng(p.lat, p.lng));
              if (d <= p.radius + 40) {
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
            );

            try {
              await SupabaseService.client.from('place_events').insert({
                'user_id': userId,
                'place_name': departedPlace,
                'event_type': 'departed',
                'icon': '🚗',
              });
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      debugPrint('Error handleMyLocation: $e');
    }
  }

  // A. GPS Hardware Stream (Mode Navigasi Cepat: update tiap 2 meter / 3 detik saat berkendara)
  LocationSettings locationSettings;
  if (defaultTargetPlatform == TargetPlatform.android) {
    locationSettings = AndroidSettings(
      accuracy: LocationAccuracy.bestForNavigation, // Akurasi tertinggi untuk berkendara
      distanceFilter: 2, // Bergerak 2 meter langsung kirim
      intervalDuration: const Duration(seconds: 3), // Cek interval 3 detik
      forceLocationManager: false,
    );
  } else {
    locationSettings = const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 2,
    );
  }

  try {
    Geolocator.getPositionStream(locationSettings: locationSettings).listen((Position pos) async {
      await handleMyLocation(pos);
    });
  } catch (e) {
    debugPrint('Error getPositionStream: $e');
  }

  // B. Loop Berkala Latar Belakang (Jalan setiap 8 detik)
  // Menjaga agar saat HP diam / layar terkunci:
  // 1. Koordinat & baterai tetap ter-push
  // 2. Mendeteksi pergerakan & kedatangan keluarga (Ibu memonitor Awanda sampai Kantor)
  Timer.periodic(const Duration(seconds: 8), (_) async {
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

      // 1. Heartbeat posisi sendiri jika stream GPS sedang hening (HP diam > 10 detik)
      if (now.difference(lastHeartbeat).inSeconds >= 10) {
        Position? pos;
        try {
          pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 5),
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
      final family = await SupabaseService.getFamilyLocations(currentUserId: userId);
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
          // Cek cooldown 15 menit agar tidak berulang
          final alertKey = 'last_alert_fam_${f.userId}_$fZone';
          final lastAlertTime = prefs.getInt(alertKey) ?? 0;

          if (nowMs - lastAlertTime > 15 * 60 * 1000) {
            await prefs.setInt(alertKey, nowMs);
            familyPlaces[f.userId] = fZone;

            // NOTIFIKASI KELUARGA TELAH TIBA DI TEMPAT TUJUAN (Hanya sekali!)
            NotificationService.showGeofenceNotification(
              name: f.name,
              placeName: fZone,
              isArriving: true,
              icon: fIcon,
            );
          } else {
            familyPlaces[f.userId] = fZone;
          }
        } else if (fZone == null && prevZone != null && prevZone.isNotEmpty) {
          // Cek buffer hysteresis (radius + 40m) sebelum menyatakan keluarga meninggalkan tempat
          bool stillNear = false;
          for (final p in cachedPlaces) {
            if (p.name == prevZone) {
              final d = distCalc.as(LengthUnit.Meter, fPos, LatLng(p.lat, p.lng));
              if (d <= p.radius + 40) {
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
            );
          }
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
      try {
        final ringAlerts = await SupabaseService.getActiveRingAlertsForMe();
        if (ringAlerts.isNotEmpty) {
          final ring = ringAlerts.first;
          NotificationService.showRingDeviceNotification(senderName: ring.senderName);
        }
      } catch (_) {}
    } catch (e) {
      debugPrint('Error periodic background loop: $e');
    }
  });
}
