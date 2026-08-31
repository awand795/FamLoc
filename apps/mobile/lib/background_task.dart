import 'dart:convert';
import 'package:workmanager/workmanager.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart' show kApiBase;

const String taskName = 'famlocPushLocation';

/// Entry point untuk background isolate — wajib top-level function.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    switch (task) {
      case taskName:
        await _pushLocationBackground();
        return true;
      default:
        return false;
    }
  });
}

/// Ambil lokasi dan push ke server dari background isolate.
Future<void> _pushLocationBackground() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('famloc_token');
    if (token == null || token.isEmpty) return;

    final sharingOn = prefs.getBool('famloc_sharing_on') ?? false;
    if (!sharingOn) return;

    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );

    final uri = Uri.parse('$kApiBase/locations');
    await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'lat': pos.latitude,
        'lng': pos.longitude,
        'accuracy': pos.accuracy,
        'heading': pos.heading >= 0 ? pos.heading : null,
        'battery': null,
        'is_mocked': pos.isMocked,
      }),
    );

    await prefs.setString('famloc_last_bg_push', DateTime.now().toIso8601String());
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
