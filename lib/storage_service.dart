import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

//this code is to have the app maintain internal storage that it can then update and keep through out restarts of the app

class StorageService {
  static Future<void> saveList(String key, List<String> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(list));
  }

  static Future<List<String>> loadList(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(key);
    if (jsonString == null) {
      return [];
    }
    return List<String>.from(jsonDecode(jsonString));
  }


  static Future<void> saveMap(String key, Map<String, List<String>> map) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonMap = map.map((k, v) => MapEntry(k, v));
    await prefs.setString(key, jsonEncode(jsonMap));
  }

  static Future<Map<String, List<String>>> loadMap(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(key);
    if (jsonString == null) return {};
    final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
    return decoded.map((key, value) => MapEntry(key, List<String>.from(value)));
  }

  static Future<bool> hasKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(key);
  }
}
