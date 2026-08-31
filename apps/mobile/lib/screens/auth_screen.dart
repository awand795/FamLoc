import 'package:flutter/material.dart';
import '../supabase_service.dart';
import '../theme.dart';
import 'map_home.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _isRegister = false;
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    setState(() { _loading = true; _error = null; });
    try {
      if (_isRegister) {
        final res = await SupabaseService.signUp(
          name: _name.text.trim(),
          email: _email.text.trim(),
          password: _password.text,
        );
        if (res.user == null) throw Exception('Gagal membuat akun');
      } else {
        final res = await SupabaseService.signIn(
          email: _email.text.trim(),
          password: _password.text,
        );
        if (res.user == null) throw Exception('Login gagal');
      }
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MapHomeScreen()),
        (_) => false,
      );
    } catch (e) {
      setState(() => _error = e.toString().replaceAll('Exception: ', '').replaceAll('AuthException(message: ', '').replaceAll(', statusCode: null)', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              // Hero gradient ala Dribbble
              Container(
                height: 190,
                decoration: BoxDecoration(
                  gradient: FamColors.accentGradient,
                  borderRadius: BorderRadius.circular(FamRadius.card),
                  boxShadow: FamColors.softShadow(opacity: 0.25),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      right: -30, top: -30,
                      child: CircleAvatar(radius: 70, backgroundColor: Colors.white.withValues(alpha: 0.12)),
                    ),
                    Positioned(
                      left: -20, bottom: -40,
                      child: CircleAvatar(radius: 60, backgroundColor: Colors.white.withValues(alpha: 0.10)),
                    ),
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.location_on_rounded, size: 52, color: Colors.white),
                          const SizedBox(height: 6),
                          Text('FamLoc',
                              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                                  color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: -1)),
                          Text('Keluarga selalu tahu rumahnya di mana',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              Text(
                _isRegister ? 'Buat akun baru' : 'Selamat datang kembali',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 20),
              if (_isRegister) ...[
                TextField(
                  controller: _name,
                  decoration: InputDecoration(
                    labelText: 'Nama panggilan',
                    prefixIcon: const Icon(Icons.person_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              TextField(
                controller: _email,
 keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'Email',
                  prefixIcon: const Icon(Icons.alternate_email_rounded),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Password (min. 8 karakter)',
                  prefixIcon: const Icon(Icons.lock_rounded),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: FamColors.danger, fontSize: 13)),
              ],
              const SizedBox(height: 22),
              GradientButton(
                label: _isRegister ? 'Daftar' : 'Masuk',
                loading: _loading,
                onPressed: _submit,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_isRegister ? 'Sudah punya akun?' : 'Belum punya akun?',
                      style: const TextStyle(color: FamColors.muted)),
                  TextButton(
                    onPressed: () => setState(() {
                      _isRegister = !_isRegister;
                      _error = null;
                    }),
                    child: Text(_isRegister ? 'Masuk' : 'Daftar',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
