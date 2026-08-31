import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../supabase_service.dart';
import '../background_task.dart';
import '../theme.dart';
import 'profile_screen.dart';

/// Atribusi wajib tile OpenStreetMap — JANGAN dihapus.
const String kOsmAttribution = '© OpenStreetMap contributors';

class MapHomeScreen extends StatefulWidget {
  const MapHomeScreen({super.key});

  @override
  State<MapHomeScreen> createState() => _MapHomeScreenState();
}

class _MapHomeScreenState extends State<MapHomeScreen>
    with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();
  StreamSubscription? _realtimeSubscription;
  AnimationController? _moveAnim;
  UserProfile? _me;
  List<FamilyMemberLocation> _family = [];
  LatLng? _myPosition;
  bool _busy = false;
  Timer? _pushTimer;

  static const jakarta = LatLng(-6.2088, 106.8456);
  final LatLng _center = jakarta;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _refreshProfile();
    await _focusMe();
    await _refreshLocations();
    await _startSharingIfOn();

    // Dengarkan perubahan realtime dari Supabase PostgreSQL Realtime
    _realtimeSubscription = SupabaseService.streamLocations().listen((_) {
      _refreshLocations();
    });

    // Interval stream lokasi sendiri tiap 5 detik
    _pushTimer = Timer.periodic(const Duration(seconds: 5), (_) => _pushMyLocation());
  }

  Future<void> _refreshProfile() async {
    try {
      final me = await SupabaseService.getMyProfile();
      if (!mounted) return;
      setState(() => _me = me);
    } catch (_) {}
  }

  Future<void> _startSharingIfOn() async {
    try {
      if (_me?.sharingOn == true) await _pushMyLocation();
    } catch (_) {}
  }

  Future<void> _refreshLocations() async {
    try {
      final list = await SupabaseService.getFamilyLocations();
      if (!mounted) return;
      setState(() => _family = list);
    } catch (_) {}
  }

  /// Kirim posisi ke Supabase HANYA saat sharing ON
  Future<void> _pushMyLocation() async {
    if (_me?.sharingOn != true || _busy) return;
    _busy = true;
    try {
      const settings = LocationSettings(accuracy: LocationAccuracy.high);
      final pos = await Geolocator.getCurrentPosition(locationSettings: settings);
      final meLatLng = LatLng(pos.latitude, pos.longitude);

      int? batteryLevel;
      try {
        final level = await Battery().batteryLevel;
        batteryLevel = level >= 0 ? level : null;
      } catch (_) {}

      await SupabaseService.pushLocation(
        lat: pos.latitude,
        lng: pos.longitude,
        accuracy: pos.accuracy,
        heading: pos.heading >= 0 ? pos.heading : null,
        battery: batteryLevel,
        isMocked: pos.isMocked,
      );

      if (mounted) setState(() => _myPosition = meLatLng);
    } catch (_) {}
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
      await SupabaseService.updateSharing(on);
      await _refreshProfile();
      _showSnack(on ? '📍 Lokasimu dibagikan ke keluarga' : 'Berbagi lokasi dimatikan');
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

  void _focusMember(FamilyMemberLocation f) {
    _animateTo(LatLng(f.lat, f.lng));
  }

  Future<void> _focusMe() async {
    if (!await _ensurePermission()) return;
    try {
      final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      if (!mounted) return;
      final meLatLng = LatLng(pos.latitude, pos.longitude);
      setState(() => _myPosition = meLatLng);
      _animateTo(meLatLng);
    } catch (_) {}
  }

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
          IconButton(
            icon: const Icon(Icons.settings_rounded),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
              _refreshProfile();
            },
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
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'eu.awanda.famloc',
              ),
              MarkerLayer(markers: _buildMarkers()),
            ],
          ),
          const Positioned(
            left: 4, bottom: 2,
            child: Text(kOsmAttribution,
                style: TextStyle(fontSize: 10, color: FamColors.muted)),
          ),
          // Banner Status Berbagi
          if (_me?.sharingOn == true)
            Positioned(
              top: kToolbarHeight + MediaQuery.of(context).padding.top + 8,
              left: 16, right: 16,
              child: GestureDetector(
                onTap: () => _toggleSharing(false),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.90),
                    borderRadius: BorderRadius.circular(FamRadius.pill),
                    boxShadow: FamColors.softShadow(opacity: 0.15),
                  ),
                  child: const Row(
                    children: [
                      PulsingDot(),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '📍 Lokasimu dibagikan secara realtime · ketuk untuk matikan',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
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
          if (_family.isNotEmpty) ...[
            FloatingActionButton.small(
              heroTag: 'focus_family',
              backgroundColor: FamColors.primary,
              foregroundColor: Colors.white,
              onPressed: () => _focusMember(_family.first),
              child: const Icon(Icons.people_alt_rounded),
            ),
            const SizedBox(height: 8),
          ],
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

    // Marker Lokasi Sendiri
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
              child: _me?.avatarUrl != null
                  ? CircleAvatar(
                      radius: 20,
                      backgroundImage: NetworkImage(_me!.avatarUrl!),
                    )
                  : InitialAvatar(name: _me?.name ?? 'Saya', radius: 20),
            ),
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(FamRadius.pill),
              ),
              child: Text(_me?.name ?? 'Saya',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ));
    }

    // Marker Anggota Keluarga (Mama / Pengguna lain)
    for (final f in _family) {
      final isLive = DateTime.now().difference(f.updatedAt).inMinutes <= 15;
      list.add(Marker(
        width: 120,
        height: 80,
        point: LatLng(f.lat, f.lng),
        child: GestureDetector(
          onTap: () => _showFamilySheet(f),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(
                    color: isLive ? FamColors.sharingActive : FamColors.muted,
                    width: 3,
                  ),
                  boxShadow: FamColors.softShadow(opacity: 0.25),
                ),
                child: f.avatarUrl != null
                    ? CircleAvatar(
                        radius: 20,
                        backgroundImage: NetworkImage(f.avatarUrl!),
                      )
                    : InitialAvatar(name: f.name, radius: 20),
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
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ));
    }
    return list;
  }

  void _showFamilySheet(FamilyMemberLocation f) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(FamRadius.sheet)),
      ),
      builder: (_) => _FamilyDetailSheet(
        member: f,
        myPosition: _myPosition,
        onFocus: () => _focusMember(f),
      ),
    );
  }

  @override
  void dispose() {
    _realtimeSubscription?.cancel();
    _pushTimer?.cancel();
    _moveAnim?.dispose();
    _mapController.dispose();
    super.dispose();
  }
}

