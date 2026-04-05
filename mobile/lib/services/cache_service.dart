import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';

/// Lightweight Hive-based cache for API responses.
/// Enables instant Today screen loads with stale-while-revalidate.
class CacheService {
  static const _boxName = 'kinwii_cache';
  static const _ttlSuffix = '__ttl';

  late Box<String> _box;

  Future<void> init() async {
    await Hive.initFlutter();
    _box = await Hive.openBox<String>(_boxName);
  }

  /// Store a JSON-serializable value with a TTL in minutes.
  Future<void> put(String key, dynamic data, {int ttlMinutes = 30}) async {
    await _box.put(key, jsonEncode(data));
    final expiry =
        DateTime.now().add(Duration(minutes: ttlMinutes)).toIso8601String();
    await _box.put('$key$_ttlSuffix', expiry);
  }

  /// Get cached data. Returns null if not found.
  /// If [respectTtl] is true, returns null when expired.
  dynamic get(String key, {bool respectTtl = false}) {
    final raw = _box.get(key);
    if (raw == null) return null;

    if (respectTtl) {
      final ttlRaw = _box.get('$key$_ttlSuffix');
      if (ttlRaw != null) {
        final expiry = DateTime.parse(ttlRaw);
        if (DateTime.now().isAfter(expiry)) return null;
      }
    }

    return jsonDecode(raw);
  }

  /// Check if a key exists and hasn't expired.
  bool isFresh(String key) {
    final ttlRaw = _box.get('$key$_ttlSuffix');
    if (ttlRaw == null) return false;
    return DateTime.now().isBefore(DateTime.parse(ttlRaw));
  }

  Future<void> remove(String key) async {
    await _box.delete(key);
    await _box.delete('$key$_ttlSuffix');
  }

  Future<void> clear() async {
    await _box.clear();
  }
}
