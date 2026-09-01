import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static bool _isInitialized = false;

  static const String channelSos = 'famloc_sos';
  static const String channelGeofence = 'famloc_geofence';
  static const String channelCheckin = 'famloc_checkin';
  static const String channelBattery = 'famloc_battery';

  static Future<void> initialize() async {
    if (_isInitialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse details) {
        // Callback saat notifikasi diketuk
      },
    );

    // Minta izin notifikasi di Android 13+
    final androidImpl = _notificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl != null) {
      await androidImpl.requestNotificationsPermission();
    }

    _isInitialized = true;
  }

  /// 🚨 Notifikasi Sinyal Darurat SOS (Paling Keras, Getar Panjang, Layar Kunci)
  static Future<void> showSosNotification({
    required String name,
    required double lat,
    required double lng,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      channelSos,
      'Peringatan Darurat SOS',
      channelDescription: 'Notifikasi darurat dari anggota keluarga',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 600, 200, 600, 200, 600, 200, 1000]),
      visibility: NotificationVisibility.public,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      presentBadge: true,
      interruptionLevel: InterruptionLevel.critical,
    );

    final details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    await _notificationsPlugin.show(
      999,
      '🚨 PERINGATAN DARURAT: $name',
      '$name baru saja menekan tombol darurat SOS dan membutuhkan bantuanmu segera!',
      details,
    );
  }

  /// 🏡 Notifikasi Geofencing Zona Aman (Tiba / Meninggalkan Tempat)
  static Future<void> showGeofenceNotification({
    required String name,
    required String placeName,
    required bool isArriving,
    String icon = '🏠',
  }) async {
    final title = isArriving
        ? '$icon $name Sudah Tiba di $placeName'
        : '🚗 $name Meninggalkan $placeName';

    final body = isArriving
        ? '$name baru saja sampai di area $placeName dengan selamat.'
        : '$name baru saja keluar dari area $placeName.';

    final androidDetails = AndroidNotificationDetails(
      channelGeofence,
      'Zona Aman (Geofencing)',
      channelDescription: 'Pemberitahuan saat keluarga tiba atau meninggalkan tempat',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 300, 150, 300]),
      visibility: NotificationVisibility.public,
      category: AndroidNotificationCategory.status,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      presentBadge: true,
    );

    final details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    final notifId = DateTime.now().millisecondsSinceEpoch.remainder(100000);
    await _notificationsPlugin.show(notifId, title, body, details);
  }

  /// 💬 Notifikasi Pesan Kabar Kilat (Quick Check-in)
  static Future<void> showCheckinNotification({
    required String name,
    required String message,
    required String icon,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      channelCheckin,
      'Kabar Kilat Keluarga',
      channelDescription: 'Pesan cepat dan update status dari keluarga',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 200, 100, 200]),
      visibility: NotificationVisibility.public,
      category: AndroidNotificationCategory.message,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      presentBadge: true,
    );

    final details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    final notifId = DateTime.now().millisecondsSinceEpoch.remainder(100000);
    await _notificationsPlugin.show(
      notifId,
      '$icon Kabar Kilat dari $name',
      '"$message"',
      details,
    );
  }

  /// 🔋 Notifikasi Peringatan Baterai Lemah
  static Future<void> showBatteryNotification({
    required String name,
    required int battery,
  }) async {
    final androidDetails = const AndroidNotificationDetails(
      channelBattery,
      'Peringatan Baterai Lemah',
      channelDescription: 'Notifikasi saat baterai HP keluarga tersisa sedikit',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      visibility: NotificationVisibility.public,
      category: AndroidNotificationCategory.reminder,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      presentBadge: true,
    );

    final details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    await _notificationsPlugin.show(
      888,
      '⚠️ Baterai HP $name Tersisa $battery%',
      'Baterai HP $name tersisa sedikit ($battery%). Ingatkan beliau untuk segera mengisi daya.',
      details,
    );
  }
}
