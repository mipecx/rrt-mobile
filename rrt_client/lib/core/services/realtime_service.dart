import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'app_state.dart';

class RealtimeService {
  RealtimeService(this._storage);

  final AppStateStorage _storage;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;

  Future<void> connect({
    required void Function(String type, Map<String, dynamic>? data) onEvent,
  }) async {
    await disconnect();
    final baseUrl = await _storage.getBaseUrl();
    final socketUrl = baseUrl.replaceFirst(RegExp(r'^http'), 'ws').replaceFirst('/api/v1', '/api/v1/ws');
    _channel = WebSocketChannel.connect(Uri.parse(socketUrl));
    _subscription = _channel!.stream.listen((message) {
      if (message is! String) return;
      try {
        final json = jsonDecode(message) as Map<String, dynamic>;
        onEvent(json['type']?.toString() ?? '', json['data'] as Map<String, dynamic>?);
      } on FormatException {
        return;
      }
    });
  }

  void sendRrtUpdate({
    required String id,
    required String name,
    required String status,
    required double lat,
    required double lng,
  }) {
    _channel?.sink.add(jsonEncode({
      'type': 'RRT_UPDATE',
      'data': {
        'id': id,
        'name': name,
        'status': status,
        'lat': lat,
        'lng': lng,
      },
    }));
  }

  Future<void> disconnect() async {
    await _subscription?.cancel();
    await _channel?.sink.close();
    _subscription = null;
    _channel = null;
  }
}
