import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants.dart';

class OfflineStorageService {
  /// Loads all locally cached encrypted items
  static Future<List<Map<String, dynamic>>> loadLocalItems() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(AppConstants.keyOfflineItems);
    if (jsonStr == null || jsonStr.isEmpty) return [];

    try {
      final List<dynamic> decoded = jsonDecode(jsonStr);
      return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Saves or updates a single encrypted item in the local cache
  static Future<void> upsertLocalItem(Map<String, dynamic> itemMap) async {
    final items = await loadLocalItems();
    final id = itemMap['id'];

    final index = items.indexWhere((i) => i['id'] == id);
    if (index != -1) {
      items[index] = itemMap;
    } else {
      items.insert(0, itemMap);
    }

    await _saveAll(items);
  }

  /// Removes an item from the local cache
  static Future<void> removeLocalItem(String id) async {
    final items = await loadLocalItems();
    items.removeWhere((i) => i['id'] == id);
    await _saveAll(items);
  }

  /// Saves the complete list of encrypted items to disk
  static Future<void> saveAllItems(List<Map<String, dynamic>> items) async {
    await _saveAll(items);
  }

  /// Internal helper to write JSON to SharedPreferences
  static Future<void> _saveAll(List<Map<String, dynamic>> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.keyOfflineItems, jsonEncode(items));
  }

  /// Clears local cache (used on logout)
  static Future<void> clearLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.keyOfflineItems);
  }
}
