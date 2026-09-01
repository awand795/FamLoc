import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../supabase_service.dart';
import '../background_task.dart';
import '../notification_service.dart';
import '../theme.dart';
import 'family_screen.dart';
import 'profile_screen.dart';

/// Atribusi peta
const String kMapAttribution = '© Google Maps / OpenStreetMap';

enum MapLayerType {
  normal,
  satellite,
  terrain,
  dark,
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
  StreamSubscription? _placesSubscription;
  StreamSubscription? _checkinSubscription;
  StreamSubscription? _ringSubscription;
  StreamSubscription<Position>? _positionStreamSub;
  AnimationController? _moveAnim;
  UserProfile? _me;
  List<FamilyMemberLocation> _family = [];
  List<SosAlert> _activeSosList = [];
  List<PlaceZone> _places = [];
  List<LatLng> _activeRouteTrail = [];
  String? _trailUserId;
  QuickCheckin? _latestCheckin;
  RingAlert? _activeRingAlert;
  LatLng? _myPosition;
  int? _myBattery;
  double? _mySpeed;
  String? _followingUserId;
  bool _busy = false;
  Timer? _pushTimer;
  MapLayerType _currentLayer = MapLayerType.normal;
  final Set<String> _lowBatteryAlertedUsers = {};
  final Set<String> _speedAlertedUsers = {};
  DateTime? _lastSelfSpeedAlert;
  DateTime? _lastBackPressTime;
  final Map<String, String> _lastKnownGeofenceZone = {}; // userId -> placeName
  final Map<String, Map<String, double>> _previousPlaceDistances = {}; // userId -> {placeId: distance}

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

    // 2. Jalankan refresh profile, lokasi, SOS, & Places secara paralel
    _refreshProfile().then((_) => _startSharingIfOn());
    _refreshLocations();
    _refreshSosAlerts();
    _refreshPlaces();
    _refreshRingAlerts();
    _focusMe(); // Update dengan GPS akurat saat satelit siap

    // Realtime Location Updates
    _realtimeSubscription = SupabaseService.streamLocations().listen((_) {
      _refreshLocations();
    });

    // Realtime SOS Emergency Signals
    _sosSubscription = SupabaseService.streamSosAlerts().listen((_) {
      _refreshSosAlerts();
    });

    // Realtime Places & Geofencing
    _placesSubscription = SupabaseService.streamPlaces().listen((_) {
      _refreshPlaces();
    });

    // Realtime Quick Check-ins
    _checkinSubscription = SupabaseService.streamQuickCheckins().listen((_) {
      _fetchLatestCheckin();
    });

    // Realtime Ring Alerts (Cari HP Lupa Taruh)
    _ringSubscription = SupabaseService.streamRingAlerts().listen((_) {
      _refreshRingAlerts();
    });

