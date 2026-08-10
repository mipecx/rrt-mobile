import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_state.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException(this.message, [this.statusCode]);

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient(this.storage);

  final AppStateStorage storage;

  Future<dynamic> get(String path, {bool authenticated = true}) {
    return _request('GET', path, authenticated: authenticated);
  }

  Future<dynamic> post(
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = false,
  }) {
    return _request('POST', path, body: body, authenticated: authenticated);
  }

  Future<dynamic> put(
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = true,
  }) {
    return _request('PUT', path, body: body, authenticated: authenticated);
  }

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    required bool authenticated,
    bool retried = false,
  }) async {
    final baseUrl = await storage.getBaseUrl();
    final uri = Uri.parse('$baseUrl$path');
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (authenticated) {
      final token = await storage.getAccessToken();
      if (token != null) headers['Authorization'] = 'Bearer $token';
    }

    http.Response response;
    try {
      final encodedBody = body == null ? null : jsonEncode(body);
      response = switch (method) {
        'GET' => await http.get(uri, headers: headers),
        'POST' => await http.post(uri, headers: headers, body: encodedBody),
        'PUT' => await http.put(uri, headers: headers, body: encodedBody),
        _ => throw ApiException('Unsupported HTTP method: $method'),
      };
    } on Exception catch (error) {
      throw ApiException('Network error: $error');
    }

    if (response.statusCode == 401 && authenticated && !retried) {
      final refreshed = await _refreshTokens();
      if (refreshed) {
        return _request(
          method,
          path,
          body: body,
          authenticated: authenticated,
          retried: true,
        );
      }
    }

    dynamic data;
    if (response.body.isNotEmpty) {
      try {
        data = jsonDecode(response.body);
      } on FormatException {
        data = response.body;
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = data is Map<String, dynamic>
          ? (data['detail'] ?? data['message'] ?? data['error'] ?? 'Request failed')
          : 'Request failed';
      throw ApiException(message.toString(), response.statusCode);
    }
    return data;
  }

  Future<bool> _refreshTokens() async {
    final refreshToken = await storage.getRefreshToken();
    if (refreshToken == null) return false;
    try {
      final data = await post(
        '/auth/refresh',
        body: {'refresh_token': refreshToken},
      ) as Map<String, dynamic>;
      final accessToken = data['access_token'] as String?;
      final nextRefreshToken = data['refresh_token'] as String?;
      if (accessToken == null || nextRefreshToken == null) return false;
      await storage.saveSession(
        accessToken: accessToken,
        refreshToken: nextRefreshToken,
      );
      return true;
    } on ApiException {
      await storage.clearSession();
      return false;
    }
  }
}
