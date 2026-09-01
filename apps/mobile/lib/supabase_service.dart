import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const String kSupabaseUrl = 'https://wcqxtwdbgxmcojllntuh.supabase.co';
const String kSupabasePublishableKey = 'sb_publishable_OzRbMlLljxLOWWZ3qVpk0A_Nef52nid';

class UserProfile {
  final String id;
  final String name;
  final String email;
  final String? phone;
  final String? avatarUrl;
  final bool sharingOn;

  UserProfile({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    this.avatarUrl,
    required this.sharingOn,
  });

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      phone: map['phone'],
      avatarUrl: map['avatar_url'],
      sharingOn: map['sharing_on'] == true,
    );
  }
}

class FamilyMemberLocation {
  final String userId;
  final String name;
  final String? phone;
  final String? avatarUrl;
  final double lat;
  final double lng;
  final double? accuracy;
  final double? heading;
  final double? speed; // in km/h
  final int? battery;
  final bool isMocked;
  final DateTime updatedAt;

  FamilyMemberLocation({
    required this.userId,
    required this.name,
    this.phone,
    this.avatarUrl,
    required this.lat,
    required this.lng,
    this.accuracy,
    this.heading,
    this.speed,
    this.battery,
    required this.isMocked,
    required this.updatedAt,
  });

  factory FamilyMemberLocation.fromMap(Map<String, dynamic> map, {String? fallbackName, String? fallbackAvatar}) {
    final profile = map['profiles'] as Map<String, dynamic>?;
    return FamilyMemberLocation(
      userId: map['user_id'] ?? '',
      name: profile?['name'] ?? fallbackName ?? 'Keluarga',
      phone: profile?['phone'],
      avatarUrl: profile?['avatar_url'] ?? fallbackAvatar,
      lat: (map['lat'] as num).toDouble(),
      lng: (map['lng'] as num).toDouble(),
      accuracy: map['accuracy'] == null ? null : (map['accuracy'] as num).toDouble(),
      heading: map['heading'] == null ? null : (map['heading'] as num).toDouble(),
      speed: map['speed'] == null ? null : (map['speed'] as num).toDouble(),
      battery: map['battery'] == null ? null : (map['battery'] as num).toInt(),
      isMocked: map['is_mocked'] == true,
      updatedAt: map['updated_at'] != null ? DateTime.parse(map['updated_at']) : DateTime.now(),
    );
  }
}

class SosAlert {
  final String id;
  final String userId;
  final String name;
  final String? avatarUrl;
  final double lat;
  final double lng;
  final int? battery;
  final bool isActive;
  final DateTime createdAt;

  SosAlert({
    required this.id,
    required this.userId,
    required this.name,
    this.avatarUrl,
    required this.lat,
    required this.lng,
    this.battery,
    required this.isActive,
    required this.createdAt,
  });

  factory SosAlert.fromMap(Map<String, dynamic> map) {
    final profile = map['profiles'] as Map<String, dynamic>?;
    return SosAlert(
      id: map['id'] ?? '',
      userId: map['user_id'] ?? '',
      name: profile?['name'] ?? 'Anggota Keluarga',
      avatarUrl: profile?['avatar_url'],
      lat: (map['lat'] as num).toDouble(),
      lng: (map['lng'] as num).toDouble(),
      battery: map['battery'] == null ? null : (map['battery'] as num).toInt(),
      isActive: map['is_active'] == true,
      createdAt: map['created_at'] != null ? DateTime.parse(map['created_at']) : DateTime.now(),
    );
  }
}

class PlaceZone {
  final String id;
  final String userId;
  final String? creatorName;
  final String name;
  final String icon;
  final double lat;
  final double lng;
  final double radius;
  final DateTime createdAt;

  PlaceZone({
    required this.id,
    required this.userId,
    this.creatorName,
    required this.name,
    required this.icon,
    required this.lat,
    required this.lng,
    required this.radius,
    required this.createdAt,
  });

  factory PlaceZone.fromMap(Map<String, dynamic> map) {
    final profile = map['profiles'] as Map<String, dynamic>?;
    return PlaceZone(
      id: map['id'] ?? '',
      userId: map['user_id'] ?? '',
      creatorName: profile?['name'],
      name: map['name'] ?? 'Tempat',
      icon: map['icon'] ?? '🏠',
      lat: (map['lat'] as num).toDouble(),
      lng: (map['lng'] as num).toDouble(),
      radius: (map['radius'] as num?)?.toDouble() ?? 150.0,
      createdAt: map['created_at'] != null ? DateTime.parse(map['created_at']) : DateTime.now(),
    );
  }
}

