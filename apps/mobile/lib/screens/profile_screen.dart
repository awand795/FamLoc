import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';

import '../api_client.dart';
import '../background_task.dart';
import '../theme.dart';
import 'onboarding_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  User? _me;
  final _nameCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    ApiClient.me().then((u) {
      if (!mounted) return;
      setState(() => _me = u);
      _nameCtrl.text = u.name;
    }).catchError((_) {});
  }

  Future<void> _saveName() async {
    // MVP: endpoint rename belum ada di kontrak v1 — placeholder UI.
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('Edit nama akan segera hadir')));
  }

  Future<void> _uploadAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
        source: ImageSource.gallery, maxWidth: 512, imageQuality: 80);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (bytes.length > 102400) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Foto terlalu besar — coba foto lain')));
      return;
    }
    try {
      await ApiClient.uploadAvatar(Uint8List.fromList(bytes));
      final u = await ApiClient.me();
      if (!mounted) return;
      setState(() => _me = u);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _togglePrecision(bool approx) async {
    try {
      await ApiClient.setPrecision(approx ? 'approx' : 'exact');
      final u = await ApiClient.me();
      if (!mounted) return;
      setState(() => _me = u);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _changePasswordDialog() async {
    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ganti Password'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: oldCtrl, obscureText: true,
              decoration: const InputDecoration(labelText: 'Password lama')),
          const SizedBox(height: 10),
          TextField(controller: newCtrl, obscureText: true,
              decoration: const InputDecoration(labelText: 'Password baru (min. 8)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: FamColors.primary),
            onPressed: () async {
              try {
                await ApiClient.changePassword(oldCtrl.text, newCtrl.text);
                if (!ctx.mounted || !mounted) return;
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    behavior: SnackBarBehavior.floating,
                    content: Text('Password berhasil diganti ✅')));
              } catch (e) {
                ScaffoldMessenger.of(ctx)
                    .showSnackBar(SnackBar(content: Text(e.toString())));
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
      appBar: AppBar(title: const Text('⚙️ Profil & Privasi')),
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
                          child: Text('Kode: ${_me!.inviteCode}',
                              style: const TextStyle(color: Colors.white, fontSize: 12, letterSpacing: 1.5)),
                        ),
                      ])),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _SectionCard(title: '🔒 Privasi', children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeThumbColor: FamColors.primary,
                    title: const Text('Mode lokasi kasar'),
                    subtitle: const Text(
                        'Keluarga hanya melihat perkiraan ±500m. Posisi akuratmu tetap tersimpan aman.',
                        style: TextStyle(fontSize: 12.5)),
                    value: _me!.locationPrecision == 'approx',
                    onChanged: (v) => _togglePrecision(v),
                  ),
                ]),
                const SizedBox(height: 14),
                _SectionCard(title: '👤 Akun', children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.edit_rounded),
                    title: const Text('Ubah nama'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _saveName,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.password_rounded),
                    title: const Text('Ganti password'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _changePasswordDialog,
                  ),
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.description_rounded),
                    title: Text('Kebijakan privasi'),
                    subtitle: Text('famloc.vercel.app/privacy', style: TextStyle(fontSize: 12)),
                  ),
                ]),
                const SizedBox(height: 14),
                _SectionCard(title: 'ℹ️ Tentang', children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      'FamLoc v0.1 — Lokasi HANYA dibagikan ke teman mutual. '
                      'Peta © OpenStreetMap contributors.',
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
                    await ApiClient.clearToken();
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
