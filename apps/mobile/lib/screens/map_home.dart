import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../api_client.dart';
import '../background_task.dart';
import '../realtime_service.dart';
import '../theme.dart';
import 'add_friend_screen.dart';
import 'family_screen.dart';
import 'notifications_screen.dart';
import 'profile_screen.dart';

/// Atribusi wajib tile OpenStreetMap — JANGAN dihapus (skill famloc-stack).
const String kOsmAttribution = '© OpenStreetMap contributors';

class MapHomeScreen extends StatefulWidget {
  const MapHomeScreen({super.key});

  @override
  State<MapHomeScreen> createState() => _MapHomeScreenState();
}

class _MapHomeScreenState extends State<MapHomeScreen>
    with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();
  final RealtimeService _realtime = RealtimeService();
  StreamSubscription<FriendLocation>? _wsSubscription;
  AnimationController? _moveAnim;
  User? _me;
  List<FriendLocation> _friends = [];
  int _unread = 0;
  LatLng? _myPosition; // posisi terakhir sendiri untuk marker
  int _totalFriends = 0; // jumlah teman total (bukan hanya yang sharing)
  bool _busy = false;
  Timer? _pollTimer;
  Timer? _pushTimer;

  // initialCenter hanya dibaca sekali oleh flutter_map v7; perpindahan kamera
  // setelahnya lewat _mapController (lihat _animateTo).
  static const jakarta = LatLng(-6.2088, 106.8456);
  final LatLng _center = jakarta;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      await _refreshAll();
      await _startSharingIfOn();
    } catch (e) {
      _showSnack('Gagal memuat data: $e');
    }

    // Inisialisasi WebSocket realtime stream
    _realtime.connect();
    _wsSubscription = _realtime.onFriendLocation.listen((updatedFriend) {
      if (!mounted) return;
      setState(() {
        final index = _friends.indexWhere((f) => f.id == updatedFriend.id);
        if (index != -1) {
          _friends[index] = updatedFriend;
        } else {
          _friends.add(updatedFriend);
        }
      });
    });

    // Backup polling untuk sync notifikasi & daftar teman per 30 detik
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) => _refreshLocations());
    // Interval stream lokasi sendiri saat bergerak
    _pushTimer = Timer.periodic(const Duration(seconds: 5), (_) => _pushMyLocation());
  }

  Future<void> _startSharingIfOn() async {
    try {
      if (_me?.sharingOn == true) await _pushMyLocation();
    } catch (_) {}
  }

  Future<void> _refreshAll() async {
    try {
      final me = await ApiClient.me();
      final notif = await ApiClient.notifications();
      if (!mounted) return;
      setState(() { _me = me; _unread = notif.length; });
      await _refreshLocations();
    } catch (e) {
      _showSnack(e.toString());
    }
  }

  Future<void> _refreshLocations() async {
    try {
      final friends = await ApiClient.friendLocations();
      if (!mounted) return;
      setState(() => _friends = friends);
    } catch (_) {/* offline: biarkan data terakhir */}
    // Ambil jumlah total teman untuk banner & unread notifikasi
    try {
      final allFriends = await ApiClient.friends();
      final notifs = await ApiClient.notifications();
      if (!mounted) return;
      setState(() {
        _totalFriends = allFriends.length;
        _unread = notifs.length;
      });
    } catch (_) {}
  }

  /// Kirim posisi ke server HANYA saat sharing ON.
  Future<void> _pushMyLocation() async {
    if (_me?.sharingOn != true || _busy) return;
    _busy = true;
    try {
      LocationSettings settings = const LocationSettings(accuracy: LocationAccuracy.high);
      final pos = await Geolocator.getCurrentPosition(locationSettings: settings);
      final meLatLng = LatLng(pos.latitude, pos.longitude);
      // Ambil level baterai
      int? batteryLevel;
      try {
        final level = await Battery().batteryLevel;
        batteryLevel = level >= 0 ? level : null;
      } catch (_) {}
      // Kirim via WebSocket realtime stream jika terhubung
      if (_realtime.isConnected) {
        _realtime.sendLocation(
          lat: pos.latitude,
          lng: pos.longitude,
          accuracy: pos.accuracy,
          heading: pos.heading >= 0 ? pos.heading : null,
          battery: batteryLevel,
          isMocked: pos.isMocked,
        );
      } else {
        // Fallback REST API jika WS belum terhubung
        await ApiClient.pushLocation(
          lat: pos.latitude,
          lng: pos.longitude,
          accuracy: pos.accuracy,
          heading: pos.heading >= 0 ? pos.heading : null,
          battery: batteryLevel,
          isMocked: pos.isMocked,
        );
      }
      if (mounted) setState(() => _myPosition = meLatLng);
    } catch (_) {} // izin lokasi ditangani lewat _ensurePermission
    finally { _busy = false; }
  }

  Future<bool> _ensurePermission() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    return perm == LocationPermission.always || perm == LocationPermission.whileInUse;
  }

  Future<void> _toggleSharing(bool on) async {
    if (on && !await _ensurePermission()) {
      _showSnack('Izin lokasi diperlukan untuk membagikan posisi');
      return;
    }
    try {
      final me2 = User(
        id: _me!.id, email: _me!.email, name: _me!.name,
        inviteCode: _me!.inviteCode, avatarVersion: _me!.avatarVersion,
        sharingOn: on, locationPrecision: _me!.locationPrecision,
      );
      await ApiClient.setSharing(on);
      if (!mounted) return;
      setState(() => _me = me2);
      _showSnack(on ? '📍 Lokasimu dibagikan' : 'Sharing dimatikan');
      if (on) {
        await _pushMyLocation();
        await startBackgroundSharing();
      } else {
        await stopBackgroundSharing();
      }
    } catch (e) {
      _showSnack(e.toString());
    }
  }

  void _focusFriend(FriendLocation f) {
    _animateTo(LatLng(f.lat, f.lng));
  }

  void _focusMe() async {
    if (!await _ensurePermission()) return;
    try {
      final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      if (!mounted) return;
      final meLatLng = LatLng(pos.latitude, pos.longitude);
      setState(() => _myPosition = meLatLng);
      _animateTo(meLatLng);
    } catch (_) {
      _showSnack('Gagal mengambil posisimu');
    }
  }

  /// Animasi halus memindahkan kamera peta ke [target].
  /// flutter_map v7 hanya membaca `initialCenter` sekali, jadi perpindahan
  /// HARUS lewat MapController.move() (perbaikan bug FAB "my location").
  void _animateTo(LatLng target, {double zoom = 15}) {
    final from = _mapController.camera.center;
    final fromZoom = _mapController.camera.zoom;
    _moveAnim?.dispose();
    final ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _moveAnim = ctrl;
    ctrl.addListener(() {
      final t = Curves.easeInOut.transform(ctrl.value);
      _mapController.move(
        LatLng(
          from.latitude + (target.latitude - from.latitude) * t,
          from.longitude + (target.longitude - from.longitude) * t,
        ),
        fromZoom + (zoom - fromZoom) * t,
      );
    });
    ctrl.forward();
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text('Halo, ${_me?.name ?? ''} 👋'),
        actions: [
          Stack(alignment: Alignment.center, children: [
            IconButton(
              icon: const Icon(Icons.notifications_rounded),
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const NotificationsScreen()));
                _refreshAll();
              },
            ),
            if (_unread > 0)
              Positioned(
                top: 10, right: 8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration:
                      const BoxDecoration(color: FamColors.danger, shape: BoxShape.circle),
                  child: Text('$_unread',
                      style: const TextStyle(fontSize: 10, color: Colors.white)),
                ),
              ),
          ]),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'family') {
                await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const FamilyScreen()));
                _refreshAll();
              } else if (v == 'add') {
                await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AddFriendScreen()));
              } else if (v == 'profile') {
                await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ProfileScreen()));
                _refreshAll();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'family', child: Text('👨‍👩‍👧 Keluargaku')),
              PopupMenuItem(value: 'add', child: Text('➕ Tambah Teman')),
              PopupMenuItem(value: 'profile', child: Text('⚙️ Profil & Privasi')),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: 14,
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
              onPositionChanged: (pos, _) {},
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'eu.awanda.famloc',
              ),
              MarkerLayer(markers: _buildMarkers()),
            ],
          ),
          // Atribusi wajib tile OSM (skill famloc-stack)
          const Positioned(
            left: 4, bottom: 2,
            child: Text('© OpenStreetMap contributors',
                style: TextStyle(fontSize: 10, color: FamColors.muted)),
          ),
          // Banner glassmorphism saat sharing ON
          if (_me?.sharingOn == true)
            Positioned(
              top: kToolbarHeight + MediaQuery.of(context).padding.top + 8,
              left: 16, right: 16,
              child: GestureDetector(
                onTap: () => _toggleSharing(false),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(FamRadius.pill),
                    boxShadow: FamColors.softShadow(opacity: 0.15),
                  ),
                  child: Row(
                    children: [
                      const PulsingDot(),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '📍 Lokasimu dibagikan ke $_totalFriends orang · ketuk untuk matikan',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            Positioned(
              top: kToolbarHeight + MediaQuery.of(context).padding.top + 8,
              left: 16, right: 16,
              child: GestureDetector(
                onTap: () => _toggleSharing(true),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    gradient: FamColors.primaryGradient,
                    borderRadius: BorderRadius.circular(FamRadius.pill),
                    boxShadow: FamColors.softShadow(),
                  ),
                  child: const Center(
                    child: Text('Nyalakan berbagi lokasi',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'focus_me',
            backgroundColor: Colors.white,
            foregroundColor: FamColors.primary,
            onPressed: _focusMe,
            child: const Icon(Icons.my_location_rounded),
          ),
        ],
      ),
    );
  }

  List<Marker> _buildMarkers() {
    final list = <Marker>[];

    // Marker lokasi sendiri (saat posisi diketahui)
    if (_myPosition != null) {
      list.add(Marker(
        width: 120, height: 80,
        point: _myPosition!,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(color: FamColors.primary, width: 3),
                boxShadow: FamColors.softShadow(opacity: 0.25),
              ),
              child: InitialAvatar(name: _me?.name ?? '?', radius: 22),
            ),
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(FamRadius.pill),
              ),
              child: Text(_me?.name ?? '',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ));
    }

    // Marker lokasi teman
    for (final f in _friends) {
      final stale = DateTime.now().difference(f.updatedAt).inMinutes > 15;
      list.add(Marker(
        width: 120,
        height: 80,
        point: LatLng(f.lat, f.lng),
        child: GestureDetector(
          onTap: () => _showFriendSheet(f),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(
                    color: stale ? FamColors.muted : FamColors.primaryLight,
                    width: 3,
                  ),
                  boxShadow: FamColors.softShadow(opacity: 0.25),
                ),
                child: InitialAvatar(name: f.name, radius: 22),
              ),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(FamRadius.pill),
                ),
                child: Text(f.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ));
    }
    return list;
  }

  void _showFriendSheet(FriendLocation f) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(FamRadius.sheet)),
      ),
      builder: (_) => _FriendDetailSheet(
        friend: f,
        onFocus: () => _focusFriend(f),
      ),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _pushTimer?.cancel();
    _wsSubscription?.cancel();
    _realtime.disconnect();
    _moveAnim?.dispose();
    _mapController.dispose();
    super.dispose();
  }
}