class QuickCheckin {
  final String id;
  final String userId;
  final String name;
  final String? avatarUrl;
  final String message;
  final String icon;
  final double lat;
  final double lng;
  final DateTime createdAt;

  QuickCheckin({
    required this.id,
    required this.userId,
    required this.name,
    this.avatarUrl,
    required this.message,
    required this.icon,
    required this.lat,
    required this.lng,
    required this.createdAt,
  });

  factory QuickCheckin.fromMap(Map<String, dynamic> map) {
    final profile = map['profiles'] as Map<String, dynamic>?;
    return QuickCheckin(
      id: map['id'] ?? '',
      userId: map['user_id'] ?? '',
      name: profile?['name'] ?? 'Keluarga',
      avatarUrl: profile?['avatar_url'],
      message: map['message'] ?? '',
      icon: map['icon'] ?? '💬',
      lat: (map['lat'] as num).toDouble(),
      lng: (map['lng'] as num).toDouble(),
      createdAt: map['created_at'] != null ? DateTime.parse(map['created_at']) : DateTime.now(),
    );
  }
}

class RingAlert {
  final String id;
  final String targetUserId;
  final String senderName;
  final bool isActive;
  final DateTime createdAt;

  RingAlert({
    required this.id,
    required this.targetUserId,
    required this.senderName,
    required this.isActive,
    required this.createdAt,
  });

  factory RingAlert.fromMap(Map<String, dynamic> map) {
    return RingAlert(
      id: map['id'] ?? '',
      targetUserId: map['target_user_id'] ?? '',
      senderName: map['sender_name'] ?? 'Keluargamu',
      isActive: map['is_active'] == true,
      createdAt: map['created_at'] != null ? DateTime.parse(map['created_at']) : DateTime.now(),
    );
  }
}

class SupabaseService {
  static SupabaseClient get client => Supabase.instance.client;

