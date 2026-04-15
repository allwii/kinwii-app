import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthService {
  static const _tokenKey = 'access_token';
  static const _onboardingKey = 'onboarding_complete';
  static const _onboardingSeenKey = 'onboarding_seen';
  static const _pendingOnboardingKey = 'pending_onboarding';
  final _storage = const FlutterSecureStorage();

  Future<String?> getToken() => _storage.read(key: _tokenKey);

  Future<void> setToken(String token) =>
      _storage.write(key: _tokenKey, value: token);

  Future<void> clearToken() => _storage.delete(key: _tokenKey);

  Future<bool> isLoggedIn() async {
    try {
      final token = await getToken();
      return token != null && token.isNotEmpty;
    } catch (_) {
      // FlutterSecureStorage can fail on iOS simulator after reinstall
      return false;
    }
  }

  Future<bool> isOnboardingComplete() async {
    final value = await _storage.read(key: _onboardingKey);
    return value == 'true';
  }

  Future<void> setOnboardingComplete() =>
      _storage.write(key: _onboardingKey, value: 'true');

  /// Whether the user has already been through the onboarding flow at least once.
  Future<bool> isOnboardingSeen() async {
    final value = await _storage.read(key: _onboardingSeenKey);
    return value == 'true';
  }

  Future<void> setOnboardingSeen() =>
      _storage.write(key: _onboardingSeenKey, value: 'true');

  /// Store onboarding answers locally so they can be submitted after signup.
  Future<void> savePendingOnboarding(Map<String, dynamic> data) =>
      _storage.write(key: _pendingOnboardingKey, value: jsonEncode(data));

  Future<Map<String, dynamic>?> getPendingOnboarding() async {
    final raw = await _storage.read(key: _pendingOnboardingKey);
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> clearPendingOnboarding() =>
      _storage.delete(key: _pendingOnboardingKey);

  Future<void> logout() async {
    await _storage.deleteAll();
  }
}
