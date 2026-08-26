import 'package:flutter/material.dart';
import '../api_client.dart';
import '../theme.dart';

class FamilyScreen extends StatefulWidget {
  const FamilyScreen({super.key});

  @override
  State<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends State<FamilyScreen> {
  List<Friend>? _friends;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final f = await ApiClient.friends();
      if (!mounted) return;
      setState(() { _friends = f; _error = null; });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  void _confirmUnfriend(Friend f) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Hapus ${f.name}?'),
        content: const Text('Kalian berhenti saling melihat lokasi. Tindakan ini tidak bisa dibatalkan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: FamColors.danger),
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
          content: Text('Permintaan dikirim ke ${f.name} 🙏')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('👨‍👩‍👧 Keluargaku')),
      body: _error != null
          ? Center(child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_error!, textAlign: TextAlign.center)))
          : _friends == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _friends!.isEmpty
                      ? ListView(children: const [
                          SizedBox(height: 120),
                          Center(child: Text(
                            'Belum punya teman?\nTambahkan keluargamu dengan QR code 👋',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: FamColors.muted),
                          )),
                        ])
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                          itemCount: _friends!.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (_, i) {
                            final f = _friends![i];
                            final loc = f.location;
                            final live = f.sharingOn &&
                                loc != null &&
                                DateTime.now().difference(loc.updatedAt).inMinutes <= 15;
                            final dist = loc?.distanceM;
                            return Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(FamRadius.card),
                                boxShadow: FamColors.softShadow(opacity: 0.10),
                              ),
                              child: Row(
                                children: [
                                  InitialAvatar(name: f.name, radius: 26),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(children: [
                                          Expanded(
                                            child: Text(f.name,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium
                                                    ?.copyWith(fontWeight: FontWeight.w800)),
                                          ),
                                          BatteryIndicator(level: live ? loc.battery : null),
                                        ]),
                                        const SizedBox(height: 6),
                                        Wrap(spacing: 6, runSpacing: 6, children: [
                                          StatusChip(
                                              label: live
                                                  ? ((loc.heading ?? -1) >= 0 ? 'Bergerak' : 'Diam')
                                                  : 'Offline',
                                              icon: live ? Icons.directions_car_rounded : Icons.pause_circle_rounded,
                                              color: live ? FamColors.primary : FamColors.muted),
                                          if (dist != null)
                                            Text('${_fmtDist(dist)} dari kamu',
                                                style: const TextStyle(fontSize: 12, color: FamColors.muted)),
                                        ]),
                                      ],
                                    ),
                                  ),
                                  PopupMenuButton<String>(
                                    onSelected: (v) {
                                      if (v == 'unfriend') _confirmUnfriend(f);
                                      if (v == 'ask') _askLocation(f);
                                    },
                                    itemBuilder: (_) => [
                                      const PopupMenuItem(value: 'ask', child: Text('📣 Minta lokasi')),
                                      const PopupMenuItem(value: 'unfriend', child: Text('❌ Hapus pertemanan')),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
    );
  }

  String _fmtDist(double m) =>
      m < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(1)} km';
}
