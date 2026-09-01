import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase_service.dart';
import '../background_task.dart';
import '../theme.dart';
import 'onboarding_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  UserProfile? _me;
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final profile = await SupabaseService.getMyProfile();
    if (!mounted) return;
    setState(() {
      _me = profile;
      if (profile != null) {
        _nameCtrl.text = profile.name;
        _phoneCtrl.text = profile.phone ?? '';
      }
    });
  }

  Future<void> _saveName() async {
    final newName = _nameCtrl.text.trim();
    if (newName.isEmpty) return;
    try {
      await SupabaseService.updateName(newName);
      await _loadProfile();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Nama berhasil disimpan ✅')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal: $e')));
    }
  }

  Future<void> _savePhone() async {
    final phone = _phoneCtrl.text.trim();
    try {
      await SupabaseService.updatePhone(phone);
      await _loadProfile();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Nomor HP berhasil disimpan ✅')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal: $e')));
    }
  }

  Future<void> _uploadAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
        source: ImageSource.gallery, maxWidth: 512, imageQuality: 80);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    try {
      await SupabaseService.uploadAvatar(Uint8List.fromList(bytes));
      await _loadProfile();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Foto profil diperbarui ✅')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload gagal: $e')));
    }
  }

  Future<void> _changePasswordDialog() async {
    final newCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ganti Password'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: newCtrl, obscureText: true,
              decoration: const InputDecoration(labelText: 'Password baru (min. 6 karakter)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: FamColors.primary),
            onPressed: () async {
              try {
                if (newCtrl.text.length < 6) throw Exception('Password minimal 6 karakter');
                await SupabaseService.client.auth.updateUser(
                  UserAttributes(password: newCtrl.text),
                );
                if (!ctx.mounted || !mounted) return;
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    behavior: SnackBarBehavior.floating,
                    content: Text('Password berhasil diganti ✅')));
              } catch (e) {
                ScaffoldMessenger.of(ctx)
                    .showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))));
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('⚙️ Profil & Pengaturan')),
      body: _me == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                // Kartu profil
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: FamColors.accentGradient,
                    borderRadius: BorderRadius.circular(FamRadius.card),
                    boxShadow: FamColors.softShadow(opacity: 0.2),
                  ),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: _uploadAvatar,
                        child: Stack(children: [
                          CircleAvatar(
                            radius: 34,
                            backgroundColor: Colors.white24,
                            backgroundImage: _me!.avatarUrl == null
                                ? null : NetworkImage(_me!.avatarUrl!),
                            child: _me!.avatarUrl == null
                                ? InitialAvatar(name: _me!.name, radius: 33)
                                : null,
                          ),
                          const Positioned(
                            right: -2, bottom: -2,
                            child: CircleAvatar(radius: 12, backgroundColor: Colors.white,
                                child: Icon(Icons.edit_rounded, size: 13, color: FamColors.primary)),
                          ),
                        ]),
                      ),
                      const SizedBox(width: 16),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_me!.name,
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                color: Colors.white, fontWeight: FontWeight.w800)),
                        Text(_me!.email,
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
                        const SizedBox(height: 6),
                        Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(color: Colors.white24,
                              borderRadius: BorderRadius.circular(FamRadius.pill)),
                          child: const Text('Keluarga',
                              style: TextStyle(color: Colors.white, fontSize: 12, letterSpacing: 1.2)),
                        ),
                      ])),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _SectionCard(title: '👤 Akun', children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.edit_rounded),
                    title: const Text('Ubah nama panggilan'),
                    subtitle: Text(_me!.name),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Ubah Nama'),
                          content: TextField(
                            controller: _nameCtrl,
                            decoration: const InputDecoration(labelText: 'Nama baru'),
                          ),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
                            FilledButton(
                              style: FilledButton.styleFrom(backgroundColor: FamColors.primary),
                              onPressed: () {
                                Navigator.pop(ctx);
                                _saveName();
                              },
                              child: const Text('Simpan'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                    ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.phone_rounded),
                    title: const Text('Nomor HP / WhatsApp'),
                    subtitle: Text(_me?.phone != null && _me!.phone!.isNotEmpty ? _me!.phone! : 'Belum diisi (opsional)'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Nomor HP / WhatsApp'),
                          content: TextField(
                            controller: _phoneCtrl,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                              labelText: 'Nomor HP (misal: 08123456789)',
                              hintText: '08123456789',
                            ),
                          ),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
                            FilledButton(
                              style: FilledButton.styleFrom(backgroundColor: FamColors.primary),
                              onPressed: () {
                                Navigator.pop(ctx);
                                _savePhone();
                              },
                              child: const Text('Simpan'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.password_rounded),
                    title: const Text('Ganti password'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _changePasswordDialog,
                  ),
                ]),
                const SizedBox(height: 14),
                _SectionCard(title: 'ℹ️ Tentang', children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      'FamLoc — Aplikasi pelacak lokasi privat keluarga.\n'
                      'Peta © OpenStreetMap contributors.\n'
                      'Didukung oleh Supabase Realtime.',
                      style: TextStyle(fontSize: 12.5, color: FamColors.muted, height: 1.5),
                    ),
                  ),
                ]),
                const SizedBox(height: 22),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: FamColors.danger,
                      side: BorderSide(color: FamColors.danger.withValues(alpha: 0.4))),
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Keluar'),
                  onPressed: () async {
                    await SupabaseService.signOut();
                    await stopBackgroundSharing();
                    if (!context.mounted) return;
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const OnboardingScreen()),
                      (_) => false,
                    );
                  },
                ),
              ],
            ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SectionCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(FamRadius.card),
        boxShadow: FamColors.softShadow(opacity: 0.08),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        ...children,
        const SizedBox(height: 8),
      ]),
    );
  }
}