  static User? get currentUser => client.auth.currentUser;
  static bool get isLoggedIn => client.auth.currentSession != null;

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: kSupabaseUrl,
      publishableKey: kSupabasePublishableKey,
      realtimeClientOptions: const RealtimeClientOptions(
        eventsPerSecond: 10,
      ),
    );
  }

  // ---- Auth ----
  static Future<AuthResponse> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    final res = await client.auth.signUp(
      email: email,
      password: password,
      data: {'name': name},
    );
    return res;
  }

  static Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    final res = await client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    return res;
  }

  static Future<void> signOut() async {
    await client.auth.signOut();
  }

  // ---- Profile ----
  static Future<UserProfile?> getMyProfile() async {
    final user = currentUser;
    if (user == null) return null;
    try {
      var res = await client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (res == null) {
        final name = user.userMetadata?['name'] ?? user.email?.split('@').first ?? 'Saya';
        await client.from('profiles').upsert({
          'id': user.id,
          'name': name,
          'email': user.email ?? '',
          'sharing_on': true,
        });
        res = await client.from('profiles').select().eq('id', user.id).maybeSingle();
      }

      if (res != null) {
        return UserProfile.fromMap(res);
      }
    } catch (_) {}

    return UserProfile(
      id: user.id,
      name: user.userMetadata?['name'] ?? 'Saya',
      email: user.email ?? '',
      sharingOn: true,
    );
  }

  static Future<void> updateSharing(bool on) async {
    final user = currentUser;
    if (user == null) return;
    await client.from('profiles').update({'sharing_on': on}).eq('id', user.id);
  }

  static Future<void> updateName(String name) async {
    final user = currentUser;
    if (user == null) return;
    await client.from('profiles').update({'name': name}).eq('id', user.id);
  }

  static Future<void> updatePhone(String phone) async {
    final user = currentUser;
    if (user == null) return;
    await client.from('profiles').update({'phone': phone}).eq('id', user.id);
  }

  static Future<String?> uploadAvatar(List<int> bytes) async {
    final user = currentUser;
    if (user == null) return null;
    final path = '${user.id}/avatar.jpg';
    await client.storage.from('avatars').uploadBinary(
          path,
          Uint8List.fromList(bytes),
          fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'),
        );
    final publicUrl = client.storage.from('avatars').getPublicUrl(path);
    await client.from('profiles').update({'avatar_url': publicUrl}).eq('id', user.id);
    return publicUrl;
  }

  // ---- Friends / Family Management ----
  static Future<List<UserProfile>> getFriends() async {
    final user = currentUser;
    if (user == null) return [];

    final res = await client
        .from('friendships')
        .select('user_id_a, user_id_b')
        .or('user_id_a.eq.${user.id},user_id_b.eq.${user.id}');

    final friendIds = <String>[];
    for (final row in (res as List)) {
      final a = row['user_id_a'] as String;
      final b = row['user_id_b'] as String;
      friendIds.add(a == user.id ? b : a);
    }

    if (friendIds.isEmpty) return [];

    final profilesRes = await client
        .from('profiles')
        .select()
        .filter('id', 'in', friendIds);

    return (profilesRes as List).map((p) => UserProfile.fromMap(p)).toList();
  }

  static Future<void> addFriendByEmail(String email) async {
    final user = currentUser;
    if (user == null) throw Exception('Silakan login terlebih dahulu');

    final cleanEmail = email.trim().toLowerCase();
    if (cleanEmail == (user.email ?? '').toLowerCase()) {
      throw Exception('Tidak bisa menambahkan diri sendiri');
    }

    final targetProfile = await client
        .from('profiles')
        .select()
        .ilike('email', cleanEmail)
        .maybeSingle();

    if (targetProfile == null) {
      throw Exception('Pengguna dengan email $cleanEmail belum terdaftar');
    }

    final targetId = targetProfile['id'] as String;
    final idA = user.id.compareTo(targetId) < 0 ? user.id : targetId;
    final idB = user.id.compareTo(targetId) < 0 ? targetId : user.id;

    await client.from('friendships').upsert({
      'user_id_a': idA,
      'user_id_b': idB,
    });
  }

  static Future<void> removeFriend(String friendId) async {
    final user = currentUser;
    if (user == null) return;

    final idA = user.id.compareTo(friendId) < 0 ? user.id : friendId;
    final idB = user.id.compareTo(friendId) < 0 ? friendId : user.id;

    await client
        .from('friendships')
        .delete()
        .match({'user_id_a': idA, 'user_id_b': idB});
  }

  // ---- Location Operations ----
  static Future<void> pushLocation({
    required double lat,
    required double lng,
    double? accuracy,
    double? heading,
    double? speed,
    int? battery,
    bool isMocked = false,
  }) async {
    final user = currentUser;
    if (user == null) return;

    await client.from('user_locations').upsert({
      'user_id': user.id,
      'lat': lat,
      'lng': lng,
      'accuracy': accuracy,
      'heading': heading,
      'speed': speed,
      'battery': battery,
      'is_mocked': isMocked,
      'updated_at': DateTime.now().toIso8601String(),
    });

    // Catat jejak perjalanan (Location History) jika bergerak
    try {
      await client.from('location_history').insert({
        'user_id': user.id,
        'lat': lat,
        'lng': lng,
        'speed': speed,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
  }

  static Future<List<FamilyMemberLocation>> getFamilyLocations() async {
    final myId = currentUser?.id;
    if (myId == null) return [];

    final friends = await getFriends();
    final friendIds = friends.map((f) => f.id).toList();

    final res = await client
        .from('user_locations')
        .select('*, profiles(name, phone, avatar_url, sharing_on)');

    final list = <FamilyMemberLocation>[];
    for (final row in (res as List)) {
      final profile = row['profiles'] as Map<String, dynamic>?;
      final sharingOn = profile?['sharing_on'] ?? true;
      final rowUserId = row['user_id'];

      if (sharingOn && rowUserId != myId) {
        if (friendIds.isEmpty || friendIds.contains(rowUserId)) {
          list.add(FamilyMemberLocation.fromMap(row));
        }
      }
    }
    return list;
  }

  /// Ambil jejak rute hari ini untuk pengguna tertentu
  static Future<List<LatLng>> getLocationHistoryToday(String userId) async {
    final todayStart = DateTime.now();
    final startOfDay = DateTime(todayStart.year, todayStart.month, todayStart.day).toIso8601String();

    try {
      final res = await client
          .from('location_history')
          .select('lat, lng')
          .eq('user_id', userId)
          .gte('created_at', startOfDay)
          .order('created_at', ascending: true)
          .limit(300);

      return (res as List)
          .map((row) => LatLng((row['lat'] as num).toDouble(), (row['lng'] as num).toDouble()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Listen realtime stream Postgres Changes via WebSocket
  static Stream<List<Map<String, dynamic>>> streamLocations() {
    return client.from('user_locations').stream(primaryKey: ['user_id']);
  }

  // ---- SOS Emergency Operations ----
  static Future<void> triggerSos({
    required double lat,
    required double lng,
    int? battery,
  }) async {
    final user = currentUser;
    if (user == null) return;
    await client.from('sos_alerts').insert({
      'user_id': user.id,
      'lat': lat,
      'lng': lng,
      'battery': battery,
      'is_active': true,
    });
  }

  static Future<void> cancelSos() async {
    final user = currentUser;
    if (user == null) return;
    await client
        .from('sos_alerts')
        .update({'is_active': false})
        .eq('user_id', user.id);
  }

  static Future<List<SosAlert>> getActiveSosAlerts() async {
    final myId = currentUser?.id;
    if (myId == null) return [];
    final friends = await getFriends();
    final friendIds = friends.map((f) => f.id).toList();

    final res = await client
        .from('sos_alerts')
        .select('*, profiles(name, avatar_url)')
        .eq('is_active', true)
        .order('created_at', ascending: false);

    final list = <SosAlert>[];
    for (final row in (res as List)) {
      final uid = row['user_id'] as String;
      if (uid != myId) {
        if (friendIds.isEmpty || friendIds.contains(uid)) {
          list.add(SosAlert.fromMap(row));
        }
      }
    }
    return list;
  }

  static Stream<List<Map<String, dynamic>>> streamSosAlerts() {
    return client.from('sos_alerts').stream(primaryKey: ['id']);
  }

  // ---- Places & Geofencing ----
  static Future<void> createPlace({
    required String name,
    required String icon,
    required double lat,
    required double lng,
    double radius = 150.0,
  }) async {
    final user = currentUser;
    if (user == null) return;
    await client.from('places').insert({
      'user_id': user.id,
      'name': name,
      'icon': icon,
      'lat': lat,
      'lng': lng,
      'radius': radius,
    });
  }

  static Future<List<PlaceZone>> getPlaces() async {
    try {
      final res = await client
          .from('places')
          .select('*, profiles(name)')
          .order('created_at', ascending: false);
      return (res as List).map((p) => PlaceZone.fromMap(p)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> deletePlace(String id) async {
    await client.from('places').delete().eq('id', id);
  }

  static Stream<List<Map<String, dynamic>>> streamPlaces() {
    return client.from('places').stream(primaryKey: ['id']);
  }

  // ---- Quick Check-in ----
  static Future<void> sendQuickCheckin({
    required String message,
    required String icon,
    required double lat,
    required double lng,
  }) async {
    final user = currentUser;
    if (user == null) return;
    await client.from('quick_checkins').insert({
      'user_id': user.id,
      'message': message,
      'icon': icon,
      'lat': lat,
      'lng': lng,
    });
  }

  static Future<List<QuickCheckin>> getRecentCheckins() async {
    final myId = currentUser?.id;
    if (myId == null) return [];
    try {
      final res = await client
          .from('quick_checkins')
          .select('*, profiles(name, avatar_url)')
          .order('created_at', ascending: false)
          .limit(10);
      return (res as List).map((c) => QuickCheckin.fromMap(c)).toList();
    } catch (_) {
      return [];
    }
  }

  static Stream<List<Map<String, dynamic>>> streamQuickCheckins() {
    return client.from('quick_checkins').stream(primaryKey: ['id']);
  }

  // ---- Deringkan HP / Cari HP ----
  static Future<void> triggerRingDevice({required String targetUserId}) async {
    final user = currentUser;
    if (user == null) return;
    final myProfile = await getMyProfile();
    await client.from('ring_alerts').insert({
      'target_user_id': targetUserId,
      'sender_name': myProfile?.name ?? 'Keluargamu',
      'is_active': true,
    });
  }

  static Future<void> cancelRingAlert(String id) async {
    await client.from('ring_alerts').update({'is_active': false}).eq('id', id);
  }

  static Stream<List<Map<String, dynamic>>> streamRingAlerts() {
    return client.from('ring_alerts').stream(primaryKey: ['id']);
  }

  static Future<List<RingAlert>> getActiveRingAlertsForMe() async {
    final user = currentUser;
    if (user == null) return [];
    try {
      final res = await client
          .from('ring_alerts')
          .select()
          .eq('target_user_id', user.id)
          .eq('is_active', true)
          .order('created_at', ascending: false);
      return (res as List).map((r) => RingAlert.fromMap(r)).toList();
    } catch (_) {
      return [];
    }
  }
}
