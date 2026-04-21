import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../config.dart';

class AuthService {
  static const _storage = FlutterSecureStorage();

  /// Refreshes the access token using the stored refresh token.
  /// Returns the new access token, or null if refresh failed.
  static Future<String?> refreshAccessToken() async {
    try {
      final refreshToken = await _storage.read(key: 'refresh_token');
      if (refreshToken == null) return null;

      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/user/api/token/refresh/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh': refreshToken}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final newAccess = data['access'] as String?;
        final newRefresh = data['refresh'] as String?;
        if (newAccess != null) {
          await _storage.write(key: 'access_token', value: newAccess);
          if (newRefresh != null) {
            await _storage.write(key: 'refresh_token', value: newRefresh);
          }
          return newAccess;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Clears all session data from secure storage.
  static Future<void> clearSession() async {
    await _storage.delete(key: 'access_token');
    await _storage.delete(key: 'refresh_token');
    await _storage.delete(key: 'travelers');
  }
}
