import 'package:flutter/material.dart';
import '../api_client.dart';
import '../theme.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<FamNotification>? _items;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final n = await ApiClient.notifications();
      if (!mounted) return;
      setState(() => _items = n);
    } catch (_) {
      if (!mounted) return;
      setState(() => _items = []);
    }
  }

  Future<void> _act(FamNotification n, String action) async {
    setState(() => _busy = true);
    try {
      if (n.type == 'friend_request') {
        await ApiClient.respondFriendRequest(n.refId, action);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(action == 'accept'
              ? 'Permintaan pertemanan ${n.name} diterima! 🎉'
              : 'Permintaan pertemanan ditolak'),
        ));
      } else if (n.type == 'location_request') {
        await ApiClient.respondLocationRequest(n.refId, action);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(action == 'accept'
              ? 'Berbagi lokasi diaktifkan untuk ${n.name} 📍'
              : 'Permintaan lokasi diabaikan'),
        ));
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(e.toString()),
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _timeAgo(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'baru saja';
    if (d.inMinutes < 60) return '${d.inMinutes} mnt lalu';
    if (d.inHours < 24) return '${d.inHours} jam lalu';
    return '${d.inDays} hari lalu';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🔔 Notifikasi'),
        actions: [
          if (_items != null && _items!.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _load,
            ),
        ],
      ),
      body: _items == null
          ? const Center(child: CircularProgressIndicator())
          : _items!.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: FamColors.primary.withValues(alpha: 0.08),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.notifications_none_rounded, size: 64, color: FamColors.muted.withValues(alpha: 0.8)),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Semua Bersih!',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Belum ada permintaan pertemanan atau permintaan lokasi baru.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: FamColors.muted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: _items!.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) {
                      final n = _items![i];
                      final isFriendReq = n.type == 'friend_request';

                      return Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(FamRadius.card),
                          boxShadow: FamColors.softShadow(opacity: 0.1),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                InitialAvatar(name: n.name, radius: 24),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        n.name,
                                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        isFriendReq
                                            ? 'Ingin berteman denganmu'
                                            : 'Minta kamu menyalakan sharing lokasi',
                                        style: TextStyle(
                                          color: isFriendReq ? FamColors.primary : FamColors.secondary,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _timeAgo(n.createdAt),
                                        style: const TextStyle(color: FamColors.muted, fontSize: 11.5),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _busy ? null : () => _act(n, isFriendReq ? 'reject' : 'dismiss'),
                                    icon: const Icon(Icons.close_rounded, size: 18),
                                    label: Text(isFriendReq ? 'Tolak' : 'Abaikan'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: FamColors.muted,
                                      side: BorderSide(color: FamColors.muted.withValues(alpha: 0.3)),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FamRadius.pill)),
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  flex: 2,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: FamColors.primaryGradient,
                                      borderRadius: BorderRadius.circular(FamRadius.pill),
                                      boxShadow: FamColors.softShadow(opacity: 0.2),
                                    ),
                                    child: FilledButton.icon(
                                      onPressed: _busy ? null : () => _act(n, 'accept'),
                                      icon: Icon(
                                        isFriendReq ? Icons.check_rounded : Icons.location_on_rounded,
                                        size: 18,
                                        color: Colors.white,
                                      ),
                                      label: Text(
                                        isFriendReq ? 'Terima Teman' : 'Nyalakan Sharing',
                                        style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
                                      ),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: Colors.transparent,
                                        shadowColor: Colors.transparent,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FamRadius.pill)),
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                      ),
                                    ),
                                  ),
                                ),
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
}

