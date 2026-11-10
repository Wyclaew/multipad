import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants.dart';

class OfflineStorageService {
  // Asynchronous queue lock to serialize read-modify-write operations
  static Future<void> _lock = Future.value();

  static Future<T> _sync<T>(Future<T> Function() computation) {
    final completer = Completer<T>();
    _lock = _lock.then((_) async {
      try {
        final result = await computation();
        completer.complete(result);
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  /// Loads all locally cached encrypted items safely
  static Future<List<Map<String, dynamic>>> loadLocalItems() async {
    return _sync(() async {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(AppConstants.keyOfflineItems);
      if (jsonStr == null || jsonStr.isEmpty) return [];

      try {
        final List<dynamic> decoded = jsonDecode(jsonStr);
        return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      } catch (_) {
        return [];
      }
    });
  }

  /// Saves or updates a single encrypted item in the local cache atomically
  static Future<void> upsertLocalItem(Map<String, dynamic> itemMap) async {
    return _sync(() async {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(AppConstants.keyOfflineItems);
      List<Map<String, dynamic>> items = [];
      if (jsonStr != null && jsonStr.isNotEmpty) {
        try {
          final List<dynamic> decoded = jsonDecode(jsonStr);
          items = decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        } catch (_) {
          items = [];
        }
      }

      final id = itemMap['id'];
      final index = items.indexWhere((i) => i['id'] == id);
      if (index != -1) {
        items[index] = itemMap;
      } else {
        items.insert(0, itemMap);
      }

      await prefs.setString(AppConstants.keyOfflineItems, jsonEncode(items));
    });
  }

  /// Removes an item from the local cache atomically
  static Future<void> removeLocalItem(String id) async {
    return _sync(() async {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(AppConstants.keyOfflineItems);
      if (jsonStr == null || jsonStr.isEmpty) return;

      try {
        final List<dynamic> decoded = jsonDecode(jsonStr);
        final items = decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        items.removeWhere((i) => i['id'] == id);
        await prefs.setString(AppConstants.keyOfflineItems, jsonEncode(items));
      } catch (_) {}
    });
  }

  /// Saves the complete list of encrypted items to disk atomically
  static Future<void> saveAllItems(List<Map<String, dynamic>> items) async {
    return _sync(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppConstants.keyOfflineItems, jsonEncode(items));
    });
  }

  /// Clears local cache (used on logout)
  static Future<void> clearLocal() async {
    return _sync(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(AppConstants.keyOfflineItems);
    });
  }
}
