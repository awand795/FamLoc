import 'package:flutter/material.dart';
import '../theme.dart';
import 'auth_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _Page {
  final IconData icon;
  final String title, body;
  const _Page(this.icon, this.title, this.body);
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _pages = [
    _Page(Icons.family_restroom_rounded, 'Keluarga selalu dekat',
        'Lihat lokasi orang tersayang di satu peta — tanpa perlu tanya "dimana kamu?" lagi.'),
    _Page(Icons.lock_person_rounded, 'Privasimu yang memegang kendali',
        'Lokasi hanya terlihat oleh teman yang sudah saling setuju. Saklar sharing ada di tanganmu.'),
    _Page(Icons.qr_code_2_rounded, 'Mulai dalam 30 detik',
        'Cukup scan QR code atau bagikan kode undangan ke keluargamu.'),
  ];

  void _next() {
    if (_page < _pages.length - 1) {
      _controller.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const AuthScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _pages[_page];
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              Align(
                alignment: Alignment.topRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const AuthScreen()),
                  ),
                  child: const Text('Lewati'),
                ),
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        gradient: p == _pages[1]
                            ? FamColors.accentGradient
                            : FamColors.primaryGradient,
                        borderRadius: BorderRadius.circular(44),
                        boxShadow: FamColors.softShadow(),
                      ),
                      child: Icon(p.icon, size: 64, color: Colors.white),
                    ),
                    const SizedBox(height: 40),
                    Text(
                      p.title,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800, letterSpacing: -0.5),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      p.body,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 15.5, height: 1.6, color: FamColors.muted),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_pages.length, (i) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _page ? 26 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _page ? FamColors.primary : FamColors.primary.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(FamRadius.pill),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 24),
              GradientButton(
                label: _page == _pages.length - 1 ? 'Mulai Sekarang' : 'Lanjut',
                onPressed: _next,
              ),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      setState(() => _page = _controller.page?.round() ?? 0);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
