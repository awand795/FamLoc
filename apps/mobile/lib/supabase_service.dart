import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const String kSupabaseUrl = 'https://wcqxtwdbgxmcojllntuh.supabase.co';
const String kSupabasePublishableKey = 'sb_publishable_OzRbMlLljxLOWWZ3qVpk0A_Nef52nid';

class UserProfile {
  final String id;
  final String name;
  final String email;
  final String? avatarUrl;
  final bool sharingOn;

  UserProfile({
    required this.id,
    required this.name,
    required this.email,
    this.avatarUrl,
    required this.sharingOn,
  });

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      avatarUrl: map['avatar_url'],
      sharingOn: map['sharing_on'] == true,
    );
  }
}

class FamilyMemberLocation {
  final String userId;
  final String name;
  final String? avatarUrl;
  final double lat;
  final double lng;
  final double? accuracy;
  final double? heading;
  final int? battery;
  final bool isMocked;
  final DateTime updatedAt;

  FamilyMemberLocation({
    required this.userId,
    required this.name,
    this.avatarUrl,
    required this.lat,
    required this.lng,
    this.accuracy,
    this.heading,
    this.battery,
    required this.isMocked,
    required this.updatedAt,
  });

  factory FamilyMemberLocation.fromMap(Map<String, dynamic> map, {String? fallbackName, String? fallbackAvatar}) {
    final profile = map['profiles'] as Map<String, dynamic>?;
    return FamilyMemberLocation(
      userId: map['user_id'] ?? '',
      name: profile?['name'] ?? fallbackName ?? 'Keluarga',
      avatarUrl: profile?['avatar_url'] ?? fallbackAvatar,
      lat: (map['lat'] as num).toDouble(),
      lng: (map['lng'] as num).toDouble(),
      accuracy: map['accuracy'] == null ? null : (map['accuracy'] as num).toDouble(),
      heading: map['heading'] == null ? null : (map['heading'] as num).toDouble(),
      battery: map['battery'] == null ? null : (map['battery'] as num).toInt(),
      isMocked: map['is_mocked'] == true,
      updatedAt: map['updated_at'] != null ? DateTime.parse(map['updated_at']) : DateTime.now(),
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
      name: user.userMetadata?['name'] ?? user.email?.split('@').first ?? 'Saya',
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
      'battery': battery,
      'is_mocked': isMocked,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  static Future<List<FamilyMemberLocation>> getFamilyLocations() async {
    final myId = currentUser?.id;
    if (myId == null) return [];

    // Ambil daftar teman yang terhubung
    final friends = await getFriends();
    final friendIds = friends.map((f) => f.id).toList();

    // Query lokasi
    final res = await client
        .from('user_locations')
        .select('*, profiles(name, avatar_url, sharing_on)');

    final list = <FamilyMemberLocation>[];
    for (final row in (res as List)) {
      final profile = row['profiles'] as Map<String, dynamic>?;
      final sharingOn = profile?['sharing_on'] ?? true;
      final rowUserId = row['user_id'];

      // Tampilkan jika sharing aktif, bukan diri sendiri, dan (jika ada teman terdaftar) masuk dalam daftar teman
      if (sharingOn && rowUserId != myId) {
        if (friendIds.isEmpty || friendIds.contains(rowUserId)) {
          list.add(FamilyMemberLocation.fromMap(row));
        }
      }
    }
    return list;
  }

  /// Listen realtime stream Postgres Changes via WebSocket
  static Stream<List<Map<String, dynamic>>> streamLocations() {
    return client.from('user_locations').stream(primaryKey: ['user_id']);
  }
}