    // Interval stream lokasi sendiri & sync heartbeat tiap 5 detik (menjaga koneksi tetap hidup di layar mati)
    _pushTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _pushMyLocation();
      if (timer.tick % 2 == 0) {
        _refreshLocations();
        _refreshSosAlerts();
        _refreshRingAlerts();
      }
    });
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
      for (final a in alerts) {
        if (!_activeSosList.any((prev) => prev.id == a.id)) {
          NotificationService.showSosNotification(
            name: a.name,
            lat: a.lat,
            lng: a.lng,
          );
        }
      }
      setState(() => _activeSosList = alerts);
    } catch (_) {}
  }

  Future<void> _refreshPlaces() async {
    try {
      final places = await SupabaseService.getPlaces();
      if (!mounted) return;
      setState(() => _places = places);
    } catch (_) {}
  }

  Future<void> _refreshRingAlerts() async {
    try {
      final alerts = await SupabaseService.getActiveRingAlertsForMe();
      if (!mounted) return;
      if (alerts.isNotEmpty) {
        final alert = alerts.first;
        if (_activeRingAlert == null || _activeRingAlert!.id != alert.id) {
          setState(() => _activeRingAlert = alert);
          NotificationService.showRingDeviceNotification(senderName: alert.senderName);
          _showLoudRingDialog(alert);
        }
      } else {
        if (_activeRingAlert != null) {
          setState(() => _activeRingAlert = null);
        }
      }
    } catch (_) {}
  }

  void _showLoudRingDialog(RingAlert alert) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FamRadius.card)),
        backgroundColor: Colors.amber.shade50,
        title: Row(
          children: [
            const Icon(Icons.volume_up_rounded, color: Colors.amber, size: 32),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '🔊 Panggilan Cari HP!',
                style: TextStyle(color: Colors.amber.shade900, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: Text(
          '${alert.senderName} sedang membunyikan HP ini agar posisinya dapat segera ditemukan.',
          style: const TextStyle(fontSize: 14, height: 1.4),
        ),
        actions: [
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.amber.shade800),
            onPressed: () async {
              Navigator.pop(ctx);
              await SupabaseService.cancelRingAlert(alert.id);
              setState(() => _activeRingAlert = null);
            },
            icon: const Icon(Icons.volume_off_rounded),
            label: const Text('🔕 HENTIKAN DERING', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Future<void> _fetchLatestCheckin() async {
    try {
      final checkins = await SupabaseService.getRecentCheckins();
      if (checkins.isNotEmpty && mounted) {
        final latest = checkins.first;
        if (_latestCheckin == null || _latestCheckin!.id != latest.id) {
          setState(() => _latestCheckin = latest);
          _showSnack('${latest.icon} ${latest.name}: "${latest.message}"');
          NotificationService.showCheckinNotification(
            name: latest.name,
            message: latest.message,
            icon: latest.icon,
          );
        }
      }
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

      // Peringatan Kecepatan Sendiri (Driver Speed Alert > 80 km/jam)
      if (speedKmh >= 80) {
        final now = DateTime.now();
        if (_lastSelfSpeedAlert == null || now.difference(_lastSelfSpeedAlert!).inMinutes >= 3) {
          _lastSelfSpeedAlert = now;
          NotificationService.showSpeedNotification(
            name: _me?.name ?? 'Saya',
            speed: speedKmh.round(),
            isSelf: true,
          );
        }
      }

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

      // Auto-Follow pergerakan keluarga
      if (_followingUserId != null) {
        final followed = _family.where((f) => f.userId == _followingUserId).firstOrNull;
        if (followed != null) {
          _animateTo(LatLng(followed.lat, followed.lng), zoom: 16);
        }
      }

      // Deteksi Geofencing, Peringatan Baterai Lemah, & Peringatan Kecepatan
      _checkSmartSensors(list);
    } catch (_) {}
  }

  void _checkSmartSensors(List<FamilyMemberLocation> members) {
    const distCalc = Distance();

    for (final m in members) {
      // 1. Peringatan Baterai Lemah
      if (m.battery != null && m.battery! <= 15 && !_lowBatteryAlertedUsers.contains(m.userId)) {
        _lowBatteryAlertedUsers.add(m.userId);
        _showSnack('⚠️ Baterai HP ${m.name} tersisa ${m.battery}%, ingatkan untuk isi daya 🔌');
        NotificationService.showBatteryNotification(name: m.name, battery: m.battery!);
      } else if (m.battery != null && m.battery! > 20) {
        _lowBatteryAlertedUsers.remove(m.userId);
      }

      // 2. Peringatan Kecepatan Keluarga (> 80 km/jam)
      if (m.speed != null && m.speed! >= 80 && !_speedAlertedUsers.contains(m.userId)) {
        _speedAlertedUsers.add(m.userId);
        NotificationService.showSpeedNotification(
          name: m.name,
          speed: m.speed!.round(),
          isSelf: false,
        );
      } else if (m.speed != null && m.speed! < 70) {
        _speedAlertedUsers.remove(m.userId);
      }

      // 3. Geofencing Tempat Favorit
      final mPos = LatLng(m.lat, m.lng);
      String? currentZone;
      String currentZoneIcon = '🏠';

      for (final p in _places) {
        final d = distCalc.as(LengthUnit.Meter, mPos, LatLng(p.lat, p.lng));
        if (d <= p.radius) {
          currentZone = p.name;
          currentZoneIcon = p.icon;
          break;
        }
      }

      final previousZone = _lastKnownGeofenceZone[m.userId];
      if (currentZone != null && currentZone != previousZone) {
        _lastKnownGeofenceZone[m.userId] = currentZone;
        _showSnack('$currentZoneIcon ${m.name} sudah tiba di $currentZone');
        NotificationService.showGeofenceNotification(
          name: m.name,
          placeName: currentZone,
          isArriving: true,
          icon: currentZoneIcon,
        );
      } else if (currentZone == null && previousZone != null) {
        _lastKnownGeofenceZone.remove(m.userId);
        _showSnack('🚗 ${m.name} baru saja meninggalkan $previousZone');
        NotificationService.showGeofenceNotification(
          name: m.name,
          placeName: previousZone,
          isArriving: false,
        );
      }

      // Simpan riwayat jarak ke setiap tempat untuk perhitungan vektor arah ETA
      final userDistances = _previousPlaceDistances.putIfAbsent(m.userId, () => {});
      for (final p in _places) {
        userDistances[p.id] = distCalc.as(LengthUnit.Meter, mPos, LatLng(p.lat, p.lng));
      }
    }
  }

  /// Hitung estimasi arah tujuan dan ETA cerdas untuk anggota keluarga
  String? _calculateDestinationEta(FamilyMemberLocation m) {
    if (m.speed == null || m.speed! < 12 || _places.isEmpty) return null;
    const distCalc = Distance();
    final mPos = LatLng(m.lat, m.lng);

    PlaceZone? bestDestination;
    double minDistance = double.infinity;

    for (final p in _places) {
      final curDist = distCalc.as(LengthUnit.Meter, mPos, LatLng(p.lat, p.lng));
      // Jika berada di dalam radius tempat, berarti sudah sampai
      if (curDist <= p.radius) return null;

      // Cek apakah jarak ke tempat ini sedang berkurang (mendekat)
      final prevDist = _previousPlaceDistances[m.userId]?[p.id];
      final isGettingCloser = prevDist == null || curDist <= prevDist + 10;

      if (isGettingCloser && curDist < minDistance && curDist < 30000) {
        minDistance = curDist;
        bestDestination = p;
      }
    }

    if (bestDestination != null && minDistance < double.infinity) {
      final speedKmh = m.speed!;
      final distKm = minDistance / 1000.0;
      final etaMinutes = (distKm / speedKmh * 60).round();
      final distStr = distKm < 1 ? '${minDistance.round()} m' : '${distKm.toStringAsFixed(1)} km';
      final etaText = etaMinutes <= 1 ? '~1 mnt' : '~$etaMinutes mnt';
      return '${bestDestination.icon} Menuju ${bestDestination.name} · Sisa $distStr · ETA $etaText';
    }
    return null;
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

  // --- SOS Emergency Dialog ---
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

  // --- Quick Check-in Dialog ---
  void _showQuickCheckinModal() {
    final presets = [
      {'icon': '🏡', 'text': 'Aku sudah sampai ya!'},
      {'icon': '🚗', 'text': 'Sedang dalam perjalanan pulang'},
      {'icon': '☕', 'text': 'Lagi istirahat makan/minum sebentar'},
      {'icon': '🛵', 'text': 'Tolong jemput sekarang ya!'},
      {'icon': '⏳', 'text': 'Tunggu sebentar lagi ya'},
      {'icon': '🛒', 'text': 'Sedang belanja kebutuhan'},
    ];

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
            const Row(
              children: [
                Icon(Icons.mark_chat_unread_rounded, color: FamColors.primary),
                SizedBox(width: 8),
                Text('Kirim Kabar Kilat (1-Ketukan)', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 6),
            const Text('Pilih pesan cepat untuk langsung disiarkan ke HP keluarga:', style: TextStyle(fontSize: 12.5, color: FamColors.muted)),
            const SizedBox(height: 14),
            ...presets.map((p) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(FamRadius.card),
                border: Border.all(color: Colors.black12),
              ),
              child: ListTile(
                leading: Text(p['icon']!, style: const TextStyle(fontSize: 24)),
                title: Text(p['text']!, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                trailing: const Icon(Icons.send_rounded, color: FamColors.primary, size: 20),
                onTap: () async {
                  Navigator.pop(ctx);
                  if (_myPosition == null) await _focusMe();
                  if (_myPosition != null) {
                    try {
                      await SupabaseService.sendQuickCheckin(
                        message: p['text']!,
                        icon: p['icon']!,
                        lat: _myPosition!.latitude,
                        lng: _myPosition!.longitude,
                      );
                      _showSnack('Pesan kilat terkirim: "${p['text']}" 🎉');
                    } catch (e) {
                      _showSnack('Gagal kirim kabar: $e');
                    }
                  }
                },
              ),
            )),
          ],
        ),
      ),
    );
  }

  // --- Daftar & Pengelola Zona Aman Bersama Keluarga ---
  void _showPlacesManagerSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(FamRadius.sheet)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
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
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: FamColors.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.shield_rounded, color: FamColors.primary, size: 22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Zona Aman Bersama (${_places.length})',
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Tersinkronisasi otomatis untuk seluruh keluarga',
                          style: TextStyle(fontSize: 12, color: FamColors.muted),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: FamColors.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FamRadius.pill)),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showAddPlaceDialog();
                    },
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('Tambah', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(FamRadius.card),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, color: Colors.blue.shade700, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Setiap zona aman yang ditambahkan otomatis aktif di HP seluruh keluarga. Notifikasi tiba/keluar akan diterima bersama.',
                        style: TextStyle(fontSize: 11.5, color: Colors.blue.shade900, height: 1.35),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (_places.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
                  alignment: Alignment.center,
                  child: Column(
                    children: [
                      const Icon(Icons.add_location_alt_outlined, size: 44, color: Colors.black26),
                      const SizedBox(height: 10),
                      const Text(
                        'Belum Ada Zona Aman Bersama',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Tambahkan Rumah, Kost, atau Kantor agar aplikasi otomatis memberi kabar saat keluarga tiba.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: FamColors.muted),
                      ),
                    ],
                  ),
                )
              else
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.45),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _places.length,
                    itemBuilder: (context, i) {
                      final p = _places[i];
                      final dist = _myPosition != null
                          ? const Distance().as(LengthUnit.Meter, _myPosition!, LatLng(p.lat, p.lng))
                          : null;
                      final distStr = dist != null
                          ? (dist < 1000 ? '${dist.round()} m' : '${(dist / 1000).toStringAsFixed(1)} km')
                          : null;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.02),
                          borderRadius: BorderRadius.circular(FamRadius.card),
                          border: Border.all(color: Colors.black12),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                          leading: Container(
                            width: 42,
                            height: 42,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: FamColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(p.icon, style: const TextStyle(fontSize: 22)),
                          ),
                          title: Text(
                            p.name,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Radius ${p.radius.round()}m · Ditambahkan ${p.creatorName ?? "Keluarga"}',
                                style: const TextStyle(fontSize: 11.5, color: FamColors.muted),
                              ),
                              if (distStr != null)
                                Text(
                                  '📍 $distStr dari posisimu saat ini',
                                  style: const TextStyle(fontSize: 11, color: FamColors.primary, fontWeight: FontWeight.w600),
                                ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.my_location_rounded, color: FamColors.primary, size: 20),
                                tooltip: 'Lihat di Peta',
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  _animateTo(LatLng(p.lat, p.lng), zoom: 16.5);
                                  _showSnack('📍 Melihat zona aman "${p.name}"');
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                                tooltip: 'Hapus Zona',
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  _confirmDeletePlace(p);
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDeletePlace(PlaceZone p) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FamRadius.card)),
        title: Text('Hapus "${p.name}"?', style: const TextStyle(fontWeight: FontWeight.w800)),
        content: Text(
          'Zona aman "${p.name}" akan dihapus dari daftar bersama seluruh keluarga. Apakah Anda yakin?',
          style: const TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus Zona'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await SupabaseService.deletePlace(p.id);
        await _refreshPlaces();
        _showSnack('Zona "${p.name}" berhasil dihapus untuk seluruh keluarga');
      } catch (e) {
        _showSnack('Gagal menghapus zona: $e');
      }
    }
  }

  // --- Place / Geofencing Creator Dialog ---
  Future<void> _showAddPlaceDialog() async {
    final nameCtrl = TextEditingController();
    String selectedIcon = '🏠';
    double radius = 150.0;

    final icons = ['🏠', '🏢', '🏫', '🛒', '🕌', '🏥', '🏖️', '☕'];

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FamRadius.card)),
          title: const Text('➕ Tambah Zona Aman (Geofence)', style: TextStyle(fontWeight: FontWeight.w800)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Tandai titik penting. Anda akan menerima notifikasi otomatis saat keluarga tiba atau meninggalkan tempat ini:',
                style: TextStyle(fontSize: 12.5, color: FamColors.muted),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: 'Nama Tempat (misal: Rumah, Kost, Kantor)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 14),
              const Text('Pilih Ikon:', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: icons.map((ic) => GestureDetector(
                  onTap: () => setDlgState(() => selectedIcon = ic),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: selectedIcon == ic ? FamColors.primary.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: selectedIcon == ic ? FamColors.primary : Colors.transparent, width: 2),
                    ),
                    child: Text(ic, style: const TextStyle(fontSize: 20)),
                  ),
                )).toList(),
              ),
              const SizedBox(height: 14),
              Text('Radius Geofence: ${radius.round()} meter', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
              Slider(
                value: radius,
                min: 50, max: 500, divisions: 9,
                activeColor: FamColors.primary,
                onChanged: (v) => setDlgState(() => radius = v),
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
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(ctx);
                if (_myPosition == null) await _focusMe();
                if (_myPosition != null) {
                  try {
                    await SupabaseService.createPlace(
                      name: name,
                      icon: selectedIcon,
                      lat: _myPosition!.latitude,
                      lng: _myPosition!.longitude,
                      radius: radius,
                    );
                    _refreshPlaces();
                    _showSnack('Zona aman "$name" berhasil disimpan! 🏡');
                  } catch (e) {
                    _showSnack('Gagal menyimpan zona: $e');
                  }
                }
              },
              child: const Text('Simpan Zona'),
            ),
          ],
        ),
      ),
    );
  }

  // --- Load Location History Breadcrumb Trail ---
  Future<void> _toggleTrailForUser(String userId, String name) async {
    if (_trailUserId == userId && _activeRouteTrail.isNotEmpty) {
      setState(() {
        _activeRouteTrail = [];
        _trailUserId = null;
      });
      _showSnack('Jejak rute disembunyikan');
      return;
    }

    try {
      final trail = await SupabaseService.getLocationHistoryToday(userId);
      if (!mounted) return;
      if (trail.isEmpty) {
        _showSnack('Belum ada rekam jejak perjalanan hari ini');
        return;
      }
      setState(() {
        _activeRouteTrail = trail;
        _trailUserId = userId;
      });
      _showSnack('Menampilkan ${trail.length} titik jejak perjalanan $name 📜');
    } catch (e) {
      _showSnack('Gagal memuat jejak: $e');
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
                const SizedBox(width: 8),
                _buildLayerOption(
                  title: 'Satelit',
                  subtitle: 'Foto Asli',
                  icon: Icons.satellite_alt_rounded,
                  type: MapLayerType.satellite,
                ),
                const SizedBox(width: 8),
                _buildLayerOption(
                  title: 'Terrain',
                  subtitle: 'Kontur',
                  icon: Icons.terrain_rounded,
                  type: MapLayerType.terrain,
                ),
                const SizedBox(width: 8),
                _buildLayerOption(
                  title: 'Malam',
                  subtitle: 'Dark Mode',
                  icon: Icons.dark_mode_rounded,
                  type: MapLayerType.dark,
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
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
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
              Icon(icon, color: isSelected ? FamColors.primary : FamColors.muted, size: 24),
              const SizedBox(height: 6),
              Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: isSelected ? FamColors.primary : FamColors.textDark)),
              Text(subtitle, style: const TextStyle(fontSize: 10, color: FamColors.muted)),
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
      case MapLayerType.dark:
        // Carto Dark Matter (Peta Mode Malam AMOLED)
        return 'https://{s}.basemaps.cartocdn.com/rastertiles/dark_all/{z}/{x}/{y}{r}.png';
      case MapLayerType.normal:
        // Google Road Map
        return 'https://mt{s}.google.com/vt/lyrs=m&x={x}&y={y}&z={z}';
    }
  }

  List<String> _getTileSubdomains() {
    switch (_currentLayer) {
      case MapLayerType.dark:
        return const ['a', 'b', 'c', 'd'];
      default:
        return const ['0', '1', '2', '3'];
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

  static Future<void> launchCall(String? phone) async {
    if (phone == null || phone.trim().isEmpty) return;
    final url = Uri.parse('tel:${phone.trim()}');
    try {
      await launchUrl(url);
    } catch (_) {}
  }

  static Future<void> launchWhatsApp(String? phone, String name) async {
    if (phone == null || phone.trim().isEmpty) return;
    var clean = phone.trim().replaceAll(RegExp(r'[^0-9]'), '');
    if (clean.startsWith('0')) {
      clean = '62${clean.substring(1)}';
    }
    final msg = Uri.encodeComponent('Halo $name, lagi di mana?');
    final url = Uri.parse('https://wa.me/$clean?text=$msg');
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final followedMember = _followingUserId != null
        ? _family.where((f) => f.userId == _followingUserId).firstOrNull
        : null;

    final destinationEta = followedMember != null ? _calculateDestinationEta(followedMember) : null;

    final followDist = (followedMember != null && _myPosition != null)
        ? const Distance().as(LengthUnit.Meter, _myPosition!, LatLng(followedMember.lat, followedMember.lng))
        : null;

    final followDistStr = followDist != null
        ? (followDist < 1000 ? '${followDist.round()} m' : '${(followDist / 1000).toStringAsFixed(1)} km')
        : null;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_followingUserId != null) {
          setState(() => _followingUserId = null);
          _showSnack('Berhenti mengikuti live');
          return;
        }
        if (_activeRouteTrail.isNotEmpty) {
          setState(() {
            _activeRouteTrail = [];
            _trailUserId = null;
          });
          _showSnack('Jejak rute disembunyikan');
          return;
        }
        final now = DateTime.now();
        if (_lastBackPressTime == null || now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
          _lastBackPressTime = now;
          _showSnack('Tekan sekali lagi untuk keluar dari aplikasi');
          return;
        }
        SystemNavigator.pop();
      },
      child: Scaffold(
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
                subdomains: _getTileSubdomains(),
                userAgentPackageName: 'eu.awanda.famloc',
                maxZoom: 20,
                tileBuilder: (context, tileWidget, tile) {
                  return Container(
                    color: _currentLayer == MapLayerType.dark ? const Color(0xFF1E1E1E) : const Color(0xFFE8ECEF),
                    child: tileWidget,
                  );
                },
              ),
              // 1. Layer Lingkaran Geofencing Tempat Favorit
              CircleLayer(
                circles: _places.map((p) => CircleMarker(
                  point: LatLng(p.lat, p.lng),
                  radius: p.radius,
                  useRadiusInMeter: true,
                  color: FamColors.primary.withValues(alpha: 0.15),
                  borderColor: FamColors.primary.withValues(alpha: 0.7),
                  borderStrokeWidth: 2,
                )).toList(),
              ),
              // 2. Layer Rekam Jejak Rute (Polyline Trail)
              if (_activeRouteTrail.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _activeRouteTrail,
                      strokeWidth: 4.5,
                      color: Colors.blueAccent.withValues(alpha: 0.85),
                      borderColor: Colors.white,
                      borderStrokeWidth: 1.5,
                    ),
                  ],
                ),
              // 3. Layer Markers (Posisi Sendiri, Keluarga, & Ikon Tempat)
              MarkerLayer(markers: [
                ..._buildPlaceMarkers(),
                ..._buildMarkers(),
              ]),
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

          // Live Companion Dashboard Card saat Mode Auto-Follow Aktif (Lengkap dengan Status, Jarak, Kecepatan, Baterai, ETA, & Aksi Cepat)
          if (followedMember != null)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(FamRadius.card),
                  boxShadow: FamColors.softShadow(opacity: 0.25),
                  border: Border.all(color: FamColors.primary.withValues(alpha: 0.3), width: 1.5),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Baris 1: Header Nama, Avatar, Status Denyut, & Tombol Tutup
                    Row(
                      children: [
                        AvatarWithRing(name: followedMember.name, isLive: true, radius: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    followedMember.name,
                                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade50,
                                      borderRadius: BorderRadius.circular(FamRadius.pill),
                                      border: Border.all(color: Colors.green.shade300),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.videocam_rounded, size: 12, color: Colors.green),
                                        SizedBox(width: 3),
                                        Text('Mengikuti Live', style: TextStyle(fontSize: 10.5, color: Colors.green, fontWeight: FontWeight.w700)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                destinationEta ?? 'Pergerakan dipantau realtime',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: destinationEta != null ? FamColors.primary : FamColors.muted,
                                  fontWeight: destinationEta != null ? FontWeight.w700 : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: FamColors.muted, size: 20),
                          tooltip: 'Berhenti Mengikuti',
                          onPressed: () => setState(() => _followingUserId = null),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Baris 2: Metrik Lengkap (Kecepatan, Jarak, Baterai)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(FamRadius.pill),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          // Kecepatan
                          Row(
                            children: [
                              const Icon(Icons.speed_rounded, size: 15, color: FamColors.primary),
                              const SizedBox(width: 4),
                              Text(
                                _formatSpeedText(followedMember.speed),
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                              ),
                            ],
                          ),
                          Container(width: 1, height: 14, color: Colors.black12),
                          // Jarak
                          Row(
                            children: [
                              const Icon(Icons.straighten_rounded, size: 15, color: FamColors.primary),
                              const SizedBox(width: 4),
                              Text(
                                followDistStr ?? 'Menghitung...',
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                              ),
                            ],
                          ),
                          Container(width: 1, height: 14, color: Colors.black12),
                          // Baterai
                          Row(
                            children: [
                              Icon(
                                (followedMember.battery ?? 100) <= 20
                                    ? Icons.battery_alert_rounded
                                    : Icons.battery_charging_full_rounded,
                                size: 15,
                                color: (followedMember.battery ?? 100) <= 20 ? Colors.red : Colors.green,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                '${followedMember.battery ?? "-"}%',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                  color: (followedMember.battery ?? 100) <= 20 ? Colors.red : Colors.green.shade800,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Baris 3: Aksi Cepat (Rute Maps, Telepon, WhatsApp, Deringkan)
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: FamColors.primary,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FamRadius.pill)),
                            ),
                            onPressed: () => launchNavigation(followedMember.lat, followedMember.lng),
                            icon: const Icon(Icons.navigation_rounded, size: 15),
                            label: const Text('Rute Maps', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton.filledTonal(
                          style: IconButton.styleFrom(padding: const EdgeInsets.all(8)),
                          icon: const Icon(Icons.phone_rounded, size: 16, color: Colors.green),
                          tooltip: 'Telepon',
                          onPressed: () => launchCall(followedMember.phone),
                        ),
                        const SizedBox(width: 4),
                        IconButton.filledTonal(
                          style: IconButton.styleFrom(padding: const EdgeInsets.all(8)),
                          icon: const Icon(Icons.chat_bubble_rounded, size: 16, color: Color(0xFF25D366)),
                          tooltip: 'WhatsApp',
                          onPressed: () => launchWhatsApp(followedMember.phone, followedMember.name),
                        ),
                        const SizedBox(width: 4),
                        IconButton.filledTonal(
                          style: IconButton.styleFrom(padding: const EdgeInsets.all(8)),
                          icon: const Icon(Icons.volume_up_rounded, size: 16, color: Colors.amber),
                          tooltip: 'Deringkan HP',
                          onPressed: () async {
                            try {
                              await SupabaseService.triggerRingDevice(targetUserId: followedMember.userId);
                              _showSnack('🔊 Sinyal dering dikirimkan ke HP ${followedMember.name}!');
                            } catch (e) {
                              _showSnack('Gagal kirim dering: $e');
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: followedMember != null ? null : Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. Tombol SOS Darurat Merah
          FloatingActionButton.small(
            heroTag: 'sos_btn',
            backgroundColor: Colors.red.shade600,
            foregroundColor: Colors.white,
            tooltip: 'Sinyal Darurat SOS',
            onPressed: _showSosConfirmation,
            child: const Icon(Icons.sos_rounded, size: 20),
          ),
          const SizedBox(height: 8),

          // 2. Tombol Kabar Kilat (Quick Check-in)
          FloatingActionButton.small(
            heroTag: 'checkin_btn',
            backgroundColor: Colors.amber.shade700,
            foregroundColor: Colors.white,
            tooltip: 'Kabar Kilat',
            onPressed: _showQuickCheckinModal,
            child: const Icon(Icons.mark_chat_unread_rounded, size: 19),
          ),
          const SizedBox(height: 8),

          // 3. Tombol Layer Switcher (Normal/Satelit/Terrain/Malam)
          FloatingActionButton.small(
            heroTag: 'layer_btn',
            backgroundColor: Colors.white,
            foregroundColor: FamColors.textDark,
            tooltip: 'Tampilan Peta',
            onPressed: _showLayerPicker,
            child: const Icon(Icons.layers_outlined),
          ),
          const SizedBox(height: 8),

          // 4. Tombol Zona Aman Bersama
          FloatingActionButton.small(
            heroTag: 'place_btn',
            backgroundColor: Colors.white,
            foregroundColor: FamColors.primary,
            tooltip: 'Zona Aman Bersama (${_places.length})',
            onPressed: _showPlacesManagerSheet,
            child: Badge(
              isLabelVisible: _places.isNotEmpty,
              label: Text('${_places.length}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
              backgroundColor: FamColors.primary,
              child: const Icon(Icons.shield_rounded),
            ),
          ),
          const SizedBox(height: 8),

          // 5. Tombol Pilih Keluarga
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

          // 6. Tombol Posisiku
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
    ));
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

  List<Marker> _buildPlaceMarkers() {
    return _places.map((p) => Marker(
      width: 100, height: 60,
      point: LatLng(p.lat, p.lng),
      child: GestureDetector(
        onTap: _showPlacesManagerSheet,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(FamRadius.pill),
                boxShadow: FamColors.softShadow(opacity: 0.1),
                border: Border.all(color: FamColors.primary, width: 1.5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(p.icon, style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 4),
                  Text(p.name, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ],
        ),
      ),
    )).toList();
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
        onToggleTrail: () => _toggleTrailForUser(f.userId, f.name),
        isTrailActive: _trailUserId == f.userId && _activeRouteTrail.isNotEmpty,
        onRingDevice: () async {
          try {
            await SupabaseService.triggerRingDevice(targetUserId: f.userId);
            _showSnack('🔊 Sinyal dering dikirimkan ke HP ${f.name}!');
          } catch (e) {
            _showSnack('Gagal mengirim dering: $e');
          }
        },
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
    _placesSubscription?.cancel();
    _checkinSubscription?.cancel();
    _ringSubscription?.cancel();
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
  final VoidCallback onToggleTrail;
  final VoidCallback onRingDevice;
  final bool isTrailActive;

  const _FamilyDetailSheet({
    required this.member,
    required this.myPosition,
    required this.onFocus,
    required this.onToggleTrail,
    required this.onRingDevice,
    required this.isTrailActive,
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
          const SizedBox(height: 14),

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
          const SizedBox(height: 16),

          // Pintasan Langsung: Telepon & WhatsApp
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.green.shade800,
                    side: BorderSide(color: Colors.green.shade300),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FamRadius.pill)),
                  ),
                  onPressed: () {
                    _MapHomeScreenState.launchCall(member.phone);
                  },
                  icon: const Icon(Icons.phone_rounded, size: 18, color: Colors.green),
                  label: const Text('Telepon', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF128C7E),
                    side: const BorderSide(color: Color(0xFF25D366)),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FamRadius.pill)),
                  ),
                  onPressed: () {
                    _MapHomeScreenState.launchWhatsApp(member.phone, member.name);
                  },
                  icon: const Icon(Icons.chat_bubble_rounded, size: 18, color: Color(0xFF25D366)),
                  label: const Text('WhatsApp', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Deringkan HP (Cari HP)',
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.amber.shade900,
                    side: BorderSide(color: Colors.amber.shade300),
                    padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FamRadius.pill)),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    onRingDevice();
                  },
                  child: const Icon(Icons.volume_up_rounded, size: 20, color: Colors.amber),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

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
              const SizedBox(width: 8),
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
                    _MapHomeScreenState.launchNavigation(member.lat, member.lng);
                  },
                  icon: const Icon(Icons.navigation_rounded, size: 18),
                  label: const Text('Rute Maps', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FamRadius.pill)),
              side: BorderSide(color: isTrailActive ? Colors.blueAccent : Colors.black12, width: isTrailActive ? 2 : 1),
            ),
            onPressed: () {
              Navigator.pop(context);
              onToggleTrail();
            },
            icon: Icon(isTrailActive ? Icons.route_rounded : Icons.timeline_rounded, color: isTrailActive ? Colors.blueAccent : FamColors.textDark, size: 18),
            label: Text(
              isTrailActive ? 'Sembunyikan Jejak Rute Hari Ini' : '📜 Lihat Jejak Rute Hari Ini',
              style: TextStyle(color: isTrailActive ? Colors.blueAccent : FamColors.textDark, fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}