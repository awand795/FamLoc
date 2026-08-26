import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Ganti sesuai lingkungan:
///  - Android emulator: http://10.0.2.2:3000/api/v1
///  - Production (Vercel): https://`<project>`.vercel.app/api/v1
const String kApiBase = 'http://10.0.2.2:3000/api/v1';

class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);
  @override
  String toString() => message;
}

class User {
  final String id, email, name, inviteCode;
  final int avatarVersion;
  final bool sharingOn;
  final String locationPrecision;
  User({
    required this.id,
    required this.email,
    required this.name,
    required this.inviteCode,
    required this.avatarVersion,
    required this.sharingOn,
    required this.locationPrecision,
  });

  factory User.fromJson(Map<String, dynamic> j) => User(
        id: j['id'],
        email: j['email'] ?? '',
        name: j['name'],
        inviteCode: j['invite_code'] ?? '',
        avatarVersion: ((j['avatar_version'] ?? 0) as num).toInt(),
        sharingOn: j['sharing_on'] == true,
        locationPrecision: j['location_precision'] ?? 'exact',
      );

  /// URL avatar dengan cache-buster versi; kosong jika belum pernah upload.
  String? get avatarUrl =>
      avatarVersion > 0 ? '$kApiBase/users/$id/avatar?v=$avatarVersion' : null;
}

class FriendLocation {
  final String id, name;
  final double lat, lng;
  final double? accuracy, heading, distanceM;
  final int? battery;
  final bool isMocked, precisionFuzzed;
  final DateTime updatedAt;
  FriendLocation({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    this.accuracy,
    this.heading,
    this.battery,
    required this.isMocked,
    required this.precisionFuzzed,
    required this.updatedAt,
    this.distanceM,
  });

  factory FriendLocation.fromJson(Map<String, dynamic> j) {
    final loc = j['location'];
    return FriendLocation(
      id: j['id'],
      name: j['name'],
      lat: (loc['lat'] as num).toDouble(),
      lng: (loc['lng'] as num).toDouble(),
      accuracy: loc['accuracy'] == null ? null : (loc['accuracy'] as num).toDouble(),
      heading: loc['heading'] == null ? null : (loc['heading'] as num).toDouble(),
      battery: loc['battery'] == null ? null : (loc['battery'] as num).toInt(),
      isMocked: loc['is_mocked'] == true,
      precisionFuzzed: j['precision_fuzzed'] == true,
      updatedAt: DateTime.parse(loc['updated_at']),
      distanceM: j['distance_m'] == null ? null : (j['distance_m'] as num).toDouble(),
    );
  }
}

class Friend {
  final String id, name;
  final int avatarVersion;
  final bool sharingOn;
  final FriendLocation? location;
  Friend({required this.id, required this.name, required this.avatarVersion, required this.sharingOn, this.location});
  factory Friend.fromJson(Map<String, dynamic> j) => Friend(
        id: j['id'],
        name: j['name'],
        avatarVersion: ((j['avatar_version'] ?? 0) as num).toInt(),
        sharingOn: j['sharing_on'] == true,
        location: j['location'] == null
            ? null
            : FriendLocation.fromJson({
                'id': j['id'], 'name': j['name'], 'location': j['location'],
                'precision_fuzzed': false, 'distance_m': null,
              }),
      );
}

class FamNotification {
  final String refId, type, userId, name;
  final int avatarVersion;
  final DateTime createdAt;
  FamNotification({required this.refId, required this.type, required this.userId,
      required this.name, required this.avatarVersion, required this.createdAt});
  factory FamNotification.fromJson(Map<String, dynamic> j) => FamNotification(
        refId: j['ref_id'], type: j['type'], userId: j['user_id'],
        name: j['name'], avatarVersion: ((j['avatar_version'] ?? 0) as num).toInt(),
        createdAt: DateTime.parse(j['created_at']),
      );
}

class ApiClient {
  static String? _token;

