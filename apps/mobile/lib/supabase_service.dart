import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const String kSupabaseUrl = 'https://wcqxtwdbgxmcojllntuh.supabase.co';
const String kSupabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndjcXh0d2RiZ3htY29qbGxudHVoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODgxNTU3NDQsImV4cCI6MjEwMzczMTc0NH0.lAUGMKhsXBOc0ItvhxnPVm8RW_Pc21VoiG6FCIRTHPI';

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
      publishableKey: kSupabaseAnonKey,
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
    final res = await client
        .from('profiles')
        .select()
        .eq('id', user.id)
        .maybeSingle();
    if (res == null) return null;
    return UserProfile.fromMap(res);
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
    final res = await client
        .from('user_locations')
        .select('*, profiles(name, avatar_url, sharing_on)');

    final list = <FamilyMemberLocation>[];
    for (final row in (res as List)) {
      final profile = row['profiles'] as Map<String, dynamic>?;
      final sharingOn = profile?['sharing_on'] ?? true;
      // Jangan tampilkan jika sharing dimatikan atau jika itu diri sendiri
      if (sharingOn && row['user_id'] != myId) {
        list.add(FamilyMemberLocation.fromMap(row));
      }
    }
    return list;
  }

  /// Listen realtime stream Postgres Changes via WebSocket
  static Stream<List<Map<String, dynamic>>> streamLocations() {
    return client.from('user_locations').stream(primaryKey: ['user_id']);
  }
}
