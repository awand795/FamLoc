import 'package:flutter/material.dart';
import '../api_client.dart';
import '../theme.dart';
import 'add_friend_screen.dart';

class FamilyScreen extends StatefulWidget {
  const FamilyScreen({super.key});

  @override
  State<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends State<FamilyScreen> {
  List<Friend>? _friends;
  int _pendingRequestsCount = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final f = await ApiClient.friends();
      int pending = 0;
      try {
        final reqs = await ApiClient.friendRequests();
        pending = reqs.incoming.length;
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _friends = f;
        _pendingRequestsCount = pending;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  void _confirmUnfriend(Friend f) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FamRadius.card)),
        title: Text('Hapus ${f.name}?'),
        content: const Text('Kalian akan berhenti saling melihat lokasi. Tindakan ini dapat dibatalkan dengan menambah teman lagi.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: FamColors.danger,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FamRadius.pill)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ApiClient.unfriend(f.id);
                _load();
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(e.toString())));
              }
            },
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
  }

  Future<void> _askLocation(Friend f) async {
    try {
      await ApiClient.requestLocation(f.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('Permintaan dikirim ke ${f.name} 🙏'),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(e.toString()),
      ));
    }
  }

  String _fmtDist(double m) =>
      m < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(1)} km';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('👨‍👩‍👧 Keluargaku'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_1_rounded),
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const AddFriendScreen(),
              ));
              _load();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'family_add_friend',
        elevation: 4,
        backgroundColor: FamColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_rounded),
        label: const Text('Tambah Teman', style: TextStyle(fontWeight: FontWeight.w700)),
        onPressed: () async {
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const AddFriendScreen(),
          ));
          _load();
        },
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center,
                        style: const TextStyle(color: FamColors.danger)),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Coba Lagi'),
                    ),
                  ],
                ),
              ),
            )
          : _friends == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    children: [
                      // Banner Permintaan Pertemanan Pending jika ada
                      if (_pendingRequestsCount > 0) ...[
                        GestureDetector(
                          onTap: () async {
                            await Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => const AddFriendScreen(initialTabIndex: 3),
                            ));
                            _load();
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              gradient: FamColors.accentGradient,
                              borderRadius: BorderRadius.circular(FamRadius.card),
                              boxShadow: FamColors.softShadow(opacity: 0.2),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: const BoxDecoration(
                                    color: Colors.white24,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.group_add_rounded, color: Colors.white, size: 24),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '$_pendingRequestsCount Permintaan Pertemanan',
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
                                      ),
                                      const SizedBox(height: 2),
                                      const Text(
                                        'Ketuk untuk menerima atau menolak',
                                        style: TextStyle(color: Colors.white70, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white70, size: 16),
                              ],
                            ),
                          ),
                        ),
                      ],

                      if (_friends!.isEmpty)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(28),
                                  decoration: BoxDecoration(
                                    color: FamColors.primary.withValues(alpha: 0.08),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.people_outline_rounded, size: 68, color: FamColors.primary),
                                ),
                                const SizedBox(height: 20),
                                const Text(
                                  'Belum Punya Teman',
                                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Tambahkan anggota keluarga atau temanmu dengan membagikan kode undangan atau scan QR Code.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: FamColors.muted, fontSize: 13.5, height: 1.4),
                                ),
                                const SizedBox(height: 24),
                                SizedBox(
                                  width: 220,
                                  child: GradientButton(
                                    label: '➕ Tambah Teman',
                                    onPressed: () async {
                                      await Navigator.of(context).push(MaterialPageRoute(
                                        builder: (_) => const AddFriendScreen(),
                                      ));
                                      _load();
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        ...List.generate(_friends!.length, (i) {
                          final f = _friends![i];
                          final loc = f.location;
                          final live = f.sharingOn &&
                              loc != null &&
                              DateTime.now().difference(loc.updatedAt).inMinutes <= 15;
                          final dist = loc?.distanceM;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(FamRadius.card),
                              boxShadow: FamColors.softShadow(opacity: 0.08),
                            ),
                            child: Row(
                              children: [
                                AvatarWithRing(
                                  name: f.name,
                                  isLive: live,
                                  radius: 26,
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              f.name,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium
                                                  ?.copyWith(fontWeight: FontWeight.w800),
                                            ),
                                          ),
                                          BatteryIndicator(level: live ? loc.battery : null),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 6,
                                        crossAxisAlignment: WrapCrossAlignment.center,
                                        children: [
                                          StatusChip(
                                            label: live
                                                ? ((loc.heading ?? -1) >= 0 ? 'Bergerak' : 'Diam')
                                                : 'Offline',
                                            icon: live ? Icons.directions_car_rounded : Icons.pause_circle_rounded,
                                            color: live ? FamColors.primary : FamColors.muted,
                                          ),
                                          if (dist != null)
                                            Text(
                                              '${_fmtDist(dist)} dari kamu',
                                              style: const TextStyle(fontSize: 12, color: FamColors.muted, fontWeight: FontWeight.w500),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                PopupMenuButton<String>(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  onSelected: (v) {
                                    if (v == 'unfriend') _confirmUnfriend(f);
                                    if (v == 'ask') _askLocation(f);
                                  },
                                  itemBuilder: (_) => [
                                    const PopupMenuItem(
                                      value: 'ask',
                                      child: Row(
                                        children: [
                                          Icon(Icons.notifications_active_rounded, size: 18, color: FamColors.primary),
                                          SizedBox(width: 10),
                                          Text('Minta Lokasi'),
                                        ],
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'unfriend',
                                      child: Row(
                                        children: [
                                          Icon(Icons.person_remove_rounded, size: 18, color: FamColors.danger),
                                          SizedBox(width: 10),
                                          Text('Hapus Pertemanan', style: TextStyle(color: FamColors.danger)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        }),
                    ],
                  ),
                ),
    );
  }
}