/// Titik "live" yang berdenyut — indikator sharing aktif.
class PulsingDot extends StatefulWidget {
  const PulsingDot({super.key});
  @override
  State<PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<PulsingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
        ..repeat(reverse: true);

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.4, end: 1.0).animate(_c),
      child: ScaleTransition(
        scale: Tween(begin: 0.85, end: 1.15).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
        child: Container(
          width: 12, height: 12,
          decoration: const BoxDecoration(color: FamColors.sharingActive, shape: BoxShape.circle),
        ),
      ),
    );
  }

  @override
  void dispose() { _c.dispose(); super.dispose(); }
}

class _FriendDetailSheet extends StatefulWidget {
  final FriendLocation friend;
  final VoidCallback onFocus;

  const _FriendDetailSheet({required this.friend, required this.onFocus});

  @override
  State<_FriendDetailSheet> createState() => _FriendDetailSheetState();
}

class _FriendDetailSheetState extends State<_FriendDetailSheet> {
  String? _address;
  bool _loadingAddress = true;

  @override
  void initState() {
    super.initState();
    _loadAddress();
  }

  Future<void> _loadAddress() async {
    try {
      final addr = await ApiClient.reverseGeocode(widget.friend.lat, widget.friend.lng);
      if (mounted) {
        setState(() {
          _address = addr;
          _loadingAddress = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingAddress = false);
    }
  }

  String _timeAgo(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'baru saja';
    if (d.inMinutes < 60) return '${d.inMinutes} mnt lalu';
    if (d.inHours < 24) return '${d.inHours} jam lalu';
    return '${d.inDays} hari lalu';
  }

  String _fmtDist(double m) =>
      m < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(1)} km';

  @override
  Widget build(BuildContext context) {
    final f = widget.friend;
    final isStale = DateTime.now().difference(f.updatedAt).inMinutes > 15;

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).padding.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: FamColors.muted.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              AvatarWithRing(name: f.name, isLive: !isStale, radius: 28),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      f.name,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Update ${_timeAgo(f.updatedAt)}',
                      style: const TextStyle(fontSize: 12, color: FamColors.muted),
                    ),
                  ],
                ),
              ),
              BatteryIndicator(level: f.battery),
            ],
          ),
          const SizedBox(height: 16),

          // Alamat lokasi kasar
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: FamColors.primary.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: FamColors.primary.withValues(alpha: 0.1)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.place_rounded, size: 20, color: FamColors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: _loadingAddress
                      ? const Text('Memuat nama lokasi...',
                          style: TextStyle(fontSize: 12.5, color: FamColors.muted, fontStyle: FontStyle.italic))
                      : Text(
                          _address ?? 'Lokasi: ${f.lat.toStringAsFixed(4)}, ${f.lng.toStringAsFixed(4)}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.3),
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatusChip(
                label: !isStale
                    ? ((f.heading ?? -1) >= 0 ? 'Bergerak' : 'Diam')
                    : 'Offline',
                icon: !isStale ? Icons.directions_car_rounded : Icons.pause_circle_rounded,
                color: !isStale ? FamColors.primary : FamColors.muted,
              ),
              if (f.distanceM != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(FamRadius.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.straighten_rounded, size: 14, color: FamColors.muted),
                      const SizedBox(width: 4),
                      Text('${_fmtDist(f.distanceM!)} dari kamu',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: FamColors.textDark)),
                    ],
                  ),
                ),
              if (f.isMocked)
                StatusChip(
                  label: '⚠️ posisi diragukan',
                  icon: Icons.warning_amber_rounded,
                  color: FamColors.secondary,
                ),
              if (f.precisionFuzzed)
                StatusChip(
                  label: 'lokasi kasar ±500m',
                  icon: Icons.blur_on_rounded,
                  color: FamColors.muted,
                ),
            ],
          ),
          const SizedBox(height: 20),

          GradientButton(
            label: '📍 Fokus ke ${f.name}',
            onPressed: () {
              Navigator.pop(context);
              widget.onFocus();
            },
          ),
        ],
      ),
    );
  }
}