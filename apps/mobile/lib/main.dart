import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'supabase_service.dart';
import 'screens/onboarding_screen.dart';
import 'screens/map_home.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await SupabaseService.initialize();
  final loggedIn = SupabaseService.isLoggedIn;
  runApp(FamLocApp(initialRoute: loggedIn ? '/home' : '/'));
}

class FamLocApp extends StatelessWidget {
  final String initialRoute;
  const FamLocApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FamLoc',
      debugShowCheckedModeBanner: false,
      theme: buildFamTheme(),
      initialRoute: initialRoute,
      routes: {
        '/': (_) => const OnboardingScreen(),
        '/home': (_) => const MapHomeScreen(),
      },
    );
  }
}
