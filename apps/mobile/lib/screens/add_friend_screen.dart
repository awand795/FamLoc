import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../api_client.dart';
import '../theme.dart';

class AddFriendScreen extends StatefulWidget {
  const AddFriendScreen({super.key});

  @override
  State<AddFriendScreen> createState() => _AddFriendScreenState();
}

class _AddFriendScreenState extends State<AddFriendScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 3, vsync: this);
  User? _me;
  final _codeCtrl = TextEditingController();
  String? _msg;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    ApiClient.me().then((u) {
      if (mounted) setState(() => _me = u);
    }).catchError((_) {});
  }

  Future<void> _addByCode(String code) async {
    if (code.trim().isEmpty) return;
    setState(() { _busy = true; _msg = null; });
    try {
      await ApiClient.sendFriendRequest(inviteCode: code.trim().toUpperCase());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Permintaan pertemanan terkirim ✅')));
      Navigator.pop(context);
    } catch (e) {
      setState(() => _msg = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('➕ Tambah Teman')),
      body: Column(
        children: [
          TabBar(
            controller: _tab,
            labelColor: FamColors.primary,
            unselectedLabelColor: FamColors.muted,
            indicatorColor: FamColors.primary,
            tabs: const [
              Tab(text: 'QR Saya'),
              Tab(text: 'Scan QR'),
              Tab(text: 'Kode'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                // --- Tab 1: QR saya ---
                Center(
                  child: _me == null
                      ? const CircularProgressIndicator()
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(FamRadius.card),
                                boxShadow: FamColors.softShadow(opacity: 0.12),
                              ),
                              child: QrImageView(
                                data: _me!.inviteCode,
                                size: 220,
                                eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: FamColors.textDark),
                                dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: FamColors.textDark),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text('Minta keluargamu scan QR ini',
                                style: TextStyle(color: FamColors.muted)),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: FamColors.primary.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(FamRadius.pill),
                              ),
                              child: Text(_me!.inviteCode,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800, letterSpacing: 3, fontSize: 18)),
                            ),
                          ],
                        ),
                ),
                // --- Tab 2: Scan QR ---
                MobileScanner(
                  onDetect: (capture) {
                    final raw = capture.barcodes.firstOrNull?.rawValue;
                    if (raw != null && !_busy) {
                      _addByCode(raw.trim());
                    }
                  },
                ),
                // --- Tab 3: kode manual / link undangan ---
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _codeCtrl,
                        textCapitalization: TextCapitalization.characters,
                        decoration: InputDecoration(
                          labelText: 'Kode undangan',
                          hintText: 'Contoh: 36SEQ58S',
                          prefixIcon: const Icon(Icons.vpn_key_rounded),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      GradientButton(
                        label: 'Kirim Permintaan',
                        loading: _busy,
                        onPressed: () => _addByCode(_codeCtrl.text),
                      ),
                      if (_msg != null) ...[
                        const SizedBox(height: 12),
                        Text(_msg!, style: const TextStyle(color: FamColors.danger)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }
}
