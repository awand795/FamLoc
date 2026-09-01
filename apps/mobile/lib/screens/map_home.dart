import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../supabase_service.dart';
import '../background_task.dart';
import '../theme.dart';
import 'family_screen.dart';
import 'profile_screen.dart';

/// Atribusi peta Google Maps
const String kMapAttribution = '© Google Maps';

enum MapLayerType {
  normal,
  satellite,
  terrain,
}

class MapHomeScreen extends StatefulWidget {
  const MapHomeScreen({super.key});

  @override
  State<MapHomeScreen> createState() => _MapHomeScreenState();
}

class _MapHomeScreenState extends State<MapHomeScreen>
    with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();
  StreamSubscription? _realtimeSubscription;
  StreamSubscription? _sosSubscription;
  StreamSubscription<Position>? _positionStreamSub;
  AnimationController? _moveAnim;
  UserProfile? _me;
  List<FamilyMemberLocation> _family = [];
  List<SosAlert> _activeSosList = [];
  LatLng? _myPosition;
  int? _myBattery;
  double? _mySpeed;
  String? _followingUserId;
  bool _busy = false;
  Timer? _pushTimer;
  MapLayerType _currentLayer = MapLayerType.normal;

  static const jakarta = LatLng(-6.2088, 106.8456);
  final LatLng _center = jakarta;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    // 1. Ambil posisi terakhir dari cache hardware HP (0 milidetik - instan)
    try {
      final lastPos = await Geolocator.getLastKnownPosition();
      if (lastPos != null && mounted) {
        final lastLatLng = LatLng(lastPos.latitude, lastPos.longitude);
        setState(() => _myPosition = lastLatLng);
        _mapController.move(lastLatLng, 15);
      }
    } catch (_) {}

    // 2. Jalankan refresh profile, lokasi, & SOS secara paralel
    _refreshProfile().then((_) => _startSharingIfOn());
    _refreshLocations();
    _refreshSosAlerts();
    _focusMe(); // Update dengan GPS akurat saat satelit siap

    // Dengarkan perubahan realtime lokasi dari Supabase
    _realtimeSubscription = SupabaseService.streamLocations().listen((_) {
      _refreshLocations();
    });

    // Dengarkan sinyal darurat SOS realtime
    _sosSubscription = SupabaseService.streamSosAlerts().listen((_) {
      _refreshSosAlerts();
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

  Future<void> _refreshSosAlerts() async {
    try {
      final alerts = await SupabaseService.getActiveSosAlerts();
      if (!mounted) return;
      setState(() => _activeSosList = alerts);
    } catch (_) {}
  }

  Future<void> _startSharingIfOn() async {
    try {
      if (_me?.sharingOn == true) {
        _startLocationStream();
        await _pushMyLocation();
      }
    } catch (_) {}
  }

  void _startLocationStream() {
    _stopLocationStream();
    if (_me?.sharingOn != true) return;

    late LocationSettings locationSettings;
    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
        forceLocationManager: false,
        intervalDuration: const Duration(seconds: 5),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationText: "FamLoc sedang aktif membagikan lokasi ke keluargamu.",
          notificationTitle: "📍 Berbagi Lokasi Aktif",
          enableWakeLock: true,
        ),
      );
    } else {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      );
    }

    _positionStreamSub = Geolocator.getPositionStream(locationSettings: locationSettings).listen((pos) async {
      final meLatLng = LatLng(pos.latitude, pos.longitude);
      int? batteryLevel;
      try {
        final level = await Battery().batteryLevel;
        batteryLevel = level >= 0 ? level : null;
      } catch (_) {}

      final speedKmh = pos.speed > 0 ? (pos.speed * 3.6) : 0.0;

      await SupabaseService.pushLocation(
        lat: pos.latitude,
        lng: pos.longitude,
        accuracy: pos.accuracy,
        heading: pos.heading >= 0 ? pos.heading : null,
        speed: speedKmh,
        battery: batteryLevel,
        isMocked: pos.isMocked,
      );

      if (mounted) {
        setState(() {
          _myPosition = meLatLng;
          _myBattery = batteryLevel;
          _mySpeed = speedKmh;
        });
      }
    });
  }

  void _stopLocationStream() {
    _positionStreamSub?.cancel();
    _positionStreamSub = null;
  }

  Future<void> _refreshLocations() async {
    try {
      final list = await SupabaseService.getFamilyLocations();
      if (!mounted) return;
      setState(() => _family = list);

      // Jika sedang dalam mode Auto-Follow seseorang, kamera otomatis mengikuti posisi barunya
      if (_followingUserId != null) {
        final followed = _family.where((f) => f.userId == _followingUserId).firstOrNull;
        if (followed != null) {
          _animateTo(LatLng(followed.lat, followed.lng), zoom: 16);
        }
      }
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

      final speedKmh = pos.speed > 0 ? (pos.speed * 3.6) : 0.0;

      await SupabaseService.pushLocation(
        lat: pos.latitude,
        lng: pos.longitude,
        accuracy: pos.accuracy,
        heading: pos.heading >= 0 ? pos.heading : null,
        speed: speedKmh,
        battery: batteryLevel,
        isMocked: pos.isMocked,
      );

      if (mounted) {
        setState(() {
          _myPosition = meLatLng;
          _myBattery = batteryLevel;
          _mySpeed = speedKmh;
        });
      }
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
      if (_me != null) {
        setState(() {
          _me = UserProfile(
            id: _me!.id,
            name: _me!.name,
            email: _me!.email,
            avatarUrl: _me!.avatarUrl,
            sharingOn: on,
          );
        });
      }
      await SupabaseService.updateSharing(on);
      await _refreshProfile();
      _showSnack(on ? '📍 Lokasimu dibagikan ke keluarga' : 'Berbagi lokasi dimatikan');
      if (on) {
        _startLocationStream();
        await _pushMyLocation();
        await startBackgroundSharing();
      } else {
        _stopLocationStream();
        await stopBackgroundSharing();
      }
    } catch (e) {
      _showSnack(e.toString());
    }
  }

  void _focusMember(FamilyMemberLocation f) {
    setState(() => _followingUserId = f.userId);
    _animateTo(LatLng(f.lat, f.lng), zoom: 16);
    _showSnack('🎥 Kamera mengikuti ${f.name} secara langsung');
  }

  Future<void> _focusMe() async {
    setState(() => _followingUserId = null);
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

  // --- SOS Emergency Dialog & Trigger ---
  Future<void> _showSosConfirmation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FamRadius.card)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
            SizedBox(width: 10),
            Text('Kirim Sinyal SOS?', style: TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
        content: const Text(
          'Peringatan darurat akan langsung dikirimkan ke HP seluruh anggota keluarga beserta lokasi koordinat presisi Anda.',
          style: TextStyle(fontSize: 13.5, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.sos_rounded),
            label: const Text('KIRIM SOS SEKARANG', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (_myPosition == null) {
        await _focusMe();
      }
      if (_myPosition != null) {
        try {
          await SupabaseService.triggerSos(
            lat: _myPosition!.latitude,
            lng: _myPosition!.longitude,
            battery: _myBattery,
          );
          _showSnack('🚨 Sinyal darurat SOS berhasil dikirim ke keluarga!');
        } catch (e) {
          _showSnack('Gagal mengirim SOS: $e');
        }
      }
    }
  }

  void _showLayerPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(FamRadius.sheet)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 20,
          bottom: MediaQuery.of(ctx).padding.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Pilih Tampilan Peta', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            Row(
              children: [
                _buildLayerOption(
                  title: 'Default',
                  subtitle: 'Jalan',
                  icon: Icons.map_outlined,
                  type: MapLayerType.normal,
                ),
                const SizedBox(width: 10),
                _buildLayerOption(
                  title: 'Satelit',
                  subtitle: 'Foto Asli',
                  icon: Icons.satellite_alt_rounded,
                  type: MapLayerType.satellite,
                ),
                const SizedBox(width: 10),
                _buildLayerOption(
                  title: 'Terrain',
                  subtitle: 'Kontur',
                  icon: Icons.terrain_rounded,
                  type: MapLayerType.terrain,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLayerOption({
    required String title,
    required String subtitle,
    required IconData icon,
    required MapLayerType type,
  }) {
    final isSelected = _currentLayer == type;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _currentLayer = type);
          Navigator.pop(context);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected ? FamColors.primary.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(FamRadius.card),
            border: Border.all(
              color: isSelected ? FamColors.primary : Colors.black12,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, color: isSelected ? FamColors.primary : FamColors.muted, size: 28),
              const SizedBox(height: 8),
              Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: isSelected ? FamColors.primary : FamColors.textDark)),
              Text(subtitle, style: const TextStyle(fontSize: 11, color: FamColors.muted)),
            ],
          ),
        ),
      ),
    );
  }

  String _getTileUrl() {
    switch (_currentLayer) {
      case MapLayerType.satellite:
        // Google Satellite Hybrid (Foto Udara + Nama Jalan)
        return 'https://mt{s}.google.com/vt/lyrs=y&x={x}&y={y}&z={z}';
      case MapLayerType.terrain:
        // Google Terrain (Kontur Topografi)
        return 'https://mt{s}.google.com/vt/lyrs=p&x={x}&y={y}&z={z}';
      case MapLayerType.normal:
        // Google Road Map
        return 'https://mt{s}.google.com/vt/lyrs=m&x={x}&y={y}&z={z}';
    }
  }

  String _formatSpeedText(double? speed) {
    if (speed == null || speed < 1.5) return '🛑 Diam';
    if (speed < 7) return '🚶 Jalan kaki';
    if (speed < 20) return '🚲 ${speed.round()} km/jam';
    return '🚗 ${speed.round()} km/jam';
  }

  static Future<void> launchNavigation(double lat, double lng) async {
    final url = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving');
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final followedMember = _followingUserId != null
        ? _family.where((f) => f.userId == _followingUserId).firstOrNull
        : null;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text('Halo, ${_me?.name ?? ''} 👋'),
        actions: [
          IconButton(
            icon: const Icon(Icons.people_alt_rounded),
            tooltip: 'Keluargaku & Teman',
            onPressed: () async {
              final selectedUserId = await Navigator.of(context).push<String>(
                MaterialPageRoute(builder: (_) => const FamilyScreen()),
              );
              await _refreshLocations();
              if (selectedUserId != null) {
                final target = _family.where((f) => f.userId == selectedUserId).firstOrNull;
                if (target != null) {
                  _focusMember(target);
                }
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_rounded),
            tooltip: 'Profil & Pengaturan',
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
              onPositionChanged: (pos, hasGesture) {
                // Jika pengguna menggeser peta secara manual, lepas mode auto-follow
                if (hasGesture && _followingUserId != null) {
                  setState(() => _followingUserId = null);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: _getTileUrl(),
                subdomains: const ['0', '1', '2', '3'],
                userAgentPackageName: 'eu.awanda.famloc',
                maxZoom: 20,
                tileBuilder: (context, tileWidget, tile) {
                  return Container(
                    color: const Color(0xFFE8ECEF),
                    child: tileWidget,
                  );
                },
              ),
              MarkerLayer(markers: _buildMarkers()),
            ],
          ),
          const Positioned(
            left: 4, bottom: 2,
            child: Text(kMapAttribution,
                style: TextStyle(fontSize: 10, color: FamColors.muted)),
          ),

          // Banner Sinyal Darurat SOS dari Keluarga
          if (_activeSosList.isNotEmpty)
            Positioned(
              top: kToolbarHeight + MediaQuery.of(context).padding.top + 8,
              left: 16, right: 16,
              child: _buildActiveSosBanner(_activeSosList.first),
            )
          // Banner Status Berbagi Lokasi Sendiri
          else if (_me?.sharingOn == true)
            Positioned(
              top: kToolbarHeight + MediaQuery.of(context).padding.top + 8,
              left: 16, right: 16,
              child: GestureDetector(
                onTap: () => _toggleSharing(false),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(FamRadius.pill),
                    boxShadow: FamColors.softShadow(opacity: 0.15),
                  ),
                  child: Row(
                    children: [
                      const PulsingDot(),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _mySpeed != null && _mySpeed! >= 1.5
                              ? '📍 Berbagi aktif · ${_formatSpeedText(_mySpeed)}'
                              : '📍 Lokasimu dibagikan secara realtime · ketuk untuk matikan',
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
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

          // Floating Pill saat Mode Auto-Follow Aktif
          if (followedMember != null)
            Positioned(
              bottom: 24,
              left: 20,
              right: 20,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(FamRadius.pill),
                    boxShadow: FamColors.softShadow(opacity: 0.3),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.videocam_rounded, color: Colors.greenAccent, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Mengikuti ${followedMember.name}',
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: () => setState(() => _followingUserId = null),
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(color: Colors.white24, shape: BoxShape.circle),
                          child: const Icon(Icons.close_rounded, color: Colors.white, size: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Tombol SOS Darurat Merah
          FloatingActionButton.small(
            heroTag: 'sos_btn',
            backgroundColor: Colors.red.shade600,
            foregroundColor: Colors.white,
            tooltip: 'Sinyal Darurat SOS',
            onPressed: _showSosConfirmation,
            child: const Icon(Icons.sos_rounded, size: 20),
          ),
          const SizedBox(height: 8),

          // Tombol Layer Switcher (Normal/Satelit/Terrain)
          FloatingActionButton.small(
            heroTag: 'layer_btn',
            backgroundColor: Colors.white,
            foregroundColor: FamColors.textDark,
            tooltip: 'Tampilan Peta',
            onPressed: _showLayerPicker,
            child: const Icon(Icons.layers_outlined),
          ),
          const SizedBox(height: 8),

          // Tombol Pilih Keluarga
          if (_family.isNotEmpty) ...[
            FloatingActionButton.small(
              heroTag: 'focus_family',
              backgroundColor: FamColors.primary,
              foregroundColor: Colors.white,
              tooltip: 'Pilih & Fokus Keluarga',
              onPressed: _showFamilyPickerSheet,
              child: const Icon(Icons.people_alt_rounded),
            ),
            const SizedBox(height: 8),
          ],

          // Tombol Posisiku
          FloatingActionButton.small(
            heroTag: 'focus_me',
            backgroundColor: Colors.white,
            foregroundColor: FamColors.primary,
            tooltip: 'Posisiku',
            onPressed: _focusMe,
            child: const Icon(Icons.my_location_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveSosBanner(SosAlert alert) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.shade600,
        borderRadius: BorderRadius.circular(FamRadius.card),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withValues(alpha: 0.4),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '🚨 PERINGATAN DARURAT: ${alert.name}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Anggota keluargamu baru saja menekan tombol darurat SOS dan membutuhkan bantuan!',
            style: TextStyle(color: Colors.white, fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.red.shade700,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  onPressed: () {
                    _animateTo(LatLng(alert.lat, alert.lng), zoom: 17);
                  },
                  child: const Text('📍 Lihat Lokasi', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.25),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  onPressed: () => launchNavigation(alert.lat, alert.lng),
                  child: const Text('🧭 Navigasi', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
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
        width: 140, height: 90,
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
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(FamRadius.pill),
                boxShadow: FamColors.softShadow(opacity: 0.1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_me?.name ?? 'Saya',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  if (_myBattery != null) ...[
                    const SizedBox(width: 4),
                    Icon(
                      _myBattery! <= 20
                          ? Icons.battery_alert_rounded
                          : (_myBattery! <= 50 ? Icons.battery_3_bar_rounded : Icons.battery_full_rounded),
                      size: 13,
                      color: _myBattery! <= 20 ? Colors.red : (_myBattery! <= 50 ? Colors.orange : Colors.green),
                    ),
                    Text(
                      '$_myBattery%',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: _myBattery! <= 20 ? Colors.red : (_myBattery! <= 50 ? Colors.orange : Colors.green.shade800),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ));
    }

    // Marker Anggota Keluarga (Mama / Teman)
    for (final f in _family) {
      final isLive = DateTime.now().difference(f.updatedAt).inMinutes <= 15;
      list.add(Marker(
        width: 150,
        height: 90,
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(FamRadius.pill),
                  boxShadow: FamColors.softShadow(opacity: 0.1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(f.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    if (f.battery != null) ...[
                      const SizedBox(width: 4),
                      Icon(
                        f.battery! <= 20
                            ? Icons.battery_alert_rounded
                            : (f.battery! <= 50 ? Icons.battery_3_bar_rounded : Icons.battery_full_rounded),
                        size: 13,
                        color: f.battery! <= 20 ? Colors.red : (f.battery! <= 50 ? Colors.orange : Colors.green),
                      ),
                      Text(
                        '${f.battery}%',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: f.battery! <= 20 ? Colors.red : (f.battery! <= 50 ? Colors.orange : Colors.green.shade800),
                        ),
                      ),
                    ],
                  ],
                ),
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

  void _showFamilyPickerSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(FamRadius.sheet)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).padding.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
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
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.people_alt_rounded, color: FamColors.primary),
                const SizedBox(width: 8),
                Text(
                  'Pilih Anggota Keluarga',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Ketuk nama untuk fokus dan mengikuti pergerakan lokasinya:',
              style: TextStyle(fontSize: 12.5, color: FamColors.muted),
            ),
            const SizedBox(height: 14),
            ..._family.map((f) {
              final isFollowing = f.userId == _followingUserId;
              final isLive = DateTime.now().difference(f.updatedAt).inMinutes <= 15;
              final dist = _myPosition != null
                  ? const Distance().as(LengthUnit.Meter, _myPosition!, LatLng(f.lat, f.lng))
                  : null;
              final distStr = dist != null
                  ? (dist < 1000 ? '${dist.round()} m' : '${(dist / 1000).toStringAsFixed(1)} km')
                  : null;

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: isFollowing ? FamColors.primary.withValues(alpha: 0.08) : Colors.white,
                  borderRadius: BorderRadius.circular(FamRadius.card),
                  border: Border.all(
                    color: isFollowing ? FamColors.primary : Colors.black12,
                    width: isFollowing ? 1.5 : 1,
                  ),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  leading: AvatarWithRing(name: f.name, isLive: isLive, radius: 22),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          f.name,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                      ),
                      if (f.battery != null) ...[
                        Icon(
                          f.battery! <= 20
                              ? Icons.battery_alert_rounded
                              : (f.battery! <= 50 ? Icons.battery_3_bar_rounded : Icons.battery_full_rounded),
                          size: 14,
                          color: f.battery! <= 20 ? Colors.red : (f.battery! <= 50 ? Colors.orange : Colors.green),
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${f.battery}%',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: f.battery! <= 20 ? Colors.red : (f.battery! <= 50 ? Colors.orange : Colors.green.shade800),
                          ),
                        ),
                      ],
                    ],
                  ),
                  subtitle: Row(
                    children: [
                      Text(
                        isLive ? _formatSpeedText(f.speed) : '⚪ Offline',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: isLive ? Colors.green.shade700 : FamColors.muted,
                        ),
                      ),
                      if (distStr != null) ...[
                        const Text(' · ', style: TextStyle(color: FamColors.muted)),
                        Text(
                          '$distStr dari kamu',
                          style: const TextStyle(fontSize: 11.5, color: FamColors.muted),
                        ),
                      ],
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.navigation_rounded, color: FamColors.primary, size: 20),
                        tooltip: 'Navigasi Google Maps',
                        onPressed: () => launchNavigation(f.lat, f.lng),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: isFollowing ? FamColors.primary : FamColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(FamRadius.pill),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.videocam_rounded,
                              size: 14,
                              color: isFollowing ? Colors.white : FamColors.primary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isFollowing ? 'Mengikuti' : 'Fokus',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: isFollowing ? Colors.white : FamColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _focusMember(f);
                  },
                ),
              );
            }),
            const SizedBox(height: 10),
            Center(
              child: TextButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  final selectedUserId = await Navigator.of(context).push<String>(
                    MaterialPageRoute(builder: (_) => const FamilyScreen()),
                  );
                  await _refreshLocations();
                  if (selectedUserId != null) {
                    final target = _family.where((f) => f.userId == selectedUserId).firstOrNull;
                    if (target != null) {
                      _focusMember(target);
                    }
                  }
                },
                icon: const Icon(Icons.person_add_rounded, size: 16),
                label: const Text('Kelola & Tambah Anggota Keluarga', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _stopLocationStream();
    _realtimeSubscription?.cancel();
    _sosSubscription?.cancel();
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

  String _formatSpeed(double? s) {
    if (s == null || s < 1.5) return '🛑 Diam';
    if (s < 7) return '🚶 Berjalan kaki';
    if (s < 20) return '🚲 ${s.round()} km/jam';
    return '🚗 ${s.round()} km/jam';
  }

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
                label: isLive ? _formatSpeed(member.speed) : 'Offline',
                icon: isLive ? Icons.speed_rounded : Icons.pause_circle_rounded,
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

          // Tombol Aksi Utama: Fokus & Navigasi Google Maps
          Row(
            children: [
              Expanded(
                flex: 3,
                child: GradientButton(
                  label: '📍 Fokus & Ikuti',
                  onPressed: () {
                    Navigator.pop(context);
                    onFocus();
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: FamColors.primary,
                    side: const BorderSide(color: FamColors.primary, width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FamRadius.pill)),
                  ),
                  onPressed: () {
                    MapHomeScreenState.launchNavigation(member.lat, member.lng);
                  },
                  icon: const Icon(Icons.navigation_rounded, size: 18),
                  label: const Text('Rute Maps', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

extension on _MapHomeScreenState {
  static void launchNavigation(double lat, double lng) =>
      _MapHomeScreenState.launchNavigation(lat, lng);
}