import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_model.dart';

class AppStateStorage {
  static const _baseUrlKey = 'base_url';
  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';
  static const _userKey = 'user';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<String> getBaseUrl() async {
    final prefs = await _prefs;
    return prefs.getString(_baseUrlKey) ?? 'http://192.168.1.1:8080/api/v1';
  }

  Future<void> setBaseUrl(String value) async {
    final baseUrl = value.trim().replaceAll(RegExp(r'/$'), '');
    await (await _prefs).setString(_baseUrlKey, baseUrl);
  }

  Future<String?> getAccessToken() async => (await _prefs).getString(_accessTokenKey);

  Future<String?> getRefreshToken() async => (await _prefs).getString(_refreshTokenKey);

  Future<void> saveSession({
    required String accessToken,
    required String refreshToken,
    UserModel? user,
  }) async {
    final prefs = await _prefs;
    await prefs.setString(_accessTokenKey, accessToken);
    await prefs.setString(_refreshTokenKey, refreshToken);
    if (user != null) {
      await prefs.setString(_userKey, jsonEncode(user.toJson()));
    }
  }

  Future<void> saveUser(UserModel user) async {
    await (await _prefs).setString(_userKey, jsonEncode(user.toJson()));
  }

  Future<UserModel?> getUser() async {
    final raw = (await _prefs).getString(_userKey);
    if (raw == null) return null;
    return UserModel.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> clearSession() async {
    final prefs = await _prefs;
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_userKey);
  }
}
