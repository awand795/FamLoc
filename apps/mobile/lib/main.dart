import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'background_service.dart';
import 'notification_service.dart';
import 'supabase_service.dart';
import 'screens/onboarding_screen.dart';
import 'screens/map_home.dart';
import 'theme.dart';

import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await NotificationService.initialize();
  await SupabaseService.initialize();
  final loggedIn = SupabaseService.isLoggedIn;
  if (loggedIn) {
    try {
      final user = SupabaseService.currentUser;
      if (user != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('famloc_user_id', user.id);
        // JANGAN paksa famloc_sharing_on = true di sini!
        // Sharing status diatur oleh user dari UI (map_home.dart _startSharingIfOn)
        // dan disimpan permanen di SharedPreferences.
        // Memaksa true di sini akan mengabaikan preferensi user yang sudah mematikan sharing.
        final sharingAlreadySet = prefs.containsKey('famloc_sharing_on');
        if (!sharingAlreadySet) {
          // Hanya set default true jika belum pernah di-set (install pertama kali)
          await prefs.setBool('famloc_sharing_on', true);
        }
      }
      await initializeBackgroundService();
    } catch (_) {}
  }
  runApp(FamLocApp(loggedIn: loggedIn));
}

class FamLocApp extends StatelessWidget {
  final bool loggedIn;
  const FamLocApp({super.key, required this.loggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FamLoc',
      debugShowCheckedModeBanner: false,
      theme: buildFamTheme(),
      home: loggedIn ? const MapHomeScreen() : const OnboardingScreen(),
    );
  }
}
