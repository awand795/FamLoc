import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../api_client.dart';
import '../theme.dart';

class AddFriendScreen extends StatefulWidget {
  final int initialTabIndex;
  const AddFriendScreen({super.key, this.initialTabIndex = 0});

  @override
  State<AddFriendScreen> createState() => _AddFriendScreenState();
}

class _AddFriendScreenState extends State<AddFriendScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(
    length: 4,
    vsync: this,
    initialIndex: widget.initialTabIndex.clamp(0, 3),
  );
  late final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  User? _me;
  final _codeCtrl = TextEditingController();
  String? _msg;
  bool _busy = false;
  bool _torchOn = false;

  // Data Permintaan Pertemanan
  List<FriendRequestItem> _incoming = [];
  List<FriendRequestItem> _outgoing = [];
  bool _loadingRequests = true;
  int _activeRequestSegment = 0; // 0 = Masuk, 1 = Keluar

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadFriendRequests();

    _tab.addListener(() {
      if (mounted) {
        setState(() {});
        if (_tab.index == 1) {
          _scannerController.start();
        } else {
          _scannerController.stop();
        }
      }
    });
  }

  Future<void> _loadProfile() async {
    try {
      final u = await ApiClient.me();
      if (mounted) setState(() => _me = u);
    } catch (_) {}
  }

  Future<void> _loadFriendRequests() async {
    try {
      final res = await ApiClient.friendRequests();
      if (!mounted) return;
      setState(() {
        _incoming = res.incoming;
        _outgoing = res.outgoing;
        _loadingRequests = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingRequests = false);
    }
  }

  String _extractInviteCode(String input) {
    input = input.trim();
    if (input.isEmpty) return '';
    try {
      final uri = Uri.tryParse(input);
      if (uri != null && uri.queryParameters.containsKey('code')) {
        return uri.queryParameters['code']!.trim().toUpperCase();
      }
      if (uri != null && uri.pathSegments.isNotEmpty && uri.pathSegments.last.length >= 6) {
        final last = uri.pathSegments.last;
        if (RegExp(r'^[A-Za-z0-9]{6,12}$').hasMatch(last)) {
          return last.toUpperCase();
        }
      }
    } catch (_) {}
    final match = RegExp(r'[A-Za-z0-9]{6,10}').firstMatch(input);
    if (match != null) return match.group(0)!.toUpperCase();
    return input.toUpperCase();
  }

  Future<void> _addByCode(String rawCode) async {
    final code = _extractInviteCode(rawCode);
    if (code.isEmpty || _busy) return;
    setState(() { _busy = true; _msg = null; });
    try {
      await ApiClient.sendFriendRequest(inviteCode: code);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('Permintaan pertemanan berhasil dikirim! 🚀'),
      ));
      _codeCtrl.clear();
      _loadFriendRequests();
      _tab.animateTo(3); // Pindah ke tab Permintaan
      setState(() => _activeRequestSegment = 1); // Buka segment Terkirim
    } catch (e) {
      if (mounted) setState(() => _msg = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _respondRequest(FriendRequestItem req, String action) async {
    try {
      await ApiClient.respondFriendRequest(req.id, action);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(action == 'accept'
            ? 'Sekarang kamu dan ${req.name} sudah berteman! 🎉'
            : 'Permintaan pertemanan ditolak'),
      ));
      _loadFriendRequests();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(e.toString()),
      ));
    }
  }

  Future<void> _cancelOutgoingRequest(FriendRequestItem req) async {
    try {
      await ApiClient.cancelFriendRequest(req.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('Permintaan pertemanan dibatalkan'),
      ));
      _loadFriendRequests();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(e.toString()),
      ));
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
    final pendingCount = _incoming.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('➕ Tambah Teman'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(FamRadius.pill),
              boxShadow: FamColors.softShadow(opacity: 0.06),
            ),
            child: TabBar(
              controller: _tab,
              labelColor: FamColors.primary,
              unselectedLabelColor: FamColors.muted,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                color: FamColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(FamRadius.pill),
              ),
              dividerColor: Colors.transparent,
              labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              tabs: [
                const Tab(text: 'QR Saya'),
                const Tab(text: 'Scan QR'),
                const Tab(text: 'Kode'),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Permintaan'),
                      if (pendingCount > 0) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: const BoxDecoration(
                            color: FamColors.danger,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '$pendingCount',
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          // ==================== TAB 1: QR SAYA ====================
          _buildMyQrTab(),

          // ==================== TAB 2: SCAN QR ====================
          _buildScanQrTab(),

          // ==================== TAB 3: INPUT KODE ====================
          _buildCodeInputTab(),

          // ==================== TAB 4: PERMINTAAN ====================
          _buildRequestsTab(),
        ],
      ),
    );
  }

  Widget _buildMyQrTab() {
    if (_me == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(FamRadius.card),
              boxShadow: FamColors.softShadow(opacity: 0.15),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    InitialAvatar(name: _me!.name, radius: 20),
                    const SizedBox(width: 10),
                    Text(
                      _me!.name,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                QrImageView(
                  data: _me!.inviteCode,
                  size: 210,
                  eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: FamColors.textDark),
                  dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: FamColors.textDark),
                ),
                const SizedBox(height: 16),
                Text(
                  'Arahkan kamera teman ke QR Code ini',
                  style: TextStyle(color: FamColors.muted, fontSize: 13),
                ),
                const SizedBox(height: 14),
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: _me!.inviteCode));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      behavior: SnackBarBehavior.floating,
                      content: Text('Kode undangan disalin ke clipboard 📋'),
                    ));
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: FamColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(FamRadius.pill),
                      border: Border.all(color: FamColors.primary.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _me!.inviteCode,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 4,
                            fontSize: 20,
                            color: FamColors.primary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.copy_rounded, size: 18, color: FamColors.primary),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Atau bagikan kode undanganmu langsung ke grup keluarga.',
            textAlign: TextAlign.center,
            style: TextStyle(color: FamColors.muted, fontSize: 12.5),
          ),
        ],
      ),
    );
  }

  Widget _buildScanQrTab() {
    return Stack(
      children: [
        MobileScanner(
          controller: _scannerController,
          errorBuilder: (context, error, child) {
            return Center(
              child: Container(
                margin: const EdgeInsets.all(24),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(FamRadius.card),
                  boxShadow: FamColors.softShadow(),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.videocam_off_rounded, size: 48, color: FamColors.danger),
                    const SizedBox(height: 12),
                    const Text('Izin Kamera Diperlukan',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Text(
                      'Izinkan akses kamera di pengaturan untuk memindai QR code teman.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: FamColors.muted, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    GradientButton(
                      label: 'Coba Lagi',
                      onPressed: () => _scannerController.start(),
                    ),
                  ],
                ),
              ),
            );
          },
          onDetect: (capture) {
            final raw = capture.barcodes.firstOrNull?.rawValue;
            if (raw != null && !_busy && raw.isNotEmpty) {
              _addByCode(raw);
            }
          },
        ),

        // Frame Viewfinder animasi Dribbble
        const ScannerViewfinder(size: 260),

        // Text panduan di atas
        Positioned(
          top: 32,
          left: 20,
          right: 20,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(FamRadius.pill),
            ),
            child: const Text(
              'Arahkan kamera ke QR code temanmu',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ),

        // Action controls (Flash & Flip camera)
        Positioned(
          bottom: 36,
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FloatingActionButton.small(
                heroTag: 'scanner_torch',
                backgroundColor: _torchOn ? FamColors.secondary : Colors.white,
                foregroundColor: _torchOn ? Colors.white : FamColors.textDark,
                onPressed: () async {
                  await _scannerController.toggleTorch();
                  setState(() => _torchOn = !_torchOn);
                },
                child: Icon(_torchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded),
              ),
              const SizedBox(width: 20),
              FloatingActionButton.small(
                heroTag: 'scanner_flip',
                backgroundColor: Colors.white,
                foregroundColor: FamColors.textDark,
                onPressed: () => _scannerController.switchCamera(),
                child: const Icon(Icons.flip_camera_ios_rounded),
              ),
            ],
          ),
        ),

        if (_busy)
          Container(
            color: Colors.black.withValues(alpha: 0.4),
            child: const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          ),
      ],
    );
  }

  Widget _buildCodeInputTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(FamRadius.card),
              boxShadow: FamColors.softShadow(opacity: 0.12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Masukkan Kode Teman',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  'Ketik 8 karakter kode undangan unik dari temanmu.',
                  style: TextStyle(color: FamColors.muted, fontSize: 13),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _codeCtrl,
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 2, fontSize: 18),
                  decoration: InputDecoration(
                    labelText: 'Kode Undangan',
                    hintText: 'Contoh: 36SEQ58S',
                    prefixIcon: const Icon(Icons.vpn_key_rounded, color: FamColors.primary),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.paste_rounded),
                      onPressed: () async {
                        final data = await Clipboard.getData('text/plain');
                        if (data?.text != null) {
                          _codeCtrl.text = data!.text!.trim().toUpperCase();
                        }
                      },
                    ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
                  ),
                ),
                const SizedBox(height: 20),
                GradientButton(
                  label: 'Kirim Permintaan',
                  loading: _busy,
                  onPressed: () => _addByCode(_codeCtrl.text),
                ),
                if (_msg != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: FamColors.danger.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded, color: FamColors.danger, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_msg!, style: const TextStyle(color: FamColors.danger, fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestsTab() {
    return Column(
      children: [
        const SizedBox(height: 12),
        // Segment selector (Masuk vs Terkirim)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(FamRadius.pill),
              boxShadow: FamColors.softShadow(opacity: 0.08),
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _activeRequestSegment = 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        gradient: _activeRequestSegment == 0 ? FamColors.primaryGradient : null,
                        borderRadius: BorderRadius.circular(FamRadius.pill),
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Masuk',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: _activeRequestSegment == 0 ? Colors.white : FamColors.muted,
                            ),
                          ),
                          if (_incoming.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _activeRequestSegment == 0 ? Colors.white : FamColors.danger,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '${_incoming.length}',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: _activeRequestSegment == 0 ? FamColors.primary : Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _activeRequestSegment = 1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        gradient: _activeRequestSegment == 1 ? FamColors.primaryGradient : null,
                        borderRadius: BorderRadius.circular(FamRadius.pill),
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Terkirim',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: _activeRequestSegment == 1 ? Colors.white : FamColors.muted,
                            ),
                          ),
                          if (_outgoing.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _activeRequestSegment == 1 ? Colors.white : FamColors.muted,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '${_outgoing.length}',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: _activeRequestSegment == 1 ? FamColors.primary : Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        Expanded(
          child: _loadingRequests
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _loadFriendRequests,
                  child: _activeRequestSegment == 0
                      ? _buildIncomingList()
                      : _buildOutgoingList(),
                ),
        ),
      ],
    );
  }

  Widget _buildIncomingList() {
    if (_incoming.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 80),
          Center(
            child: Column(
              children: [
                Icon(Icons.mark_email_read_rounded, size: 64, color: FamColors.muted),
                SizedBox(height: 12),
                Text('Tidak ada permintaan masuk',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                SizedBox(height: 4),
                Text('Bagikan QR Code atau kode undanganmu ke teman',
                    style: TextStyle(color: FamColors.muted, fontSize: 13)),
              ],
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: _incoming.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        final req = _incoming[i];
        return Container(
          padding: const EdgeInsets.all(16),
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
                  InitialAvatar(name: req.name, radius: 24),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          req.name,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Ingin berteman · ${_timeAgo(req.createdAt)}',
                          style: TextStyle(color: FamColors.muted, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _respondRequest(req, 'reject'),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text('Tolak'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: FamColors.muted,
                        side: BorderSide(color: FamColors.muted.withValues(alpha: 0.3)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FamRadius.pill)),
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
                        onPressed: () => _respondRequest(req, 'accept'),
                        icon: const Icon(Icons.check_rounded, size: 18, color: Colors.white),
                        label: const Text('Terima Teman', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FamRadius.pill)),
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
    );
  }

  Widget _buildOutgoingList() {
    if (_outgoing.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 80),
          Center(
            child: Column(
              children: [
                Icon(Icons.send_rounded, size: 64, color: FamColors.muted),
                SizedBox(height: 12),
                Text('Belum ada permintaan terkirim',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                SizedBox(height: 4),
                Text('Kirim permintaan dengan scan QR atau masukkan kode teman',
                    style: TextStyle(color: FamColors.muted, fontSize: 13)),
              ],
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: _outgoing.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        final req = _outgoing[i];
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(FamRadius.card),
            boxShadow: FamColors.softShadow(opacity: 0.08),
          ),
          child: Row(
            children: [
              InitialAvatar(name: req.name, radius: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      req.name,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Menunggu persetujuan · ${_timeAgo(req.createdAt)}',
                      style: TextStyle(color: FamColors.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              OutlinedButton(
                onPressed: () => _cancelOutgoingRequest(req),
                style: OutlinedButton.styleFrom(
                  foregroundColor: FamColors.danger,
                  side: BorderSide(color: FamColors.danger.withValues(alpha: 0.3)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FamRadius.pill)),
                ),
                child: const Text('Batal'),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _tab.dispose();
    _scannerController.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }
}