  static Future<void> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('famloc_token');
  }

  static Future<bool> hasToken() async => _token != null && _token!.isNotEmpty;

  static Future<void> saveToken(String token) async {
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('famloc_token', token);
  }

  static Future<void> clearToken() async {
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('famloc_token');
  }

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  static Future<Map<String, dynamic>> _send(
    String method,
    String path,
    Map<String, dynamic>? body,
  ) async {
    final uri = Uri.parse('$kApiBase$path');
    late http.Response resp;
    switch (method) {
      case 'POST':
        resp = await http.post(uri, headers: _headers, body: jsonEncode(body ?? {}));
        break;
      case 'PUT':
        resp = await http.put(uri, headers: _headers, body: jsonEncode(body ?? {}));
        break;
      case 'PATCH':
        resp = await http.patch(uri, headers: _headers, body: jsonEncode(body ?? {}));
        break;
      case 'DELETE':
        resp = await http.delete(uri, headers: _headers);
        break;
      default:
        resp = await http.get(uri, headers: _headers);
    }
    final decoded = resp.body.isEmpty ? {} : jsonDecode(resp.body);
    if (resp.statusCode >= 400) {
      throw ApiException(resp.statusCode, decoded['error'] ?? 'Terjadi kesalahan');
    }
    return (decoded as Map).cast<String, dynamic>();
  }

  // ---- Auth ----
  static Future<(User, String)> register(String name, String email, String password) async {
    final r = await _send('POST', '/auth/register',
        {'name': name, 'email': email, 'password': password});
    await saveToken(r['token']);
    return (User.fromJson(r['user']), r['token'] as String);
  }

  static Future<User> login(String email, String password) async {
    final r = await _send('POST', '/auth/login', {'email': email, 'password': password});
    await saveToken(r['token']);
    return User.fromJson(r['user']);
  }

  // ---- Me ----
  static Future<User> me() async {
    final r = await _send('GET', '/me', null);
    return User.fromJson(r['user']);
  }

  static Future<bool> setSharing(bool on) async {
    final r = await _send('PATCH', '/me/sharing', {'sharing_on': on});
    return r['sharing_on'] == true;
  }

  static Future<void> setPrecision(String mode) =>
      _send('PATCH', '/me/precision', {'mode': mode});

  static Future<void> changePassword(String oldPw, String newPw) =>
      _send('PATCH', '/me/password', {'old_password': oldPw, 'new_password': newPw});

  static Future<void> uploadAvatar(List<int> jpegBytes) => _send('PUT', '/me/avatar',
      {'image_base64': base64Encode(jpegBytes)});

  // ---- Friends ----
  static Future<void> sendFriendRequest({String? inviteCode}) =>
      _send('POST', '/friends/request', inviteCode != null ? {'invite_code': inviteCode} :
          throw ArgumentError('inviteCode wajib di MVP'));

  static Future<List<Friend>> friends() async {
    final r = await _send('GET', '/friends', null);
    return (r['friends'] as List).map((e) => Friend.fromJson(e)).toList();
  }

  static Future<List<FriendLocation>> friendLocations() async {
    final r = await _send('GET', '/friends/locations', null);
    return (r['friends'] as List).map((e) => FriendLocation.fromJson(e)).toList();
  }

  static Future<void> unfriend(String userId) => _send('DELETE', '/friends/$userId', null);

  static Future<List<FamNotification>> notifications() async {
    final r = await _send('GET', '/notifications', null);
    return (r['notifications'] as List).map((e) => FamNotification.fromJson(e)).toList();
  }

  static Future<void> respondFriendRequest(String requestId, String action) =>
      _send('POST', '/friend-requests/respond', {'request_id': requestId, 'action': action});

  static Future<void> respondLocationRequest(String rid, String action) =>
      _send('POST', '/location-requests/$rid', {'action': action});

  static Future<void> requestLocation(String friendId) =>
      _send('POST', '/friends/$friendId/location-request', {});

  // ---- Locations ----
  static Future<void> pushLocation({
    required double lat,
    required double lng,
    double? accuracy,
    double? heading,
    int? battery,
    bool isMocked = false,
  }) =>
      _send('POST', '/locations', {
        'lat': lat, 'lng': lng, 'accuracy': accuracy, 'heading': heading,
        'battery': battery, 'is_mocked': isMocked,
      });
}
