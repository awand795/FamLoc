import 'package:workmanager/workmanager.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'supabase_service.dart';

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

/// Ambil lokasi dan push ke Supabase dari background isolate.
Future<void> _pushLocationBackground() async {
  try {
    final prefs = await SharedPreferences.getInstance();
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

    // Dapatkan token Supabase yang tersimpan di local storage
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
