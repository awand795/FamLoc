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
    } catch (e) {
      if (!mounted) return;
      setState(() => _items = []);
    }
  }

  Future<void> _act(FamNotification n, String action) async {
    try {
      if (n.type == 'friend_request') {
        await ApiClient.respondFriendRequest(n.refId, action);
      } else if (n.type == 'location_request') {
        await ApiClient.respondLocationRequest(n.refId, action);
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('🔔 Notifikasi')),
      body: _items == null
          ? const Center(child: CircularProgressIndicator())
          : _items!.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.notifications_none_rounded, size: 72, color: FamColors.muted.withValues(alpha: 0.4)),
                      const SizedBox(height: 8),
                      const Text('Belum ada notifikasi',
                          style: TextStyle(color: FamColors.muted)),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: _items!.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final n = _items![i];
                    final isFriendReq = n.type == 'friend_request';
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(FamRadius.card),
                        boxShadow: FamColors.softShadow(opacity: 0.08),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              InitialAvatar(name: n.name, radius: 22),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  isFriendReq
                                      ? '${n.name} ingin berteman denganmu'
                                      : '${n.name} minta melihat lokasimu',
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _act(n,
                                    isFriendReq ? 'reject' : 'dismiss'),
                                icon: const Icon(Icons.close_rounded, size: 18),
                                label: Text(isFriendReq ? 'Tolak' : 'Abaikan'),
                                style: OutlinedButton.styleFrom(
                                    foregroundColor: FamColors.muted),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 2,
                              child: FilledButton.icon(
                                onPressed: () => _act(n,
                                    isFriendReq ? 'accept' : 'accept'),
                                icon: Icon(isFriendReq
                                    ? Icons.check_rounded
                                    : Icons.location_on_rounded, size: 18),
                                label: Text(isFriendReq
                                    ? 'Terima'
                                    : 'Nyalakan Sharing'),
                                style: FilledButton.styleFrom(
                                    backgroundColor: FamColors.primary),
                              ),
                            ),
                          ]),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
