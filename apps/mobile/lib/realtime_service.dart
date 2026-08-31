import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'api_client.dart';

class RealtimeService {
  static final RealtimeService _instance = RealtimeService._internal();
  factory RealtimeService() => _instance;
  RealtimeService._internal();

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  bool _isConnected = false;
  bool _isDisposed = false;

  final _friendLocationController = StreamController<FriendLocation>.broadcast();
  Stream<FriendLocation> get onFriendLocation => _friendLocationController.stream;

  final _connectionStateController = StreamController<bool>.broadcast();
  Stream<bool> get onConnectionState => _connectionStateController.stream;

  bool get isConnected => _isConnected;

  String get _wsUrl {
    final token = ApiClient.token ?? '';
    final base = kApiBase.replaceAll(RegExp(r'/api/v1/?$'), '');
    final isSecure = base.startsWith('https://');
    final cleanHost = base.replaceFirst(RegExp(r'^https?://'), '');
    final scheme = isSecure ? 'wss' : 'ws';
    return '$scheme://$cleanHost/ws?token=$token';
  }

  void connect() {
    _isDisposed = false;
    if (_isConnected || _channel != null) return;
    final token = ApiClient.token;
    if (token == null || token.isEmpty) return;

    try {
      final uri = Uri.parse(_wsUrl);
      _channel = WebSocketChannel.connect(uri);

      _subscription = _channel!.stream.listen(
        (message) {
          _onMessage(message);
        },
        onDone: () {
          _handleDisconnect();
        },
        onError: (err) {
          debugPrint('WebSocket error: $err');
          _handleDisconnect();
        },
        cancelOnError: true,
      );

      _isConnected = true;
      _connectionStateController.add(true);
      _startHeartbeat();
    } catch (e) {
      debugPrint('WebSocket connect exception: $e');
      _handleDisconnect();
    }
  }

  void _onMessage(dynamic raw) {
    try {
      final data = jsonDecode(raw.toString()) as Map<String, dynamic>;
      final type = data['type'];

      if (type == 'friend:location_updated') {
        final payload = data['payload'] as Map<String, dynamic>;
        final friendLoc = FriendLocation.fromJson(payload);
        _friendLocationController.add(friendLoc);
      }
    } catch (e) {
      debugPrint('Error parsing WS message: $e');
    }
  }

  void sendLocation({
    required double lat,
    required double lng,
    double? accuracy,
    double? heading,
    int? battery,
    bool isMocked = false,
  }) {
    if (!_isConnected || _channel == null) return;

    final msg = jsonEncode({
      'type': 'location:update',
      'payload': {
        'lat': lat,
        'lng': lng,
        'accuracy': accuracy,
        'heading': heading,
        'battery': battery,
        'is_mocked': isMocked,
      },
    });

    try {
      _channel?.sink.add(msg);
    } catch (e) {
      debugPrint('Error sending location via WS: $e');
    }
  }

  void _startHeartbeat() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      if (_isConnected && _channel != null) {
        try {
          _channel?.sink.add(jsonEncode({'type': 'ping'}));
        } catch (_) {}
      }
    });
  }

  void _handleDisconnect() {
    _isConnected = false;
    _connectionStateController.add(false);
    _pingTimer?.cancel();
    _subscription?.cancel();
    _subscription = null;
    _channel = null;

    if (!_isDisposed) {
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(const Duration(seconds: 4), () {
        if (!_isDisposed) connect();
      });
    }
  }

  void disconnect() {
    _isDisposed = true;
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
    _isConnected = false;
    _connectionStateController.add(false);
  }
}
