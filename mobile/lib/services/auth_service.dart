import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

class AuthService {
  static const _tokenKey = 'access_token';
  static const _deviceIdKey = 'device_id';
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
      return false;
    }
  }

  /// Get or create a stable device UUID. Persists across app launches
  /// but is lost on app reinstall (new anonymous account on reinstall).
  Future<String> getOrCreateDeviceId() async {
    var deviceId = await _storage.read(key: _deviceIdKey);
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = const Uuid().v4();
      await _storage.write(key: _deviceIdKey, value: deviceId);
    }
    return deviceId;
  }

  Future<String?> getDeviceId() => _storage.read(key: _deviceIdKey);

  Future<bool> isOnboardingComplete() async {
    try {
      final value = await _storage.read(key: _onboardingKey);
      return value == 'true';
    } catch (_) {
      return false;
    }
  }

  Future<void> setOnboardingComplete() =>
      _storage.write(key: _onboardingKey, value: 'true');

  Future<bool> isOnboardingSeen() async {
    try {
      final value = await _storage.read(key: _onboardingSeenKey);
      return value == 'true';
    } catch (_) {
      return false;
    }
  }

  Future<void> setOnboardingSeen() =>
      _storage.write(key: _onboardingSeenKey, value: 'true');

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
    // Keep device_id so re-registration gets the same user
    final deviceId = await _storage.read(key: _deviceIdKey);
    await _storage.deleteAll();
    if (deviceId != null) {
      await _storage.write(key: _deviceIdKey, value: deviceId);
    }
  }
}
