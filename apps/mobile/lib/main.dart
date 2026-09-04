import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'background_service.dart';
import 'notification_service.dart';
import 'supabase_service.dart';
import 'screens/onboarding_screen.dart';
import 'screens/map_home.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await NotificationService.initialize();
  await SupabaseService.initialize();
  final loggedIn = SupabaseService.isLoggedIn;
  if (loggedIn) {
    try {
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
