import 'dart:convert';

import '../models/user_model.dart';
import 'api_client.dart';
import 'app_state.dart';

class AuthService {
  AuthService(this._client, this._storage);

  final ApiClient _client;
  final AppStateStorage _storage;

  Future<void> sendOtp(String phone) async {
    await _client.post('/auth/send-otp', body: {'phone': phone});
  }

  Future<UserModel> login(String phone, String password) async {
    final data = await _client.post(
      '/auth/login',
      body: {'phone': phone, 'password': password},
    ) as Map<String, dynamic>;
    await _saveTokens(data);
    return loadProfile();
  }

  Future<UserModel> register({
    required String phone,
    required String code,
    required String password,
    required String fullName,
    required String role,
  }) async {
    final data = await _client.post(
      '/auth/register',
      body: {
        'phone': phone,
        'code': code,
        'password': password,
        'full_name': fullName,
        'role': role,
      },
    ) as Map<String, dynamic>;
    await _saveTokens(data);
    return loadProfile();
  }

  Future<UserModel> loadProfile() async {
    final data = await _client.get('/me') as Map<String, dynamic>;
    final userData = data['user'] is Map<String, dynamic> ? data['user'] : data;
    final profile = UserModel.fromJson(userData as Map<String, dynamic>);
    final savedUser = await _storage.getUser();
    final tokenUser = _userFromToken(await _storage.getAccessToken());
    final fallbackUser = savedUser?.id.isNotEmpty == true ? savedUser : tokenUser;
    final user = UserModel(
      id: profile.id.isNotEmpty ? profile.id : fallbackUser?.id ?? '',
      phone: profile.phone.isNotEmpty ? profile.phone : fallbackUser?.phone ?? '',
      fullName: profile.fullName.isNotEmpty ? profile.fullName : fallbackUser?.fullName ?? '',
      role: profile.role != 'tourist' || fallbackUser == null ? profile.role : fallbackUser.role,
    );
    await _storage.saveUser(user);
    return user;
  }

  Future<UserModel?> storedUser() => _storage.getUser();

  Future<bool> hasSession() async => (await _storage.getAccessToken()) != null;

  Future<void> logout() => _storage.clearSession();

  Future<void> _saveTokens(Map<String, dynamic> data) async {
    final accessToken = data['access_token'] as String?;
    final refreshToken = data['refresh_token'] as String?;
    if (accessToken == null || refreshToken == null) {
      throw ApiException('Server did not return a valid session.');
    }
    final claims = _jwtClaims(accessToken);
    final sessionUser = UserModel(
      id: (claims['uuid'] ?? claims['user_id'] ?? claims['id'] ?? claims['sub'] ?? '').toString(),
      phone: (claims['phone'] ?? '').toString(),
      fullName: (claims['full_name'] ?? claims['name'] ?? '').toString(),
      role: (claims['role'] ?? 'tourist').toString(),
    );
    await _storage.saveSession(
      accessToken: accessToken,
      refreshToken: refreshToken,
      user: sessionUser.id.isEmpty ? null : sessionUser,
    );
  }

  Map<String, dynamic> _jwtClaims(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return const {};
    try {
      final payload = base64Url.normalize(parts[1]);
      return jsonDecode(utf8.decode(base64Url.decode(payload))) as Map<String, dynamic>;
    } on FormatException {
      return const {};
    }
  }

  UserModel? _userFromToken(String? token) {
    if (token == null) return null;
    final claims = _jwtClaims(token);
    final id = (claims['uuid'] ?? claims['user_id'] ?? claims['id'] ?? claims['sub'] ?? '').toString();
    if (id.isEmpty) return null;
    return UserModel(
      id: id,
      phone: (claims['phone'] ?? '').toString(),
      fullName: (claims['full_name'] ?? claims['name'] ?? '').toString(),
      role: (claims['role'] ?? 'tourist').toString(),
    );
  }
}
