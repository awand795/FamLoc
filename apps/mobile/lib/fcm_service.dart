import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';

import 'notification_service.dart';
import 'supabase_service.dart';

@pragma('vm:entry-point')
Future<void> famlocFirebaseBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  await Firebase.initializeApp();
  await NotificationService.initialize();
  await NotificationService.showRemoteNotification(message.data);
}

class FcmService {
  static bool _configured = false;

  static Future<bool> initialize() async {
    if (_configured) return true;
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(famlocFirebaseBackgroundHandler);
    await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);

    FirebaseMessaging.onMessage.listen((message) async {
      await NotificationService.showRemoteNotification(message.data);
    });
    FirebaseMessaging.instance.onTokenRefresh.listen(_saveToken);
    _configured = true;
    return true;
  }

  static Future<void> registerCurrentDevice() async {
    if (!await initialize()) return;
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) await _saveToken(token);
  }

  static Future<void> _saveToken(String token) async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    await SupabaseService.client.from('device_tokens').upsert({
      'token': token,
      'user_id': user.id,
      'platform': 'android',
      'updated_at': DateTime.now().toIso8601String(),
    });
  }
}
