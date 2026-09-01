import 'package:flutter/material.dart';
import '../supabase_service.dart';
import '../theme.dart';

class FamilyScreen extends StatefulWidget {
  const FamilyScreen({super.key});

  @override
  State<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends State<FamilyScreen> {
  List<UserProfile> _friends = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    setState(() => _loading = true);
    try {
      final list = await SupabaseService.getFriends();
      if (!mounted) return;
      setState(() {
        _friends = list;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showAddFriendDialog() {
    final emailCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FamRadius.card)),
        title: const Text('➕ Tambah Keluarga / Teman'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Masukkan email yang sudah didaftarkan oleh anggota keluarga atau temanmu:',
              style: TextStyle(fontSize: 13, color: FamColors.muted),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: 'Email anggota keluarga',
                prefixIcon: const Icon(Icons.alternate_email_rounded),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: FamColors.primary),
            onPressed: () async {
              final email = emailCtrl.text.trim();
              if (email.isEmpty) return;
              Navigator.pop(ctx);
              _addFriend(email);
            },
            child: const Text('Tambah'),
          ),
        ],
      ),
    );
  }

  Future<void> _addFriend(String email) async {
    try {
      await SupabaseService.addFriendByEmail(email);
      _loadFriends();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(behavior: SnackBarBehavior.floating, content: Text('Berhasil ditambahkan ke keluarga! 🎉')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, content: Text(e.toString().replaceAll('Exception: ', ''))),
      );
    }
  }

  Future<void> _confirmRemoveFriend(UserProfile friend) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FamRadius.card)),
        title: Text('Hapus ${friend.name}?'),
        content: Text(
          'Kalian tidak akan lagi bisa saling melihat lokasi di peta setelah dihapus.',
          style: const TextStyle(fontSize: 13.5, color: FamColors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: FamColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await SupabaseService.removeFriend(friend.id);
        _loadFriends();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(behavior: SnackBarBehavior.floating, content: Text('${friend.name} berhasil dihapus')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(behavior: SnackBarBehavior.floating, content: Text('Gagal menghapus: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('👨‍👩‍👧 Keluargaku & Teman'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _friends.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                            color: FamColors.primary.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.people_outline_rounded, size: 48, color: FamColors.primary),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Belum Ada Anggota Keluarga',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Tambahkan email akun Mama atau keluargamu agar bisa saling memantau lokasi secara realtime.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13.5, color: FamColors.muted, height: 1.5),
                        ),
                        const SizedBox(height: 24),
                        GradientButton(
                          label: '➕ Tambah Anggota Sekarang',
                          onPressed: _showAddFriendDialog,
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _friends.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (ctx, idx) {
                    final f = _friends[idx];
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => Navigator.pop(context, f.id),
                        borderRadius: BorderRadius.circular(FamRadius.card),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(FamRadius.card),
                            boxShadow: FamColors.softShadow(opacity: 0.08),
                          ),
                          child: Row(
                            children: [
                              f.avatarUrl != null
                                  ? CircleAvatar(
                                      radius: 24,
                                      backgroundImage: NetworkImage(f.avatarUrl!),
                                    )
                                  : InitialAvatar(name: f.name, radius: 24),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      f.name,
                                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        const Icon(Icons.my_location_rounded, size: 12, color: FamColors.primary),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Ketuk untuk lacak di peta',
                                          style: TextStyle(fontSize: 12, color: FamColors.primary.withValues(alpha: 0.8), fontWeight: FontWeight.w600),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.person_remove_rounded, color: FamColors.danger),
                                tooltip: 'Hapus Teman',
                                onPressed: () => _confirmRemoveFriend(f),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: _friends.isNotEmpty
          ? FloatingActionButton.extended(
              backgroundColor: FamColors.primary,
              foregroundColor: Colors.white,
              onPressed: _showAddFriendDialog,
              icon: const Icon(Icons.person_add_rounded),
              label: const Text('Tambah Anggota', style: TextStyle(fontWeight: FontWeight.w700)),
            )
          : null,
    );
  }
}