/// Titik "live" berdenyut
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

class _FamilyDetailSheet extends StatelessWidget {
  final FamilyMemberLocation member;
  final LatLng? myPosition;
  final VoidCallback onFocus;

  const _FamilyDetailSheet({
    required this.member,
    required this.myPosition,
    required this.onFocus,
  });

  String _timeAgo(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'baru saja';
    if (d.inMinutes < 60) return '${d.inMinutes} mnt lalu';
    if (d.inHours < 24) return '${d.inHours} jam lalu';
    return '${d.inDays} hari lalu';
  }

  double? _calculateDistance() {
    if (myPosition == null) return null;
    return const Distance().as(
      LengthUnit.Meter,
      myPosition!,
      LatLng(member.lat, member.lng),
    );
  }

  String _fmtDist(double m) =>
      m < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(1)} km';

  @override
  Widget build(BuildContext context) {
    final isLive = DateTime.now().difference(member.updatedAt).inMinutes <= 15;
    final dist = _calculateDistance();

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
              AvatarWithRing(name: member.name, isLive: isLive, radius: 28),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member.name,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Update ${_timeAgo(member.updatedAt)}',
                      style: const TextStyle(fontSize: 12, color: FamColors.muted),
                    ),
                  ],
                ),
              ),
              BatteryIndicator(level: member.battery),
            ],
          ),
          const SizedBox(height: 16),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatusChip(
                label: isLive
                    ? ((member.heading ?? -1) >= 0 ? 'Bergerak' : 'Diam')
                    : 'Offline',
                icon: isLive ? Icons.directions_car_rounded : Icons.pause_circle_rounded,
                color: isLive ? FamColors.primary : FamColors.muted,
              ),
              if (dist != null)
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
                      Text('${_fmtDist(dist)} dari kamu',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: FamColors.textDark)),
                    ],
                  ),
                ),
              if (member.isMocked)
                StatusChip(
                  label: '⚠️ posisi diragukan',
                  icon: Icons.warning_amber_rounded,
                  color: FamColors.secondary,
                ),
            ],
          ),
          const SizedBox(height: 20),

          GradientButton(
            label: '📍 Fokus ke ${member.name}',
            onPressed: () {
              Navigator.pop(context);
              onFocus();
            },
          ),
        ],
      ),
    );
  }
}